import SwiftUI
import AppKit
import LeobogCore

struct FnKeysView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var fn: FnKeyService
    @EnvironmentObject var remap: HidutilRemapService
    @State private var toggle = false

    private struct FKey: Identifiable { let id: Int; let usage: UInt32 }
    private let fRow: [FKey] = [FKey(id: 2, usage: 0x3A), FKey(id: 3, usage: 0x3B), FKey(id: 4, usage: 0x3C), FKey(id: 5, usage: 0x3D), FKey(id: 6, usage: 0x3E), FKey(id: 7, usage: 0x3F),
                                FKey(id: 8, usage: 0x40), FKey(id: 9, usage: 0x41), FKey(id: 10, usage: 0x42), FKey(id: 11, usage: 0x43), FKey(id: 12, usage: 0x44), FKey(id: 13, usage: 0x45)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "F1–F12 가 지금 어떻게 동작하나", subtitle: "이 키보드는 Fn 조합을 펌웨어에서 처리합니다. Fn 없이 누르면 F1–F12, Fn 과 함께 누르면 아래 표의 기능이 '미디어 키 usage' 로 맥에 전달됩니다.") {
                    KeyboardDiagramView(keys: model.layoutKeys, pressed: model.pressedKeyIDs, remapped: fRowRemapLabels, highlighted: Set(fRow.map { $0.id }))
                        .frame(maxHeight: 200)
                    Table(fRow) {
                        TableColumn("키") { r in Text(Hi8SELayout.byID(for: model.keyboardMode)[r.id]?.label ?? "").bold() }.width(50)
                        TableColumn("기본 (Fn 없이)") { r in
                            let u = HIDUsage.keyboard(r.usage)
                            if let m = remap.activeFromSystem.first(where: { $0.src == u }) { Text("\(m.dst.name)  (매핑됨)").foregroundStyle(.orange) }
                            else { Text(u.name) }
                        }
                        TableColumn("Fn + 키 (펌웨어)") { r in
                            Text(FnLayerReference.shortcuts.first { $0.keyID == r.id }?.macAction ?? "—")
                        }
                    }.frame(height: 330)
                }

                Card(title: "Fn 없이 바로 미디어 키로 쓰기", subtitle: "Mac 내장 키보드처럼 F7–F12 를 누르면 곧바로 미디어 기능이 되도록 hidutil 매핑을 적용합니다. 펌웨어는 건드리지 않습니다.") {
                    HStack {
                        Button("F7–F12 → 미디어 키 적용") {
                            remap.apply(preset: HidutilRemapService.presets.first { $0.id == "f-media" }!)
                            try? remap.save(); _ = remap.applyToSystem()
                        }.buttonStyle(.borderedProminent)
                        Button("F1/F2 → 화면 밝기 적용") {
                            remap.apply(preset: HidutilRemapService.presets.first { $0.id == "f-bright" }!)
                            try? remap.save(); _ = remap.applyToSystem()
                        }
                        Button("F열 매핑 되돌리기") {
                            for k in fRow { remap.remove(src: .keyboard(k.usage)) }
                            try? remap.save(); _ = remap.applyToSystem()
                        }
                        Spacer()
                        Text(remap.lastMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("적용 후에는 '키 매핑' 화면에서 재연결 자동 재적용(LaunchAgent)을 설치해 두면 키보드를 다시 켜도 유지됩니다.").font(.caption).foregroundStyle(.secondary)
                }

                Card(title: "macOS 펑션키 설정 (com.apple.keyboard.fnState)", subtitle: "시스템 설정 › 키보드 › 'F1, F2 등의 키를 표준 기능 키로 사용' 과 같은 값입니다. Apple 키보드와 macOS 가 Fn 키를 인식하는 키보드에 적용되며, Leobog 의 Fn 조합은 펌웨어 처리라 영향이 거의 없습니다.") {
                    HStack {
                        Toggle("F1, F2 등의 키를 표준 기능 키로 사용", isOn: $toggle)
                            .onChange(of: toggle) { _, v in if v != (fn.standardFunctionKeys ?? false) { fn.set(standardFunctionKeys: v) } }
                        Spacer()
                        Text(fn.standardFunctionKeys == nil ? "현재: 설정 안 됨 (기본값 = 꺼짐)" : (fn.standardFunctionKeys! ? "현재: 켜짐" : "현재: 꺼짐")).font(.caption).foregroundStyle(.secondary)
                        Button("키보드 설정 열기") { NSWorkspace.shared.open(FnKeyService.settingsURL) }
                    }
                    if !fn.lastMessage.isEmpty { Text(fn.lastMessage).font(.caption).foregroundStyle(.secondary) }
                }

                Card(title: "macOS Fn(🌐) 키 만들기", subtitle: model.keyboardMode == .mac
                     ? "키보드 자체 Fn 키는 호스트로 전송되지 않는 펌웨어 전용 키라 macOS 에서 바꿀 수 없습니다. 대신 스페이스 바로 오른쪽 키(오른쪽 ⌘)를 macOS Fn/🌐 키로 매핑할 수 있습니다."
                     : "키보드 자체 Fn 키는 호스트로 전송되지 않는 펌웨어 전용 키라 macOS 에서 바꿀 수 없습니다. 대신 스페이스 오른쪽 두 번째 키(오른쪽 Ctrl)를 macOS Fn/🌐 키로 매핑할 수 있습니다.") {
                    Text(model.keyboardMode == .mac
                         ? "Mac 모드: 하단열은 ⌃ · ⌥ · ⌘ · Space · 오른쪽 ⌘ · Fn 입니다. Fn 키(스페이스 오른쪽 두 번째)는 펌웨어 전용이고, 스페이스 바로 오른쪽 키는 오른쪽 ⌘(0xE7)로 들어오므로 이 키를 macOS Fn/🌐 로 바꿀 수 있습니다 (받아쓰기, 이모지, fn+화살표 등)."
                         : "Windows 모드: 하단열은 Ctrl · Win · Alt · Space · Fn · Ctrl 입니다. Fn 키(스페이스 바로 오른쪽)는 펌웨어 전용이고, 그 오른쪽 Ctrl(0xE4)을 macOS Fn/🌐 로 바꿀 수 있습니다.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        let presetID = model.keyboardMode == .mac ? "rcmd-fn" : "rctrl-fn"
                        let src: HIDUsage = .keyboard(model.keyboardMode == .mac ? 0xE7 : 0xE4)
                        let active = remap.activeFromSystem.contains { $0.src == src && $0.dst == .appleFn }
                        Button(model.keyboardMode == .mac ? "오른쪽 ⌘ → Fn(🌐) 적용" : "오른쪽 Ctrl → Fn(🌐) 적용") {
                            remap.apply(preset: HidutilRemapService.presets.first { $0.id == presetID }!)
                            try? remap.save(); _ = remap.applyToSystem()
                        }.buttonStyle(.borderedProminent).disabled(active)
                        Button("되돌리기") {
                            remap.remove(src: src)
                            try? remap.save(); _ = remap.applyToSystem()
                        }.disabled(!active)
                        if active { Label("적용됨", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption) }
                        Spacer()
                    }
                    Text("모드 전환은 키보드에서 Fn + M. 키보드 자체 Fn 조합(Fn+F8 재생 등)은 이 매핑과 무관하게 계속 동작합니다.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .onAppear { toggle = fn.standardFunctionKeys ?? false }
    }

    private var fRowRemapLabels: [Int: String] {
        var m: [Int: String] = [:]
        for k in fRow {
            if let r = remap.activeFromSystem.first(where: { $0.src == .keyboard(k.usage) }) { m[k.id] = r.dst.shortName }
        }
        return m
    }
}
