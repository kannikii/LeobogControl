namespace LeobogControl.Core;

public enum FnSource { Driver, Manual, Both, Measured }

public static class FnSourceExt
{
    public static string Label(this FnSource s) => s switch
    {
        FnSource.Driver => "공식 드라이버 KB.ini",
        FnSource.Manual => "Leobog 설명서(공통)",
        FnSource.Both => "드라이버 + 설명서",
        _ => "실측 (이 키보드)",
    };
}

/// Fn 조합(단축키) 한 줄. 출처: 공식 LEOBOG ONE 드라이버의 Hi8SE KB.ini [FN1] 레이어 + Leobog 공통 설명서.
public sealed record FnShortcut(string Combo, int? KeyId, string Category, string WinAction, string MacAction,
                                HidUsage? Expected = null, FnSource Source = FnSource.Both, bool Certain = true);

public static class FnLayerReference
{
    public static readonly string[] Categories = { "미디어 · 화면", "조명", "모드 · 연결", "편집 키", "시스템 · 기타", "노브" };

    static HidUsage C(uint u) => HidUsage.Consumer(u);
    static HidUsage K(uint u) => HidUsage.Keyboard(u);

    public static readonly IReadOnlyList<FnShortcut> Shortcuts = new[]
    {
        new FnShortcut("Fn + F1", 2, "미디어 · 화면", "화면 밝기 낮추기", "화면 밝기 낮추기", C(0x70)),
        new FnShortcut("Fn + F2", 3, "미디어 · 화면", "화면 밝기 높이기", "화면 밝기 높이기", C(0x6F)),
        new FnShortcut("Fn + F3", 4, "미디어 · 화면", "Alt + Tab (앱 전환)", "Mission Control", null, FnSource.Both, false),
        new FnShortcut("Fn + F4", 5, "미디어 · 화면", "Alt + Esc (창 전환)", "Launchpad / Spotlight", null, FnSource.Both, false),
        new FnShortcut("Fn + F5", 6, "미디어 · 화면", "키보드 조명 밝기 낮추기", "키보드 조명 밝기 낮추기", null, FnSource.Both, false),
        new FnShortcut("Fn + F6", 7, "미디어 · 화면", "키보드 조명 밝기 높이기", "키보드 조명 밝기 높이기", null, FnSource.Both, false),
        new FnShortcut("Fn + F7", 8, "미디어 · 화면", "이전 곡", "이전 곡", C(0xB6)),
        new FnShortcut("Fn + F8", 9, "미디어 · 화면", "재생 / 일시정지", "재생 / 일시정지", C(0xCD)),
        new FnShortcut("Fn + F9", 10, "미디어 · 화면", "다음 곡", "다음 곡", C(0xB5)),
        new FnShortcut("Fn + F10", 11, "미디어 · 화면", "음소거", "음소거", C(0xE2)),
        new FnShortcut("Fn + F11", 12, "미디어 · 화면", "볼륨 낮추기", "볼륨 낮추기", C(0xEA)),
        new FnShortcut("Fn + F12", 13, "미디어 · 화면", "볼륨 높이기", "볼륨 높이기", C(0xE9)),
        new FnShortcut("Fn + Tab", 30, "조명", "조명 효과 전환", "조명 효과 전환"),
        new FnShortcut("Fn + \\", 43, "조명", "조명 색상 전환", "조명 색상 전환", null, FnSource.Both, false),
        new FnShortcut("Fn + ↑", 70, "조명", "조명 밝기 높이기", "조명 밝기 높이기"),
        new FnShortcut("Fn + ↓", 78, "조명", "조명 밝기 낮추기", "조명 밝기 낮추기"),
        new FnShortcut("Fn + →", 79, "조명", "조명 속도 높이기", "조명 속도 높이기", null, FnSource.Both, false),
        new FnShortcut("Fn + ←", 77, "조명", "조명 속도 낮추기", "조명 속도 낮추기", null, FnSource.Both, false),
        new FnShortcut("Fn + M", 65, "모드 · 연결", "Mac ↔ Windows 모드 전환 (Fn 은 스페이스 바로 오른쪽)", "Mac ↔ Windows 모드 전환 (Fn 은 스페이스 오른쪽 두 번째)", null, FnSource.Measured),
        new FnShortcut("Fn + W", 32, "모드 · 연결", "Windows 모드로 전환 (드라이버 코드만 있음, 이 키보드에서는 미확인 — Fn + M 사용)", "Windows 모드로 전환 (미확인)", null, FnSource.Driver, false),
        new FnShortcut("Fn + Q", 31, "모드 · 연결", "Mac 모드로 전환", "Mac 모드로 전환", null, FnSource.Driver, false),
        new FnShortcut("Fn + E", 33, "모드 · 연결", "기능 코드 0x1A (모드 전환 계열, 미확인)", "기능 코드 0x1A (미확인)", null, FnSource.Driver, false),
        new FnShortcut("Fn + 1 / 2 / 3", 16, "모드 · 연결", "블루투스 장치 1 / 2 / 3 선택 (3초 길게: 페어링)", "블루투스 장치 1 / 2 / 3 선택 (3초 길게: 페어링)", null, FnSource.Both, false),
        new FnShortcut("Fn + `", 15, "모드 · 연결", "기능 코드 0x08 (연결 계열, 미확인)", "기능 코드 0x08 (미확인)", null, FnSource.Driver, false),
        new FnShortcut("Fn + Space (길게)", 74, "모드 · 연결", "배터리 잔량 표시 (설명서 공통)", "배터리 잔량 표시", null, FnSource.Manual, false),
        new FnShortcut("Fn + B", 63, "모드 · 연결", "기능 코드 0x11 (배터리 표시로 추정)", "기능 코드 0x11 (추정)", null, FnSource.Driver, false),
        new FnShortcut("Fn + U", 37, "편집 키", "Print Screen", "Print Screen (F13 계열)", K(0x46), FnSource.Driver),
        new FnShortcut("Fn + I", 38, "편집 키", "Scroll Lock", "Scroll Lock (F14 계열)", K(0x47), FnSource.Driver),
        new FnShortcut("Fn + O", 39, "편집 키", "Pause", "Pause (F15 계열)", K(0x48), FnSource.Driver, false),
        new FnShortcut("Fn + Del", 29, "편집 키", "Insert", "Insert", K(0x49), FnSource.Driver),
        new FnShortcut("Fn + End", 14, "편집 키", "Home", "Home", K(0x4A), FnSource.Driver),
        new FnShortcut("Fn + Win 자리 키", 72, "시스템 · 기타", "Win 키 잠금 / 해제", "Win 자리 키(Mac 모드에서는 ⌥) 잠금 / 해제 — 미확인", null, FnSource.Driver, false),
        new FnShortcut("Fn + Esc", 1, "시스템 · 기타", "기능 코드 0x04 (키보드 잠금/초기화 계열, 미확인)", "기능 코드 0x04 (미확인)", null, FnSource.Driver, false),
        new FnShortcut("Fn + ` (3초 길게)", 15, "시스템 · 기타", "공장 초기화 (설명서 공통)", "공장 초기화 (설명서 공통)", null, FnSource.Manual, false),
        new FnShortcut("Fn + G", 50, "시스템 · 기타", "기능 코드 0x0A (게임 모드로 추정)", "기능 코드 0x0A (추정)", null, FnSource.Driver, false),
        new FnShortcut("노브 돌리기", 81, "노브", "볼륨 조절", "볼륨 조절", C(0xE9)),
        new FnShortcut("노브 누르기", 81, "노브", "음소거", "음소거", C(0xE2), FnSource.Both, false),
    };

    public static IEnumerable<FnShortcut> In(string category) => Shortcuts.Where(s => s.Category == category);
}
