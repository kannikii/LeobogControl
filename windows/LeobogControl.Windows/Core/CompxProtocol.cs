using System.Text;

namespace LeobogControl.Core;

/// 체크섬 변형. 수신 패킷으로 어느 쪽인지 자동 판별한다.
public enum ChecksumStyle
{
    /// sum(bytes[0..18]) & 0xFF (aula-f75 에서 키맵 쓰기까지 검증)
    SumAll,
    /// (19 + sum(bytes[1..17])) & 0xFF (openrgb-rk-r87pro)
    RkStyle,
}

public static class ChecksumStyleExt
{
    public static byte Compute(this ChecksumStyle s, byte[] b)
    {
        var sum = 0;
        if (s == ChecksumStyle.SumAll) { for (var i = 0; i < 19; i++) sum += b[i]; return (byte)(sum & 0xFF); }
        for (var i = 1; i < 18; i++) sum += b[i];
        return (byte)((19 + sum) & 0xFF);
    }

    public static string Label(this ChecksumStyle s) => s == ChecksumStyle.SumAll ? "sum(0…18) 방식 (aula-f75)" : "19+sum(1…17) 방식 (rk-r87pro)";
}

/// Compx(CX) 계열 키보드가 쓰는 벤더 채널(usage page 0xFF02, Report ID 0x13, 20바이트) 패킷.
/// [0] 0x13 / [1] cmd / [2] 페이지 수(bit7 = busy) / [3] 페이지 번호 / [4] (dataLen&0x0F)|(board<<4) / [5..18] 페이로드 / [19] 체크섬
public sealed class CompxPacket : IEquatable<CompxPacket>
{
    public const int Length = 20;
    public const byte ReportId = 0x13;
    public const int PayloadLength = 14;

    public byte[] Bytes { get; }

    public CompxPacket(ReadOnlySpan<byte> raw)
    {
        var b = new byte[Length];
        var src = raw;
        if (src.Length == 0 || src[0] != ReportId) { b[0] = ReportId; src.Slice(0, Math.Min(src.Length, Length - 1)).CopyTo(b.AsSpan(1)); }
        else src.Slice(0, Math.Min(src.Length, Length)).CopyTo(b);
        Bytes = b;
    }

    public CompxPacket(byte cmd, byte pageCount = 1, byte pageIndex = 0, byte dataLength = 0, byte board = 0,
                       ReadOnlySpan<byte> payload = default, ChecksumStyle checksum = ChecksumStyle.SumAll)
    {
        var b = new byte[Length];
        b[0] = ReportId; b[1] = cmd; b[2] = (byte)(pageCount & 0x7F); b[3] = (byte)(pageIndex & 0x7F);
        b[4] = (byte)((dataLength & 0x0F) | ((board & 0x0F) << 4));
        payload.Slice(0, Math.Min(payload.Length, PayloadLength)).CopyTo(b.AsSpan(5));
        b[19] = checksum.Compute(b);
        Bytes = b;
    }

    /// AULA 식 단순 명령: [0x13, cmd, body...] (바이트 2 부터 바로 페이로드)
    public static CompxPacket Simple(byte cmd, ReadOnlySpan<byte> body = default, ChecksumStyle checksum = ChecksumStyle.SumAll)
    {
        var b = new byte[Length];
        b[0] = ReportId; b[1] = cmd;
        body.Slice(0, Math.Min(body.Length, 17)).CopyTo(b.AsSpan(2));
        b[19] = checksum.Compute(b);
        return new CompxPacket(b);
    }

    public byte Cmd => Bytes[1];
    public byte PageCount => (byte)(Bytes[2] & 0x7F);
    public byte PageIndex => (byte)(Bytes[3] & 0x7F);
    public byte DataLength => (byte)(Bytes[4] & 0x0F);
    public byte Board => (byte)(Bytes[4] >> 4);
    public ReadOnlySpan<byte> Payload => Bytes.AsSpan(5, PayloadLength);
    public byte ChecksumByte => Bytes[19];
    /// 응답 패킷의 바이트 2 bit7 이 1이면 아직 처리 중(재전송 요청), 0이면 ACK
    public bool IsAck => (Bytes[2] >> 7) == 0;

    public bool ChecksumValid(ChecksumStyle s) => s.Compute(Bytes) == Bytes[19];
    public IReadOnlyList<ChecksumStyle> MatchingChecksumStyles =>
        new[] { ChecksumStyle.SumAll, ChecksumStyle.RkStyle }.Where(ChecksumValid).ToList();

