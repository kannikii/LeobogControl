namespace LeobogControl.Core;

/// HID usage 식별자. page 0x07 = 키보드, 0x0C = 소비자(미디어), 0xFF = Apple 벤더(Fn/🌐, Mac 전용).
public readonly record struct HidUsage(uint Page, uint Usage)
{
    public static HidUsage Keyboard(uint u) => new(0x07, u);
    public static HidUsage Consumer(uint u) => new(0x0C, u);
    /// macOS 의 Apple Fn/Globe 키. Windows 에서는 보낼 수 없지만 macOS 앱과 같은 remaps.json 을 읽기 위해 둔다.
    public static readonly HidUsage AppleFn = new(0xFF, 0x03);
    /// 키 비활성화 (Scancode Map 에서 0x0000 으로 매핑)
    public static readonly HidUsage Disabled = new(0x07, 0x00);

    public ulong CombinedValue => ((ulong)Page << 32) | Usage;
    public string HexString => $"0x{CombinedValue:X}";
    public bool IsKeyboard => Page == 0x07;
    public bool IsConsumer => Page == 0x0C;
    public bool IsModifier => Page == 0x07 && Usage >= 0xE0 && Usage <= 0xE7;
    public string Name => HidUsageNames.Name(this);
    public string ShortName => HidUsageNames.ShortName(this);
    public override string ToString() => $"{Name} ({HexString})";
}

public static class HidUsageNames
{
    static readonly Dictionary<uint, (string Short, string Full)> Keyboard = Build();

