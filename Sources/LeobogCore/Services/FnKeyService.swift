import Foundation
import Combine

/// macOS 펑션키 동작 설정 (`com.apple.keyboard.fnState`).
/// - true  : F1–F12 를 표준 기능 키로 사용 (미디어 동작은 Fn 과 함께)
/// - false : F1–F12 가 밝기/볼륨 등 특수 기능 (기본값)
/// 주의: 이 설정은 macOS 가 'Fn 키를 인식하는' 키보드에 적용된다. Leobog 키보드는 Fn 조합을 펌웨어에서 처리해
/// Mac 모드에서는 Fn+F7 등이 곧바로 미디어 usage 로 전송되므로, 보통 이 설정과 무관하게 동작한다.
public final class FnKeyService: ObservableObject {
    @Published public private(set) var standardFunctionKeys: Bool? = nil   // nil = 설정 안 됨(기본 false)
    @Published public private(set) var lastMessage = ""

    public init() { refresh() }

    public func refresh() {
        switch HidutilRemapService.run(["read", "-g", "com.apple.keyboard.fnState"], tool: "/usr/bin/defaults") {
        case .success(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            standardFunctionKeys = (t == "1" || t.lowercased() == "true")
        case .failure:
            standardFunctionKeys = nil
        }
    }

    public func set(standardFunctionKeys on: Bool) {
        let r = HidutilRemapService.run(["write", "-g", "com.apple.keyboard.fnState", "-bool", on ? "true" : "false"], tool: "/usr/bin/defaults")
        switch r {
        case .success:
            // 현재 세션에 바로 반영되도록 환경설정 변경 알림
            let center = CFNotificationCenterGetDistributedCenter()
            CFNotificationCenterPostNotification(center, CFNotificationName("com.apple.keyboard.fnstatedidchange" as CFString), nil, nil, true)
            lastMessage = on ? "F1–F12 를 표준 기능 키로 사용 (적용에 로그아웃이 필요할 수 있음)" : "F1–F12 를 특수 기능 키로 사용 (적용에 로그아웃이 필요할 수 있음)"
        case .failure(let e):
            lastMessage = "설정 실패: \(e.localizedDescription)"
        }
        refresh()
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    public static let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
}
