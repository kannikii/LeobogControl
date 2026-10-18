using HidSharp;
using HidSharp.Reports;

namespace LeobogControl.Core;

public sealed record HidDeviceInfo(string Path, int VendorId, int ProductId, string Product, string Manufacturer, string Serial,
                                   int MaxInput, int MaxOutput, int MaxFeature, IReadOnlyList<uint> TopUsages, int Rank)
{
    public string TopUsageText => string.Join(", ", TopUsages.Select(u => $"{u >> 16:X4}:{u & 0xFFFF:X4}"));
}

/// LEOBOG(VID 0x3554) 장치를 찾아 벤더 채널(usage page 0xFF02, Report ID 0x13, 20바이트) 인터페이스를 연다.
/// Windows 는 키보드/마우스 컬렉션(0x01:0x06) 을 직접 읽지 못하게 막으므로 키 테스터는 RawKeyboardInput(Raw Input)이 담당한다.
public sealed class HidDeviceManager : IDisposable
{
    public const int LeobogVendorId = 0x3554;

    readonly object _lock = new();
    HidStream? _stream;
    Thread? _reader;

    public IReadOnlyList<HidDeviceInfo> Devices { get; private set; } = Array.Empty<HidDeviceInfo>();
    public HidDeviceInfo? OpenDevice { get; private set; }
    public bool IsOpen => _stream is not null;
    public string LastError { get; private set; } = "";

    /// UI 스레드로 마샬링하지 않는다 — 구독자가 Invoke 해야 한다.
    public event Action? DevicesChanged;
    public event Action<CompxPacket>? VendorReportReceived;
    public event Action<string>? Note;

    public HidDeviceManager()
    {
        DeviceList.Local.Changed += (_, _) => { Refresh(); };
    }

    static int RankOf(HidDevice d, IReadOnlyList<uint> usages, int maxOut)
    {
        if (usages.Any(u => (u >> 16) == 0xFF02)) return 0;
        if (maxOut >= 20 && !usages.Any(u => u == 0x00010006 || u == 0x00010002)) return 1;
        return 2;
    }

    public void Refresh()
    {
        var list = new List<HidDeviceInfo>();
        foreach (var d in DeviceList.Local.GetHidDevices(LeobogVendorId))
        {
            var usages = new List<uint>();
            int maxIn = 0, maxOut = 0, maxFeat = 0;
            try { maxIn = d.GetMaxInputReportLength(); maxOut = d.GetMaxOutputReportLength(); maxFeat = d.GetMaxFeatureReportLength(); } catch { }
            try
            {
                var rd = d.GetReportDescriptor();
                foreach (var item in rd.DeviceItems) usages.AddRange(item.Usages.GetAllValues());
            }
            catch { }
            string S(Func<string> f) { try { return f() ?? ""; } catch { return ""; } }
            list.Add(new HidDeviceInfo(d.DevicePath, d.VendorID, d.ProductID, S(d.GetProductName), S(d.GetManufacturer), S(d.GetSerialNumber),
                                       maxIn, maxOut, maxFeat, usages, RankOf(d, usages, maxOut)));
        }
        Devices = list.OrderBy(x => x.Rank).ThenBy(x => x.Path).ToList();
        AppLog.Info("hid", $"장치 {Devices.Count}개: " + string.Join(" | ", Devices.Select(x => $"{x.ProductId:X4} rank{x.Rank} out{x.MaxOutput} [{x.TopUsageText}]")));

        // 열려 있던 장치가 사라졌으면 닫는다
        if (OpenDevice is not null && Devices.All(x => x.Path != OpenDevice.Path)) Close();
        DevicesChanged?.Invoke();
    }

    /// 벤더 채널 후보(가장 낮은 rank) 를 연다. 이미 열려 있으면 아무것도 하지 않는다.
    public bool OpenBest()
    {
        if (IsOpen) return true;
        var best = Devices.FirstOrDefault(x => x.Rank < 2);
        if (best is null) { LastError = "벤더 채널 인터페이스(usage page 0xFF02 또는 20바이트 출력 리포트)를 가진 LEOBOG 장치가 없습니다."; return false; }
        return Open(best);
    }

