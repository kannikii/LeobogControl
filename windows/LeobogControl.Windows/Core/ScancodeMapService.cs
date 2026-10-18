using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace LeobogControl.Core;

public sealed record KeyRemap(HidUsage Src, HidUsage Dst);

public sealed record RemapPreset(string Id, string Title, string Detail, IReadOnlyList<KeyRemap> Remaps, bool MacOnly = false);

/// Windows 의 키 재배치: HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map.
///  · 시스템 전체(연결된 모든 키보드)에 적용된다 — macOS 의 hidutil(장치별)과 다르다.
///  · 쓰기는 관리자 권한이 필요해 .reg 파일을 만들어 UAC 승격된 reg.exe 로 가져온다.
///  · 적용/해제 후 로그아웃·로그인(또는 재부팅)해야 반영된다.
/// 저장 형식(remaps.json)은 macOS 버전과 같다: [{"src":{"page":7,"usage":57},"dst":{"page":7,"usage":224}}]
public sealed class ScancodeMapService
{
    const string RegKey = @"SYSTEM\CurrentControlSet\Control\Keyboard Layout";
    const string RegValue = "Scancode Map";

    readonly List<KeyRemap> _remaps = new();
    public IReadOnlyList<KeyRemap> Remaps => _remaps;
    List<KeyRemap> _system = new();
    /// 레지스트리에 들어 있는 매핑. 같은 스캔코드를 쓰는 usage(예: Consumer Power 0x30 ↔ Keyboard Power 0x66)는 목록의 항목으로 맞춰 준다.
    public IReadOnlyList<KeyRemap> ActiveFromSystem => _system.Select(a => _remaps.FirstOrDefault(r => SameScan(r, a)) ?? a).ToList();
    static bool SameScan(KeyRemap a, KeyRemap b) => ScancodeTable.Scancode(a.Src) == ScancodeTable.Scancode(b.Src) && ScancodeTable.Scancode(a.Dst) == ScancodeTable.Scancode(b.Dst);
    public bool IsActiveInSystem(KeyRemap r) => _system.Any(a => SameScan(a, r));
    public string LastMessage { get; private set; } = "";
    public event Action? Changed;

    public static readonly IReadOnlyList<RemapPreset> Presets = new[]
    {
        new RemapPreset("swap-cmd-opt", "⌘ ↔ ⌥ 서로 바꾸기 (Win ↔ Alt)", "왼쪽·오른쪽 Win 과 Alt 를 서로 바꿉니다.",
            new[] { R(0xE3, 0xE2), R(0xE2, 0xE3), R(0xE7, 0xE6), R(0xE6, 0xE7) }),
        new RemapPreset("caps-ctrl", "Caps Lock → Ctrl", "Caps Lock 을 왼쪽 Ctrl 로.", new[] { R(0x39, 0xE0) }),
        new RemapPreset("caps-esc", "Caps Lock → Esc", "Caps Lock 을 Esc 로 (vim 사용자용).", new[] { R(0x39, 0x29) }),
        new RemapPreset("f-media", "F7–F12 → 미디어 키", "F7 이전곡 · F8 재생/일시정지 · F9 다음곡 · F10 음소거 · F11 음량 낮춤 · F12 음량 높임",
            new[] { RC(0x40, 0xB6), RC(0x41, 0xCD), RC(0x42, 0xB5), RC(0x43, 0xE2), RC(0x44, 0xEA), RC(0x45, 0xE9) }),
        new RemapPreset("f-bright", "F1–F2 → 화면 밝기", "Windows 의 Scancode Map 으로는 밝기 키를 표현할 수 없습니다 (macOS 전용).",
            new[] { RC(0x3A, 0x70), RC(0x3B, 0x6F) }, MacOnly: true),
        new RemapPreset("rcmd-fn", "오른쪽 ⌘ → Fn(🌐)", "macOS 전용 (Windows 에는 Globe/Fn 키 개념이 없습니다).",
            new[] { new KeyRemap(HidUsage.Keyboard(0xE7), HidUsage.AppleFn) }, MacOnly: true),
        new RemapPreset("rctrl-fn", "오른쪽 Ctrl → Fn(🌐)", "macOS 전용.", new[] { new KeyRemap(HidUsage.Keyboard(0xE4), HidUsage.AppleFn) }, MacOnly: true),
        new RemapPreset("del-fwd", "Delete → Backspace", "Delete 키를 Backspace 로.", new[] { R(0x4C, 0x2A) }),
        new RemapPreset("rwin-menu", "오른쪽 Win → 메뉴(App)", "오른쪽 Win 키를 컨텍스트 메뉴 키로.", new[] { R(0xE7, 0x65) }),
    };

