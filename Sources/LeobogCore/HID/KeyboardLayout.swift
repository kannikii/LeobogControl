import Foundation
import CoreGraphics

/// 키보드 펌웨어의 배열 모드. Fn + M 으로 전환되며 하단열의 의미가 달라진다.
public enum KeyboardMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case mac, windows
    public var id: String { rawValue }
    public var label: String { self == .mac ? "Mac 모드" : "Windows 모드" }
}

/// 물리 키 하나. 좌표/LED 인덱스는 공식 LEOBOG ONE 드라이버의 Hi8SE KB.ini 에서 가져옴.
public struct PhysicalKey: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case key, fn, knob }

    public let id: Int              // 드라이버의 K 번호 (1...81)
    public let label: String        // 키캡 라벨
    public let macLabel: String?    // Mac 모드에서 의미가 다른 경우
    public let usage: HIDUsage?     // 기본 레이어에서 호스트로 보내는 usage (Fn/노브는 nil)
    public let altUsages: [HIDUsage] // 같은 물리 키에서 추가로 도착할 수 있는 usage (예: Fn 키의 Apple Fn 바이트)
    public let frame: CGRect        // 드라이버 좌표계 (약 660 x 276)
    public let ledIndex: Int
    public let kind: Kind

    public var displayLabel: String { macLabel ?? label }

    /// 이 물리 키가 보낸 것으로 볼 수 있는 usage 인가
    public func matches(_ u: HIDUsage) -> Bool { usage == u || altUsages.contains(u) }

    // 주의: ==/hash 는 모든 필드를 비교한다. id 만 비교하면 Mac/Windows 목록이 같다고 판정되어 모드 전환 시 다시 그리지 않을 수 있다.
    // CGRect 는 macOS 14 SDK(Xcode 15) 에서 Hashable 이 아니라 합성이 안 되므로 직접 구현한다.
    public static func == (a: PhysicalKey, b: PhysicalKey) -> Bool {
        a.id == b.id && a.label == b.label && a.macLabel == b.macLabel && a.usage == b.usage && a.altUsages == b.altUsages
            && a.frame.equalTo(b.frame) && a.ledIndex == b.ledIndex && a.kind == b.kind
    }
    public func hash(into h: inout Hasher) {
        h.combine(id); h.combine(label); h.combine(macLabel); h.combine(usage); h.combine(altUsages)
        h.combine(frame.origin.x); h.combine(frame.origin.y); h.combine(frame.size.width); h.combine(frame.size.height)
        h.combine(ledIndex); h.combine(kind)
    }
}

public enum Hi8SELayout {
    public static let canvasSize = CGSize(width: 662, height: 268)

