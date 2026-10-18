import SwiftUI
import LeobogCore

struct LightingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var compx: CompxClient
    @State private var effect: LedEffect = LedEffects.all[LedEffects.defaultIndex - 1]
    @State private var brightness: Double = 4
    @State private var speed: Double = 2
    @State private var randomColor = true
    @State private var color: Color = .cyan
    @State private var result: String = ""
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusBanner

                Card(title: "조명 효과", subtitle: "공식 드라이버(LEOBOG ONE)의 Hi8SE 효과 목록 20종 · 기본값 \(LedEffects.all[LedEffects.defaultIndex - 1].name)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(LedEffects.all) { e in
                            Button {
                                effect = e
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(e.id)").font(.caption2).foregroundStyle(.secondary)
                                    Text(e.name).font(.callout).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(effect.id == e.id ? .accentColor : nil)
                        }
                    }
                }

                Card(title: "옵션 — \(effect.name)", subtitle: "지원하는 옵션만 활성화됩니다 (드라이버 LedOpt 기준)") {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("밝기 \(Int(brightness)) / 4").font(.caption)
                            Slider(value: $brightness, in: 0...4, step: 1).disabled(!effect.supportsBrightness)
                        }
                        VStack(alignment: .leading) {
                            Text("속도 \(Int(speed)) / 4").font(.caption)
                            Slider(value: $speed, in: 0...4, step: 1).disabled(!effect.supportsSpeed)
                        }
                        VStack(alignment: .leading) {
                            Toggle("알록달록하게 (랜덤 색)", isOn: $randomColor).disabled(!effect.supportsRandomColor)
                            HStack {
                                ColorPicker("사용자 정의 색상", selection: $color, supportsOpacity: false).disabled(!effect.supportsCustomColor || randomColor)
                                ForEach(LedEffects.presetColors, id: \.0) { c in
                                    Circle().fill(Color(red: Double(c.1) / 255, green: Double(c.2) / 255, blue: Double(c.3) / 255)).frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                                        .onTapGesture { color = Color(red: Double(c.1) / 255, green: Double(c.2) / 255, blue: Double(c.3) / 255); randomColor = false }
                                        .help(c.0)
                                }
                            }
                        }
                    }
                    KeyboardDiagramView(keys: model.layoutKeys, pressed: [], colors: previewColors).frame(maxHeight: 170)
                    HStack {
                        Button(working ? "전송 중…" : "키보드에 적용 (벤더 채널)") { Task { await applyEffect() } }
                            .buttonStyle(.borderedProminent).disabled(working || !compx.protocolVerified)
                        Button("키 전체를 이 색으로 (키별 색상 전송)") { Task { await applySolidColor() } }
                            .disabled(working || !compx.protocolVerified)
                        if !compx.protocolVerified {
                            Button("먼저 연결 확인") { Task { _ = await compx.probe(); result = compx.log.last?.line ?? "" } }
                        }
                        Spacer()
                    }
                    if !result.isEmpty { Text(result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }

                Card(title: "항상 되는 방법: 키보드 단축키", subtitle: "펌웨어가 직접 처리하므로 권한·프로토콜과 무관하게 동작합니다.") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                        ForEach(FnLayerReference.shortcuts(in: "조명")) { s in
                            GridRow {
                                Text(s.combo).bold()
                                Text(s.macAction + (s.certain ? "" : " (추정)"))
                            }
                        }
                        GridRow { Text("Fn + F5 / F6").bold(); Text("조명 밝기 낮추기 / 높이기 (추정)") }
                    }.font(.callout)
                    Text("효과 순서(Fn+Tab 순환): " + LedEffects.all.filter { $0.fnCycle }.map { "\($0.id) \($0.name)" }.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private var statusBanner: some View {
        Group {
            if !hid.isOpen {
                Label("조명을 소프트웨어로 바꾸려면 입력 모니터링 권한이 필요합니다 ('장치' 화면). 권한 전에는 아래 키보드 단축키를 쓰세요.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if !compx.protocolVerified {
                Label("벤더 채널(Report 0x13)이 아직 확인되지 않았습니다. '연결 확인' 을 눌러 읽기 전용 명령으로 응답을 검사합니다. 응답이 없으면 블루투스 모드에서는 설정 채널이 닫혀 있는 것입니다 (공식 드라이버도 Windows 모드/유선을 요구).", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            } else {
                Label("벤더 채널 통신 확인됨 · 체크섬 \(compx.checksumStyle.label). 효과 페이로드 구조는 공개 자료 기준의 추정이므로 결과를 보며 조정하세요.", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
        }.font(.callout)
    }

    private var previewColors: [Int: Color] {
        var m: [Int: Color] = [:]
        let base = randomColor && effect.supportsRandomColor ? nil : color
        let dim = Double(brightness) / 4
        for k in model.layoutKeys {
            if effect.hardwareID == 0 { m[k.id] = Color.gray.opacity(0.25); continue }
            if let b = base {
                m[k.id] = b.opacity(0.25 + 0.75 * dim)
            } else {
                m[k.id] = Color(hue: Double(k.ledIndex % 90) / 90, saturation: 0.7, brightness: 0.95).opacity(0.25 + 0.75 * dim)
            }
        }
        return m
    }

    private func rgb() -> (UInt8, UInt8, UInt8) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return (UInt8(max(0, min(255, ns.redComponent * 255))), UInt8(max(0, min(255, ns.greenComponent * 255))), UInt8(max(0, min(255, ns.blueComponent * 255))))
    }

    private func applyEffect() async {
        working = true
        defer { working = false }
        let c = rgb()
        let s = CompxClient.LedEffectSetting(effect: effect.hardwareID, speed: UInt8(speed), brightness: UInt8(brightness), direction: 0,
                                             random: randomColor && effect.supportsRandomColor ? 1 : 0, r: c.0, g: c.1, b: c.2)
        do {
            let r = try await compx.setLedEffect(s)
            result = "응답: \(r.hex)"
        } catch {
            result = "실패: \(error)"
        }
    }

    private func applySolidColor() async {
        working = true
        defer { working = false }
        let c = rgb()
        do {
            try await compx.setLedColors(Array(repeating: c, count: 126))
            try? await compx.commit()
            result = "키별 색상 전송 완료"
        } catch { result = "실패: \(error)" }
    }
}
