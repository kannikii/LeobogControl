import SwiftUI
import AppKit
import LeobogCore

/// 크래시 · 메모리 모니터: 직전 실행 판정, 크래시 리포트 목록과 원인 판정, 실시간 메모리, 앱 로그
struct CrashMonitorView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @State private var reports: [CrashReport] = []
    @State private var selected: CrashReport?
    @State private var memory = MemoryStats.current()
    @State private var logLines: [String] = []
    @State private var peakFootprint: UInt64 = 0
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                lastRunCard
                reportsCard
                logCard
            }
            VStack(alignment: .leading, spacing: 12) {
                memoryCard
                hidCard
                helpCard
            }
            .frame(width: 360)
        }
        .padding(16)
        .onAppear { refresh() }
        .onReceive(timer) { _ in tick() }
    }

    private func refresh() {
        reports = CrashReportReader.loadAll()
        if selected == nil { selected = reports.first }
        tick()
    }

    private func tick() {
        memory = MemoryStats.current()
        peakFootprint = max(peakFootprint, memory.footprintBytes)
        logLines = AppLog.shared.recentLines(120)
    }

    // MARK: 카드

    private var lastRunCard: some View {
        Card(title: "직전 실행", subtitle: "앱 시작 때 실행 표식(running.json)과 크래시 리포트를 대조해 판정") {
            HStack(spacing: 8) {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                Text(model.lastRun.message).font(.callout)
            }
            if let r = model.lastRun.report {
                Text("리포트: \(r.url.lastPathComponent)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var statusIcon: String {
        switch model.lastRun.outcome {
        case .cleanOrFirst: return "checkmark.circle"
        case .crashed: return "exclamationmark.triangle.fill"
        case .killed: return "stop.circle"
        }
    }
    private var statusColor: Color {
        switch model.lastRun.outcome {
        case .cleanOrFirst: return .green
        case .crashed: return .red
        case .killed: return .orange
        }
    }

    private var reportsCard: some View {
        Card(title: "크래시 리포트 (\(reports.count)건)", subtitle: "~/Library/Logs/DiagnosticReports 와 /Library/Logs/DiagnosticReports 의 LeobogControl-*.ips · JetsamEvent-*.ips") {
            HStack {
                Button("다시 읽기") { refresh() }
                Button("Finder 에서 열기") {
                    NSWorkspace.shared.activateFileViewerSelecting([CrashReportReader.directories[0]])
                }
                Spacer()
            }
            if reports.isEmpty {
                Text("이 앱의 크래시 리포트가 없습니다.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    List(reports, selection: Binding(get: { selected?.id }, set: { id in selected = reports.first { $0.id == id } })) { r in
                        HStack(spacing: 6) {
                            Image(systemName: r.isMemoryRelated ? "memorychip" : "ladybug")
                                .foregroundStyle(r.isMemoryRelated ? .orange : .red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(DateFormatter.shortKR.string(from: r.date)).font(.caption.monospaced())
                                Text(r.exceptionType.isEmpty ? r.terminationIndicator : "\(r.exceptionType) \(r.signal)").font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(r.id)
                    }
                    .frame(minHeight: 180, maxHeight: 260)
                    .frame(width: 220)
                    if let r = selected { reportDetail(r) } else { Spacer() }
                }
            }
        }
    }

    @ViewBuilder
    private func reportDetail(_ r: CrashReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(r.verdict).font(.callout.bold()).foregroundStyle(r.isMemoryRelated ? .orange : .red)
                InfoRow(label: "예외", value: [r.exceptionType, r.signal].filter { !$0.isEmpty }.joined(separator: " · "))
                if !r.subtype.isEmpty { InfoRow(label: "세부", value: r.subtype) }
                InfoRow(label: "종료", value: [r.terminationNamespace, r.terminationIndicator, r.terminationBy.isEmpty ? "" : "by " + r.terminationBy].filter { !$0.isEmpty }.joined(separator: " · "))
                if r.pid > 0 { InfoRow(label: "pid", value: String(r.pid)) }
                if !r.processLaunch.isEmpty { InfoRow(label: "앱 시작", value: r.processLaunch) }
                if !r.osVersion.isEmpty { InfoRow(label: "macOS", value: r.osVersion) }
                if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(.secondary) }
                if !r.topFrames.isEmpty {
                    Text("죽은 스레드 (\(r.faultingThreadName)) 상위 프레임").font(.caption.bold()).padding(.top, 4)
                    ForEach(Array(r.topFrames.enumerated()), id: \.offset) { i, f in
                        Text("\(i)  \(f)").font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                if !r.mallocSummary.isEmpty {
                    Text("크래시 당시 메모리(vmSummary)").font(.caption.bold()).padding(.top, 4)
                    Text(r.mallocSummary).font(.caption2.monospaced()).textSelection(.enabled)
                }
                Button("리포트 파일 열기") { NSWorkspace.shared.open(r.url) }.font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 180, maxHeight: 260)
    }

    private var logCard: some View {
        Card(title: "앱 로그 (브레드크럼)", subtitle: AppLog.fileURL.path) {
            HStack {
                Button("새로고침") { tick() }
                Button("로그 비우기") { AppLog.shared.clear(); AppLog.shared.log("app", "로그 비움"); tick() }
                Button("Finder 에서 열기") { NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL]) }
                Spacer()
                Text("크래시 직전 마지막 줄이 '무엇을 하다 죽었는지' 입니다").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.caption2.monospaced()).textSelection(.enabled)
                                .foregroundStyle(line.contains("경고") || line.contains("크래시") ? Color.red : Color.primary)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 220)
                .onChange(of: logLines.count) { _, n in if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) } }
            }
        }
    }

    private var memoryCard: some View {
        Card(title: "실시간 메모리", subtitle: "2초마다 갱신 · task_info / host_statistics / kern.memorystatus") {
            InfoRow(label: "이 앱 footprint", value: MemoryStats.format(memory.footprintBytes))
            InfoRow(label: "이 앱 상주(RSS)", value: MemoryStats.format(memory.residentBytes))
            InfoRow(label: "세션 최고 footprint", value: MemoryStats.format(peakFootprint))
            InfoRow(label: "시스템 총 메모리", value: MemoryStats.format(memory.systemTotalBytes))
            InfoRow(label: "시스템 여유(free+inactive)", value: MemoryStats.format(memory.systemFreeBytes))
            if let p = memory.systemAvailablePercent { InfoRow(label: "사용 가능 비율", value: "\(p)%") }
            HStack(alignment: .top) {
                Text("메모리 압박").foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                Text(memory.pressureLabel).foregroundStyle(pressureColor)
                Spacer()
            }.font(.callout)
            Text("이 앱이 메모리 때문에 죽으려면 footprint 가 수 GB 에 이르거나 압박이 '위험' 이어야 합니다. 그 경우 리포트에 JETSAM / EXC_RESOURCE 가 남고 위 목록에서 주황색(메모리칩)으로 표시됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pressureColor: Color {
        switch memory.pressureLevel {
        case 1: return .green
        case 2: return .orange
        case 4: return .red
        default: return .secondary
        }
    }

    private var hidCard: some View {
        Card(title: "HID 리포트 버퍼", subtitle: "인터페이스별 입력 리포트 통계 · 잘림 0 이어야 정상") {
            if hid.reportStats.isEmpty {
                Text("아직 받은 리포트가 없습니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(hid.reportStats.keys.sorted(), id: \.self) { id in
                    let st = hid.reportStats[id]!
                    HStack {
                        Text(String(format: "ID 0x%02X", id)).font(.caption.monospaced())
                        Text("\(st.count)회 · 최대 \(st.maxLength)B").font(.caption)
                        if st.overrunCount > 0 { Text("잘림 \(st.overrunCount)").font(.caption).foregroundStyle(.red) }
                        Spacer()
                    }
                }
            }
            if let info = hid.deviceInfo() {
                Text("대표 인터페이스 최대 입력 \(info.maxInput)B / 출력 \(info.maxOutput)B → 버퍼 \(max(HIDDeviceManager.minReportBufferSize, info.maxInput + 1 + HIDDeviceManager.reportBufferMargin))B")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var helpCard: some View {
        Card(title: "판정 기준") {
            Text("• EXC_BAD_ACCESS / SIGSEGV / SIGBUS → 소프트웨어 버그(잘못된 메모리 접근). 메모리 부족이 아닙니다.\n• EXC_BREAKPOINT → Swift 런타임 트랩.\n• EXC_CRASH / SIGABRT → abort.\n• EXC_RESOURCE(MEMORY), namespace JETSAM, JetsamEvent 리포트 → 메모리 부족·초과로 macOS 가 종료.\n• 터미널: scripts/crash-monitor.sh 로 같은 내용을 실시간으로 볼 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
