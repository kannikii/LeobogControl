import Foundation

/// 공식 드라이버 Hi8SE KB.ini 의 LedOpt 행을 그대로 옮긴 조명 효과 표.
/// `LedOptN = 하드웨어번호, 아이콘, 속도지원, 밝기지원, 방향지원, 알록달록(랜덤색)지원, 사용자색지원`
public struct LedEffect: Identifiable, Sendable, Hashable {
    public let id: Int             // UI 순번 (1...20)
    public let hardwareID: UInt8   // 키보드에 보내는 효과 번호
    public let name: String        // 드라이버 한국어 라벨
    public let supportsSpeed: Bool
    public let supportsBrightness: Bool
    public let supportsDirection: Bool
    public let supportsRandomColor: Bool
    public let supportsCustomColor: Bool
    public let fnCycle: Bool       // Fn+Tab 순환에 포함(추정: 사용자 정의/끄기 제외)
}

public enum LedEffects {
    public static let defaultIndex = 10   // KB.ini DefLedIndex
    public static let all: [LedEffect] = {
        let rows: [(UInt8, Int, Int, Int, Int, Int)] = [
            (1, 0, 1, 0, 1, 1), (2, 1, 1, 0, 1, 1), (3, 1, 1, 0, 0, 0), (4, 1, 1, 0, 1, 1), (5, 1, 1, 0, 1, 1),
            (6, 1, 1, 0, 1, 1), (7, 1, 1, 0, 1, 1), (8, 1, 1, 0, 1, 1), (9, 1, 1, 0, 1, 1), (10, 1, 1, 0, 1, 1),
            (11, 1, 1, 0, 1, 1), (12, 1, 1, 0, 1, 1), (13, 1, 1, 0, 1, 1), (14, 1, 1, 0, 1, 1), (15, 1, 1, 0, 0, 0),
            (16, 1, 1, 0, 0, 0), (17, 1, 1, 0, 0, 0), (18, 1, 1, 0, 1, 1), (21, 0, 0, 0, 0, 0), (0, 0, 0, 0, 0, 0),
        ]
        let names = ["항상 켜짐", "숨쉬기", "무지개", "반응(가로)", "빗방울", "무지개 룰렛", "반응(파동)", "별빛", "눈길 발자국(踏雪无痕)",
                     "스네이크", "흐르는 물(流水)", "반응", "라인 웨이브", "좌우 스캔(左右扫描)", "무지개 바람개비", "무지개 폭포", "꽃잎",
                     "회전 폭풍(旋转风暴)", "사용자 정의 모드", "끄기"]
        return rows.enumerated().map { i, r in
            LedEffect(id: i + 1, hardwareID: r.0, name: names[i], supportsSpeed: r.1 == 1, supportsBrightness: r.2 == 1,
                      supportsDirection: r.3 == 1, supportsRandomColor: r.4 == 1, supportsCustomColor: r.5 == 1,
                      fnCycle: i < 18)
        }
    }()

    public static let presetColors: [(String, UInt8, UInt8, UInt8)] = [
        ("빨강", 255, 0, 0), ("주황", 255, 128, 0), ("노랑", 255, 255, 0), ("초록", 0, 255, 0), ("청록", 0, 255, 255),
        ("파랑", 0, 0, 255), ("보라", 160, 0, 255), ("분홍", 255, 0, 160), ("흰색", 255, 255, 255),
    ]
}
