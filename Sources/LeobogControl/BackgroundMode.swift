import SwiftUI
import AppKit
import ServiceManagement
import LeobogCore

/// 창을 닫았을 때의 동작 (설정 화면에서 고른다)
enum CloseBehavior: String, CaseIterable, Identifiable {
    /// 창만 닫고 앱은 메뉴 막대 아이콘으로 계속 실행 (Dock 아이콘은 숨긴다)
    case background
    /// 창을 닫으면 앱도 종료
    case quit

    var id: String { rawValue }
    static let key = "closeBehavior"
    static var current: CloseBehavior { CloseBehavior(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .background }
}

/// 로그인 시 자동 실행 (시스템 설정 → 일반 → 로그인 항목의 '로그인 시 열기' 목록에 들어간다)
enum LoginItem {
    /// 처음 실행 때 '자동 실행으로 등록할까요?' 를 이미 물었는가
    static let askedKey = "loginItemAsked"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    static var statusText: String {
        switch status {
        case .enabled: return "등록됨"
        case .requiresApproval: return "승인 필요 — 시스템 설정 → 일반 → 로그인 항목에서 켜 주세요"
        case .notRegistered: return "등록 안 됨"
        case .notFound: return "등록 안 됨"
        @unknown default: return "알 수 없음"
        }
    }

    /// 등록/해제. 실패하면 오류 문구를 돌려준다.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            AppLog.shared.log("login", "로그인 항목 \(on ? "등록" : "해제") → \(statusText)")
            return nil
        } catch {
            AppLog.shared.log("login", "로그인 항목 \(on ? "등록" : "해제") 실패: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// 이번 실행이 로그인 항목으로 시작됐는가. applicationDidFinishLaunching 안에서만 의미가 있다.
    static var wasLaunchedAtLogin: Bool {
        if let e = NSAppleEventManager.shared().currentAppleEvent, e.eventID == kAEOpenApplication,
           e.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        // SMAppService 로 등록한 항목은 위 AppleEvent 표시가 없을 수 있다 → 로그인 직후(로그인 세션 시작 2분 이내) 실행이면 로그인 실행으로 본다
        guard isEnabled,
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first?.processIdentifier,
              let login = processStartDate(pid)
        else { return false }
        return Date().timeIntervalSince(login) < 120
    }

    /// 프로세스 시작 시각 (loginwindow 는 LaunchServices 로 뜬 앱이 아니라 launchDate 가 비어 있다)
    private static func processStartDate(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }
}

/// 메인 창 찾기·열기와 Dock 아이콘 표시 전환
@MainActor
enum MainWindow {
    /// LeobogControlApp 의 WindowGroup id. SwiftUI 창의 identifier 는 "main-1240-AppWindow-1" 처럼 이 값으로 시작한다.
    static let id = "main-1240"

    static func isMain(_ w: NSWindow) -> Bool { w.identifier?.rawValue.hasPrefix(id) ?? false }

    /// 화면에 있거나 Dock 으로 내려간 메인 창
    static var existing: NSWindow? { NSApp.windows.first { isMain($0) && ($0.isVisible || $0.isMiniaturized) } }

    /// 메뉴 막대 아이콘 · 다시 실행 등에서 창을 앞으로 가져온다. 닫혀 있으면 새로 연다.
    static func show(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        if let w = existing {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: id)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 메인 창이 모두 닫혔을 때: 백그라운드 모드면 Dock 아이콘을 숨긴다 (종료 모드는 AppDelegate 가 앱을 끝낸다)
    static func didCloseMainWindow(_ closing: NSWindow) {
        let others = NSApp.windows.contains { $0 !== closing && isMain($0) && ($0.isVisible || $0.isMiniaturized) }
        guard !others, CloseBehavior.current == .background else { return }
        NSApp.setActivationPolicy(.accessory)
        AppLog.shared.log("app", "창 닫힘 → 백그라운드 실행 (메뉴 막대 아이콘)")
    }

    /// 창이 열리면 Dock 아이콘을 다시 보인다
    static func didShowMainWindow() {
        if !startHidden, NSApp.activationPolicy() != .regular {
            AppLog.shared.log("app", "창 열림 → Dock 아이콘 다시 표시")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 로그인 시작·--background 실행에서 첫 창을 띄우지 않고 메뉴 막대로만 시작하기
    static var startHidden = false
}

/// 메뉴 막대 아이콘: 앱 로고(키 격자 + RGB 띠)를 단색 템플릿으로 그린 것. 라이트/다크 메뉴 막대 색을 자동으로 따른다.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 15)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let cols = 6, rows = 3
            let ox: CGFloat = 1, kw: CGFloat = 3.0, kh: CGFloat = 3.2, gap: CGFloat = 0.75
            let barH: CGFloat = 1.6, barY: CGFloat = 0.6
            let oy = barY + barH + 1.4
            for r in 0..<rows {
                var c = 0
                while c < cols {
                    // 아래 줄 가운데 4칸은 스페이스바 하나 (앱 아이콘과 같은 배치)
                    let span = (r == 0 && c == 1) ? 4 : 1
                    let rect = NSRect(x: ox + CGFloat(c) * kw + gap / 2, y: oy + CGFloat(r) * kh + gap / 2,
                                      width: CGFloat(span) * kw - gap, height: kh - gap)
                    NSBezierPath(roundedRect: rect, xRadius: 0.6, yRadius: 0.6).fill()
                    c += span
                }
            }
            let bar = NSRect(x: ox + kw * 0.5, y: barY, width: kw * CGFloat(cols - 1), height: barH)
            NSBezierPath(roundedRect: bar, xRadius: barH / 2, yRadius: barH / 2).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Leobog Control"
        return img
    }()
}

/// 메뉴 막대 아이콘을 눌렀을 때 나오는 메뉴
struct MenuBarMenu: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var ble: BLEBatteryReader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Leobog Control 열기") { MainWindow.show(openWindow) }
        Divider()
        Text(hid.devices.isEmpty ? "키보드 없음" : (hid.isOpen ? "키보드 연결됨" : "키보드 연결됨 · 권한 대기"))
        if let b = ble.percent ?? battery.status?.batteryPercent {
            Text("배터리 \(b)%")
        }
        Divider()
        Button("키 매핑…") { model.section = .remap; MainWindow.show(openWindow) }
        Button("설정…") { model.section = .settings; MainWindow.show(openWindow) }
        Divider()
        Button("Leobog Control 종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
