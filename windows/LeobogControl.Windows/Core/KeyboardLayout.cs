using System.Drawing;

namespace LeobogControl.Core;

/// 키보드 펌웨어의 배열 모드. Fn + M 으로 전환되며 하단열의 의미가 달라진다.
public enum KeyboardMode { Mac, Windows }

public static class KeyboardModeExt
{
    public static string Label(this KeyboardMode m) => m == KeyboardMode.Mac ? "Mac 모드" : "Windows 모드";
}

public enum KeyKind { Key, Fn, Knob }

/// 물리 키 하나. 좌표/LED 인덱스는 공식 LEOBOG ONE 드라이버의 Hi8SE KB.ini 에서 가져옴.
public sealed record PhysicalKey(int Id, string Label, string? MacLabel, HidUsage? Usage, IReadOnlyList<HidUsage> AltUsages,
                                 RectangleF Frame, int LedIndex, KeyKind Kind)
{
    public string DisplayLabel => MacLabel ?? Label;
    /// 이 물리 키가 보낸 것으로 볼 수 있는 usage 인가
    public bool Matches(HidUsage u) => Usage == u || AltUsages.Contains(u);
}

public static class Hi8SELayout
{
    public static readonly SizeF CanvasSize = new(662, 268);

    static PhysicalKey K(int id, string label, uint? usage, float x1, float y1, float x2, float y2, int led,
                         string? mac = null, KeyKind kind = KeyKind.Key, HidUsage[]? alt = null) =>
        new(id, label, mac, usage.HasValue ? HidUsage.Keyboard(usage.Value) : null, alt ?? Array.Empty<HidUsage>(),
            new RectangleF(x1, y1, x2 - x1, y2 - y1), led, kind);

    /// 0~4열: 모드와 무관하게 같은 usage 를 보낸다.
    static readonly PhysicalKey[] UpperRows =
    {
        K(1, "Esc", 0x29, 30, 20, 56, 48, 0),
        K(2, "F1", 0x3A, 97, 20, 125, 48, 12), K(3, "F2", 0x3B, 137, 20, 165, 48, 18), K(4, "F3", 0x3C, 176, 20, 204, 48, 24), K(5, "F4", 0x3D, 216, 20, 244, 48, 30),
        K(6, "F5", 0x3E, 274, 20, 302, 48, 36), K(7, "F6", 0x3F, 314, 20, 342, 48, 42), K(8, "F7", 0x40, 354, 20, 382, 48, 48), K(9, "F8", 0x41, 393, 20, 421, 48, 54),
        K(10, "F9", 0x42, 452, 20, 480, 48, 60), K(11, "F10", 0x43, 492, 20, 520, 48, 66), K(12, "F11", 0x44, 530, 20, 558, 48, 72), K(13, "F12", 0x45, 570, 20, 598, 48, 78),
        K(81, "노브", null, 614, 14, 656, 56, 84, kind: KeyKind.Knob),
        K(15, "`", 0x35, 29, 70, 57, 98, 1),
        K(16, "1", 0x1E, 69, 70, 97, 98, 7), K(17, "2", 0x1F, 108, 70, 136, 98, 13), K(18, "3", 0x20, 148, 70, 176, 98, 19), K(19, "4", 0x21, 188, 70, 216, 98, 25),
        K(20, "5", 0x22, 227, 70, 255, 98, 31), K(21, "6", 0x23, 267, 70, 295, 98, 37), K(22, "7", 0x24, 306, 70, 334, 98, 43), K(23, "8", 0x25, 346, 70, 374, 98, 49),
        K(24, "9", 0x26, 385, 70, 413, 98, 55), K(25, "0", 0x27, 425, 70, 453, 98, 61), K(26, "-", 0x2D, 465, 70, 493, 98, 67), K(27, "=", 0x2E, 504, 70, 532, 98, 73),
        K(28, "⌫", 0x2A, 544, 70, 612, 98, 79), K(29, "Del", 0x4C, 621, 70, 649, 98, 85),
        K(30, "Tab", 0x2B, 32, 110, 76, 138, 2),
        K(31, "Q", 0x14, 88, 110, 116, 138, 8), K(32, "W", 0x1A, 128, 110, 156, 138, 14), K(33, "E", 0x08, 167, 110, 195, 138, 20), K(34, "R", 0x15, 206, 110, 234, 138, 26),
        K(35, "T", 0x17, 246, 110, 274, 138, 32), K(36, "Y", 0x1C, 285, 110, 313, 138, 38), K(37, "U", 0x18, 324, 110, 352, 138, 44), K(38, "I", 0x0C, 364, 110, 392, 138, 50),
        K(39, "O", 0x12, 404, 110, 432, 138, 56), K(40, "P", 0x13, 444, 110, 472, 138, 62), K(41, "[", 0x2F, 483, 110, 511, 138, 68), K(42, "]", 0x30, 522, 110, 550, 138, 74),
        K(43, "\\", 0x31, 560, 110, 610, 138, 80), K(44, "PgUp", 0x4B, 621, 110, 649, 138, 86),
        K(45, "Caps", 0x39, 31, 149, 88, 177, 3),
        K(46, "A", 0x04, 98, 149, 126, 177, 9), K(47, "S", 0x16, 137, 149, 165, 177, 15), K(48, "D", 0x07, 177, 149, 205, 177, 21), K(49, "F", 0x09, 216, 149, 244, 177, 27),
        K(50, "G", 0x0A, 256, 149, 284, 177, 33), K(51, "H", 0x0B, 295, 149, 323, 177, 39), K(52, "J", 0x0D, 335, 149, 363, 177, 45), K(53, "K", 0x0E, 375, 149, 403, 177, 51),
        K(54, "L", 0x0F, 414, 149, 442, 177, 57), K(55, ";", 0x33, 453, 149, 481, 177, 63), K(56, "'", 0x34, 493, 149, 521, 177, 69), K(57, "Enter", 0x28, 534, 149, 610, 177, 81),
        K(80, "PgDn", 0x4E, 621, 149, 649, 177, 87),
        K(58, "Shift", 0xE1, 30, 188, 106, 216, 4),
        K(59, "Z", 0x1D, 117, 188, 145, 216, 10), K(60, "X", 0x1B, 157, 188, 185, 216, 16), K(61, "C", 0x06, 197, 188, 225, 216, 22), K(62, "V", 0x19, 236, 188, 264, 216, 28),
        K(63, "B", 0x05, 276, 188, 304, 216, 34), K(64, "N", 0x11, 315, 188, 343, 216, 40), K(65, "M", 0x10, 354, 188, 382, 216, 46), K(66, ",", 0x36, 393, 188, 421, 216, 52),
        K(67, ".", 0x37, 433, 188, 461, 216, 58), K(68, "/", 0x38, 473, 188, 501, 216, 64), K(69, "Shift", 0xE5, 514, 188, 570, 216, 70),
        K(70, "↑", 0x52, 581, 188, 609, 216, 82), K(14, "End", 0x4D, 621, 188, 649, 216, 88),
    };

