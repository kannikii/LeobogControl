import SwiftUI
import LeobogCore

struct KeyTesterView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var remap: HidutilRemapService
    @State private var everPressed: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if hid.isOpen {
                    Label("HID 입력 리포트로 실시간 확인 중 — 아무 키나 눌러 보세요 (Fn 조합, 노브 포함). 방향키·Tab 도 이 화면이 받습니다 (⌘ 조합 제외)", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
                } else {
                    Label("권한 없음: 이 창이 앞에 있을 때만 키를 볼 수 있습니다 (NSEvent). 전체 기능은 입력 모니터링 권한 허용 후.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Spacer()
                Picker("키보드 모드", selection: $model.keyboardMode) {
                    ForEach(KeyboardMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 210)
                .help("키보드에서 Fn + M 으로 전환하는 펌웨어 모드. 하단열(⌥ / ⌘ / Fn) 배열이 달라집니다.")
                Button("기록 지우기") { model.clearEvents(); everPressed.removeAll() }
            }.font(.callout)

            KeyboardDiagramView(keys: model.layoutKeys, pressed: model.pressedKeyIDs, remapped: remapLabels, highlighted: everPressed)
                .frame(maxHeight: 330)
                .onChange(of: model.pressedKeyIDs) { _, new in everPressed.formUnion(new) }
                .onChange(of: model.keyboardMode) { _, _ in everPressed.removeAll() }

            HStack(alignment: .top, spacing: 12) {
                Card(title: "최근 입력", subtitle: "usage page : usage · 이름 · 눌림/뗌") {
                    ScrollViewReader { proxy in
                        List(model.displayedEvents.suffix(60).reversed()) { ev in
                            HStack {
                                Text(ev.timestamp.formatted(date: .omitted, time: .standard)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(ev.usage.hexString).font(.caption.monospaced())
                                Text(ev.usage.name).bold()
                                if let label = model.eventLabel(for: ev.usage) { Text(label).font(.caption).foregroundStyle(.secondary) }
                                if let m = remap.mapping(for: ev.usage) { Text("→ \(m.shortName) (매핑)").foregroundStyle(.orange).font(.caption) }
                                Spacer()
                                Text(ev.isDown ? "눌림" : "뗌").foregroundStyle(ev.isDown ? .green : .secondary).font(.caption)
                            }.id(ev.id)
                        }
                        .frame(minHeight: 160)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Card(title: "키보드 자체 Fn 키", subtitle: fnKeyPosition) {
                        Text("펌웨어가 직접 처리하는 키라 혼자 누르면 맥으로 아무 입력도 오지 않습니다 — 다이어그램에 안 켜지는 것이 정상입니다. 조합으로만 보입니다:")
                            .font(.caption)
                        Text("• Fn + F1–F12 → 밝기·미디어 (예: Fn+F8 재생/일시정지). Fn 키와 그 키가 함께 켜집니다.\n• Fn + M → Mac ↔ Windows 모드 전환. 맥에는 아무것도 오지 않으니 위의 모드 선택기도 같이 바꿔 주세요.\n• Fn + U/I/O, Fn + Del/End → Print Screen·Scroll Lock·Pause·Insert·Home. 전체 목록은 '단축키 · Fn 레이어'.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !hid.isOpen {
                            Text("입력 모니터링 권한이 없어 Fn 조합을 확인할 수 없습니다 (HID 리포트가 필요합니다).")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Text(model.fnComboCount > 0
                                 ? "이번 세션 Fn 조합 감지: \(model.fnComboCount)회 — Fn 키는 정상입니다."
                                 : "아직 Fn 조합이 들어오지 않았습니다. Fn 을 누른 채 F8 을 눌러 보세요.")
                                .font(.caption).foregroundStyle(model.fnComboCount > 0 ? .green : .secondary)
                        }
                    }
                    Card(title: "눌러 본 키", subtitle: "노란 테두리 = 이번 세션에서 한 번이라도 눌린 키") {
                        let plain = model.layoutKeys.filter { $0.kind == .key }
                        let unpressed = plain.filter { !everPressed.contains($0.id) }
                        Text("\(plain.count - unpressed.count) / \(plain.count) 키 확인됨")
                        if everPressed.count > 0 && !unpressed.isEmpty {
                            Text("아직 안 눌린 키: " + unpressed.map { $0.displayLabel }.joined(separator: " "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        }
                        Text(bottomRowNote).font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "배열표에 없는 입력", subtitle: "현재 모드의 하단열 배열과 맞지 않는 usage") {
                        if model.unmatchedUsages.isEmpty {
                            Text("없음").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(model.unmatchedUsages, id: \.self) { u in
                                HStack(spacing: 6) {
                                    Text(u.hexString).font(.caption.monospaced())
                                    Text(u.name).font(.caption).bold()
                                }
                            }
                        }
                        if model.keyboardMode == .mac, model.loneRightCtrlCount > 0 {
                            Text("오른쪽 Ctrl(0xE4) 이 다른 키 없이 혼자 눌림: \(model.loneRightCtrlCount)회").font(.caption).foregroundStyle(.secondary)
                        }
                        if model.modeMismatchSuspected {
                            Text(mismatchHint).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .frame(width: 320)
            }
        }
        .padding(16)
    }

    private var fnKeyPosition: String {
        switch model.keyboardMode {
        case .mac: return "Mac 모드: 스페이스 오른쪽 두 번째 키 (오른쪽 ⌘ 의 오른쪽)"
        case .windows: return "Windows 모드: 스페이스 바로 오른쪽 키"
        }
    }

    private var bottomRowNote: String {
        switch model.keyboardMode {
        case .mac:
            return "Mac 모드 하단열: ⌃ · ⌥ · ⌘ · Space · 오른쪽 ⌘ · Fn. Fn 키는 펌웨어 전용이라 '눌러 본 키' 집계에서 빼며, 조합 중에 R⌃(0xE4) 로 보일 때가 있습니다. 노브는 볼륨 usage 로 보입니다."
        case .windows:
            return "Windows 모드 하단열: Ctrl · Win · Alt · Space · Fn · Ctrl. Fn 키는 펌웨어 전용이라 '눌러 본 키' 집계에서 뺍니다."
        }
    }

    private var mismatchHint: String {
        switch model.keyboardMode {
        case .mac: return "오른쪽 Ctrl 이 혼자 눌린 것으로 반복해서 보이거나 ⌥/⌘ 위치가 바뀌어 보이면 키보드가 Windows 모드일 수 있습니다. 키보드에서 Fn + M 을 누르거나 위에서 모드를 바꾸세요."
        case .windows: return "오른쪽 ⌘(0xE7) 이 보이면 키보드가 Mac 모드일 수 있습니다. 키보드에서 Fn + M 을 누르거나 위에서 모드를 바꾸세요."
        }
    }

    private var remapLabels: [Int: String] {
        var m: [Int: String] = [:]
        for r in remap.activeFromSystem {
            if let k = model.layoutKeys.first(where: { $0.usage == r.src }) { m[k.id] = r.dst.shortName }
        }
        return m
    }
}
