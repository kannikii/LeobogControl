namespace LeobogControl.Core;

public sealed record LedEffectSetting(LedEffect Effect, int Speed, int Brightness, int Direction, bool RandomColor, byte R, byte G, byte B)
{
    public byte[] Payload => new[] { Effect.HardwareId, (byte)Math.Clamp(Speed, 0, 4), (byte)Math.Clamp(Brightness, 0, 4), (byte)Direction, (byte)(RandomColor ? 1 : 0), R, G, B };
}

public sealed record ProbeResult(bool HeartbeatSeen, bool CommandAnswered, string? Firmware, string Summary);

/// 벤더 채널 요청/응답 로직. macOS 의 CompxClient 와 같은 타이밍·재시도 규칙을 쓴다.
public sealed class CompxClient
{
    const int LogLimit = 400;
    readonly HidDeviceManager _hid;
    readonly object _lock = new();
    readonly List<VendorLogEntry> _log = new();
    readonly List<(Func<CompxPacket, bool> Match, Action<CompxPacket> OnPacket)> _listeners = new();

    public IReadOnlyList<VendorLogEntry> Log { get { lock (_lock) return _log.ToList(); } }
    public event Action? LogChanged;
    public event Action? StateChanged;

    public ChecksumStyle? DetectedChecksum { get; private set; }
    public bool ProtocolVerified { get; private set; }
    public string? Firmware { get; private set; }
    public int HeartbeatCount { get; private set; }
    public DateTime? LastHeartbeat { get; private set; }
    public byte[]? LastHeartbeatPayload { get; private set; }
    public int ReceivedCount { get; private set; }

    public ChecksumStyle WriteChecksum => DetectedChecksum ?? ChecksumStyle.SumAll;

    public CompxClient(HidDeviceManager hid)
    {
        _hid = hid;
        hid.VendorReportReceived += OnReceived;
        hid.Note += n => AddNote(n);
    }

    public void ResetState()
    {
        DetectedChecksum = null; ProtocolVerified = false; Firmware = null; HeartbeatCount = 0; LastHeartbeat = null; LastHeartbeatPayload = null; ReceivedCount = 0;
        StateChanged?.Invoke();
    }

    public void AddNote(string note)
    {
        lock (_lock) { _log.Add(new VendorLogEntry(DateTime.Now, LogDirection.Note, null, note)); Trim(); }
        LogChanged?.Invoke();
    }

    public void ClearLog() { lock (_lock) _log.Clear(); LogChanged?.Invoke(); }

    void Trim() { if (_log.Count > LogLimit) _log.RemoveRange(0, _log.Count - LogLimit); }

    void OnReceived(CompxPacket p)
    {
        List<(Func<CompxPacket, bool>, Action<CompxPacket>)> ls;
        lock (_lock)
        {
            ReceivedCount++;
            _log.Add(new VendorLogEntry(DateTime.Now, LogDirection.Rx, p, "")); Trim();
            if (DetectedChecksum is null)
            {
                var m = p.MatchingChecksumStyles;
                if (m.Count == 1) { DetectedChecksum = m[0]; _log.Add(new VendorLogEntry(DateTime.Now, LogDirection.Note, null, $"체크섬 방식 판별: {m[0].Label()}")); }
            }
            if (p.Cmd == CompxCommand.ActivelyReport) { HeartbeatCount++; LastHeartbeat = DateTime.Now; LastHeartbeatPayload = p.Bytes.ToArray(); }
            ls = _listeners.ToList();
        }
        foreach (var (match, on) in ls) { try { if (match(p)) on(p); } catch { } }
        LogChanged?.Invoke();
        StateChanged?.Invoke();
    }

    void Send(CompxPacket p, string note = "")
    {
        _hid.Send(p);
        lock (_lock) { _log.Add(new VendorLogEntry(DateTime.Now, LogDirection.Tx, p, note)); Trim(); }
        LogChanged?.Invoke();
    }

