using System.Diagnostics;
using LeobogControl.Core;

namespace LeobogControl.UI;

public sealed class MainForm : Form
{
    readonly HidDeviceManager _hid = new();
    readonly CompxClient _client;
    readonly ScancodeMapService _remap = new();
    readonly RawKeyboardInput _raw = new();
    KeyboardMode _mode = KeyboardMode.Windows;

    // 상단
    readonly Label _status = new() { AutoSize = true, Padding = new Padding(4) };
    readonly ComboBox _modeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
    readonly TabControl _tabs = new() { Dock = DockStyle.Fill };

    // 장치 탭
    readonly ListView _devList = new() { View = View.Details, FullRowSelect = true, Dock = DockStyle.Fill, MultiSelect = false };
    readonly Label _devInfo = new() { Dock = DockStyle.Bottom, AutoSize = false, Height = 120, Padding = new Padding(8) };
    readonly Button _openBtn = new() { Text = "열기", AutoSize = true }, _closeBtn = new() { Text = "닫기", AutoSize = true }, _probeBtn = new() { Text = "프로브 (읽기 전용)", AutoSize = true };

    // 키 테스터
    readonly KeyboardDiagram _testerDiagram = new() { Dock = DockStyle.Fill, Clickable = false };
    readonly ListBox _keyLog = new() { Dock = DockStyle.Fill, IntegralHeight = false };
    readonly CheckBox _allKeyboards = new() { Text = "모든 키보드 표시 (기본: LEOBOG VID 3554 만)", AutoSize = true };
    readonly Label _lastKey = new() { AutoSize = true, Padding = new Padding(4) };