    /// 5열 (하단열) — Mac 모드. 실측: Win 자리 = ⌥(0xE2), Alt 자리 = ⌘(0xE3), 스페이스 바로 오른쪽 = 오른쪽 ⌘(0xE7), 그 오른쪽 = Fn(펌웨어 전용).
    static readonly PhysicalKey[] BottomRowMac =
    {
        K(71, "Ctrl", 0xE0, 31, 228, 67, 256, 5, mac: "⌃"), K(72, "Win", 0xE2, 80, 228, 116, 256, 11, mac: "⌥"), K(73, "Alt", 0xE3, 127, 228, 165, 256, 17, mac: "⌘"),
        K(74, "Space", 0x2C, 177, 228, 409, 256, 35),
        K(76, "R⌘", 0xE7, 425, 228, 460, 256, 53),
        K(75, "Fn", null, 475, 228, 510, 256, 59, kind: KeyKind.Fn, alt: new[] { HidUsage.AppleFn, HidUsage.Keyboard(0xE4) }),
        K(77, "←", 0x50, 543, 228, 569, 256, 77), K(78, "↓", 0x51, 581, 228, 609, 256, 83), K(79, "→", 0x4F, 621, 228, 649, 256, 89),
    };

    /// 5열 (하단열) — Windows 모드. 공식 드라이버 KB.ini 그대로: Ctrl, Win, Alt, Space, Fn, RCtrl.
    static readonly PhysicalKey[] BottomRowWindows =
    {
        K(71, "Ctrl", 0xE0, 31, 228, 67, 256, 5), K(72, "Win", 0xE3, 80, 228, 116, 256, 11), K(73, "Alt", 0xE2, 127, 228, 165, 256, 17),
        K(74, "Space", 0x2C, 177, 228, 409, 256, 35),
        K(76, "Fn", null, 425, 228, 460, 256, 53, kind: KeyKind.Fn, alt: new[] { HidUsage.AppleFn }),
        K(75, "Ctrl", 0xE4, 475, 228, 510, 256, 59),
        K(77, "←", 0x50, 543, 228, 569, 256, 77), K(78, "↓", 0x51, 581, 228, 609, 256, 83), K(79, "→", 0x4F, 621, 228, 649, 256, 89),
    };

    static readonly IReadOnlyList<PhysicalKey> KeysMac = UpperRows.Concat(BottomRowMac).ToList();
    static readonly IReadOnlyList<PhysicalKey> KeysWindows = UpperRows.Concat(BottomRowWindows).ToList();

    public static IReadOnlyList<PhysicalKey> Keys(KeyboardMode mode) => mode == KeyboardMode.Mac ? KeysMac : KeysWindows;

    /// usage → 물리 키 (기본 레이어 + AltUsages 기준)
    public static PhysicalKey? KeyFor(HidUsage usage, KeyboardMode mode)
    {
        var list = Keys(mode);
        return list.FirstOrDefault(k => k.Usage == usage) ?? list.FirstOrDefault(k => k.AltUsages.Contains(usage));
    }

    public static PhysicalKey FnKey(KeyboardMode mode) => Keys(mode).First(k => k.Kind == KeyKind.Fn);
}
