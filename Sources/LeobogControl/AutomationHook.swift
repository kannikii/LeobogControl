import SwiftUI
import AppKit
import LeobogCore

/// 문서용 스크린샷 자동화 훅. `open -a "Leobog Control" --args -automation YES` 로 띄웠을 때만 켜지며,
/// 분산 알림 `com.leobog.control.automation` 의 userInfo 로 화면 전환·창 크기 조절·자기 창 캡처를 한다.
///   section : SidebarSection.rawValue (예: "키 매핑")
///   size    : "1120x740" (창 내용 크기)
///   capture : PNG 저장 경로 — 자기 창만 캡처하므로 화면 기록 권한이 필요 없다
/// 일반 실행에서는 알림을 구독하지 않는다.
enum AutomationHook {
    static let name = Notification.Name("com.leobog.control.automation")
    static var enabled: Bool { CommandLine.arguments.contains("-automation") }

    private static var observer: Observer?

    /// 앱 시작 시 한 번 호출. SwiftUI 의 onReceive 대신 selector 로 직접 등록하는 이유: 앱이 비활성(다른 앱이 앞)일 때
    /// AppKit 이 분산 알림 센터를 suspend 하는데, `.deliverImmediately` 로 등록해야 그 상태에서도 바로 받는다.
    @MainActor
    static func start(model: AppModel) {
        AppLog.shared.log("automation", "start 호출: enabled=\(enabled) args=\(CommandLine.arguments.dropFirst().joined(separator: " "))")
        guard enabled, observer == nil else { return }
        let o = Observer(model: model)
        DistributedNotificationCenter.default().addObserver(o, selector: #selector(Observer.receive(_:)), name: name, object: nil, suspensionBehavior: .deliverImmediately)
        observer = o
        AppLog.shared.log("automation", "자동화 훅 등록 (\(name.rawValue))")
    }

    @MainActor
    private final class Observer: NSObject {
        let model: AppModel
        init(model: AppModel) { self.model = model }
        @objc func receive(_ n: Notification) { AutomationHook.handle(n, model: model) }
    }

    @MainActor
    static func handle(_ n: Notification, model: AppModel) {
        guard enabled, let info = n.userInfo else { return }
        if let raw = info["section"] as? String, let s = SidebarSection(rawValue: raw) { model.section = s }
        let window = NSApp.windows.first { $0.isVisible && $0.contentView != nil && !$0.title.isEmpty } ?? NSApp.windows.first { $0.isVisible }
        if let size = info["size"] as? String, let w = window {
            let p = size.split(separator: "x").compactMap { Double($0) }
            if p.count == 2 { w.setContentSize(NSSize(width: p[0], height: p[1])); w.center() }
        }
        guard let path = info["capture"] as? String, let w = window else { return }
        // 화면 전환 애니메이션이 끝난 뒤 캡처
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { capture(w, to: path) }
    }

    @MainActor
    private static func capture(_ w: NSWindow, to path: String) {
        let id = CGWindowID(w.windowNumber)
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else {
            AppLog.shared.log("automation", "캡처 실패: \(path)"); return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do { try data.write(to: URL(fileURLWithPath: path)); AppLog.shared.log("automation", "캡처 저장: \(path)") }
        catch { AppLog.shared.log("automation", "캡처 저장 실패: \(error)") }
    }
}