    static Dictionary<uint, (string, string)> Build()
    {
        var m = new Dictionary<uint, (string, string)>();
        for (var i = 0; i < 26; i++) { var s = ((char)('A' + i)).ToString(); m[(uint)(0x04 + i)] = (s, s); }
        var digits = "1234567890";
        for (var i = 0; i < 10; i++) { var s = digits[i].ToString(); m[(uint)(0x1E + i)] = (s, s); }
        (uint, string, string)[] rest =
        {
            (0x00, "없음", "없음(비활성화)"),
            (0x28, "Enter", "Enter"), (0x29, "Esc", "Escape"), (0x2A, "⌫", "Backspace"),
            (0x2B, "Tab", "Tab"), (0x2C, "Space", "Space"), (0x2D, "-", "- (빼기)"), (0x2E, "=", "= (등호)"),
            (0x2F, "[", "[ (왼쪽 대괄호)"), (0x30, "]", "] (오른쪽 대괄호)"), (0x31, "\\", "\\ (역슬래시)"),
            (0x32, "#", "Non-US # / ~"), (0x33, ";", "; (세미콜론)"), (0x34, "'", "' (따옴표)"),
            (0x35, "`", "` (그레이브/물결)"), (0x36, ",", ", (쉼표)"), (0x37, ".", ". (마침표)"), (0x38, "/", "/ (슬래시)"),
            (0x39, "Caps", "Caps Lock"),
            (0x3A, "F1", "F1"), (0x3B, "F2", "F2"), (0x3C, "F3", "F3"), (0x3D, "F4", "F4"), (0x3E, "F5", "F5"), (0x3F, "F6", "F6"),
            (0x40, "F7", "F7"), (0x41, "F8", "F8"), (0x42, "F9", "F9"), (0x43, "F10", "F10"), (0x44, "F11", "F11"), (0x45, "F12", "F12"),
            (0x46, "PrtSc", "Print Screen"), (0x47, "ScrLk", "Scroll Lock"), (0x48, "Pause", "Pause"),
            (0x49, "Ins", "Insert"), (0x4A, "Home", "Home"), (0x4B, "PgUp", "Page Up"), (0x4C, "Del", "Delete(앞으로 지우기)"),
            (0x4D, "End", "End"), (0x4E, "PgDn", "Page Down"),
            (0x4F, "→", "오른쪽 화살표"), (0x50, "←", "왼쪽 화살표"), (0x51, "↓", "아래 화살표"), (0x52, "↑", "위 화살표"),
            (0x53, "NumLk", "Num Lock / Clear"), (0x54, "KP /", "키패드 /"), (0x55, "KP *", "키패드 *"), (0x56, "KP -", "키패드 -"),
            (0x57, "KP +", "키패드 +"), (0x58, "KP ⏎", "키패드 Enter"),
            (0x59, "KP 1", "키패드 1"), (0x5A, "KP 2", "키패드 2"), (0x5B, "KP 3", "키패드 3"), (0x5C, "KP 4", "키패드 4"),
            (0x5D, "KP 5", "키패드 5"), (0x5E, "KP 6", "키패드 6"), (0x5F, "KP 7", "키패드 7"), (0x60, "KP 8", "키패드 8"),
            (0x61, "KP 9", "키패드 9"), (0x62, "KP 0", "키패드 0"), (0x63, "KP .", "키패드 ."),
            (0x64, "\\", "Non-US \\ / |"), (0x65, "Menu", "Application(메뉴)"), (0x66, "Power", "Power"), (0x67, "KP =", "키패드 ="),
            (0x68, "F13", "F13"), (0x69, "F14", "F14"), (0x6A, "F15", "F15"), (0x6B, "F16", "F16"), (0x6C, "F17", "F17"), (0x6D, "F18", "F18"),
            (0x6E, "F19", "F19"), (0x6F, "F20", "F20"), (0x70, "F21", "F21"), (0x71, "F22", "F22"), (0x72, "F23", "F23"), (0x73, "F24", "F24"),
            (0x74, "Exec", "Execute"), (0x75, "Help", "Help"), (0x76, "Menu", "Menu"), (0x77, "Select", "Select"), (0x78, "Stop", "Stop"),
            (0x79, "Again", "Again"), (0x7A, "Undo", "Undo"), (0x7B, "Cut", "Cut"), (0x7C, "Copy", "Copy"), (0x7D, "Paste", "Paste"),
            (0x7E, "Find", "Find"), (0x7F, "Mute", "Mute(키보드 페이지)"), (0x80, "Vol+", "Volume Up(키보드 페이지)"), (0x81, "Vol-", "Volume Down(키보드 페이지)"),
            (0x87, "Ro", "International 1 (ろ)"), (0x88, "かな", "International 2 (かな)"), (0x89, "¥", "International 3 (¥)"),
            (0x8A, "変換", "International 4 (変換)"), (0x8B, "無変換", "International 5 (無変換)"),
            (0x90, "한/영", "Lang 1 (한/영)"), (0x91, "한자", "Lang 2 (한자)"), (0x92, "Lang3", "Lang 3"),
            (0xE0, "LCtrl", "왼쪽 Control"), (0xE1, "LShift", "왼쪽 Shift"), (0xE2, "LAlt", "왼쪽 Alt(Option)"), (0xE3, "LWin", "왼쪽 Win(Command/GUI)"),
            (0xE4, "RCtrl", "오른쪽 Control"), (0xE5, "RShift", "오른쪽 Shift"), (0xE6, "RAlt", "오른쪽 Alt(Option)"), (0xE7, "RWin", "오른쪽 Win(Command/GUI)"),
        };
        foreach (var (u, s, f) in rest) m[u] = (s, f);
        return m;
    }

    static readonly Dictionary<uint, (string Short, string Full)> Consumer = new()
    {
        [0x30] = ("Power", "전원"), [0x32] = ("Sleep", "잠자기"), [0x34] = ("Sleep", "잠자기 모드"),
        [0x6F] = ("밝기+", "화면 밝기 높이기"), [0x70] = ("밝기-", "화면 밝기 낮추기"),
        [0x79] = ("KB밝기+", "키보드 백라이트 밝기 높이기"), [0x7A] = ("KB밝기-", "키보드 백라이트 밝기 낮추기"),
        [0x7C] = ("KB조명", "키보드 백라이트 토글"),
        [0xB0] = ("Play", "재생"), [0xB1] = ("Pause", "일시정지"), [0xB2] = ("Rec", "녹음"), [0xB3] = ("FF", "빨리 감기"), [0xB4] = ("Rew", "되감기"),
        [0xB5] = ("⏭", "다음 곡"), [0xB6] = ("⏮", "이전 곡"), [0xB7] = ("⏹", "정지"), [0xB8] = ("⏏", "꺼내기(Eject)"),
        [0xCD] = ("⏯", "재생/일시정지"), [0xE2] = ("🔇", "음소거"), [0xE9] = ("🔊+", "볼륨 높이기"), [0xEA] = ("🔉-", "볼륨 낮추기"),
        [0x183] = ("Media", "미디어 플레이어"), [0x18A] = ("Mail", "메일"), [0x192] = ("Calc", "계산기"), [0x194] = ("PC", "내 컴퓨터/파일"),
        [0x221] = ("Search", "검색"), [0x223] = ("Home", "브라우저 홈"), [0x224] = ("Back", "뒤로"), [0x225] = ("Fwd", "앞으로"),
        [0x226] = ("Stop", "브라우저 정지"), [0x227] = ("Refresh", "새로 고침"), [0x22A] = ("Fav", "즐겨찾기"),
        [0x29F] = ("Mission", "Mission Control(AC Desktop Show All)"), [0x2A2] = ("Apps", "AC Desktop Show All Applications"),
    };