    public bool Open(HidDeviceInfo info)
    {
        lock (_lock)
        {
            if (IsOpen) Close();
            var dev = DeviceList.Local.GetHidDevices(LeobogVendorId).FirstOrDefault(d => d.DevicePath == info.Path);
            if (dev is null) { LastError = "장치를 찾을 수 없습니다 (연결이 끊겼을 수 있음)."; return false; }
            try
            {
                var cfg = new OpenConfiguration();
                cfg.SetOption(OpenOption.Exclusive, false);
                if (!dev.TryOpen(cfg, out var stream)) { LastError = "장치를 열 수 없습니다 (다른 프로그램이 점유 중이거나 권한 부족)."; return false; }
                stream.ReadTimeout = 500;
                stream.WriteTimeout = 1000;
                _stream = stream;
                OpenDevice = info;
                var maxIn = info.MaxInput;
                _reader = new Thread(() => ReadLoop(stream, maxIn)) { IsBackground = true, Name = "leobog-hid-reader" };
                _reader.Start();
                LastError = "";
                AppLog.Info("hid", $"열림: {info.Path} (PID {info.ProductId:X4}, in {info.MaxInput} / out {info.MaxOutput})");
                Note?.Invoke($"장치 열림: PID {info.ProductId:X4}, 입력 {info.MaxInput}B / 출력 {info.MaxOutput}B");
                return true;
            }
            catch (Exception e) { LastError = "열기 실패: " + e.Message; AppLog.Error("hid", LastError); return false; }
        }
    }

    public void Close()
    {
        HidStream? s;
        lock (_lock) { s = _stream; _stream = null; OpenDevice = null; }
        try { s?.Close(); } catch { }
        AppLog.Info("hid", "닫힘");
    }

    /// 이 스레드가 연 스트림이 아직 현재 스트림인가. 재오픈 뒤 남아 있는 이전 reader 가 새 스트림을 닫지 않도록 한다.
    bool Owns(HidStream s) { lock (_lock) return ReferenceEquals(_stream, s); }

    void ReadLoop(HidStream stream, int maxInput)
    {
        var buf = new byte[Math.Max(64, maxInput)];
        while (Owns(stream))
        {
            int n;
            try { n = stream.Read(buf, 0, buf.Length); }
            catch (TimeoutException) { continue; }
            catch (Exception e)
            {
                if (!Owns(stream)) break;   // 우리가 닫았거나 다른 장치로 바뀜 — 조용히 종료
                AppLog.Error("hid", "읽기 오류: " + e.Message);
                Note?.Invoke("읽기 오류로 장치를 닫습니다: " + e.Message);
                Close();
                break;
            }
            if (n <= 0) continue;
            // Windows 는 버퍼[0] 에 Report ID 를 넣어 준다. 벤더 패킷(0x13)만 올린다.
            var span = buf.AsSpan(0, n);
            if (span[0] == CompxPacket.ReportId && n >= 2) VendorReportReceived?.Invoke(new CompxPacket(span));
        }
    }

    /// 20바이트 벤더 패킷을 출력 리포트로 보낸다 (macOS 의 IOHIDDeviceSetReport(kIOHIDReportTypeOutput, 0x13) 와 같은 경로).
    public void Send(CompxPacket packet)
    {
        HidStream? s; int maxOut;
        lock (_lock) { s = _stream; maxOut = OpenDevice?.MaxOutput ?? 0; }
        if (s is null) throw new InvalidOperationException("장치가 열려 있지 않습니다.");
        var len = Math.Max(CompxPacket.Length, maxOut);
        var buf = new byte[len];
        packet.Bytes.CopyTo(buf, 0);
        s.Write(buf, 0, len);
    }

    public void Dispose() { Close(); }
}
