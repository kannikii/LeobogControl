namespace LeobogControl.Core;

/// 공식 드라이버 Hi8SE KB.ini 의 LedOpt 행을 그대로 옮긴 조명 효과 표.
public sealed record LedEffect(int Id, byte HardwareId, string Name, bool SupportsSpeed, bool SupportsBrightness,
                               bool SupportsDirection, bool SupportsRandomColor, bool SupportsCustomColor, bool FnCycle)
{
    public override string ToString() => $"{Id}. {Name}";
}

public static class LedEffects
{
    public const int DefaultIndex = 10;   // KB.ini DefLedIndex

    public static readonly IReadOnlyList<LedEffect> All = Build();

    static IReadOnlyList<LedEffect> Build()
    {
        (byte Hw, int Speed, int Bright, int Dir, int Random, int Custom)[] rows =
        {
            (1, 0, 1, 0, 1, 1), (2, 1, 1, 0, 1, 1), (3, 1, 1, 0, 0, 0), (4, 1, 1, 0, 1, 1), (5, 1, 1, 0, 1, 1),
            (6, 1, 1, 0, 1, 1), (7, 1, 1, 0, 1, 1), (8, 1, 1, 0, 1, 1), (9, 1, 1, 0, 1, 1), (10, 1, 1, 0, 1, 1),
            (11, 1, 1, 0, 1, 1), (12, 1, 1, 0, 1, 1), (13, 1, 1, 0, 1, 1), (14, 1, 1, 0, 1, 1), (15, 1, 1, 0, 0, 0),
            (16, 1, 1, 0, 0, 0), (17, 1, 1, 0, 0, 0), (18, 1, 1, 0, 1, 1), (21, 0, 0, 0, 0, 0), (0, 0, 0, 0, 0, 0),
        };
        string[] names =
        {
            "항상 켜짐", "숨쉬기", "무지개", "반응(가로)", "빗방울", "무지개 룰렛", "반응(파동)", "별빛", "눈길 발자국(踏雪无痕)",
            "스네이크", "흐르는 물(流水)", "반응", "라인 웨이브", "좌우 스캔(左右扫描)", "무지개 바람개비", "무지개 폭포", "꽃잎",
            "회전 폭풍(旋转风暴)", "사용자 정의 모드", "끄기",
        };
        return rows.Select((r, i) => new LedEffect(i + 1, r.Hw, names[i], r.Speed == 1, r.Bright == 1, r.Dir == 1, r.Random == 1, r.Custom == 1, i < 18)).ToList();
    }

    public static readonly IReadOnlyList<(string Name, byte R, byte G, byte B)> PresetColors = new[]
    {
        ("빨강", (byte)255, (byte)0, (byte)0), ("주황", (byte)255, (byte)128, (byte)0), ("노랑", (byte)255, (byte)255, (byte)0),
        ("초록", (byte)0, (byte)255, (byte)0), ("청록", (byte)0, (byte)255, (byte)255), ("파랑", (byte)0, (byte)0, (byte)255),
        ("보라", (byte)160, (byte)0, (byte)255), ("분홍", (byte)255, (byte)0, (byte)160), ("흰색", (byte)255, (byte)255, (byte)255),
    };
}
