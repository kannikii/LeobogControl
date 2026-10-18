namespace LeobogControl.Core;

/// 앱이 쓰는 파일 위치. macOS 버전의 ~/Library/Application Support/LeobogControl 에 대응한다.
public static class AppPaths
{
    public static string SupportDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LeobogControl");
    public static string LogDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LeobogControl", "Logs");
    public static string LogFile => Path.Combine(LogDir, "app.log");
    /// 키 매핑 저장 파일 — macOS 앱의 remaps.json 과 같은 JSON 형식 ({"src":{"page":7,"usage":57},"dst":{...}})
    public static string RemapsFile => Path.Combine(SupportDir, "remaps.json");
    public static string RegApplyFile => Path.Combine(SupportDir, "scancode-map.reg");
    public static string RegRemoveFile => Path.Combine(SupportDir, "scancode-map-remove.reg");
}