    static KeyRemap R(uint src, uint dst) => new(HidUsage.Keyboard(src), HidUsage.Keyboard(dst));
    static KeyRemap RC(uint src, uint dst) => new(HidUsage.Keyboard(src), HidUsage.Consumer(dst));

    public ScancodeMapService()
    {
        Load();
        RefreshSystem();
    }

    public KeyRemap? MappingFor(HidUsage src) => _remaps.FirstOrDefault(r => r.Src == src);
    public bool IsExpressible(KeyRemap r) => ScancodeTable.Scancode(r.Src) is not null && ScancodeTable.CanExpress(r.Dst) && r.Src != HidUsage.Disabled;

    public void Set(KeyRemap r)
    {
        _remaps.RemoveAll(x => x.Src == r.Src);
        if (r.Src != r.Dst) _remaps.Add(r);
        Save(); Changed?.Invoke();
    }

    public void Remove(HidUsage src) { _remaps.RemoveAll(x => x.Src == src); Save(); Changed?.Invoke(); }
    public void RemoveAll() { _remaps.Clear(); Save(); Changed?.Invoke(); }
    public void Apply(RemapPreset p) { foreach (var r in p.Remaps) { _remaps.RemoveAll(x => x.Src == r.Src); _remaps.Add(r); } Save(); Changed?.Invoke(); }

    // ---------- 저장 ----------
    sealed class UsageJson { [JsonPropertyName("page")] public uint Page { get; set; } [JsonPropertyName("usage")] public uint Usage { get; set; } }
    sealed class RemapJson { [JsonPropertyName("src")] public UsageJson Src { get; set; } = new(); [JsonPropertyName("dst")] public UsageJson Dst { get; set; } = new(); }

