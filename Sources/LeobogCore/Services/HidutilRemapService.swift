import Foundation
import Combine

/// 한 쌍의 키 매핑 (물리 키 usage → 보낼 usage)
public struct KeyRemap: Codable, Identifiable, Hashable, Sendable {
    public var src: HIDUsage
    public var dst: HIDUsage
    public var id: UInt64 { src.hidutilValue }
    public init(src: HIDUsage, dst: HIDUsage) { self.src = src; self.dst = dst }
    public var isIdentity: Bool { src == dst }
}

public struct RemapPreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let remaps: [KeyRemap]
}

/// macOS `hidutil` 의 장치별 UserKeyMapping 으로 키를 바꾸는 서비스.
/// - 권한 불필요, 즉시 적용, 이 키보드(VID 0x3554 / PID 0xFA07)에만 적용된다.
/// - 재연결/재부팅 시 초기화되므로 LaunchAgent(`leobog-cli watch`)가 다시 적용한다.
public final class HidutilRemapService: ObservableObject {
    public static let matching = "{\"VendorID\":0x3554,\"ProductID\":0xFA07}"
    public static let launchAgentLabel = "com.leobog.control.remap"

    @Published public private(set) var remaps: [KeyRemap] = []
    @Published public private(set) var activeFromSystem: [KeyRemap] = []   // hidutil --get 결과
    @Published public private(set) var lastMessage: String = ""
    @Published public private(set) var launchAgentInstalled = false
    /// LaunchAgent 가 실제로 실행 중인지 (launchctl print). `refreshLaunchAgentState()` 가 백그라운드에서 갱신한다.
    @Published public private(set) var launchAgentRunning = false
    /// 설치/제거가 일어날 때마다 올라가는 세대 번호. 백그라운드 조회가 시작될 때의 값과 다르면 그 결과는 버린다
    /// (제거 버튼을 누른 직후 아직 돌고 있던 `launchctl print` 결과가 '설치됨' 으로 되돌리는 것을 막는다).
    private var agentStateGeneration = 0

    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LeobogControl", isDirectory: true)
    }
    public static var storeURL: URL { supportDir.appendingPathComponent("remaps.json") }
    public static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    public init() {
        load()
        launchAgentInstalled = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
        refreshLaunchAgentState()
    }

    // MARK: 저장/불러오기

    public func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let list = try? JSONDecoder().decode([KeyRemap].self, from: data) else { return }
        remaps = list
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(remaps).write(to: Self.storeURL, options: .atomic)
    }

    // MARK: 편집

    public func set(_ remap: KeyRemap) {
        remaps.removeAll { $0.src == remap.src }
        if !remap.isIdentity { remaps.append(remap) }
        remaps.sort { $0.src.hidutilValue < $1.src.hidutilValue }
    }

    public func remove(src: HIDUsage) { remaps.removeAll { $0.src == src } }
    /// 목록을 비우고 저장 파일(remaps.json)도 비운다 — 저장 파일이 남아 있으면 LaunchAgent 가 재연결 때 옛 매핑을 되살린다.
    public func removeAll() {
        remaps.removeAll()
        try? save()
    }

    public func mapping(for src: HIDUsage) -> HIDUsage? { remaps.first { $0.src == src }?.dst }

    public func apply(preset: RemapPreset) {
        for r in preset.remaps { set(r) }
    }

    // MARK: hidutil 실행

    public static let presets: [RemapPreset] = [
        RemapPreset(id: "swap-cmd-opt", title: "Win ↔ Alt 교체 (⌘/⌥ Mac 배열)",
                    detail: "Win 자리를 ⌥, Alt 자리를 ⌘ 로 바꿉니다. 이 키보드는 Mac 모드(Fn + M)에서 펌웨어가 이미 바꿔 주므로 Windows 모드로 쓸 때만 필요합니다.",
                    remaps: [KeyRemap(src: .keyboard(0xE3), dst: .keyboard(0xE2)), KeyRemap(src: .keyboard(0xE2), dst: .keyboard(0xE3)),
                             KeyRemap(src: .keyboard(0xE7), dst: .keyboard(0xE6)), KeyRemap(src: .keyboard(0xE6), dst: .keyboard(0xE7))]),
        RemapPreset(id: "caps-ctrl", title: "Caps Lock → Control", detail: "Caps Lock 을 왼쪽 Control 로.",
                    remaps: [KeyRemap(src: .keyboard(0x39), dst: .keyboard(0xE0))]),
        RemapPreset(id: "caps-esc", title: "Caps Lock → Esc", detail: "Caps Lock 을 Escape 로 (Vim 사용자용).",
                    remaps: [KeyRemap(src: .keyboard(0x39), dst: .keyboard(0x29))]),
        RemapPreset(id: "f-media", title: "F7–F12 → 미디어 키", detail: "Fn 없이 F7 이전곡, F8 재생/일시정지, F9 다음곡, F10 음소거, F11/F12 볼륨.",
                    remaps: [KeyRemap(src: .keyboard(0x40), dst: .consumer(0xB6)), KeyRemap(src: .keyboard(0x41), dst: .consumer(0xCD)),
                             KeyRemap(src: .keyboard(0x42), dst: .consumer(0xB5)), KeyRemap(src: .keyboard(0x43), dst: .consumer(0xE2)),
                             KeyRemap(src: .keyboard(0x44), dst: .consumer(0xEA)), KeyRemap(src: .keyboard(0x45), dst: .consumer(0xE9))]),
        RemapPreset(id: "f-bright", title: "F1/F2 → 화면 밝기", detail: "F1 밝기 낮추기, F2 밝기 높이기.",
                    remaps: [KeyRemap(src: .keyboard(0x3A), dst: .consumer(0x70)), KeyRemap(src: .keyboard(0x3B), dst: .consumer(0x6F))]),
        RemapPreset(id: "rcmd-fn", title: "오른쪽 ⌘ → Fn(🌐)",
                    detail: "Mac 모드에서 스페이스 바로 오른쪽 키(오른쪽 ⌘, 0xE7)를 macOS Fn/🌐 키로 (받아쓰기·이모지·fn 조합). 키보드 자체 Fn 키는 그대로입니다.",
                    remaps: [KeyRemap(src: .keyboard(0xE7), dst: .appleFn)]),
        RemapPreset(id: "rctrl-fn", title: "오른쪽 Ctrl → Fn(🌐) (Windows 모드용)",
                    detail: "Windows 모드에서 스페이스 오른쪽 두 번째 키(오른쪽 Control, 0xE4)를 macOS Fn/🌐 키로.",
                    remaps: [KeyRemap(src: .keyboard(0xE4), dst: .appleFn)]),
        RemapPreset(id: "del-fwd", title: "Del 키 → Backspace", detail: "오른쪽 위 Del 을 지우기(⌫) 로.",
                    remaps: [KeyRemap(src: .keyboard(0x4C), dst: .keyboard(0x2A))]),
    ]

    /// 현재 remaps 를 시스템에 적용
    @discardableResult
    public func applyToSystem() -> Result<String, Error> {
        AppLog.shared.log("remap", "hidutil 매핑 적용 \(remaps.count)개")
        let json = Self.hidutilJSON(remaps)
        let r = Self.run(["property", "--matching", Self.matching, "--set", json])
        switch r {
        case .success:
            refreshFromSystem()
            if remaps.isEmpty {
                lastMessage = "매핑을 모두 해제했습니다"
            } else if activeFromSystem.isEmpty {
                // hidutil --set 은 장치가 없어도 성공(0)으로 끝난다. 읽어서 비어 있으면 실제로는 적용되지 않은 것.
                lastMessage = "매핑 \(remaps.count)개를 보냈지만 시스템에서 확인되지 않음 — 키보드가 연결되어 있지 않을 수 있습니다 (연결되면 자동 재적용)"
            } else {
                lastMessage = "\(remaps.count)개 매핑 적용됨"
            }
            return .success(lastMessage)
        case .failure(let e):
            lastMessage = "hidutil 실패: \(e.localizedDescription)"
            return .failure(e)
        }
    }

    /// 시스템에서 매핑 해제. 화면의 목록은 그대로 두지만(다시 '시스템에 적용' 으로 되살릴 수 있게) 저장 파일은 빈 목록으로
    /// 바꾼다 — LaunchAgent 는 저장 파일을 다시 적용하므로, 그대로 두면 키보드를 다시 연결할 때 방금 해제한 매핑이 되살아난다.
    @discardableResult
    public func clearSystem() -> Result<String, Error> {
        AppLog.shared.log("remap", "hidutil 매핑 해제")
        let r = Self.run(["property", "--matching", Self.matching, "--set", "{\"UserKeyMapping\":[]}"])
        refreshFromSystem()
        switch r {
        case .success:
            Self.persistEmptyList()
            lastMessage = "시스템 매핑 해제됨 (저장 파일도 비움 — 목록은 '시스템에 적용' 으로 다시 켤 수 있음)"
            return .success(lastMessage)
        case .failure(let e): lastMessage = "hidutil 실패: \(e.localizedDescription)"; return .failure(e)
        }
    }

    /// 저장 파일을 빈 목록으로 덮어쓴다 (메모리의 `remaps` 는 건드리지 않음).
    private static func persistEmptyList() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? Data("[]".utf8).write(to: storeURL, options: .atomic)
    }

    /// `hidutil --get UserKeyMapping` 결과를 해석해 현재 시스템에 적용된 매핑을 읽는다.
    public func refreshFromSystem() {
        activeFromSystem = Self.readSystemMappings()
    }

    public static func readSystemMappings() -> [KeyRemap] {
        guard case .success(let out) = run(["property", "--matching", matching, "--get", "UserKeyMapping"]) else { return [] }
        return parseHidutilOutput(out)
    }

    /// 출력 예: `RegistryID 1000ba809 UserKeyMapping ( { HIDKeyboardModifierMappingDst = 30064771187; HIDKeyboardModifierMappingSrc = 30064771187; } )`
    public static func parseHidutilOutput(_ s: String) -> [KeyRemap] {
        var result: [KeyRemap] = []
        let pattern = #"HIDKeyboardModifierMappingDst\s*=\s*(\d+);\s*HIDKeyboardModifierMappingSrc\s*=\s*(\d+);"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let dst = UInt64(ns.substring(with: m.range(at: 1))), let src = UInt64(ns.substring(with: m.range(at: 2))) else { continue }
            result.append(KeyRemap(src: HIDUsage(hidutilValue: src), dst: HIDUsage(hidutilValue: dst)))
        }
        // Src 가 Dst 보다 먼저 오는 변형도 처리
        if result.isEmpty {
            let p2 = #"HIDKeyboardModifierMappingSrc\s*=\s*(\d+);\s*HIDKeyboardModifierMappingDst\s*=\s*(\d+);"#
            if let re2 = try? NSRegularExpression(pattern: p2) {
                for m in re2.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    guard let src = UInt64(ns.substring(with: m.range(at: 1))), let dst = UInt64(ns.substring(with: m.range(at: 2))) else { continue }
                    result.append(KeyRemap(src: HIDUsage(hidutilValue: src), dst: HIDUsage(hidutilValue: dst)))
                }
            }
        }
        return result
    }

    public static func hidutilJSON(_ remaps: [KeyRemap]) -> String {
        let items = remaps.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.src.hexString),\"HIDKeyboardModifierMappingDst\":\($0.dst.hexString)}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    /// 외부 도구를 동기로 실행한다 (hidutil / launchctl / defaults / system_profiler / tccutil).
    ///
    /// 중요: `Process.waitUntilExit()` 는 **현재 스레드의 런루프를 돌리면서** 기다린다. 메인 스레드에서, 특히 SwiftUI 가
    /// 뷰 body·레이아웃을 계산하는 도중 그것이 불리면 런루프가 재진입돼 (타이머·HID 콜백·AX 요청·CATransaction 커밋 →
    /// 중첩 `NSHostingView.layout()`) 바깥 레이아웃이 들고 있던 StackLayout 자식 배열 포인터가 끊기고 `swift_release` 에서
    /// EXC_BAD_ACCESS 로 죽는다 (2026-10-19 03:17 ~ 04:27 크래시 10건 전부 이 스택). 그래서 여기서는 런루프를 절대 돌리지 않고,
    /// 파이프를 EOF 까지 읽은 뒤 종료 핸들러의 세마포어로만 기다린다. 뷰 body 안에서는 아예 부르지 말고
    /// (`refreshLaunchAgentState()` 처럼) 백그라운드 큐에서 부른 뒤 메인에 반영한다.
    @discardableResult
    public static func run(_ args: [String], tool: String = "/usr/bin/hidutil") -> Result<String, Error> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return .failure(error) }
        // stderr 는 다른 큐에서 읽어야 두 파이프가 동시에 차도 교착되지 않는다
        let errBox = DataBox()
        let errRead = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            errRead.signal()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()   // read(2) 로 블록 — 런루프는 돌지 않음
        errRead.wait()
        exited.wait()
        let s = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let e = String(data: errBox.data, encoding: .utf8) ?? ""
            return .failure(NSError(domain: "hidutil", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: e.isEmpty ? s : e]))
        }
        return .success(s)
    }

    private final class DataBox: @unchecked Sendable { var data = Data() }

    // MARK: LaunchAgent (재연결 시 자동 재적용)

    /// `cliPath` 는 `leobog-cli` 실행 파일 경로 (앱 번들 안의 것을 권장)
    public func installLaunchAgent(cliPath: String) throws {
        let plist: [String: Any] = [
            "Label": Self.launchAgentLabel,
            "ProgramArguments": [cliPath, "watch"],
            "RunAtLoad": true,
            // 실행 파일이 있을 때만 살려 둔다. `true` 로 두면 앱을 지운 뒤에도 launchd 가 없는 바이너리를 영원히 재시작하려 든다.
            "KeepAlive": ["PathState": [cliPath: true]],
            "ThrottleInterval": 10,
            "ProcessType": "Background",
            "StandardOutPath": Self.supportDir.appendingPathComponent("watch.log").path,
            "StandardErrorPath": Self.supportDir.appendingPathComponent("watch.log").path,
        ]
        try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // 기존 것이 있으면 먼저 내린다. bootout 은 비동기(SIGTERM 만 보내고 돌아옴)라 곧바로 bootstrap 하면
        // "37: Operation already in progress" 로 실패한다 → 서비스가 사라질 때까지 기다린 뒤 올린다.
        _ = Self.run(["bootout", "gui/\(getuid())/\(Self.launchAgentLabel)"], tool: "/bin/launchctl")
        Self.waitUntilAgentGone(timeout: 3)
        try data.write(to: Self.launchAgentURL, options: .atomic)
        var lastError: Error?
        for attempt in 0..<6 {
            if attempt > 0 { usleep(250_000) }
            switch Self.run(["bootstrap", "gui/\(getuid())", Self.launchAgentURL.path], tool: "/bin/launchctl") {
            case .success: lastError = nil
            case .failure(let e): lastError = e; continue
            }
            break
        }
        if let e = lastError {
            // 올리지 못했으면 plist 를 남겨 두지 않는다 ('설치됨' 으로 보이는데 실제로는 안 도는 상태 방지)
            try? FileManager.default.removeItem(at: Self.launchAgentURL)
            agentStateGeneration += 1
            launchAgentInstalled = false
            launchAgentRunning = false
            AppLog.shared.log("remap", "LaunchAgent bootstrap 실패: \(e.localizedDescription)")
            throw e
        }
        agentStateGeneration += 1
        launchAgentInstalled = true
        lastMessage = "자동 재적용(LaunchAgent) 설치됨"
        refreshLaunchAgentState()
        // bootstrap 직후에는 아직 'running' 이 아닐 수 있어 잠시 뒤 한 번 더 본다
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshLaunchAgentState() }
    }

    public func uninstallLaunchAgent() {
        _ = Self.run(["bootout", "gui/\(getuid())/\(Self.launchAgentLabel)"], tool: "/bin/launchctl")
        try? FileManager.default.removeItem(at: Self.launchAgentURL)
        agentStateGeneration += 1
        launchAgentInstalled = false
        launchAgentRunning = false
        lastMessage = "자동 재적용(LaunchAgent) 제거됨"
    }

    /// bootout 뒤 launchd 에서 서비스가 실제로 사라질 때까지 기다린다 (100 ms 간격, 최대 `timeout` 초).
    private static func waitUntilAgentGone(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .failure = run(["print", "gui/\(getuid())/\(launchAgentLabel)"], tool: "/bin/launchctl") { return }
            usleep(100_000)
        }
    }

    /// `launchctl print` 로 LaunchAgent 실행 여부를 조회한다. 자식 프로세스를 띄우므로 수십 ms 걸린다 —
    /// SwiftUI body 에서 직접 부르지 말고 `refreshLaunchAgentState()` 를 쓸 것.
    public static func queryLaunchAgentRunning() -> Bool {
        if case .success(let s) = run(["print", "gui/\(getuid())/\(launchAgentLabel)"], tool: "/bin/launchctl") {
            return s.contains("state = running")
        }
        return false
    }

    /// `launchAgentInstalled` / `launchAgentRunning` 을 백그라운드에서 조회해 메인 스레드에서 반영한다 (값이 바뀔 때만 publish).
    public func refreshLaunchAgentState() {
        let generation = agentStateGeneration   // 메인 스레드에서 읽음
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
            let running = installed && Self.queryLaunchAgentRunning()
            DispatchQueue.main.async {
                guard let self, self.agentStateGeneration == generation else { return }   // 조회 중에 설치/제거가 있었으면 버림
                if self.launchAgentInstalled != installed { self.launchAgentInstalled = installed }
                if self.launchAgentRunning != running { self.launchAgentRunning = running }
            }
        }
    }
}
