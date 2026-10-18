import Foundation

/// Fn 조합(단축키) 한 줄. 출처: 공식 LEOBOG ONE 드라이버의 Hi8SE KB.ini [FN1] 레이어 + Leobog 공통 설명서.
public struct FnShortcut: Identifiable, Sendable, Hashable {
    public enum Source: String, Sendable { case driver = "공식 드라이버 KB.ini", manual = "Leobog 설명서(공통)", both = "드라이버 + 설명서", measured = "실측 (이 키보드)" }

    public let id: String
    public let combo: String            // 예: "Fn + F7"
    public let keyID: Int?              // 물리 키 번호 (다이어그램 강조용)
    public let category: String
    public let winAction: String        // Windows 모드 동작
    public let macAction: String        // Mac 모드 동작
    public let expected: HIDUsage?      // Mac 에서 눌렀을 때 도착할 것으로 기대되는 usage (키 테스터로 확인)
    public let source: Source
    public let certain: Bool            // false = 코드만 있고 의미는 추정

    public init(_ combo: String, key: Int?, cat: String, win: String, mac: String, expected: HIDUsage? = nil, source: Source = .both, certain: Bool = true) {
        self.id = combo; self.combo = combo; self.keyID = key; self.category = cat
        self.winAction = win; self.macAction = mac; self.expected = expected; self.source = source; self.certain = certain
    }
}

public enum FnLayerReference {
    public static let categories = ["미디어 · 화면", "조명", "모드 · 연결", "편집 키", "시스템 · 기타", "노브"]

