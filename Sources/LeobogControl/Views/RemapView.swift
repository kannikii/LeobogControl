import SwiftUI
import LeobogCore

struct RemapView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var remap: HidutilRemapService
    @State private var selectedKey: PhysicalKey?
    @State private var alertMessage: String?
    @State private var launchAgentError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("키를 클릭해 다른 키로 바꾸세요. macOS 의 장치별 매핑(hidutil)이라 이 키보드에만 적용되고, Windows 노트북에는 영향이 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                KeyboardDiagramView(keys: model.layoutKeys, pressed: model.pressedKeyIDs, remapped: pendingLabels, selected: selectedKey?.id) { key in
                    if key.usage != nil { selectedKey = key }
                }
                .frame(maxHeight: 300)
                .onChange(of: model.keyboardMode) { _, _ in selectedKey = nil }

                HStack {
                    Button("시스템에 적용") { apply() }.buttonStyle(.borderedProminent).disabled(remap.remaps.isEmpty && remap.activeFromSystem.isEmpty)
                    Button("시스템 매핑 해제") { if case .failure(let e) = remap.clearSystem() { alertMessage = e.localizedDescription } }
                    Button("목록 비우기") { remap.removeAll() }
                    Menu("프리셋") {
                        ForEach(presetsForMode) { p in
                            Button(p.title) { remap.apply(preset: p) }.help(p.detail)
                        }
                    }
                    Spacer()
                    Text(remap.lastMessage).font(.caption).foregroundStyle(.secondary)
                }

                Card(title: "현재 목록 (\(remap.remaps.count)개)", subtitle: "시스템에 적용된 것: \(remap.activeFromSystem.count)개 · 주황색 = 적용 대기/적용됨") {
                    if remap.remaps.isEmpty {
                        Text("매핑이 없습니다. 위 다이어그램에서 키를 클릭하거나 프리셋을 고르세요.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        List(remap.remaps) { r in
                            HStack {
                                Text(r.src.name).frame(width: 220, alignment: .leading)
                                Image(systemName: "arrow.right")
                                Text(r.dst.name).bold()
                                Spacer()
                                if remap.activeFromSystem.contains(r) { Text("적용됨").font(.caption).foregroundStyle(.green) }
                                else { Text("미적용").font(.caption).foregroundStyle(.orange) }
                                Button(role: .destructive) { remap.remove(src: r.src) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            }
                        }.frame(minHeight: 120, maxHeight: 220)
                    }
                }

                Card(title: "재연결 시 자동 재적용", subtitle: "hidutil 매핑은 키보드를 껐다 켜거나 재부팅하면 사라집니다. LaunchAgent 가 키보드가 나타날 때마다 저장된 목록(remaps.json)을 다시 적용합니다 — '시스템에 적용' 이 저장하고, '시스템 매핑 해제'·'목록 비우기' 는 저장 파일도 비웁니다.") {
                    HStack {
                        if remap.launchAgentInstalled {
                            Label("설치됨 (\(remap.launchAgentRunning ? "실행 중" : "중지됨"))", systemImage: "checkmark.circle").foregroundStyle(.green)
                            Button("제거") { remap.uninstallLaunchAgent() }
                            Button("다시 설치") { installAgent() }
                        } else {
                            Label("미설치", systemImage: "circle").foregroundStyle(.secondary)
                            Button("설치") { installAgent() }.buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Text(model.cliPath).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if let e = launchAgentError { Text(e).foregroundStyle(.red).font(.caption) }
                }
            }

            targetPicker.frame(width: 300)
        }
        .padding(16)
        // LaunchAgent 상태는 body 안에서 동기 조회하지 않는다 (launchctl 을 body 에서 돌리면 런루프 재진입 → 레이아웃 메모리 손상 크래시)
        .onAppear { remap.refreshLaunchAgentState() }
        .alert("키 매핑", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("확인") { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
    }

    /// 현재 모드에서 의미 없는 프리셋은 숨긴다 (Mac 모드의 오른쪽 Ctrl → Fn, Windows 모드의 오른쪽 ⌘ → Fn)
    private var presetsForMode: [RemapPreset] {
        let hidden = model.keyboardMode == .mac ? "rctrl-fn" : "rcmd-fn"
        return HidutilRemapService.presets.filter { $0.id != hidden }
    }

    private var pendingLabels: [Int: String] {
        var m: [Int: String] = [:]
        // 기본 usage 로만 매칭 (altUsages 로 매칭하면 펌웨어 Fn 키 위에 바꿀 수 없는 라벨이 붙는다)
        for r in remap.remaps { if let k = model.layoutKeys.first(where: { $0.usage == r.src }) { m[k.id] = r.dst.shortName } }
        return m
    }

    private func apply() {
        do { try remap.save() } catch { alertMessage = "저장 실패: \(error.localizedDescription)" }
        if case .failure(let e) = remap.applyToSystem() { alertMessage = e.localizedDescription }
    }

    private func installAgent() {
        do { try remap.save(); try remap.installLaunchAgent(cliPath: model.cliPath); launchAgentError = nil }
        catch { launchAgentError = "설치 실패: \(error.localizedDescription)" }
    }

    @ViewBuilder
    private var targetPicker: some View {
        Card(title: selectedKey.map { "\($0.displayLabel) 키를 바꾸기" } ?? "바꿀 키를 선택하세요",
             subtitle: selectedKey?.usage.map { "원래: \($0.name)" }) {
            if let key = selectedKey, let src = key.usage {
                if let cur = remap.mapping(for: src) {
                    HStack {
                        Text("현재: \(cur.name)").font(.callout)
                        Spacer()
                        Button("원래대로") { remap.remove(src: src) }
                    }
                }
                if key.id == 76, model.keyboardMode == .mac {
                    Text("스페이스 바로 오른쪽 키(오른쪽 ⌘)입니다. 아래에서 Fn🌐 를 고르면 macOS Fn 키(받아쓰기·이모지·fn 조합)로 동작합니다. 키보드 자체 Fn 키(그 오른쪽)는 그대로입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(RemapTargets.groups) { g in
                            Text(g.title).font(.caption.bold()).foregroundStyle(.secondary)
                            FlowLayout(spacing: 4) {
                                ForEach(g.items, id: \.self) { u in
                                    Button(u.shortName) { remap.set(KeyRemap(src: src, dst: u)) }
                                        .buttonStyle(.bordered)
                                        .tint(remap.mapping(for: src) == u ? .orange : nil)
                                        .help(u.name)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("다이어그램에서 키를 클릭하면 여기에서 새 기능을 고를 수 있습니다. 키보드 자체 Fn 키와 노브는 펌웨어 전용이라 바꿀 수 없습니다. Mac 모드에서 스페이스 바로 오른쪽 키(오른쪽 ⌘)는 바꿀 수 있고, 프리셋 '오른쪽 ⌘ → Fn(🌐)' 로 macOS Fn 키를 만들 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// 간단한 줄바꿈 레이아웃
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
