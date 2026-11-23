using System.Runtime.InteropServices;
using LeobogControl.Core;

namespace LeobogControl.UI;

/// 백그라운드 실행(알림 영역 아이콘) · 창 닫기 동작 · 시작 프로그램 등록
public sealed partial class MainForm
{
    readonly AppSettings _settings;
    bool _startHidden;      // --background 로 시작: 첫 표시를 건너뛰고 트레이 아이콘으로만 시작
    bool _exiting;          // 트레이 [종료] 로 끄는 중 — FormClosing 에서 숨기지 않는다
    NotifyIcon _tray = null!;
    ToolStripMenuItem _trayStatus = null!;
    RegisteredWaitHandle? _showWait;

    // 설정 탭
    readonly RadioButton _bgRadio = new() { Text = "백그라운드에서 계속 실행 — 작업 표시줄 오른쪽 아래 알림 영역에 아이콘 표시", AutoSize = true };
    readonly RadioButton _quitRadio = new() { Text = "그냥 끄기 — 창을 닫으면 앱도 종료", AutoSize = true };
    readonly CheckBox _startupCheck = new() { Text = "Windows 시작 시 자동 실행 (창 없이 알림 영역 아이콘으로 시작)", AutoSize = true };
    readonly Label _startupStatus = new() { AutoSize = true, ForeColor = Color.DimGray, Padding = new Padding(18, 2, 0, 0) };
    bool _syncingStartup;

    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);

    void SetupBackground()
    {
        var menu = new ContextMenuStrip();
        _trayStatus = new ToolStripMenuItem { Enabled = false };
        menu.Items.Add(new ToolStripMenuItem("Leobog Control 열기", null, (_, _) => ShowFromTray()) { Font = _boldFont });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_trayStatus);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("설정…", null, (_, _) => { ShowFromTray(); _tabs.SelectedIndex = _tabs.TabPages.Count - 1; }));
        menu.Items.Add(new ToolStripMenuItem("종료", null, (_, _) => ExitApp()));
        menu.Opening += (_, _) => _trayStatus.Text = _hid.IsOpen ? "키보드 연결됨" : (_hid.Devices.Any(d => d.VendorId == HidDeviceManager.LeobogVendorId) ? "키보드 발견 · 열리지 않음" : "키보드 없음");

        _tray = new NotifyIcon { Text = "Leobog Control", Icon = LoadTrayIcon(), ContextMenuStrip = menu };
        _tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowFromTray(); };
        UpdateTrayVisibility();

        FormClosing += (_, e) =>
        {
            // X 버튼·Alt+F4 만 숨긴다. Windows 종료·작업 관리자·트레이 [종료] 는 그대로 끈다.
            if (_exiting || e.CloseReason != CloseReason.UserClosing || _settings.CloseBehavior != CloseBehavior.Background) return;
            e.Cancel = true;
            Hide();
            AppLog.Info("app", "창 닫힘 → 백그라운드 실행 (알림 영역 아이콘)");
            if (!_settings.TrayHintShown)
            {
                _tray.ShowBalloonTip(5000, "Leobog Control 은 계속 실행 중입니다",
                    "알림 영역 아이콘을 누르면 다시 열고, 오른쪽 클릭으로 종료할 수 있습니다. [설정] 탭에서 '그냥 끄기' 로 바꿀 수 있습니다.", ToolTipIcon.Info);
                _settings.TrayHintShown = true;
                _settings.Save();
            }
        };
        FormClosed += (_, _) => { _showWait?.Unregister(null); _tray.Visible = false; _tray.Dispose(); };
        Shown += (_, _) => BeginInvoke(AskStartupIfFirstRun);
    }

    /// 트레이 아이콘: 실행 파일에 넣은 app.ico 에서 작은 아이콘(보통 16px) 프레임을 고른다
    static Icon LoadTrayIcon()
    {
        try
        {
            using var s = typeof(MainForm).Assembly.GetManifestResourceStream("app.ico");
            if (s is not null) return new Icon(s, SystemInformation.SmallIconSize);
        }
        catch { }
        try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application; } catch { return SystemIcons.Application; }
    }

    void UpdateTrayVisibility() => _tray.Visible = _settings.CloseBehavior == CloseBehavior.Background;

    /// 창 없이 시작: Application.Run 의 첫 표시 요청을 가로채 핸들만 만들고 숨긴 채로 둔다
    protected override void SetVisibleCore(bool value)
    {
        if (_startHidden && value)
        {
            _startHidden = false;
            if (!IsHandleCreated) CreateHandle();
            InitOnce();
            AppLog.Info("app", "창 없이 시작 (알림 영역 아이콘)");
            value = false;
        }
        base.SetVisibleCore(value);
    }

    /// 두 번째 실행(바로 가기 다시 누름 등)이 보내는 신호를 받아 창을 앞으로 가져온다
    public void ListenForShowSignal(EventWaitHandle signal) =>
        _showWait = ThreadPool.RegisterWaitForSingleObject(signal, (_, _) => UI(ShowFromTray), null, Timeout.Infinite, false);

    void ShowFromTray()
    {
        if (IsDisposed) return;
        Show();
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate();
        SetForegroundWindow(Handle);
    }

    void ExitApp()
    {
        _exiting = true;
        _tray.Visible = false;
        Close();
    }

    TabPage BuildSettingsTab()
    {
        var page = new TabPage("설정");
        var flow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(12) };

        var closeBox = new GroupBox { Text = "창을 닫을 때", AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, MinimumSize = new Size(640, 0), Padding = new Padding(10) };
        var closeFlow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true };
        (_settings.CloseBehavior == CloseBehavior.Background ? _bgRadio : _quitRadio).Checked = true;
        void OnCloseChanged(object? _, EventArgs __)
        {
            var b = _bgRadio.Checked ? CloseBehavior.Background : CloseBehavior.Quit;
            if (b == _settings.CloseBehavior) return;
            _settings.CloseBehavior = b;
            _settings.Save();
            UpdateTrayVisibility();
            AppLog.Info("settings", "창 닫기 동작: " + (b == CloseBehavior.Background ? "백그라운드 실행" : "그냥 끄기"));
        }
        _bgRadio.CheckedChanged += OnCloseChanged;
        _quitRadio.CheckedChanged += OnCloseChanged;
        closeFlow.Controls.Add(_bgRadio);
        closeFlow.Controls.Add(_quitRadio);
        closeFlow.Controls.Add(new Label
        {
            AutoSize = true, ForeColor = Color.DimGray, Padding = new Padding(18, 6, 0, 0),
            Text = "백그라운드 실행 중에는 알림 영역 아이콘을 누르면 창이 다시 열리고, 오른쪽 클릭 메뉴에서 열기·종료할 수 있습니다.",
        });
        closeBox.Controls.Add(closeFlow);

        var startBox = new GroupBox { Text = "시작 프로그램", AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, MinimumSize = new Size(640, 0), Padding = new Padding(10) };
        var startFlow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true };
        _startupCheck.CheckedChanged += (_, _) =>
        {
            if (_syncingStartup) return;
            var err = StartupRegistration.Set(_startupCheck.Checked);
            if (err is not null) Msg("시작 프로그램 설정을 바꾸지 못했습니다: " + err);
            RefreshStartup();
        };
        startFlow.Controls.Add(_startupCheck);
        startFlow.Controls.Add(_startupStatus);
        startBox.Controls.Add(startFlow);

        flow.Controls.Add(closeBox);
        flow.Controls.Add(startBox);
        page.Controls.Add(flow);
        page.Enter += (_, _) => RefreshStartup();   // 작업 관리자 → 시작 앱 에서 끈 경우도 반영
        RefreshStartup();
        return page;
    }

    void RefreshStartup()
    {
        _syncingStartup = true;
        _startupCheck.Checked = StartupRegistration.IsEnabled;
        _syncingStartup = false;
        _startupStatus.Text = StartupRegistration.IsEnabled ? "등록됨 — 작업 관리자 → 시작 앱 목록에 'LeobogControl' 로 보입니다."
            : StartupRegistration.PointsElsewhere ? "다른 위치의 실행 파일로 등록돼 있습니다 — 체크하면 지금 위치로 고칩니다."
            : "등록 안 됨";
    }

    /// 처음 실행 때 한 번: 시작 프로그램으로 등록할지 묻는다
    void AskStartupIfFirstRun()
    {
        if (_settings.StartupAsked || !Visible) return;
        _settings.StartupAsked = true;
        _settings.Save();
        if (StartupRegistration.IsEnabled) return;
        var r = MessageBox.Show(this,
            "Windows 를 켤 때마다 Leobog Control 을 자동으로 실행할까요?\n\n" +
            "자동 실행하면 창 없이 작업 표시줄 오른쪽 아래 알림 영역 아이콘으로만 시작합니다.\n" +
            "나중에 [설정] 탭에서 언제든 바꿀 수 있습니다.",
            "시작 프로그램으로 등록", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        AppLog.Info("startup", "첫 실행 질문: " + (r == DialogResult.Yes ? "등록" : "나중에"));
        if (r == DialogResult.Yes)
        {
            var err = StartupRegistration.Set(true);
            if (err is not null) Msg("시작 프로그램으로 등록하지 못했습니다: " + err);
        }
        RefreshStartup();
    }
}