    IDisposable Listen(Func<CompxPacket, bool> match, Action<CompxPacket> on)
    {
        var entry = (match, on);
        lock (_lock) _listeners.Add(entry);
        return new Unsub(() => { lock (_lock) _listeners.Remove(entry); });
    }

    sealed class Unsub : IDisposable { readonly Action _a; public Unsub(Action a) => _a = a; public void Dispose() => _a(); }

    /// 단순 명령을 보내고 같은 cmd 의 첫 응답을 기다린다.
    public async Task<CompxPacket?> RequestAsync(byte cmd, byte[]? body = null, int retries = 3, double timeout = 0.5, CancellationToken ct = default)
    {
        for (var attempt = 1; attempt <= retries; attempt++)
        {
            var tcs = new TaskCompletionSource<CompxPacket>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var _ = Listen(p => p.Cmd == cmd, p => tcs.TrySetResult(p));
            try { Send(CompxPacket.Simple(cmd, body ?? Array.Empty<byte>(), WriteChecksum), attempt > 1 ? $"재시도 {attempt}" : ""); }
            catch (Exception e) { AddNote($"전송 실패: {e.Message}"); return null; }
            var done = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(timeout), ct));
            if (done == tcs.Task) return tcs.Task.Result;
            ct.ThrowIfCancellationRequested();
        }
        return null;
    }

    /// 여러 페이지로 오는 응답을 모아 pageIndex 순으로 돌려준다. 하나도 못 받으면 예외.
    public async Task<List<CompxPacket>> ReadPagesAsync(byte cmd, byte[]? body = null, double timeout = 2.5, double quiet = 0.35, CancellationToken ct = default)
    {
        var pages = new Dictionary<int, CompxPacket>();
        var last = DateTime.Now;
        using var _ = Listen(p => p.Cmd == cmd, p => { lock (pages) { pages[p.PageIndex] = p; last = DateTime.Now; } });
        Send(CompxPacket.Simple(cmd, body ?? Array.Empty<byte>(), WriteChecksum));
        var start = DateTime.Now;
        while ((DateTime.Now - start).TotalSeconds < timeout)
        {
            await Task.Delay(50, ct);
            lock (pages)
            {
                if (pages.Count > 0)
                {
                    var expected = pages.Values.First().PageCount;
                    if (expected > 0 && pages.Count >= expected) break;
                    if ((DateTime.Now - last).TotalSeconds > quiet) break;
                }
            }
        }
        lock (pages)
        {
            if (pages.Count == 0) throw new TimeoutException($"{CompxCommand.Name(cmd)} 응답이 없습니다.");
            return pages.OrderBy(k => k.Key).Select(k => k.Value).ToList();
        }
    }

    /// 수동 청취 → 읽기 전용 0x05 질의. 쓰기 기능은 이 프로브가 성공해야 열린다.
    public async Task<ProbeResult> ProbeAsync(double listen = 1.5, CancellationToken ct = default)
    {
        if (!_hid.IsOpen) throw new InvalidOperationException("장치가 열려 있지 않습니다.");
        AddNote($"프로브 시작: {(int)(listen * 1000)}ms 동안 수동 청취 (키를 몇 번 눌러 보세요)");
        var before = HeartbeatCount;
        await Task.Delay(TimeSpan.FromSeconds(listen), ct);
        var heartbeat = HeartbeatCount > before;

        var reply = await RequestAsync(CompxCommand.GetDeviceInfo, null, 3, 0.6, ct);
        string? fw = null;
        var answered = reply is not null;
        if (reply is not null)
        {
            var b = reply.Bytes;
            fw = $"v{b[4]}.{b[5]} (AULA 해석) / {b[13]:X2}{b[14]:X2} (RK 해석)";
            Firmware = fw;
        }
        else if (LastHeartbeatPayload is { } hb) Firmware = $"{hb[4]}.{hb[5]} (하트비트 기준)";

        ProtocolVerified = heartbeat || answered;
        string summary;
        if (ProtocolVerified)
            summary = "벤더 채널 통신 확인됨" + (answered ? "" : " (하트비트만 수신, 명령 응답은 없음)");
        else
            summary = "벤더 채널 응답이 없습니다. 2.4G 동글로 연결되어 있는지, 공식 드라이버(LEOBOG ONE)가 장치를 점유하고 있지 않은지 확인하세요. 블루투스 연결에서는 벤더 채널이 닫혀 있습니다.";
        AddNote("프로브 결과: " + summary);
        StateChanged?.Invoke();
        return new ProbeResult(heartbeat, answered, fw, summary);
    }

    void RequireVerified()
    {
        if (!ProtocolVerified) throw new InvalidOperationException("먼저 '장치' 탭에서 프로브를 실행해 벤더 채널 통신을 확인하세요. 확인 전에는 쓰기 명령을 보내지 않습니다.");
    }

    async Task<bool> SendPagedAsync(byte cmd, byte pageCount, byte pageIndex, byte dataLength, byte[] payload, int attempts, double wait, CancellationToken ct)
    {
        for (var a = 1; a <= attempts; a++)
        {
            var tcs = new TaskCompletionSource<CompxPacket>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var _ = Listen(p => p.Cmd == cmd && p.IsAck, p => tcs.TrySetResult(p));
            Send(new CompxPacket(cmd, pageCount, pageIndex, dataLength, 0, payload, WriteChecksum), a > 1 ? $"재시도 {a}" : "");
            var done = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(wait), ct));
            if (done == tcs.Task) return true;
        }
        return false;
    }

    public async Task<bool> CommitAsync(CancellationToken ct = default)
    {
        var r = await RequestAsync(CompxCommand.Commit, null, 2, 0.8, ct);
        var ok = r is not null && (r.Bytes[2] == 1 || r.IsAck);
        AddNote(ok ? "Commit(플래시 저장) 확인" : "Commit 응답 없음 — 설정이 전원 재시작 후 유지되지 않을 수 있습니다");
        return ok;
    }

    public async Task<bool> SetLedEffectAsync(LedEffectSetting s, bool commit, CancellationToken ct = default)
    {
        RequireVerified();
        AddNote($"조명 효과 쓰기: {s.Effect.Name} 속도 {s.Speed} 밝기 {s.Brightness} RGB({s.R},{s.G},{s.B}) 랜덤 {(s.RandomColor ? "켬" : "끔")}");
        var ok = await SendPagedAsync(CompxCommand.SetLedEffect, 1, 0, 8, s.Payload, 3, 0.6, ct);
        if (!ok) { AddNote("조명 효과: ACK 없음"); return false; }
        if (commit) await CommitAsync(ct);
        return true;
    }

    /// 키별 색상 (R[126] G[126] B[126] 평면 배열) — 14바이트씩 나눠 보낸다.
    public async Task<bool> SetLedColorsAsync(byte[] r, byte[] g, byte[] b, bool commit, CancellationToken ct = default)
    {
        RequireVerified();
        var planar = r.Concat(g).Concat(b).ToArray();
        var chunks = (planar.Length + 13) / 14;
        AddNote($"키별 색상 쓰기: {chunks} 페이지");
        for (var i = 0; i < chunks; i++)
        {
            var slice = planar.Skip(i * 14).Take(14).ToArray();
            var ok = await SendPagedAsync(CompxCommand.SetLedColors, (byte)chunks, (byte)i, (byte)slice.Length, slice, 5, 0.4, ct);
            if (!ok) { AddNote($"키별 색상: 페이지 {i} ACK 없음"); return false; }
        }
        if (commit) await CommitAsync(ct);
        return true;
    }

    public async Task<List<KeymapPage>> ReadKeymapAsync(byte layerCmd = CompxCommand.GetKeyMatrix, CancellationToken ct = default)
    {
        var pages = await ReadPagesAsync(layerCmd, null, 2.5, 0.35, ct);
        return pages.Select(KeymapPage.From).Where(x => x is not null).Select(x => x!).ToList();
    }
}
