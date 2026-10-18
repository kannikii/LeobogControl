namespace LeobogControl.Core;

/// 동작 기록. %LOCALAPPDATA%\LeobogControl\Logs\app.log 에 남기고, 진단 탭에도 바로 보여 준다.
public static class AppLog
{
    static readonly object Gate = new();
    public static event Action<string>? Line;

    public static void Info(string category, string message) => Write("I", category, message);
    public static void Error(string category, string message) => Write("E", category, message);

    static void Write(string level, string category, string message)
    {
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {level} [{category}] {message}";
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(AppPaths.LogDir);
                File.AppendAllText(AppPaths.LogFile, line + Environment.NewLine);
            }
            catch { /* 로그 실패는 무시 */ }
        }
        Line?.Invoke(line);
    }
}
