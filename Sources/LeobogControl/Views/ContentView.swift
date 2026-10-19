import SwiftUI
import LeobogCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var battery: BatteryService

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $model.section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { statusFooter }
        } detail: {
            VStack(spacing: 0) {
                if model.lastRun.outcome == .crashed, !model.crashBannerDismissed { crashBanner }
                detailContent
            }
            .navigationTitle(model.section.rawValue)
        }
        .onAppear { AutomationHook.start(model: model) }
    }

    private var crashBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("지난 실행이 크래시로 끝났습니다").font(.callout.bold())
                Text(model.lastRun.report?.verdict ?? "").font(.caption)
            }
            Spacer()
            Button("자세히") { model.section = .crash }
            Button { model.crashBannerDismissed = true } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
    }

    private var detailContent: some View {
            Group {
                switch model.section {
                case .device: DeviceView()
                case .tester: KeyTesterView()
                case .remap: RemapView()
                case .shortcuts: ShortcutsView()
                case .fnkeys: FnKeysView()
                case .lighting: LightingView()
                case .diagnostics: DiagnosticsView()
                case .crash: CrashMonitorView()
                }
            }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(hid.devices.isEmpty ? Color.red : (hid.isOpen ? Color.green : Color.orange)).frame(width: 8, height: 8)
                Text(hid.devices.isEmpty ? "키보드 없음" : (hid.isOpen ? "연결됨 · 입력 감시 중" : "연결됨 · 권한 대기"))
                    .font(.caption)
            }
            if let b = battery.status?.batteryPercent {
                HStack(spacing: 4) {
                    Image(systemName: b > 80 ? "battery.100" : b > 50 ? "battery.75" : b > 25 ? "battery.50" : "battery.25")
                    Text("배터리 \(b)%")
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

/// 공용: 섹션 카드
struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let s = subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }.font(.callout)
    }
}
