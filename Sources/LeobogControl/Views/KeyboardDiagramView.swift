import SwiftUI
import LeobogCore

/// 공식 드라이버 좌표로 그린 Hi8SE 키보드 다이어그램
struct KeyboardDiagramView: View {
    var keys: [PhysicalKey]                // 모드별 키 목록 (model.layoutKeys) — 기본값 없음: 모드를 빠뜨리지 않도록
    var pressed: Set<Int> = []
    var remapped: [Int: String] = [:]      // keyID → 바뀐 라벨
    var highlighted: Set<Int> = []
    var selected: Int? = nil
    var colors: [Int: Color] = [:]         // keyID → 조명 미리보기 색
    var onTap: ((PhysicalKey) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Hi8SELayout.canvasSize.width, geo.size.height / Hi8SELayout.canvasSize.height)
            let w = Hi8SELayout.canvasSize.width * scale
            let h = Hi8SELayout.canvasSize.height * scale
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * scale)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 12 * scale).stroke(Color.primary.opacity(0.15)))
                    .frame(width: w, height: h)
                ForEach(keys) { key in
                    withHelp(keyView(key, scale: scale), key: key)
                        .frame(width: key.frame.width * scale, height: key.frame.height * scale)
                        .offset(x: key.frame.minX * scale, y: key.frame.minY * scale)
                        .onTapGesture { onTap?(key) }
                }
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(Hi8SELayout.canvasSize.width / Hi8SELayout.canvasSize.height, contentMode: .fit)
    }

    @ViewBuilder
    private func keyView(_ key: PhysicalKey, scale: CGFloat) -> some View {
        let isPressed = pressed.contains(key.id)
        let isSel = selected == key.id
        let isHi = highlighted.contains(key.id)
        let remapLabel = remapped[key.id]
        let fill: Color = isPressed ? .accentColor : (colors[key.id] ?? (key.kind == .knob ? Color.gray.opacity(0.35) : Color(nsColor: .controlColor)))
        let fontSize = max(7, (key.frame.width > 40 ? 9 : 8) * scale * 1.2)
        ZStack {
            Group {
                if key.kind == .knob {
                    Circle().fill(fill)
                } else {
                    RoundedRectangle(cornerRadius: 4 * scale).fill(fill)
                }
            }
            .overlay(
                Group {
                    if key.kind == .knob { Circle().stroke(strokeColor(sel: isSel, hi: isHi, remap: remapLabel != nil), lineWidth: isSel || isHi ? 2 : 1) }
                    else { RoundedRectangle(cornerRadius: 4 * scale).stroke(strokeColor(sel: isSel, hi: isHi, remap: remapLabel != nil), lineWidth: isSel || isHi ? 2 : 1) }
                }
            )
            VStack(spacing: 0) {
                Text(key.displayLabel)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isPressed ? Color.white : (colors[key.id] != nil ? Color.black.opacity(0.75) : Color.primary))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let r = remapLabel {
                    Text("→\(r)")
                        .font(.system(size: fontSize * 0.85, weight: .semibold))
                        .foregroundStyle(isPressed ? Color.white : Color.orange)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .padding(1)
        }
        .contentShape(Rectangle())
    }

    /// 펌웨어 전용 키(Fn)에는 왜 혼자 눌러도 안 켜지는지 툴팁으로 설명
    @ViewBuilder
    private func withHelp<V: View>(_ v: V, key: PhysicalKey) -> some View {
        if key.kind == .fn {
            v.help("키보드 자체(펌웨어) Fn 키 — 혼자 누르면 맥으로 아무 입력도 오지 않아 켜지지 않습니다. Fn+F8(재생) 같은 조합이나 Fn+M(Mac/Windows 전환)으로만 씁니다.")
        } else {
            v
        }
    }

    private func strokeColor(sel: Bool, hi: Bool, remap: Bool) -> Color {
        if sel { return .accentColor }
        if hi { return .yellow }
        if remap { return .orange }
        return Color.primary.opacity(0.25)
    }
}