    public static let shortcuts: [FnShortcut] = [
        // 미디어/화면 (드라이버 FN1: F1=0x02000070, F2=0x0200006F, F7=0x020000B6, F8=0x020000CD, F9=0x020000B5, F10=0x020000E2, F11=0x020000EA, F12=0x020000E9)
        FnShortcut("Fn + F1", key: 2, cat: "미디어 · 화면", win: "화면 밝기 낮추기", mac: "화면 밝기 낮추기", expected: .consumer(0x70)),
        FnShortcut("Fn + F2", key: 3, cat: "미디어 · 화면", win: "화면 밝기 높이기", mac: "화면 밝기 높이기", expected: .consumer(0x6F)),
        FnShortcut("Fn + F3", key: 4, cat: "미디어 · 화면", win: "Alt + Tab (앱 전환)", mac: "Mission Control", expected: nil, certain: false),
        FnShortcut("Fn + F4", key: 5, cat: "미디어 · 화면", win: "Alt + Esc (창 전환)", mac: "Launchpad / Spotlight", expected: nil, certain: false),
        FnShortcut("Fn + F5", key: 6, cat: "미디어 · 화면", win: "키보드 조명 밝기 낮추기", mac: "키보드 조명 밝기 낮추기", expected: nil, certain: false),
        FnShortcut("Fn + F6", key: 7, cat: "미디어 · 화면", win: "키보드 조명 밝기 높이기", mac: "키보드 조명 밝기 높이기", expected: nil, certain: false),
        FnShortcut("Fn + F7", key: 8, cat: "미디어 · 화면", win: "이전 곡", mac: "이전 곡", expected: .consumer(0xB6)),
        FnShortcut("Fn + F8", key: 9, cat: "미디어 · 화면", win: "재생 / 일시정지", mac: "재생 / 일시정지", expected: .consumer(0xCD)),
        FnShortcut("Fn + F9", key: 10, cat: "미디어 · 화면", win: "다음 곡", mac: "다음 곡", expected: .consumer(0xB5)),
        FnShortcut("Fn + F10", key: 11, cat: "미디어 · 화면", win: "음소거", mac: "음소거", expected: .consumer(0xE2)),
        FnShortcut("Fn + F11", key: 12, cat: "미디어 · 화면", win: "볼륨 낮추기", mac: "볼륨 낮추기", expected: .consumer(0xEA)),
        FnShortcut("Fn + F12", key: 13, cat: "미디어 · 화면", win: "볼륨 높이기", mac: "볼륨 높이기", expected: .consumer(0xE9)),
        // 조명 (드라이버: Tab=0x08020000, \=0x08000000, ↑=0x08030100, ↓=0x08030200, ←=0x08040200, →=0x08040100)
        FnShortcut("Fn + Tab", key: 30, cat: "조명", win: "조명 효과 전환", mac: "조명 효과 전환", source: .both),
        FnShortcut("Fn + \\", key: 43, cat: "조명", win: "조명 색상 전환", mac: "조명 색상 전환", certain: false),
        FnShortcut("Fn + ↑", key: 70, cat: "조명", win: "조명 밝기 높이기", mac: "조명 밝기 높이기"),
        FnShortcut("Fn + ↓", key: 78, cat: "조명", win: "조명 밝기 낮추기", mac: "조명 밝기 낮추기"),
        FnShortcut("Fn + →", key: 79, cat: "조명", win: "조명 속도 높이기", mac: "조명 속도 높이기", certain: false),
        FnShortcut("Fn + ←", key: 77, cat: "조명", win: "조명 속도 낮추기", mac: "조명 속도 낮추기", certain: false),
        // 모드/연결 (드라이버: Q=0x07000019, W=0x07000018, E=0x0700001A, 1/2/3=0x07000005/06/07, `=0x07000008)
        FnShortcut("Fn + M", key: 65, cat: "모드 · 연결", win: "Mac ↔ Windows 모드 전환 (Fn 은 스페이스 바로 오른쪽)", mac: "Mac ↔ Windows 모드 전환 (Fn 은 스페이스 오른쪽 두 번째)", source: .measured),
        FnShortcut("Fn + W", key: 32, cat: "모드 · 연결", win: "Windows 모드로 전환 (드라이버 코드만 있음, 이 키보드에서는 미확인 — Fn + M 사용)", mac: "Windows 모드로 전환 (미확인)", source: .driver, certain: false),
        FnShortcut("Fn + Q", key: 31, cat: "모드 · 연결", win: "Mac 모드로 전환", mac: "Mac 모드로 전환", source: .driver, certain: false),
        FnShortcut("Fn + E", key: 33, cat: "모드 · 연결", win: "기능 코드 0x1A (모드 전환 계열, 미확인)", mac: "기능 코드 0x1A (미확인)", source: .driver, certain: false),
        FnShortcut("Fn + 1 / 2 / 3", key: 16, cat: "모드 · 연결", win: "블루투스 장치 1 / 2 / 3 선택 (3초 길게: 페어링)", mac: "블루투스 장치 1 / 2 / 3 선택 (3초 길게: 페어링)", certain: false),
        FnShortcut("Fn + `", key: 15, cat: "모드 · 연결", win: "기능 코드 0x08 (연결 계열, 미확인)", mac: "기능 코드 0x08 (미확인)", source: .driver, certain: false),
        FnShortcut("Fn + Space (길게)", key: 74, cat: "모드 · 연결", win: "배터리 잔량 표시 (설명서 공통)", mac: "배터리 잔량 표시", source: .manual, certain: false),
        FnShortcut("Fn + B", key: 63, cat: "모드 · 연결", win: "기능 코드 0x11 (배터리 표시로 추정)", mac: "기능 코드 0x11 (추정)", source: .driver, certain: false),
        // 편집 키 (드라이버: U=PrtSc, I=ScrLk, O=Pause, Del=Insert, End=Home)
        FnShortcut("Fn + U", key: 37, cat: "편집 키", win: "Print Screen", mac: "Print Screen (F13 계열)", expected: .keyboard(0x46), source: .driver),
        FnShortcut("Fn + I", key: 38, cat: "편집 키", win: "Scroll Lock", mac: "Scroll Lock (F14 계열)", expected: .keyboard(0x47), source: .driver),
        FnShortcut("Fn + O", key: 39, cat: "편집 키", win: "Pause", mac: "Pause (F15 계열)", expected: .keyboard(0x48), source: .driver, certain: false),
        FnShortcut("Fn + Del", key: 29, cat: "편집 키", win: "Insert", mac: "Insert", expected: .keyboard(0x49), source: .driver),
        FnShortcut("Fn + End", key: 14, cat: "편집 키", win: "Home", mac: "Home", expected: .keyboard(0x4A), source: .driver),
        // 시스템/기타 (드라이버: Win=0x07000001 Win 잠금, Esc=0x07000004, G=0x0700000A)
        FnShortcut("Fn + Win 자리 키", key: 72, cat: "시스템 · 기타", win: "Win 키 잠금 / 해제", mac: "Win 자리 키(Mac 모드에서는 ⌥) 잠금 / 해제 — 미확인", source: .driver, certain: false),
        FnShortcut("Fn + Esc", key: 1, cat: "시스템 · 기타", win: "기능 코드 0x04 (키보드 잠금/초기화 계열, 미확인)", mac: "기능 코드 0x04 (미확인)", source: .driver, certain: false),
        FnShortcut("Fn + ` (3초 길게)", key: 15, cat: "시스템 · 기타", win: "공장 초기화 (설명서 공통)", mac: "공장 초기화 (설명서 공통)", source: .manual, certain: false),
        FnShortcut("Fn + G", key: 50, cat: "시스템 · 기타", win: "기능 코드 0x0A (게임 모드로 추정)", mac: "기능 코드 0x0A (추정)", source: .driver, certain: false),
        // 노브 (드라이버 K81 = 0x0700001D)
        FnShortcut("노브 돌리기", key: 81, cat: "노브", win: "볼륨 조절", mac: "볼륨 조절", expected: .consumer(0xE9)),
        FnShortcut("노브 누르기", key: 81, cat: "노브", win: "음소거", mac: "음소거", expected: .consumer(0xE2), certain: false),
    ]

    public static func shortcuts(in category: String) -> [FnShortcut] { shortcuts.filter { $0.category == category } }
}
