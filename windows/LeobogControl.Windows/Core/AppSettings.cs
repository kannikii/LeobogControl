using System.Text.Json;
using System.Text.Json.Serialization;

namespace LeobogControl.Core;

/// 창을 닫았을 때의 동작 (macOS 버전의 CloseBehavior 와 같은 값)
public enum CloseBehavior
{
    /// 창만 숨기고 작업 표시줄 알림 영역(트레이) 아이콘으로 계속 실행
    Background,
    /// 창을 닫으면 앱도 종료
    Quit,
}

/// 앱 설정. %APPDATA%\LeobogControl\settings.json 에 저장한다.
public sealed class AppSettings
{
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public CloseBehavior CloseBehavior { get; set; } = CloseBehavior.Background;
    /// 처음 실행 때 '시작 프로그램으로 등록할까요?' 를 이미 물었는가
    public bool StartupAsked { get; set; }
    /// 창을 처음 숨겼을 때 '트레이에서 계속 실행 중' 풍선 알림을 이미 보였는가
    public bool TrayHintShown { get; set; }

    static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(AppPaths.SettingsFile))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(AppPaths.SettingsFile), Options) ?? new();
        }
        catch (Exception e) { AppLog.Error("settings", "설정 읽기 실패, 기본값 사용: " + e.Message); }
        return new();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(AppPaths.SupportDir);
            File.WriteAllText(AppPaths.SettingsFile, JsonSerializer.Serialize(this, Options));
        }
        catch (Exception e) { AppLog.Error("settings", "설정 저장 실패: " + e.Message); }
    }
}
