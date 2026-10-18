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

    var body: some Scene {
        WindowGroup("Leobog Control") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.hid)
                .environmentObject(model.compx)
                .environmentObject(model.remap)
                .environmentObject(model.fn)
                .environmentObject(model.battery)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
