using System.Runtime.InteropServices;
using LeobogControl.Core;
using LeobogControl.UI;

namespace LeobogControl;

static class Program
{
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int processId);
    const int AsfwAny = -1;

    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        var background = args.Any(a => string.Equals(a, StartupRegistration.BackgroundArg, StringComparison.OrdinalIgnoreCase));

        // 한 번만 실행: 이미 떠 있으면 (트레이에 숨어 있어도) 그 창을 앞으로 가져오고 끝낸다
        using var mutex = new Mutex(true, @"Local\LeobogControl.SingleInstance", out var first);
        using var showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\LeobogControl.Show");
        if (!first)
        {
            if (!background) { AllowSetForegroundWindow(AsfwAny); showSignal.Set(); }
            return;
        }

        var settings = AppSettings.Load();
        var startHidden = background && settings.CloseBehavior == CloseBehavior.Background;
        AppLog.Info("app", "시작 (Windows)" + (background ? " — 로그인 자동 실행" : ""));
        Application.ThreadException += (_, e) => AppLog.Error("app", "UI 예외: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => AppLog.Error("app", "처리되지 않은 예외: " + e.ExceptionObject);
        Application.ApplicationExit += (_, _) => AppLog.Info("app", "종료");

        var form = new MainForm(settings, startHidden);
        form.ListenForShowSignal(showSignal);
        Application.Run(form);
        GC.KeepAlive(mutex);
    }
}
