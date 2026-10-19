import SwiftUI
import LeobogCore

struct ShortcutsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @State private var category = FnLayerReference.categories[0]
    @State private var hover: FnShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("키보드 펌웨어의 Fn 레이어입니다 (공식 LEOBOG ONE 드라이버의 Hi8SE 설정 + Leobog 설명서 + 실측). Fn 키는 Mac 모드에서 스페이스 오른쪽 두 번째, Windows 모드에서 스페이스 바로 오른쪽이며 Fn + M 으로 모드를 전환합니다. 목록 위에 마우스를 올리면 다이어그램에서 키가 강조되고, 실제로 눌러 보면 '최근 입력' 에 도착한 usage 가 보입니다. '추정' 표시는 드라이버에 코드만 있고 의미는 확인되지 않은 항목입니다.")
                .font(.callout).foregroundStyle(.secondary)
            KeyboardDiagramView(keys: model.layoutKeys, pressed: model.pressedKeyIDs, highlighted: Set([hover?.keyID, Hi8SELayout.fnKey(for: model.keyboardMode).id].compactMap { $0 }))
                .frame(maxHeight: 240)

            HStack {
                Picker("분류", selection: $category) {
                    ForEach(FnLayerReference.categories, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Text("키보드 모드").foregroundStyle(.secondary).fixedSize()
                Picker("키보드 모드", selection: $model.keyboardMode) {
                    ForEach(KeyboardMode.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 200).help("키보드에서 Fn + M 으로 전환하는 펌웨어 모드")
            }

            Table(FnLayerReference.shortcuts(in: category)) {
                TableColumn("조합") { s in
                    Text(s.combo).bold().onHover { if $0 { hover = s } }
                }.width(min: 110, ideal: 130)
                TableColumn("Mac 모드") { s in
                    HStack {
                        Text(s.macAction)
                        if !s.certain { Text("추정").font(.caption2).padding(.horizontal, 4).background(Color.orange.opacity(0.2)).cornerRadius(3) }
                    }.onHover { if $0 { hover = s } }
                }
                TableColumn("Windows 모드") { s in Text(s.winAction).foregroundStyle(.secondary).onHover { if $0 { hover = s } } }
                TableColumn("Mac 에 도착하는 usage") { s in
                    if let e = s.expected {
                        HStack(spacing: 4) {
                            Text(e.hexString).font(.caption.monospaced())
                            if seen(e) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("이번 세션에서 실제로 확인됨") }
                        }
                    } else { Text("—").foregroundStyle(.tertiary) }
                }.width(min: 150, ideal: 170)
                TableColumn("출처") { s in Text(s.source.rawValue).font(.caption).foregroundStyle(.secondary) }.width(min: 120, ideal: 140)
            }

            HStack {
                Text("최근 입력:").font(.caption).foregroundStyle(.secondary)
                ForEach(model.displayedEvents.suffix(8).filter { $0.isDown }) { ev in
                    Text(ev.usage.shortName).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15)).cornerRadius(4)
                }
                Spacer()
                Text("Mac 전용 단축키(⌘ 조합 등)는 macOS 시스템 설정 › 키보드 › 키보드 단축키에서 관리됩니다.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    private func seen(_ u: HIDUsage) -> Bool { model.displayedEvents.contains { $0.usage == u } }
}
