import SwiftUI
import AppKit
import LeobogCore

/// 정상 종료 표식 처리. 종료(⌘Q·메뉴·SIGTERM)는 여기서 running.json 을 지우고, 크래시는 못 지우므로 다음 실행에서 구분된다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // pkill / launchctl 의 SIGTERM 도 정상 종료로 처리 (기본 동작은 즉시 종료라 표식이 남아 '강제 종료' 로 보인다)
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler {
            AppLog.shared.log("app", "SIGTERM 수신 → 정상 종료")
            NSApp.terminate(nil)
        }
        src.resume()
        sigterm = src

        // 로그인 항목으로 시작했거나 --background 로 띄웠으면(백그라운드 모드일 때만) 창 없이 메뉴 막대 아이콘으로 대기
        let args = ProcessInfo.processInfo.arguments
        let atLogin = LoginItem.wasLaunchedAtLogin
        if CloseBehavior.current == .background, atLogin || args.contains("--background") {
            NSApp.setActivationPolicy(.accessory)
            AppLog.shared.log("app", "백그라운드로 시작 (\(atLogin ? "로그인 항목" : "--background"))")
            // SwiftUI 가 이 시점보다 먼저 첫 창을 만들었으면 바로 닫고, 아직이면 ContentView.onAppear 가 닫는다
            let early = NSApp.windows.filter(MainWindow.isMain)
            MainActor.assumeIsolated {
                if early.isEmpty { MainWindow.startHidden = true } else { early.forEach { $0.close() } }
            }
        }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { if MainWindow.isMain(w) { MainWindow.didCloseMainWindow(w) } }
        }
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { if MainWindow.isMain(w) { MainWindow.didShowMainWindow() } }
        }
    }

    /// Dock·Finder·open 으로 다시 열 때. 보이는 창이 없으면 숨겨 둔 메인 창을 앞으로, 그것도 없으면 SwiftUI 가 새 창을 연다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            let mains = NSApp.windows.filter(MainWindow.isMain)
            AppLog.shared.log("app", "다시 열기 요청: 보이는 창 \(flag) · 메인 창 \(mains.map { "\($0.identifier?.rawValue ?? "?") visible=\($0.isVisible)" })")
            if !flag {
                NSApp.setActivationPolicy(.regular)
                if let w = mains.first { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return false }
                NSApp.activate(ignoringOtherApps: true)
            }
            return true
        }
    }

    /// '그냥 끄기' 모드에서만 마지막 창을 닫을 때 앱을 끝낸다. 백그라운드 모드는 메뉴 막대 아이콘으로 남는다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        CloseBehavior.current == .quit
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.shared.log("app", "정상 종료")
        RunMarker.endSession()
    }
}

@main
struct LeobogControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage(CloseBehavior.key) private var closeBehavior: CloseBehavior = .background

    var body: some Scene {
        // id 를 주면 창 프레임 자동 저장 키가 바뀌어, 예전 기본 크기(1120×740)로 저장된 프레임 대신 새 defaultSize 가 적용된다
        WindowGroup("Leobog Control", id: MainWindow.id) {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.hid)
                .environmentObject(model.compx)
                .environmentObject(model.remap)
                .environmentObject(model.fn)
                .environmentObject(model.battery)
                .environmentObject(model.bleBattery)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1240, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("설정…") {
                    model.section = .settings
                    MainWindow.existing?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut(",")
            }
        }

        // 백그라운드 실행 모드: 상단 메뉴 막대의 작은 로고 아이콘 (열기 · 상태 · 종료)
        MenuBarExtra(isInserted: Binding(get: { closeBehavior == .background }, set: { _ in })) {
            MenuBarMenu()
                .environmentObject(model)
                .environmentObject(model.hid)
                .environmentObject(model.battery)
                .environmentObject(model.bleBattery)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}