    public string Hex => string.Join(" ", Bytes.Select(x => x.ToString("X2")));
    public override string ToString() => Hex;
    public bool Equals(CompxPacket? o) => o is not null && Bytes.AsSpan().SequenceEqual(o.Bytes);
    public override bool Equals(object? o) => Equals(o as CompxPacket);
    public override int GetHashCode() { var h = new HashCode(); h.AddBytes(Bytes); return h.ToHashCode(); }
}

/// 알려진 명령 코드 (오픈소스 분석 + 공식 드라이버 문자열 종합)
public static class CompxCommand
{
    public const byte SetKeyMatrix = 0x01, SetLedColors = 0x02, SetMacros = 0x03, SetProfile = 0x04, GetDeviceInfo = 0x05,
        SetFactory = 0x06, GetDongleStatus = 0x07, SetLedEffect = 0x09, ActivelyReport = 0x0A,
        GetKeyMatrix = 0x41, GetKeyMatrixLayer2 = 0x42, GetKeyMatrixLayer3 = 0x43, GetProfile = 0x44, GetLedEffect = 0x49,
        WriteKeyMatrixPage = 0x81, WriteLedPage = 0x89, Abort = 0xFC, Commit = 0xFD, BeginSession = 0xFE;

    public static string Name(byte cmd) => cmd switch
    {
        SetKeyMatrix => "SetKeyMatrix", SetLedColors => "SetLedColors", SetMacros => "SetMacros", SetProfile => "SetProfile",
        GetDeviceInfo => "GetDeviceInfo / GetPassword", SetFactory => "SetFactory(공장 초기화)", GetDongleStatus => "GetDongleStatus",
        SetLedEffect => "SetLedEffect", ActivelyReport => "ActivelyReport(하트비트)", GetKeyMatrix => "GetKeyMatrix(레이어1)",
        GetKeyMatrixLayer2 => "GetKeyMatrix 레이어2 / GetLedColors", GetKeyMatrixLayer3 => "GetKeyMatrix 레이어3 / GetMacros",
        GetProfile => "GetProfile / 조명 설정 읽기", GetLedEffect => "GetLedEffect / 키별 RGB 읽기", WriteKeyMatrixPage => "WriteKeyMatrixPage",
        WriteLedPage => "WriteLedPage(추정)", Abort => "Abort(0xFC)", Commit => "Commit(플래시 저장)", BeginSession => "BeginSession(0xFE)",
        _ => $"알 수 없음 0x{cmd:X2}",
    };
}

public enum LogDirection { Tx, Rx, Note }

/// 벤더 채널 로그 한 줄 (진단 화면용)
public sealed record VendorLogEntry(DateTime Time, LogDirection Direction, CompxPacket? Packet, string Note)
{
    public string Line
    {
        get
        {
            var t = Time.ToString("HH:mm:ss.fff");
            var arrow = Direction switch { LogDirection.Tx => "→", LogDirection.Rx => "←", _ => "·" };
            if (Packet is null) return $"{t} {arrow} {Note}";
            var cs = string.Concat(Packet.MatchingChecksumStyles.Select(s => s == ChecksumStyle.SumAll ? "A" : "R"));
            var sb = new StringBuilder();
            sb.Append(t).Append(' ').Append(arrow).Append(' ').Append(Packet.Hex).Append("  [").Append(CompxCommand.Name(Packet.Cmd))
              .Append(cs.Length == 0 ? " 체크섬불일치" : " cs:" + cs).Append(']');
            if (Note.Length > 0) sb.Append("  ").Append(Note);
            return sb.ToString();
        }
    }
}

/// 키맵 페이지 해석 (페이지당 7키 × 2바이트 빅엔디언 HID usage)
public sealed class KeymapPage
{
    public byte LayerCmd { get; }
    public int PageCount { get; }
    public int PageIndex { get; }
    public ushort[] Usages { get; }

    KeymapPage(CompxPacket p)
    {
        LayerCmd = p.Cmd; PageCount = p.PageCount; PageIndex = p.PageIndex;
        var pl = p.Payload;
        Usages = new ushort[7];
        for (var i = 0; i < 7; i++) Usages[i] = (ushort)((pl[i * 2] << 8) | pl[i * 2 + 1]);
    }

    public static KeymapPage? From(CompxPacket p) => (p.DataLength == 14 || p.PageCount > 0) ? new KeymapPage(p) : null;

    public CompxPacket WritePacket(ChecksumStyle cs)
    {
        var payload = new byte[14];
        for (var i = 0; i < 7; i++) { payload[i * 2] = (byte)(Usages[i] >> 8); payload[i * 2 + 1] = (byte)(Usages[i] & 0xFF); }
        return new CompxPacket(CompxCommand.WriteKeyMatrixPage, (byte)PageCount, (byte)PageIndex, 14, 0, payload, cs);
    }
}