    void Load()
    {
        try
        {
            if (!File.Exists(AppPaths.RemapsFile)) return;
            var list = JsonSerializer.Deserialize<List<RemapJson>>(File.ReadAllText(AppPaths.RemapsFile)) ?? new();
            _remaps.Clear();
            foreach (var j in list) _remaps.Add(new KeyRemap(new HidUsage(j.Src.Page, j.Src.Usage), new HidUsage(j.Dst.Page, j.Dst.Usage)));
        }
        catch (Exception e) { AppLog.Error("remap", "remaps.json 읽기 실패: " + e.Message); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(AppPaths.SupportDir);
            var list = _remaps.Select(r => new RemapJson { Src = new UsageJson { Page = r.Src.Page, Usage = r.Src.Usage }, Dst = new UsageJson { Page = r.Dst.Page, Usage = r.Dst.Usage } }).ToList();
            File.WriteAllText(AppPaths.RemapsFile, JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception e) { AppLog.Error("remap", "remaps.json 저장 실패: " + e.Message); }
    }

    // ---------- 레지스트리 ----------
    /// Scancode Map 바이너리: 헤더 8바이트(0) · 항목 수+1 · 항목(DWORD: 상위 워드 = 원래 스캔코드, 하위 워드 = 새 스캔코드) · 종료 0.
    public static byte[] BuildMap(IEnumerable<KeyRemap> remaps)
    {
        var entries = new List<(ushort From, ushort To)>();
        foreach (var r in remaps)
        {
            var from = ScancodeTable.Scancode(r.Src); var to = ScancodeTable.Scancode(r.Dst);
            if (from is null || to is null || from == 0) continue;
            entries.Add((from.Value, to.Value));
        }
        var ms = new MemoryStream();
        var w = new BinaryWriter(ms);
        w.Write(0u); w.Write(0u);
        w.Write((uint)(entries.Count + 1));
        foreach (var (from, to) in entries) w.Write((uint)(((uint)from << 16) | to));
        w.Write(0u);
        return ms.ToArray();
    }

    public static List<KeyRemap> ParseMap(byte[]? data)
    {
        var list = new List<KeyRemap>();
        if (data is null || data.Length < 16) return list;
        var count = BitConverter.ToUInt32(data, 8);
        for (var i = 0; i + 1 < count && 12 + i * 4 + 4 <= data.Length; i++)
        {
            var v = BitConverter.ToUInt32(data, 12 + i * 4);
            var from = (ushort)(v >> 16); var to = (ushort)(v & 0xFFFF);
            var src = ScancodeTable.Usage(from);
            var dst = to == 0 ? HidUsage.Disabled : ScancodeTable.Usage(to);
            if (src is not null && dst is not null) list.Add(new KeyRemap(src.Value, dst.Value));
        }
        return list;
    }

    public void RefreshSystem()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(RegKey);
            _system = ParseMap(k?.GetValue(RegValue) as byte[]);
        }
        catch (Exception e) { AppLog.Error("remap", "레지스트리 읽기 실패: " + e.Message); _system = new(); }
        Changed?.Invoke();
    }

    public string RegText(bool remove)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Windows Registry Editor Version 5.00");
        sb.AppendLine();
        sb.AppendLine("; Leobog Control 이 만든 키 재배치. 로그아웃/로그인 후 적용됩니다.");
        sb.AppendLine($"[HKEY_LOCAL_MACHINE\\{RegKey}]");
        if (remove) sb.AppendLine($"\"{RegValue}\"=-");
        else
        {
            var bytes = BuildMap(_remaps);
            var hex = string.Join(",", bytes.Select(b => b.ToString("x2")));
            sb.AppendLine($"\"{RegValue}\"=hex:{hex}");
        }
        return sb.ToString();
    }

    /// .reg 파일을 쓰고 UAC 승격된 reg.exe 로 가져온다. 사용자가 UAC 를 거부하면 실패 메시지.
    public bool ApplyToSystem()
    {
        var skipped = _remaps.Where(r => !IsExpressible(r)).ToList();
        return Import(AppPaths.RegApplyFile, RegText(false),
            ok => skipped.Count == 0 ? $"적용됨 ({_remaps.Count}개). 로그아웃 후 다시 로그인하면 반영됩니다."
                                     : $"적용됨 ({_remaps.Count - skipped.Count}개, {skipped.Count}개는 Windows 에서 표현 불가라 제외). 로그아웃 후 다시 로그인하면 반영됩니다.");
    }

    /// 레지스트리 값을 지운다. UAC 취소 등으로 실패하면 목록(remaps.json)은 그대로 둔다.
    public bool ClearSystem()
    {
        var ok = Import(AppPaths.RegRemoveFile, RegText(true), _ => "시스템 매핑을 제거했습니다. 로그아웃 후 다시 로그인하면 반영됩니다.");
        if (ok) { _remaps.Clear(); Save(); Changed?.Invoke(); }
        return ok;
    }

    bool Import(string path, string text, Func<bool, string> okMessage)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.SupportDir);
            File.WriteAllText(path, text, new UTF8Encoding(false));
            var psi = new ProcessStartInfo("reg.exe", $"import \"{path}\"") { UseShellExecute = true, Verb = "runas", CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
            using var p = Process.Start(psi);
            if (p is null) { LastMessage = "reg.exe 를 시작하지 못했습니다."; Changed?.Invoke(); return false; }
            p.WaitForExit(15000);
            if (p.ExitCode != 0) { LastMessage = $"reg import 실패 (종료 코드 {p.ExitCode})."; AppLog.Error("remap", LastMessage); RefreshSystem(); return false; }
            LastMessage = okMessage(true);
            AppLog.Info("remap", LastMessage);
            RefreshSystem();
            return true;
        }
        catch (System.ComponentModel.Win32Exception e) when (e.NativeErrorCode == 1223)
        {
            LastMessage = "관리자 권한 요청(UAC)이 취소되었습니다."; Changed?.Invoke(); return false;
        }
        catch (Exception e) { LastMessage = "적용 실패: " + e.Message; AppLog.Error("remap", LastMessage); Changed?.Invoke(); return false; }
    }
}
