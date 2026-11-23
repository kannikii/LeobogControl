using Microsoft.Win32;

namespace LeobogControl.Core;

/// Windows 시작 시 자동 실행. 현재 사용자 Run 키(HKCU\Software\Microsoft\Windows\CurrentVersion\Run)에 등록하므로 관리자 권한이 필요 없고,
/// 작업 관리자 → 시작 앱 목록에도 'LeobogControl' 로 나타난다. 로그인 때는 --background 로 실행돼 창 없이 트레이 아이콘으로만 시작한다.
public static class StartupRegistration
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ValueName = "LeobogControl";
    public const string BackgroundArg = "--background";

    static string Command => $"\"{Environment.ProcessPath ?? Application.ExecutablePath}\" {BackgroundArg}";

    /// 등록돼 있고, 지금 실행 중인 exe 를 가리키는가
    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey);
                return key?.GetValue(ValueName) is string v && string.Equals(v, Command, StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }
    }

    /// 다른 위치의 exe 로 등록돼 있는가 (앱을 옮긴 경우 — 다시 켜면 현재 위치로 고친다)
    public static bool PointsElsewhere
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey);
                return key?.GetValue(ValueName) is string v && !string.Equals(v, Command, StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }
    }

    /// 등록/해제. 실패하면 오류 문구를 돌려준다.
    public static string? Set(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (on) key.SetValue(ValueName, Command);
            else if (key.GetValue(ValueName) is not null) key.DeleteValue(ValueName);
            AppLog.Info("startup", on ? $"시작 프로그램 등록: {Command}" : "시작 프로그램 해제");
            return null;
        }
        catch (Exception e)
        {
            AppLog.Error("startup", $"시작 프로그램 {(on ? "등록" : "해제")} 실패: {e.Message}");
            return e.Message;
        }
    }
}
