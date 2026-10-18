using LeobogControl.Core;
using LeobogControl.UI;

namespace LeobogControl;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        AppLog.Info("app", "시작 (Windows)");
        Application.ThreadException += (_, e) => AppLog.Error("app", "UI 예외: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => AppLog.Error("app", "처리되지 않은 예외: " + e.ExceptionObject);
        Application.ApplicationExit += (_, _) => AppLog.Info("app", "종료");
        Application.Run(new MainForm());
    }
}
