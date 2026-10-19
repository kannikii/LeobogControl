import SwiftUI
import AppKit
import Combine
import LeobogCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case device = "장치"
    case tester = "키 테스터"
    case remap = "키 매핑"
    case shortcuts = "단축키 · Fn 레이어"
    case fnkeys = "펑션키"
    case lighting = "조명 (RGB)"
    case diagnostics = "진단 · 벤더 채널"
    case crash = "크래시 · 메모리 모니터"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .device: return "keyboard"
        case .tester: return "hand.tap"
        case .remap: return "arrow.triangle.swap"
        case .shortcuts: return "command"
        case .fnkeys: return "fn"
        case .lighting: return "lightbulb.led"
        case .diagnostics: return "stethoscope"
        case .crash: return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let hid = HIDDeviceManager()
    let compx: CompxClient
    let remap = HidutilRemapService()
    let fn = FnKeyService()
    let battery = BatteryService()
    let bleBattery = BLEBatteryReader(pollInterval: 60) { AppLog.shared.log("ble", $0) }

    @Published var section: SidebarSection = .device {
        didSet { if section != oldValue { AppLog.shared.log("ui", "화면 전환: \(oldValue.rawValue) → \(section.rawValue)") } }
    }
    /// 직전 실행이 어떻게 끝났는지 (앱 시작 시 한 번 판정). 크래시였으면 상단 배너와 모니터 화면에 보인다.
    @Published private(set) var lastRun: LastRunStatus
    /// 상단 배너를 닫았는가
    @Published var crashBannerDismissed = false
    private var memoryPressure: MemoryPressureWatcher?
    @Published var pressedKeyIDs: Set<Int> = []
    /// 키보드 펌웨어 모드 (키보드에서 Fn + M 으로 전환). 하단열 라벨과 usage ↔ 물리 키 매칭이 달라진다.
    @Published var keyboardMode: KeyboardMode = KeyboardMode(rawValue: UserDefaults.standard.string(forKey: "keyboardMode") ?? "") ?? .mac {
        didSet {
            UserDefaults.standard.set(keyboardMode.rawValue, forKey: "keyboardMode")
            pressedKeyIDs.removeAll()
            unmatchedUsages.removeAll()
            loneRightCtrlCount = 0
            fnComboCount = 0
        }
    }
    /// 이번 세션에 펌웨어 Fn 조합(Fn+F8 등)이 들어온 횟수. Fn 키 자체는 혼자 눌러도 아무 입력이 없으므로, 이 값이 Fn 키가 살아 있다는 증거다.
    @Published private(set) var fnComboCount = 0
    /// 현재 모드의 배열표에서 찾지 못한 입력 (눌림 기준, 중복 없이, 오래된 것부터)
    @Published private(set) var unmatchedUsages: [HIDUsage] = []
    /// Mac 모드에서 다른 키 없이 오른쪽 Ctrl(0xE4) 만 눌린 횟수. 펌웨어 Fn 은 조합 중에만 0xE4 를 섞어 보내므로,
    /// 혼자 눌린 0xE4 가 반복되면 키보드가 실제로는 Windows 모드(그 자리가 오른쪽 Ctrl)일 가능성이 높다.
    @Published private(set) var loneRightCtrlCount = 0
    /// 모드 불일치가 의심되는가 (키 테스터 안내용)
    var modeMismatchSuspected: Bool { !unmatchedUsages.isEmpty || (keyboardMode == .mac && loneRightCtrlCount >= 2) }

    /// 현재 모드의 물리 키 목록
    var layoutKeys: [PhysicalKey] { Hi8SELayout.keys(for: keyboardMode) }
    /// 현재 모드 기준 usage → 물리 키
    func layoutKey(for usage: HIDUsage) -> PhysicalKey? { Hi8SELayout.key(for: usage, mode: keyboardMode) }
    @Published var permissionRequested = false
    /// 권한 카드에 보여 줄 안내 (요청 결과, 거부 기록 안내 등)
    @Published var permissionMessage: String?
    private var permissionPoll: AnyCancellable?
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.leobog.control"

    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var releaseTimers: [Int: DispatchWorkItem] = [:]

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let previous = RunMarker.beginSession(version: version)
        let status = CrashReportReader.lastRunStatus(previous: previous)
        lastRun = status
        compx = CompxClient(hid: hid)   // 여기까지 모든 저장 프로퍼티 초기화 완료
        let mem = MemoryStats.current()
        AppLog.shared.log("app", "시작 v\(version) pid \(getpid()) · 메모리 footprint \(MemoryStats.format(mem.footprintBytes)) · 시스템 압박 \(mem.pressureLabel)")
        switch status.outcome {
        case .crashed: AppLog.shared.log("app", "직전 실행 크래시 감지: " + (status.report?.verdict ?? "") + " (" + (status.report?.url.lastPathComponent ?? "") + ")")
        case .killed: AppLog.shared.log("app", "직전 실행(pid \(status.previousPid))이 정상 종료 표식 없이 끝남 — 크래시 리포트 없음(강제 종료/재빌드로 추정)")
        case .cleanOrFirst: break
        }
        memoryPressure = MemoryPressureWatcher { label in
            let m = MemoryStats.current()
            AppLog.shared.log("memory", "시스템 메모리 압박 알림: \(label) · 이 앱 footprint \(MemoryStats.format(m.footprintBytes)) · 시스템 여유 \(MemoryStats.format(m.systemFreeBytes))")
        }

        hid.start()
        AppLog.shared.log("hid", "매니저 시작 · 권한 \(hid.permission.rawValue)")
        battery.startAutoRefresh(interval: 120)
        // 블루투스 권한이 이미 허용된 경우에만 자동 시작 — 아니면 장치 탭의 버튼으로 (시스템 대화상자가 뜬다)
        if BLEBatteryReader.isAuthorized { bleBattery.start() } else { AppLog.shared.log("ble", "블루투스 권한 \(BLEBatteryReader.authorizationLabel) — 직접 읽기는 수동 시작 대기") }
        remap.refreshFromSystem()

        // 권한이 없으면 앱 이름으로 요청 (기록이 없을 때만 시스템 대화상자가 뜬다)
        if hid.permission != .granted {
            permissionRequested = true
            hid.requestPermission()
            if hid.permission == .denied {
                permissionMessage = Self.deniedMessage
            } else if hid.permission != .granted {
                permissionMessage = Self.promptMessage
                startPermissionPolling()
            }
        }

        hid.keyEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] ev in self?.handleKeyEvent(ev) }
            .store(in: &cancellables)

        // 앱이 다시 활성화될 때 권한이 생겼으면 자동으로 다시 연다
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reopenIfPermitted() }
            .store(in: &cancellables)

        installLocalMonitor()
    }

    static let deniedMessage = "macOS 가 이 앱의 이전 결정(거부, 또는 앱을 다시 빌드해서 무효가 된 허용)을 기억하고 있어 대화상자를 다시 띄우지 않습니다. '권한 기록 지우고 다시 요청' 을 누르면 기록을 지우고 바로 다시 묻습니다."
    /// 입력 모니터링 대화상자에는 '허용' 버튼이 없다 ('시스템 설정 열기' / '거부' 뿐). 허용은 시스템 설정의 스위치로 한다.
    static let promptMessage = "시스템 대화상자에서 '시스템 설정 열기' 를 누른 뒤, 입력 모니터링 목록에서 Leobog Control 스위치를 켜세요 (대화상자에 '허용' 버튼은 없습니다). 켜면 앱으로 돌아오거나 몇 초 안에 자동으로 장치를 다시 엽니다."

    /// 권한이 생겼으면 장치를 연다. 이미 열려 있으면 건드리지 않는다.
    /// (예전에는 장치 열거가 끝나기 전 isOpen == false 를 보고 매번 stop/start 를 반복했고, 그때 입력 중이던 리포트 버퍼가 해제돼 앱이 죽었다.)
    func reopenIfPermitted() {
        hid.refreshPermission()
        guard hid.permission == .granted else { return }
        permissionMessage = nil
        permissionPoll = nil
        if !hid.isManagerOpen { AppLog.shared.log("hid", "권한 허용 확인 → 장치 다시 열기"); hid.reopen() }
    }

    /// '권한 요청' 버튼. 거부(또는 재빌드로 무효가 된 허용) 기록이 있으면 macOS 가 다시 묻지 않으므로 기록을 먼저 지운다.
    func requestPermission() {
        permissionRequested = true
        hid.refreshPermission()
        AppLog.shared.log("perm", "권한 요청 버튼 · 현재 \(hid.permission.rawValue)")
        if hid.permission == .denied {
            guard hid.resetPermissionRecord(bundleID: Self.bundleID) else {
                permissionMessage = "권한 기록을 지우지 못했습니다 (\(hid.lastError ?? "tccutil 오류")). 시스템 설정 › 개인정보 보호 및 보안 › 입력 모니터링에서 Leobog Control 을 목록에서 지우고(−) 다시 추가(+)한 뒤 '권한 다시 확인' 을 누르세요."
                openInputMonitoringSettings()
                return
            }
        }
        hid.requestPermission()
        if hid.permission == .granted {
            permissionMessage = nil
            permissionPoll = nil
            hid.reopen()
            return
        }
        permissionMessage = Self.promptMessage + " 대화상자가 보이지 않으면 아래 '시스템 설정 열기' 버튼으로 가세요."
        startPermissionPolling()
    }

    /// 대화상자가 떠 있는 동안 1초마다 권한을 다시 확인해, 허용되면 장치를 열고 안내문을 지운다 (최대 3분).
    private func startPermissionPolling() {
        var ticks = 0
        permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                ticks += 1
                self.reopenIfPermitted()   // 허용됐으면 안내문을 지우고 장치를 연다
                switch self.hid.permission {
                case .granted:
                    self.permissionPoll = nil
                case .denied, .unknown:
                    // '거부됨' 으로 보여도 사용자가 시스템 설정에서 스위치를 켜는 중일 수 있으므로 타임아웃까지 계속 확인한다
                    if self.hid.permission == .denied, ticks == 1 { self.permissionMessage = Self.deniedMessage + " 시스템 설정에서 스위치를 켜면 자동으로 반영됩니다." }
                    if ticks >= 180 {
                        self.permissionMessage = "3분 동안 허용되지 않아 자동 확인을 멈췄습니다. 시스템 설정의 입력 모니터링에서 Leobog Control 을 켠 뒤 '권한 다시 확인' 을 누르세요."
                        self.permissionPoll = nil
                    }
                }
            }
    }

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(FnKeyService.inputMonitoringURL)
    }

    var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/leobog-cli").path
    }

    // MARK: 키 이벤트 → 다이어그램 강조

    private func handleKeyEvent(_ ev: HIDKeyEvent) {
        if let key = Hi8SELayout.key(for: ev.usage, mode: keyboardMode) {
            // Mac 모드에서 다른 키 없이 0xE4 만 눌리면 Windows 모드 신호로 센다 (펌웨어 Fn 은 조합 중에만 0xE4 를 보냄)
            if keyboardMode == .mac, ev.isDown, ev.usage == .keyboard(0xE4), pressedKeyIDs.subtracting([key.id]).isEmpty {
                loneRightCtrlCount += 1
            }
            if ev.isDown { pressedKeyIDs.insert(key.id) } else { pressedKeyIDs.remove(key.id) }
            return
        }
        // Fn 레이어 출력 (미디어 usage 또는 Fn+U/I/O/Del/End 같은 키보드 usage) 은 Fn + 해당 키로 표시.
        // 볼륨·음소거 usage 는 노브와 Fn+F10–F12 가 같은 값을 보내므로 노브로 표시한다.
        if let ids = fnLayerKeyIDs(for: ev.usage) {
            if ev.isDown, ids.contains(Hi8SELayout.fnKey(for: keyboardMode).id) { fnComboCount += 1 }
            for id in ids { if ev.isDown { pressedKeyIDs.insert(id) } else { pressedKeyIDs.remove(id) } }
            return
        }
        // 그 밖의 알 수 없는 입력은 따로 모아 보여 준다 (모드 불일치 진단용)
        if ev.isDown, !unmatchedUsages.contains(ev.usage) {
            unmatchedUsages.append(ev.usage)
            if unmatchedUsages.count > 30 { unmatchedUsages.removeFirst() }
        }
    }

    /// Fn 레이어/노브 출력이면 다이어그램에서 켤 키 번호들, 아니면 nil
    private func fnLayerKeyIDs(for usage: HIDUsage) -> [Int]? {
        if usage.page == 0x0C, [0xE9, 0xEA, 0xE2].contains(usage.usage) { return [Hi8SELayout.knob.id] }
        if let s = FnLayerReference.shortcuts.first(where: { $0.expected == usage }), let kid = s.keyID {
            return [kid, Hi8SELayout.fnKey(for: keyboardMode).id]
        }
        return nil
    }

    /// '최근 입력' 목록용 설명: 물리 키 이름, 또는 Fn 레이어/노브 출력이면 그 조합
    func eventLabel(for usage: HIDUsage) -> String? {
        if let k = layoutKey(for: usage) { return "= \(k.displayLabel) 키" }
        if usage.page == 0x0C, [0xE9, 0xEA, 0xE2].contains(usage.usage) {
            let alt = FnLayerReference.shortcuts.first { $0.expected == usage && $0.keyID != Hi8SELayout.knob.id }?.combo
            return "= 노브" + (alt.map { " (또는 \($0))" } ?? "")
        }
        if let s = FnLayerReference.shortcuts.first(where: { $0.expected == usage }) { return "= \(s.combo)" }
        return nil
    }

    /// 권한이 없을 때의 대안: 앱 창이 앞에 있을 때 NSEvent 로 키를 본다.
    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] ev in
            guard let self else { return ev }
            self.handleLocalEvent(ev)
            // 키 테스터 화면에서는 키 입력을 화면이 삼킨다. 그대로 넘기면 첫 응답자인 사이드바 List 가 방향키로
            // 다른 화면으로 이동해 버린다 (Tab/Space 도 마찬가지). ⌘ 조합(⌘Q, ⌘W, ⌘, …)은 그대로 통과시킨다.
            if self.section == .tester, ev.type == .keyDown || ev.type == .keyUp, !ev.modifierFlags.contains(.command) {
                return nil
            }
            return ev
        }
    }

    @Published private(set) var localEvents: [HIDKeyEvent] = []

    private func handleLocalEvent(_ ev: NSEvent) {
        guard !hid.isOpen else { return }   // HID 경로가 살아 있으면 중복 방지
        var usage: HIDUsage?
        var down = true
        switch ev.type {
        case .keyDown: usage = VirtualKeyMap.usage(for: ev.keyCode); down = true
        case .keyUp: usage = VirtualKeyMap.usage(for: ev.keyCode); down = false
        case .flagsChanged:
            usage = VirtualKeyMap.usage(for: ev.keyCode)
            down = VirtualKeyMap.modifierIsDown(keyCode: ev.keyCode, flags: ev.modifierFlags)
        case .systemDefined:
            guard ev.subtype.rawValue == 8 else { return }
            let keyCode = Int((ev.data1 & 0xFFFF_0000) >> 16)
            let flags = ev.data1 & 0x0000_FFFF
            down = ((flags & 0xFF00) >> 8) == 0x0A
            usage = VirtualKeyMap.mediaUsage(for: keyCode)
        default: return
        }
        guard let u = usage else { return }
        let e = HIDKeyEvent(timestamp: Date(), usage: u, value: down ? 1 : 0)
        localEvents.append(e)
        if localEvents.count > 200 { localEvents.removeFirst(localEvents.count - 200) }
        handleKeyEvent(e)
    }

    var displayedEvents: [HIDKeyEvent] { hid.isOpen ? hid.lastKeyEvents : localEvents }
    func clearEvents() { hid.clearKeyEvents(); localEvents.removeAll(); pressedKeyIDs.removeAll(); unmatchedUsages.removeAll(); loneRightCtrlCount = 0; fnComboCount = 0 }
}

