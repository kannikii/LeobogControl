import SwiftUI
import AppKit
import ServiceManagement
import LeobogCore

/// 앱 설정: 창 닫기 동작(백그라운드 실행 / 그냥 끄기)과 로그인 시 자동 실행
struct SettingsView: View {
    @AppStorage(CloseBehavior.key) private var closeBehavior: CloseBehavior = .background
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card(title: "창을 닫을 때", subtitle: "빨간 닫기 버튼(⌘W)을 눌렀을 때의 동작입니다. 앱을 완전히 끄려면 언제든 ⌘Q 를 누르세요.") {
                    Picker("", selection: $closeBehavior) {
                        Text("백그라운드에서 계속 실행 — 메뉴 막대에 아이콘 표시").tag(CloseBehavior.background)
                        Text("그냥 끄기 — 앱 종료").tag(CloseBehavior.quit)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    HStack(spacing: 6) {
                        Image(nsImage: MenuBarIcon.image)
                        Text(closeBehavior == .background
                             ? "창을 닫아도 키보드 연결·배터리 감시가 계속되고, 메뉴 막대 아이콘으로 다시 열거나 종료할 수 있습니다. 창이 없을 땐 Dock 아이콘이 숨겨집니다."
                             : "창을 닫으면 앱이 종료됩니다. 키 매핑은 앱과 별개로 로그인 시 자동 적용되므로 영향이 없습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Card(title: "로그인 시 자동 실행", subtitle: "Mac 을 켜고 로그인할 때마다 Leobog Control 을 자동으로 실행합니다 (시스템 설정 → 일반 → 로그인 항목).") {
                    Toggle("로그인 시 Leobog Control 열기", isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: { on in
                            loginError = LoginItem.set(on)
                            loginStatus = LoginItem.status
                        }))
                    .toggleStyle(.switch)
                    InfoRow(label: "상태", value: LoginItem.statusText)
                    if closeBehavior == .background {
                        Text("백그라운드 실행 모드에서는 로그인 시 창 없이 메뉴 막대 아이콘으로만 시작합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = loginError {
                        Text("변경 실패: \(e)").font(.caption).foregroundStyle(.red)
                    }
                    if loginStatus == .requiresApproval {
                        Button("로그인 항목 설정 열기…") { LoginItem.openSystemSettings() }
                    }
                }
            }
            .padding(16)
        }
        .onAppear { loginStatus = LoginItem.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = LoginItem.status
        }
    }
}
