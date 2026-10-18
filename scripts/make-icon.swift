import AppKit

// 앱 아이콘 생성: 둥근 사각형 그라데이션 + 키보드 심볼
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let rect = NSRect(origin: .zero, size: size)
    let inset = rect.insetBy(dx: CGFloat(px) * 0.05, dy: CGFloat(px) * 0.05)
    let path = NSBezierPath(roundedRect: inset, xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    let grad = NSGradient(colors: [NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.28, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.14, alpha: 1)])!
    grad.draw(in: path, angle: -90)
    // RGB 띠
    let bar = NSRect(x: inset.minX + inset.width * 0.18, y: inset.minY + inset.height * 0.22, width: inset.width * 0.64, height: inset.height * 0.07)
    NSGradient(colors: [.systemRed, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple])!.draw(in: NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2), angle: 0)
    // 키 격자
    let cols = 6, rows = 3
    let kw = inset.width * 0.64 / CGFloat(cols), kh = inset.height * 0.40 / CGFloat(rows)
    let ox = inset.minX + inset.width * 0.18, oy = inset.minY + inset.height * 0.36
    for r in 0..<rows {
        for c in 0..<cols {
            let isWide = (r == 0 && c >= 1 && c <= 4)
            if r == 0 && c > 1 && c <= 4 { continue }
            let w = isWide ? kw * 4 : kw
            let kr = NSRect(x: ox + CGFloat(c) * kw + kw * 0.08, y: oy + CGFloat(r) * kh + kh * 0.08, width: w - kw * 0.16, height: kh - kh * 0.16)
            NSColor(calibratedWhite: 0.92, alpha: r == 0 && c == 1 ? 0.75 : 0.9).setFill()
            NSBezierPath(roundedRect: kr, xRadius: kr.height * 0.2, yRadius: kr.height * 0.2).fill()
        }
    }
    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset written to \(outDir)")