    // 키 매핑
    readonly KeyboardDiagram _remapDiagram = new() { Dock = DockStyle.Fill };
    readonly ListView _remapList = new() { View = View.Details, FullRowSelect = true, Dock = DockStyle.Fill };
    readonly FlowLayoutPanel _targets = new() { Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true };
    readonly Label _pickerTitle = new() { Dock = DockStyle.Top, AutoSize = false, Height = 48, Padding = new Padding(6), Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold) };
    readonly Label _remapMsg = new() { AutoSize = true, Padding = new Padding(4), ForeColor = Color.DimGray };
    PhysicalKey? _selectedKey;

    // Fn 레이어
    readonly ListView _fnList = new() { View = View.Details, FullRowSelect = true, Dock = DockStyle.Fill, ShowGroups = true };
    readonly KeyboardDiagram _fnDiagram = new() { Dock = DockStyle.Top, Height = 220, Clickable = false };

    // 조명
    readonly ComboBox _effect = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
    readonly NumericUpDown _speed = new() { Minimum = 0, Maximum = 4, Value = 2, Width = 60 }, _bright = new() { Minimum = 0, Maximum = 4, Value = 4, Width = 60 };
    readonly ComboBox _direction = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
    readonly CheckBox _random = new() { Text = "랜덤 색상", AutoSize = true }, _commit = new() { Text = "플래시에 저장(Commit)", AutoSize = true, Checked = true };
    readonly ComboBox _presetColor = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
    readonly Panel _swatch = new() { Width = 40, Height = 24, BorderStyle = BorderStyle.FixedSingle, BackColor = Color.White };
    readonly Button _ledApply = new() { Text = "효과 적용", AutoSize = true }, _ledFill = new() { Text = "모든 키를 이 색으로", AutoSize = true };
    readonly Label _ledMsg = new() { AutoSize = true, ForeColor = Color.DimGray, Padding = new Padding(4) };
    Color _color = Color.White;

    // 진단
    readonly TextBox _vendorLog = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, Dock = DockStyle.Fill, Font = new Font("Consolas", 9f), WordWrap = false };
    readonly TextBox _appLog = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, Dock = DockStyle.Fill, Font = new Font("Consolas", 9f), WordWrap = false };
    readonly Label _diagState = new() { Dock = DockStyle.Top, AutoSize = false, Height = 96, Padding = new Padding(8) };   // 4줄 분량
    readonly ToolTip _tip = new();                                                   // RefreshPicker 마다 새로 만들면 핸들이 누수된다
    readonly Font _boldFont = new(SystemFonts.DefaultFont, FontStyle.Bold);

    public MainForm()
    {
        _client = new CompxClient(_hid);
        Text = "Leobog Control (Windows)";
        AutoScaleMode = AutoScaleMode.Dpi; AutoScaleDimensions = new SizeF(96F, 96F);   // 고DPI 에서 픽셀 높이 고정 Label 이 잘리지 않도록
        Width = 1100; Height = 760; MinimumSize = new Size(900, 620);
        StartPosition = FormStartPosition.CenterScreen;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

        var top = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(6), WrapContents = false };
        _modeBox.Items.AddRange(new object[] { "Windows 모드 (Fn+M)", "Mac 모드 (Fn+M)" });
        _modeBox.SelectedIndex = 0;
        _modeBox.SelectedIndexChanged += (_, _) => SetMode(_modeBox.SelectedIndex == 1 ? KeyboardMode.Mac : KeyboardMode.Windows);
        var refresh = new Button { Text = "장치 새로 고침", AutoSize = true };
        refresh.Click += (_, _) => _hid.Refresh();
        top.Controls.Add(new Label { Text = "키보드 배열:", AutoSize = true, Padding = new Padding(0, 6, 0, 0) });
        top.Controls.Add(_modeBox);
        top.Controls.Add(refresh);
        top.Controls.Add(_status);

        _tabs.TabPages.Add(BuildDeviceTab());
        _tabs.TabPages.Add(BuildTesterTab());
        _tabs.TabPages.Add(BuildRemapTab());
        _tabs.TabPages.Add(BuildFnTab());
        _tabs.TabPages.Add(BuildLedTab());
        _tabs.TabPages.Add(BuildDiagTab());
        Controls.Add(_tabs);
        Controls.Add(top);

        _hid.DevicesChanged += () => UI(RefreshDevices);
        _client.LogChanged += () => UI(RefreshVendorLog);
        _client.StateChanged += () => UI(RefreshState);
        _remap.Changed += () => UI(RefreshRemaps);
        AppLog.Line += l => UI(() => AppendAppLog(l));
        _raw.KeyEvent += OnRawKey;

        Load += (_, _) =>
        {
            _raw.Register(Handle);
            _hid.Refresh();
            if (!_hid.IsOpen) _hid.OpenBest();
            RefreshState(); RefreshRemaps(); RefreshVendorLog();
            // 지금까지의 이벤트 줄은 이미 파일에도 있으므로, 파일 꼬리로 한 번에 바꿔 중복·순서 역전을 막는다
            try { if (File.Exists(AppPaths.LogFile)) { var tail = File.ReadLines(AppPaths.LogFile).TakeLast(200).ToList(); _appLines.Clear(); _appLines.AddRange(tail); RenderAppLog(); } } catch { }
        };
        FormClosed += (_, _) => { _raw.Dispose(); _hid.Dispose(); };
    }

    protected override void WndProc(ref Message m)
    {
        _raw.ProcessMessage(ref m);
        base.WndProc(ref m);   // WM_INPUT 도 DefWindowProc 로 넘겨 시스템이 정리하게 한다
    }

    readonly int _uiThread = Environment.CurrentManagedThreadId;
    void UI(Action a)
    {
        if (IsDisposed) return;
        if (Environment.CurrentManagedThreadId == _uiThread) { a(); return; }
        if (IsHandleCreated) BeginInvoke(a);
        // 핸들 생성 전 백그라운드 이벤트(HidSharp 모니터 스레드)는 버린다 — Load 에서 Refresh/RefreshState 로 다시 채운다
    }

    void SetMode(KeyboardMode m)
    {
        _mode = m;
        _selectedKey = null;
        foreach (var d in new[] { _testerDiagram, _remapDiagram, _fnDiagram }) { d.Keys = Hi8SELayout.Keys(m); d.Pressed.Clear(); d.Highlight.Clear(); d.Selected = null; }
        RefreshRemaps(); RefreshPicker(); RefreshFnHighlight();
    }

    // ---------------- 장치 ----------------
    TabPage BuildDeviceTab()
    {
        var page = new TabPage("장치");
        _devList.Columns.Add("PID", 60); _devList.Columns.Add("제품", 180); _devList.Columns.Add("순위", 45); _devList.Columns.Add("입력/출력/기능", 110); _devList.Columns.Add("최상위 usage", 220); _devList.Columns.Add("경로", 400);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(4) };
        _openBtn.Click += (_, _) => { if (SelectedDevice() is { } d) { if (!_hid.Open(d)) Msg(_hid.LastError); } else if (!_hid.OpenBest()) Msg(_hid.LastError); RefreshState(); };
        _closeBtn.Click += (_, _) => { _hid.Close(); _client.ResetState(); RefreshState(); };
        _probeBtn.Click += async (_, _) => await RunProbe();
        buttons.Controls.AddRange(new Control[] { _openBtn, _closeBtn, _probeBtn,
            new Label { Text = "프로브는 1.5초 동안 수신만 하고 읽기 전용 질의(0x05) 하나만 보냅니다. 조명 쓰기는 프로브 성공 뒤에만 열립니다.", AutoSize = true, Padding = new Padding(8, 8, 0, 0), ForeColor = Color.DimGray } });
        page.Controls.Add(_devList); page.Controls.Add(_devInfo); page.Controls.Add(buttons);
        return page;
    }

    HidDeviceInfo? SelectedDevice() => _devList.SelectedItems.Count > 0 ? _devList.SelectedItems[0].Tag as HidDeviceInfo : null;

    void RefreshDevices()
    {
        _devList.BeginUpdate(); _devList.Items.Clear();
        foreach (var d in _hid.Devices)
        {
            var it = new ListViewItem(new[] { $"{d.ProductId:X4}", d.Product, d.Rank.ToString(), $"{d.MaxInput}/{d.MaxOutput}/{d.MaxFeature}", d.TopUsageText, d.Path }) { Tag = d };
            if (_hid.OpenDevice?.Path == d.Path) it.BackColor = Color.FromArgb(222, 240, 222);
            _devList.Items.Add(it);
        }
        _devList.EndUpdate();
        RefreshState();
    }

    void RefreshState()
    {
        var dev = _hid.OpenDevice;
        var open = _hid.IsOpen && dev is not null;   // reader/모니터 스레드의 Close() 와 경쟁하므로 둘 다 확인
        _status.Text = _hid.Devices.Count == 0 ? "LEOBOG 장치 없음 (2.4G 동글 또는 USB 로 연결하세요)"
                     : open ? $"연결됨: PID {dev!.ProductId:X4} · {(_client.ProtocolVerified ? "벤더 채널 확인됨" : "프로브 전")}"
                     : $"장치 {_hid.Devices.Count}개 발견, 열리지 않음";
        _status.ForeColor = open ? Color.DarkGreen : Color.DarkOrange;
        _devInfo.Text = $"열린 장치: {(dev is null ? "없음" : $"{dev.Product} (PID {dev.ProductId:X4}, 제조사 {dev.Manufacturer}, S/N {dev.Serial})")}\r\n" +
                        $"펌웨어: {_client.Firmware ?? "-"}   체크섬: {(_client.DetectedChecksum?.Label() ?? "미판별")}   수신 패킷: {_client.ReceivedCount}   하트비트: {_client.HeartbeatCount}회" +
                        (_client.LastHeartbeat is { } hb ? $" (마지막 {hb:HH:mm:ss})" : "") + "\r\n" +
                        $"벤더 채널: {(_client.ProtocolVerified ? "확인됨 — 조명 쓰기 가능" : "미확인 — 프로브를 실행하세요")}\r\n" +
                        "참고: 블루투스로 연결된 경우 벤더 채널이 닫혀 있어 키 테스터·키 매핑만 동작합니다.";
        _diagState.Text = _devInfo.Text;
        _probeBtn.Enabled = open; _closeBtn.Enabled = open;
        _ledApply.Enabled = _ledFill.Enabled = open && _client.ProtocolVerified;
    }

    async Task RunProbe()
    {
        if (!_hid.IsOpen && !_hid.OpenBest()) { Msg(_hid.LastError); return; }
        _probeBtn.Enabled = false;
        try { var r = await _client.ProbeAsync(); Msg(r.Summary + (r.Firmware is null ? "" : "\n펌웨어: " + r.Firmware)); }
        catch (Exception e) { Msg("프로브 실패: " + e.Message); }
        finally { RefreshState(); }
    }

    // ---------------- 키 테스터 ----------------
    TabPage BuildTesterTab()
    {
        var page = new TabPage("키 테스터");
        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, FixedPanel = FixedPanel.Panel1, Size = new Size(1100, 700), SplitterDistance = 300 };
        split.Panel1.Controls.Add(_testerDiagram);
        var bottom = new Panel { Dock = DockStyle.Fill };
        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(4) };
        var clear = new Button { Text = "기록 지우기", AutoSize = true };
        clear.Click += (_, _) => { _keyLog.Items.Clear(); _testerDiagram.Pressed.Clear(); _testerDiagram.Invalidate(); };
        bar.Controls.AddRange(new Control[] { _allKeyboards, clear, _lastKey });
        bottom.Controls.Add(_keyLog); bottom.Controls.Add(bar);
        split.Panel2.Controls.Add(bottom);
        page.Controls.Add(split);
        page.Controls.Add(new Label { Dock = DockStyle.Top, AutoSize = false, Height = 36, Padding = new Padding(8, 4, 8, 0), ForeColor = Color.DimGray,
            Text = "Raw Input 으로 키를 받습니다 (창이 뒤에 있어도 동작). 키보드 자체 Fn 조합은 펌웨어가 처리해 보이지 않으며, Scancode Map 이 적용돼 있으면 바뀐 뒤의 키가 보입니다." });
        return page;
    }

    void OnRawKey(RawKeyEvent e)
    {
        UI(() =>
        {
            if (!e.IsLeobog && !_allKeyboards.Checked) return;
            var usage = e.Usage;
            var key = usage is { } u ? Hi8SELayout.KeyFor(u, _mode) : null;
            if (key is not null) { if (e.Pressed) _testerDiagram.Pressed.Add(key.Id); else _testerDiagram.Pressed.Remove(key.Id); _testerDiagram.Invalidate(); }
            var name = usage?.Name ?? $"스캔코드 {ScancodeTable.ScanText(e.Scancode)}";
            _lastKey.Text = $"{(e.Pressed ? "누름" : "뗌")}: {name}";
            if (e.Pressed)
            {
                _keyLog.Items.Insert(0, $"{DateTime.Now:HH:mm:ss.fff}  {name}  [sc {ScancodeTable.ScanText(e.Scancode)}]{(e.IsLeobog ? "" : "  (다른 키보드)")}");
                while (_keyLog.Items.Count > 300) _keyLog.Items.RemoveAt(_keyLog.Items.Count - 1);
            }
        });
    }

    // ---------------- 키 매핑 ----------------
    TabPage BuildRemapTab()
    {
        var page = new TabPage("키 매핑");
        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Vertical, FixedPanel = FixedPanel.Panel2, Size = new Size(1100, 700), SplitterDistance = 760 };
        var left = new Panel { Dock = DockStyle.Fill };
        _remapDiagram.Height = 300; _remapDiagram.Dock = DockStyle.Top;
        _remapDiagram.KeyClicked += k => { if (k.Usage is not null) { _selectedKey = k; _remapDiagram.Selected = k.Id; RefreshPicker(); } };

        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(4) };
        var apply = new Button { Text = "시스템에 적용 (관리자 권한)", AutoSize = true };
        apply.Click += (_, _) => { _remap.Save(); _remap.ApplyToSystem(); _remapMsg.Text = _remap.LastMessage; };
        var clearSys = new Button { Text = "시스템 매핑 해제", AutoSize = true };
        clearSys.Click += (_, _) => { if (!_remap.ClearSystem()) Msg(_remap.LastMessage); _remapMsg.Text = _remap.LastMessage; };
        var clearList = new Button { Text = "목록 비우기", AutoSize = true };
        clearList.Click += (_, _) => _remap.RemoveAll();
        var presets = new Button { Text = "프리셋 ▾", AutoSize = true };
        var menu = new ContextMenuStrip();
        foreach (var p in ScancodeMapService.Presets)
        {
            var item = new ToolStripMenuItem(p.Title + (p.MacOnly ? " (macOS 전용)" : "")) { ToolTipText = p.Detail, Enabled = !p.MacOnly };
            var preset = p;
            item.Click += (_, _) => _remap.Apply(preset);
            menu.Items.Add(item);
        }
        presets.Click += (_, _) => menu.Show(presets, new Point(0, presets.Height));
        var openReg = new Button { Text = ".reg 폴더 열기", AutoSize = true };
        openReg.Click += (_, _) => { try { Directory.CreateDirectory(AppPaths.SupportDir); Process.Start(new ProcessStartInfo("explorer.exe", AppPaths.SupportDir) { UseShellExecute = true }); } catch { } };
        bar.Controls.AddRange(new Control[] { apply, clearSys, clearList, presets, openReg, _remapMsg });

        _remapList.Columns.Add("원래 키", 220); _remapList.Columns.Add("→ 새 키", 220); _remapList.Columns.Add("상태", 110); _remapList.Columns.Add("스캔코드", 120);
        _remapList.KeyDown += (_, e) => { if (e.KeyCode == Keys.Delete && _remapList.SelectedItems.Count > 0 && _remapList.SelectedItems[0].Tag is KeyRemap r) _remap.Remove(r.Src); };
        var listMenu = new ContextMenuStrip();
        listMenu.Items.Add("이 매핑 삭제", null, (_, _) => { if (_remapList.SelectedItems.Count > 0 && _remapList.SelectedItems[0].Tag is KeyRemap r) _remap.Remove(r.Src); });
        _remapList.ContextMenuStrip = listMenu;

        var info = new Label { Dock = DockStyle.Top, AutoSize = false, Height = 52, Padding = new Padding(8, 4, 8, 0), ForeColor = Color.DimGray,
            Text = "키를 클릭해 다른 키로 바꾸세요. Windows 의 Scancode Map(레지스트리)은 연결된 모든 키보드에 적용되며, 적용·해제 후 로그아웃/로그인해야 반영됩니다. " +
                   "쓰기에는 관리자 권한(UAC)이 필요하고, 밝기 키·Fn🌐 처럼 PS/2 스캔코드가 없는 대상은 제외됩니다." };
        left.Controls.Add(_remapList); left.Controls.Add(bar); left.Controls.Add(_remapDiagram); left.Controls.Add(info);
        split.Panel1.Controls.Add(left);

        var right = new Panel { Dock = DockStyle.Fill };
        right.Controls.Add(_targets); right.Controls.Add(_pickerTitle);
        split.Panel2.Controls.Add(right);
        page.Controls.Add(split);
        RefreshPicker();
        return page;
    }

    void RefreshRemaps()
    {
        _remapDiagram.Remapped.Clear();
        foreach (var r in _remap.Remaps) { var k = _remapDiagram.Keys.FirstOrDefault(k => k.Usage == r.Src); if (k is not null) _remapDiagram.Remapped[k.Id] = r.Dst.ShortName; }
        _remapDiagram.Invalidate();
        _remapList.BeginUpdate(); _remapList.Items.Clear();
        foreach (var r in _remap.Remaps)
        {
            var active = _remap.ActiveFromSystem.Contains(r);
            var expressible = _remap.IsExpressible(r);
            var sc = ScancodeTable.Scancode(r.Src) is { } a && ScancodeTable.Scancode(r.Dst) is { } b ? $"{ScancodeTable.ScanText(a)} → {ScancodeTable.ScanText(b)}" : "-";
            var it = new ListViewItem(new[] { r.Src.Name, r.Dst.Name, !expressible ? "표현 불가" : active ? "적용됨" : "미적용", sc }) { Tag = r };
            it.ForeColor = !expressible ? Color.Gray : active ? Color.DarkGreen : Color.DarkOrange;
            _remapList.Items.Add(it);
        }
        foreach (var r in _remap.ActiveFromSystem.Where(x => !_remap.Remaps.Contains(x)))
            _remapList.Items.Add(new ListViewItem(new[] { r.Src.Name, r.Dst.Name, "시스템에만 있음", "" }) { Tag = r, ForeColor = Color.SteelBlue });
        _remapList.EndUpdate();
        _remapMsg.Text = _remap.LastMessage;
        _tabs.TabPages[2].Text = $"키 매핑 ({_remap.Remaps.Count})";
        RefreshPicker();
    }

    void RefreshPicker()
    {
        _targets.SuspendLayout();
        var old = _targets.Controls.Cast<Control>().ToArray();
        _targets.Controls.Clear();
        foreach (var c in old) { _tip.SetToolTip(c, null); c.Dispose(); }   // Clear 는 Dispose 하지 않아 핸들이 누적된다
        if (_selectedKey is null || _selectedKey.Usage is null)
        {
            _pickerTitle.Text = "바꿀 키를 선택하세요";
            _targets.Controls.Add(new Label { AutoSize = true, MaximumSize = new Size(280, 0), ForeColor = Color.DimGray, Padding = new Padding(6),
                Text = "다이어그램에서 키를 클릭하면 여기에서 새 기능을 고를 수 있습니다. 키보드 자체 Fn 키와 노브는 펌웨어 전용이라 바꿀 수 없습니다." });
            _targets.ResumeLayout(); return;
        }
        var src = _selectedKey.Usage.Value;
        var cur = _remap.MappingFor(src);
        _pickerTitle.Text = $"{_selectedKey.DisplayLabel} 키를 바꾸기\n원래: {src.Name}" + (cur is null ? "" : $"   ·   현재: {cur.Dst.Name}");
        if (cur is not null)
        {
            var reset = new Button { Text = "원래대로", AutoSize = true, Margin = new Padding(6) };
            reset.Click += (_, _) => _remap.Remove(src);
            _targets.Controls.Add(reset);
            _targets.SetFlowBreak(reset, true);
        }
        foreach (var g in RemapTargets.Groups)
        {
            var title = new Label { Text = g.Title, AutoSize = true, Font = _boldFont, ForeColor = Color.DimGray, Margin = new Padding(6, 10, 6, 2) };
            _targets.Controls.Add(title); _targets.SetFlowBreak(title, true);
            Control? last = null;
            foreach (var u in g.Items)
            {
                var ok = ScancodeTable.CanExpress(u);
                var b = new Button { Text = u.ShortName, AutoSize = true, Margin = new Padding(2), Enabled = ok, Tag = u };
                if (cur?.Dst == u) b.BackColor = Color.FromArgb(255, 221, 150);
                _tip.SetToolTip(b, u.Name + (ok ? "" : "\n(Windows Scancode Map 으로 표현할 수 없음)"));
                var target = u;
                b.Click += (_, _) => _remap.Set(new KeyRemap(src, target));
                _targets.Controls.Add(b); last = b;
            }
            if (last is not null) _targets.SetFlowBreak(last, true);
        }
        _targets.ResumeLayout();
    }

    // ---------------- Fn 레이어 ----------------
    TabPage BuildFnTab()
    {
        var page = new TabPage("단축키·Fn 레이어");
        _fnList.Columns.Add("조합", 140); _fnList.Columns.Add("Windows 모드", 260); _fnList.Columns.Add("Mac 모드", 260); _fnList.Columns.Add("출처", 150); _fnList.Columns.Add("확실성", 70);
        foreach (var c in FnLayerReference.Categories)
        {
            var grp = new ListViewGroup(c, c);
            _fnList.Groups.Add(grp);
            foreach (var s in FnLayerReference.In(c))
                _fnList.Items.Add(new ListViewItem(new[] { s.Combo, s.WinAction, s.MacAction, s.Source.Label(), s.Certain ? "확인됨" : "추정" }) { Group = grp, Tag = s });
        }
        _fnList.SelectedIndexChanged += (_, _) => RefreshFnHighlight();
        page.Controls.Add(_fnList); page.Controls.Add(_fnDiagram);
        page.Controls.Add(new Label { Dock = DockStyle.Top, AutoSize = false, Height = 30, Padding = new Padding(8, 6, 8, 0), ForeColor = Color.DimGray,
            Text = "키보드 펌웨어가 처리하는 Fn 조합 참고표입니다 (앱이 바꿀 수 없음). 항목을 고르면 다이어그램에 해당 키가 표시됩니다." });
        return page;
    }

    void RefreshFnHighlight()
    {
        _fnDiagram.Highlight.Clear();
        if (_fnList.SelectedItems.Count > 0 && _fnList.SelectedItems[0].Tag is FnShortcut s)
        {
            _fnDiagram.Highlight.Add(Hi8SELayout.FnKey(_mode).Id);   // 모드에 따라 Fn 키 위치가 다르다 (Windows: 오른쪽 끝, Mac: 스페이스 옆 두 번째)
            if (s.KeyId is { } id) _fnDiagram.Highlight.Add(id);
        }
        _fnDiagram.Invalidate();
    }

    // ---------------- 조명 ----------------
    TabPage BuildLedTab()
    {
        var page = new TabPage("조명");
        var grid = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, Padding = new Padding(10) };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize)); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        void Row(string label, Control c) { grid.Controls.Add(new Label { Text = label, AutoSize = true, Padding = new Padding(0, 6, 8, 0) }); grid.Controls.Add(c); }
        foreach (var e in LedEffects.All) _effect.Items.Add(e);
        _effect.SelectedIndex = Math.Clamp(LedEffects.DefaultIndex - 1, 0, _effect.Items.Count - 1);   // DefLedIndex 는 1부터
        _effect.SelectedIndexChanged += (_, _) => RefreshLedEnable();
        _direction.Items.AddRange(new object[] { "정방향", "역방향" }); _direction.SelectedIndex = 0;
        foreach (var c in LedEffects.PresetColors) _presetColor.Items.Add(c.Name);
        _presetColor.SelectedIndex = _presetColor.Items.Count - 1;
        _presetColor.SelectedIndexChanged += (_, _) => { var c = LedEffects.PresetColors[_presetColor.SelectedIndex]; SetColor(Color.FromArgb(c.R, c.G, c.B)); };
        var pick = new Button { Text = "색 고르기…", AutoSize = true };
        pick.Click += (_, _) => { using var dlg = new ColorDialog { Color = _color, FullOpen = true }; if (dlg.ShowDialog(this) == DialogResult.OK) SetColor(dlg.Color); };
        var colorRow = new FlowLayoutPanel { AutoSize = true }; colorRow.Controls.AddRange(new Control[] { _presetColor, _swatch, pick, _random });
        Row("효과", _effect); Row("속도 (0–4)", _speed); Row("밝기 (0–4)", _bright); Row("방향", _direction); Row("색상", colorRow);
        var actions = new FlowLayoutPanel { AutoSize = true }; actions.Controls.AddRange(new Control[] { _ledApply, _ledFill, _commit });
        Row("", actions); Row("", _ledMsg);
        _ledApply.Click += async (_, _) => await LedApply();
        _ledFill.Click += async (_, _) => await LedFill();
        page.Controls.Add(grid);
        page.Controls.Add(new Label { Dock = DockStyle.Bottom, AutoSize = false, Height = 60, Padding = new Padding(10), ForeColor = Color.DimGray,
            Text = "쓰기 명령은 '장치' 탭의 프로브로 벤더 채널 통신이 확인된 뒤에만 보냅니다. 2.4G 동글 연결에서만 동작하며, 공식 드라이버가 실행 중이면 장치를 점유해 열리지 않을 수 있습니다.\n" +
                   "효과 번호·속도·밝기 값은 공식 드라이버 KB.ini 와 오픈소스 분석을 따릅니다. 반응이 없으면 '진단' 탭의 벤더 로그에서 ACK 여부를 확인하세요." });
        RefreshLedEnable();
        return page;
    }

    void SetColor(Color c) { _color = c; _swatch.BackColor = c; }
    void RefreshLedEnable()
    {
        if (_effect.SelectedItem is not LedEffect e) return;
        _speed.Enabled = e.SupportsSpeed; _bright.Enabled = e.SupportsBrightness; _direction.Enabled = e.SupportsDirection; _random.Enabled = e.SupportsRandomColor; _presetColor.Enabled = e.SupportsCustomColor;
        if (!e.SupportsRandomColor) _random.Checked = false;
    }

    async Task LedApply()
    {
        if (_effect.SelectedItem is not LedEffect e) return;
        _ledApply.Enabled = false;
        try
        {
            var s = new LedEffectSetting(e, (int)_speed.Value, (int)_bright.Value, e.SupportsDirection ? _direction.SelectedIndex : 0, _random.Checked && e.SupportsRandomColor, _color.R, _color.G, _color.B);
            var ok = await _client.SetLedEffectAsync(s, _commit.Checked);
            _ledMsg.Text = ok ? $"적용됨: {e.Name}" : "키보드가 ACK 를 보내지 않았습니다 (진단 탭 참고)";
        }
        catch (Exception ex) { _ledMsg.Text = ex.Message; }
        finally { RefreshState(); }
    }

    async Task LedFill()
    {
        _ledFill.Enabled = false;
        try
        {
            var r = Enumerable.Repeat(_color.R, 126).ToArray(); var g = Enumerable.Repeat(_color.G, 126).ToArray(); var b = Enumerable.Repeat(_color.B, 126).ToArray();
            var ok = await _client.SetLedColorsAsync(r, g, b, _commit.Checked);
            _ledMsg.Text = ok ? "모든 키 색상을 보냈습니다 (효과를 '사용자 지정'류로 두어야 보입니다)" : "일부 페이지에 ACK 가 없었습니다";
        }
        catch (Exception ex) { _ledMsg.Text = ex.Message; }
        finally { RefreshState(); }
    }

    // ---------------- 진단 ----------------
    TabPage BuildDiagTab()
    {
        var page = new TabPage("진단");
        var split = new SplitContainer { Dock = DockStyle.Fill, Orientation = Orientation.Horizontal, FixedPanel = FixedPanel.Panel1, Size = new Size(1100, 700), SplitterDistance = 320 };
        var bar = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(4) };
        var probe = new Button { Text = "프로브", AutoSize = true }; probe.Click += async (_, _) => await RunProbe();
        var readKm = new Button { Text = "키맵 읽기 (0x41, 읽기 전용)", AutoSize = true };
        readKm.Click += async (_, _) =>
        {
            if (!_hid.IsOpen) { Msg("장치가 열려 있지 않습니다."); return; }
            try { var pages = await _client.ReadKeymapAsync(); _client.AddNote($"키맵 {pages.Count} 페이지 수신: " + string.Join(" ", pages.Select(p => $"[{p.PageIndex}: {string.Join(",", p.Usages.Select(u => u.ToString("X4")))}]"))); }
            catch (Exception e) { _client.AddNote("키맵 읽기 실패: " + e.Message); }
        };
        var clear = new Button { Text = "벤더 로그 지우기", AutoSize = true }; clear.Click += (_, _) => _client.ClearLog();
        var openLog = new Button { Text = "로그 폴더 열기", AutoSize = true };
        openLog.Click += (_, _) => { try { Directory.CreateDirectory(AppPaths.LogDir); Process.Start(new ProcessStartInfo("explorer.exe", AppPaths.LogDir) { UseShellExecute = true }); } catch { } };
        bar.Controls.AddRange(new Control[] { probe, readKm, clear, openLog });
        var topPanel = new Panel { Dock = DockStyle.Fill };
        topPanel.Controls.Add(_vendorLog); topPanel.Controls.Add(new Label { Dock = DockStyle.Top, Text = "벤더 채널 로그 (→ 송신, ← 수신, · 메모)", AutoSize = true, Padding = new Padding(6, 4, 0, 2) });
        topPanel.Controls.Add(bar); topPanel.Controls.Add(_diagState);
        split.Panel1.Controls.Add(topPanel);
        var bottomPanel = new Panel { Dock = DockStyle.Fill };
        bottomPanel.Controls.Add(_appLog); bottomPanel.Controls.Add(new Label { Dock = DockStyle.Top, Text = $"앱 로그 ({AppPaths.LogFile})", AutoSize = true, Padding = new Padding(6, 4, 0, 2) });
        split.Panel2.Controls.Add(bottomPanel);
        page.Controls.Add(split);
        return page;
    }

    void RefreshVendorLog()
    {
        var lines = _client.Log.Select(e => e.Line).ToArray();
        _vendorLog.Text = string.Join(Environment.NewLine, lines);
        _vendorLog.SelectionStart = _vendorLog.TextLength; _vendorLog.ScrollToCaret();
    }

    readonly List<string> _appLines = new();
    void AppendAppLog(string line)
    {
        _appLines.Add(line); if (_appLines.Count > 400) _appLines.RemoveAt(0);
        RenderAppLog();
    }
    void RenderAppLog()
    {
        _appLog.Text = string.Join(Environment.NewLine, _appLines);
        _appLog.SelectionStart = _appLog.TextLength; _appLog.ScrollToCaret();
    }

    void Msg(string text) => MessageBox.Show(this, text, "Leobog Control", MessageBoxButtons.OK, MessageBoxIcon.Information);
}