    private static func k(_ id: Int, _ label: String, _ usage: UInt32?, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ led: Int,
                          mac: String? = nil, kind: PhysicalKey.Kind = .key, alt: [HIDUsage] = []) -> PhysicalKey {
        PhysicalKey(id: id, label: label, macLabel: mac, usage: usage.map { HIDUsage.keyboard($0) }, altUsages: alt,
                    frame: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), ledIndex: led, kind: kind)
    }

    /// 0~4열: 모드와 무관하게 같은 usage 를 보낸다.
    private static let upperRows: [PhysicalKey] = [
        // 0열: Esc, F1–F12, 노브
        k(1, "Esc", 0x29, 30, 20, 56, 48, 0),
        k(2, "F1", 0x3A, 97, 20, 125, 48, 12), k(3, "F2", 0x3B, 137, 20, 165, 48, 18), k(4, "F3", 0x3C, 176, 20, 204, 48, 24), k(5, "F4", 0x3D, 216, 20, 244, 48, 30),
        k(6, "F5", 0x3E, 274, 20, 302, 48, 36), k(7, "F6", 0x3F, 314, 20, 342, 48, 42), k(8, "F7", 0x40, 354, 20, 382, 48, 48), k(9, "F8", 0x41, 393, 20, 421, 48, 54),
        k(10, "F9", 0x42, 452, 20, 480, 48, 60), k(11, "F10", 0x43, 492, 20, 520, 48, 66), k(12, "F11", 0x44, 530, 20, 558, 48, 72), k(13, "F12", 0x45, 570, 20, 598, 48, 78),
        k(81, "노브", nil, 614, 14, 656, 56, 84, kind: .knob),
        // 1열
        k(15, "`", 0x35, 29, 70, 57, 98, 1),
        k(16, "1", 0x1E, 69, 70, 97, 98, 7), k(17, "2", 0x1F, 108, 70, 136, 98, 13), k(18, "3", 0x20, 148, 70, 176, 98, 19), k(19, "4", 0x21, 188, 70, 216, 98, 25),
        k(20, "5", 0x22, 227, 70, 255, 98, 31), k(21, "6", 0x23, 267, 70, 295, 98, 37), k(22, "7", 0x24, 306, 70, 334, 98, 43), k(23, "8", 0x25, 346, 70, 374, 98, 49),
        k(24, "9", 0x26, 385, 70, 413, 98, 55), k(25, "0", 0x27, 425, 70, 453, 98, 61), k(26, "-", 0x2D, 465, 70, 493, 98, 67), k(27, "=", 0x2E, 504, 70, 532, 98, 73),
        k(28, "⌫", 0x2A, 544, 70, 612, 98, 79), k(29, "Del", 0x4C, 621, 70, 649, 98, 85),
        // 2열
        k(30, "Tab", 0x2B, 32, 110, 76, 138, 2),
        k(31, "Q", 0x14, 88, 110, 116, 138, 8), k(32, "W", 0x1A, 128, 110, 156, 138, 14), k(33, "E", 0x08, 167, 110, 195, 138, 20), k(34, "R", 0x15, 206, 110, 234, 138, 26),
        k(35, "T", 0x17, 246, 110, 274, 138, 32), k(36, "Y", 0x1C, 285, 110, 313, 138, 38), k(37, "U", 0x18, 324, 110, 352, 138, 44), k(38, "I", 0x0C, 364, 110, 392, 138, 50),
        k(39, "O", 0x12, 404, 110, 432, 138, 56), k(40, "P", 0x13, 444, 110, 472, 138, 62), k(41, "[", 0x2F, 483, 110, 511, 138, 68), k(42, "]", 0x30, 522, 110, 550, 138, 74),
        k(43, "\\", 0x31, 560, 110, 610, 138, 80), k(44, "PgUp", 0x4B, 621, 110, 649, 138, 86),
        // 3열
        k(45, "Caps", 0x39, 31, 149, 88, 177, 3),
        k(46, "A", 0x04, 98, 149, 126, 177, 9), k(47, "S", 0x16, 137, 149, 165, 177, 15), k(48, "D", 0x07, 177, 149, 205, 177, 21), k(49, "F", 0x09, 216, 149, 244, 177, 27),
        k(50, "G", 0x0A, 256, 149, 284, 177, 33), k(51, "H", 0x0B, 295, 149, 323, 177, 39), k(52, "J", 0x0D, 335, 149, 363, 177, 45), k(53, "K", 0x0E, 375, 149, 403, 177, 51),
        k(54, "L", 0x0F, 414, 149, 442, 177, 57), k(55, ";", 0x33, 453, 149, 481, 177, 63), k(56, "'", 0x34, 493, 149, 521, 177, 69), k(57, "Enter", 0x28, 534, 149, 610, 177, 81),
        k(80, "PgDn", 0x4E, 621, 149, 649, 177, 87),
        // 4열
        k(58, "Shift", 0xE1, 30, 188, 106, 216, 4),
        k(59, "Z", 0x1D, 117, 188, 145, 216, 10), k(60, "X", 0x1B, 157, 188, 185, 216, 16), k(61, "C", 0x06, 197, 188, 225, 216, 22), k(62, "V", 0x19, 236, 188, 264, 216, 28),
        k(63, "B", 0x05, 276, 188, 304, 216, 34), k(64, "N", 0x11, 315, 188, 343, 216, 40), k(65, "M", 0x10, 354, 188, 382, 216, 46), k(66, ",", 0x36, 393, 188, 421, 216, 52),
        k(67, ".", 0x37, 433, 188, 461, 216, 58), k(68, "/", 0x38, 473, 188, 501, 216, 64), k(69, "Shift", 0xE5, 514, 188, 570, 216, 70),
        k(70, "↑", 0x52, 581, 188, 609, 216, 82), k(14, "End", 0x4D, 621, 188, 649, 216, 88),
    ]

    /// 5열 (하단열) — Mac 모드. 실측(2026-10): 물리 Win 자리 = ⌥(0xE2), Alt 자리 = ⌘(0xE3),
    /// 스페이스 바로 오른쪽 = 오른쪽 ⌘(0xE7), 그 오른쪽 = Fn (펌웨어 전용; 조합 중 가끔 0xE4 로 보임, 디스크립터에 Apple Fn 바이트 있음).
    private static let bottomRowMac: [PhysicalKey] = [
        k(71, "Ctrl", 0xE0, 31, 228, 67, 256, 5, mac: "⌃"), k(72, "Win", 0xE2, 80, 228, 116, 256, 11, mac: "⌥"), k(73, "Alt", 0xE3, 127, 228, 165, 256, 17, mac: "⌘"),
        k(74, "Space", 0x2C, 177, 228, 409, 256, 35),
        k(76, "R⌘", 0xE7, 425, 228, 460, 256, 53),
        k(75, "Fn", nil, 475, 228, 510, 256, 59, kind: .fn, alt: [.appleFn, .keyboard(0xE4)]),
        k(77, "←", 0x50, 543, 228, 569, 256, 77), k(78, "↓", 0x51, 581, 228, 609, 256, 83), k(79, "→", 0x4F, 621, 228, 649, 256, 89),
    ]

    /// 5열 (하단열) — Windows 모드. 공식 드라이버 KB.ini 그대로: Ctrl, Win, Alt, Space, Fn, RCtrl.
    private static let bottomRowWindows: [PhysicalKey] = [
        k(71, "Ctrl", 0xE0, 31, 228, 67, 256, 5), k(72, "Win", 0xE3, 80, 228, 116, 256, 11), k(73, "Alt", 0xE2, 127, 228, 165, 256, 17),
        k(74, "Space", 0x2C, 177, 228, 409, 256, 35),
        k(76, "Fn", nil, 425, 228, 460, 256, 53, kind: .fn, alt: [.appleFn]),
        k(75, "Ctrl", 0xE4, 475, 228, 510, 256, 59),
        k(77, "←", 0x50, 543, 228, 569, 256, 77), k(78, "↓", 0x51, 581, 228, 609, 256, 83), k(79, "→", 0x4F, 621, 228, 649, 256, 89),
    ]

    private static let keysMac: [PhysicalKey] = upperRows + bottomRowMac
    private static let keysWindows: [PhysicalKey] = upperRows + bottomRowWindows
    private static let byIDMac: [Int: PhysicalKey] = Dictionary(uniqueKeysWithValues: keysMac.map { ($0.id, $0) })
    private static let byIDWindows: [Int: PhysicalKey] = Dictionary(uniqueKeysWithValues: keysWindows.map { ($0.id, $0) })

    /// 모드별 전체 키 목록
    public static func keys(for mode: KeyboardMode) -> [PhysicalKey] { mode == .mac ? keysMac : keysWindows }
    public static func byID(for mode: KeyboardMode) -> [Int: PhysicalKey] { mode == .mac ? byIDMac : byIDWindows }

    /// usage → 물리 키 (기본 레이어 + altUsages 기준)
    public static func key(for usage: HIDUsage, mode: KeyboardMode) -> PhysicalKey? {
        let list = keys(for: mode)
        return list.first { $0.usage == usage } ?? list.first { $0.altUsages.contains(usage) }
    }

    /// 모드별 Fn 키 (Mac: K75 = 스페이스 오른쪽 두 번째, Windows: K76 = 스페이스 바로 오른쪽)
    public static func fnKey(for mode: KeyboardMode) -> PhysicalKey { mode == .mac ? byIDMac[75]! : byIDWindows[76]! }

    // MARK: 모드와 무관한 편의 접근자 (기본 = Mac 모드)

    public static var keys: [PhysicalKey] { keysMac }
    public static var byID: [Int: PhysicalKey] { byIDMac }
    public static func key(for usage: HIDUsage) -> PhysicalKey? { key(for: usage, mode: .mac) }
    public static var knob: PhysicalKey { byIDMac[81]! }
    public static var fnKey: PhysicalKey { fnKey(for: .mac) }
}