    public static string ShortName(HidUsage u) => u.Page switch
    {
        0x07 => Keyboard.TryGetValue(u.Usage, out var k) ? k.Short : $"K{u.Usage:X2}",
        0x0C => Consumer.TryGetValue(u.Usage, out var c) ? c.Short : $"C{u.Usage:X}",
        0xFF when u.Usage == 0x03 => "Fn🌐",
        _ => $"{u.Page:X}:{u.Usage:X}",
    };

    public static string Name(HidUsage u) => u.Page switch
    {
        0x07 => Keyboard.TryGetValue(u.Usage, out var k) ? k.Full : $"키보드 usage 0x{u.Usage:X2}",
        0x0C => Consumer.TryGetValue(u.Usage, out var c) ? c.Full : $"소비자(미디어) usage 0x{u.Usage:X}",
        0xFF when u.Usage == 0x03 => "Fn / 🌐 (Globe, macOS 전용)",
        _ => $"usage page 0x{u.Page:X} / usage 0x{u.Usage:X}",
    };
}

public sealed record RemapTargetGroup(string Id, string Title, IReadOnlyList<HidUsage> Items);

/// 키 매핑 UI 에서 고를 수 있는 대상 목록 (그룹별). macOS 앱과 같은 목록이지만
/// Windows 의 Scancode Map 은 키보드 페이지(0x07) 만 표현할 수 있어 미디어·Apple Fn 은 '표현 불가' 로 표시된다.
public static class RemapTargets
{
    static IReadOnlyList<HidUsage> Kb(uint from, uint to) => Enumerable.Range((int)from, (int)(to - from + 1)).Select(i => HidUsage.Keyboard((uint)i)).ToList();
    static IReadOnlyList<HidUsage> Kb(params uint[] a) => a.Select(HidUsage.Keyboard).ToList();
    static IReadOnlyList<HidUsage> Cs(params uint[] a) => a.Select(HidUsage.Consumer).ToList();

    public static readonly IReadOnlyList<RemapTargetGroup> Groups = new[]
    {
        new RemapTargetGroup("mod", "수정자 키", Kb(0xE0, 0xE7).Append(HidUsage.AppleFn).ToList()),
        new RemapTargetGroup("edit", "편집 · 이동", Kb(0x29, 0x2B, 0x39, 0x2C, 0x28, 0x2A, 0x4C, 0x49, 0x4A, 0x4D, 0x4B, 0x4E, 0x50, 0x52, 0x51, 0x4F, 0x46, 0x47, 0x48, 0x65)),
        new RemapTargetGroup("fn", "기능 키 F1–F24", Kb(0x3A, 0x45).Concat(Kb(0x68, 0x73)).ToList()),
        new RemapTargetGroup("alpha", "문자", Kb(0x04, 0x1D)),
        new RemapTargetGroup("num", "숫자 · 기호", Kb(0x1E, 0x27).Concat(Kb(0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x64)).ToList()),
        new RemapTargetGroup("media", "미디어 · 시스템", Cs(0xCD, 0xB5, 0xB6, 0xB7, 0xE2, 0xE9, 0xEA, 0x6F, 0x70, 0xB8, 0x32, 0x30, 0x221, 0x192, 0x18A, 0x223)),
        new RemapTargetGroup("lang", "언어 전환", Kb(0x90, 0x91, 0x88, 0x8A, 0x8B)),
        new RemapTargetGroup("keypad", "키패드", Kb(0x53, 0x63)),
        new RemapTargetGroup("off", "비활성화", new[] { HidUsage.Disabled }),
    };

    public static IReadOnlyList<HidUsage> All => Groups.SelectMany(g => g.Items).ToList();
}