/// macOS 가상 키코드 → HID usage (ANSI 배열). 권한 없이 NSEvent 로 볼 때만 사용.
enum VirtualKeyMap {
    static let table: [UInt16: UInt32] = [
        0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08, 0x03: 0x09, 0x05: 0x0A, 0x04: 0x0B, 0x22: 0x0C, 0x26: 0x0D,
        0x28: 0x0E, 0x25: 0x0F, 0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12, 0x23: 0x13, 0x0C: 0x14, 0x0F: 0x15, 0x01: 0x16, 0x11: 0x17,
        0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B, 0x10: 0x1C, 0x06: 0x1D,
        0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22, 0x16: 0x23, 0x1A: 0x24, 0x1C: 0x25, 0x19: 0x26, 0x1D: 0x27,
        0x24: 0x28, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C, 0x1B: 0x2D, 0x18: 0x2E, 0x21: 0x2F, 0x1E: 0x30, 0x2A: 0x31,
        0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37, 0x2C: 0x38, 0x39: 0x39,
        0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x64: 0x41, 0x65: 0x42, 0x6D: 0x43, 0x67: 0x44, 0x6F: 0x45,
        0x69: 0x46, 0x6B: 0x47, 0x71: 0x48, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B, 0x75: 0x4C, 0x77: 0x4D, 0x79: 0x4E,
        0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
        0x47: 0x53, 0x4B: 0x54, 0x43: 0x55, 0x4E: 0x56, 0x45: 0x57, 0x4C: 0x58, 0x53: 0x59, 0x54: 0x5A, 0x55: 0x5B, 0x56: 0x5C,
        0x57: 0x5D, 0x58: 0x5E, 0x59: 0x5F, 0x5B: 0x60, 0x5C: 0x61, 0x52: 0x62, 0x41: 0x63, 0x51: 0x67, 0x6E: 0x65,
        0x3B: 0xE0, 0x38: 0xE1, 0x3A: 0xE2, 0x37: 0xE3, 0x3E: 0xE4, 0x3C: 0xE5, 0x3D: 0xE6, 0x36: 0xE7, 0x3F: 0xFFFF,
    ]
    static func usage(for keyCode: UInt16) -> HIDUsage? {
        guard let u = table[keyCode] else { return nil }
        if u == 0xFFFF { return .appleFn }
        return .keyboard(u)
    }
    static func modifierIsDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 0x3B, 0x3E: return flags.contains(.control)
        case 0x38, 0x3C: return flags.contains(.shift)
        case 0x3A, 0x3D: return flags.contains(.option)
        case 0x37, 0x36: return flags.contains(.command)
        case 0x39: return flags.contains(.capsLock)
        case 0x3F: return flags.contains(.function)
        default: return true
        }
    }
    static func mediaUsage(for nxKey: Int) -> HIDUsage? {
        switch nxKey {
        case 0: return .consumer(0xE9)   // SOUND_UP
        case 1: return .consumer(0xEA)   // SOUND_DOWN
        case 2: return .consumer(0x6F)   // BRIGHTNESS_UP
        case 3: return .consumer(0x70)   // BRIGHTNESS_DOWN
        case 7: return .consumer(0xE2)   // MUTE
        case 16: return .consumer(0xCD)  // PLAY
        case 17: return .consumer(0xB5)  // NEXT
        case 18: return .consumer(0xB6)  // PREVIOUS
        case 19: return .consumer(0xB3)  // FAST
        case 20: return .consumer(0xB4)  // REWIND
        case 21: return .consumer(0x79)  // ILLUMINATION_UP
        case 22: return .consumer(0x7A)  // ILLUMINATION_DOWN
        default: return nil
        }
    }
}
