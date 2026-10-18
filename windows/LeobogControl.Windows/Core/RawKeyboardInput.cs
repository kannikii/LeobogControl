using System.Runtime.InteropServices;

namespace LeobogControl.Core;

public sealed record RawKeyEvent(HidUsage? Usage, ushort Scancode, bool Pressed, string DeviceName, bool IsLeobog);

/// Raw Input(WM_INPUT) 으로 키보드 입력을 장치별로 받는다. 키 테스터용.
/// 전역 후크와 달리 어느 장치에서 왔는지(VID_3554) 구분할 수 있고, 백신이 싫어하는 WH_KEYBOARD_LL 을 쓰지 않는다.
/// 주의: Scancode Map 이 적용된 뒤의 스캔코드가 보인다 (키보드 클래스 드라이버에서 이미 치환됨).
public sealed class RawKeyboardInput : IDisposable
{
    const int WM_INPUT = 0x00FF;
    const int WM_INPUT_DEVICE_CHANGE = 0x00FE;
    const uint RIDEV_INPUTSINK = 0x00000100;
    const uint RIDEV_DEVNOTIFY = 0x00002000;
    const uint RIDEV_REMOVE = 0x00000001;
    const uint RID_INPUT = 0x10000003;
    const uint RIDI_DEVICENAME = 0x20000007;
    const uint RIM_TYPEKEYBOARD = 1;
    const ushort RI_KEY_BREAK = 1, RI_KEY_E0 = 2, RI_KEY_E1 = 4;

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE { public ushort UsagePage; public ushort Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER { public uint Type; public uint Size; public IntPtr Device; public IntPtr WParam; }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWKEYBOARD { public ushort MakeCode; public ushort Flags; public ushort Reserved; public ushort VKey; public uint Message; public uint ExtraInformation; }

    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices([In] RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr hRawInput, uint cmd, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr device, uint cmd, IntPtr data, ref uint size);

    readonly Dictionary<IntPtr, string> _names = new();
    IntPtr _hwnd;
    public event Action<RawKeyEvent>? KeyEvent;
    public string LastError { get; private set; } = "";

    public bool Register(IntPtr hwnd)
    {
        _hwnd = hwnd;
        var dev = new[] { new RAWINPUTDEVICE { UsagePage = 0x01, Usage = 0x06, Flags = RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, Target = hwnd } };
        if (!RegisterRawInputDevices(dev, 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>()))
        {
            LastError = "RegisterRawInputDevices 실패: " + Marshal.GetLastWin32Error();
            AppLog.Error("rawinput", LastError);
            return false;
        }
        AppLog.Info("rawinput", "등록됨");
        return true;
    }

    /// MainForm.WndProc 에서 호출. WM_INPUT 이면 처리하고 true. (호출자는 그래도 DefWindowProc 로 넘겨야 한다.)
    public bool ProcessMessage(ref Message m)
    {
        if (m.Msg == WM_INPUT_DEVICE_CHANGE) { _names.Clear(); return false; }   // 장치 탈착 → hDevice 재사용 대비 이름 캐시 비움
        if (m.Msg != WM_INPUT) return false;
        uint size = 0;
        var headerSize = (uint)Marshal.SizeOf<RAWINPUTHEADER>();
        GetRawInputData(m.LParam, RID_INPUT, IntPtr.Zero, ref size, headerSize);
        if (size == 0) return true;
        var buf = Marshal.AllocHGlobal((int)size);
        try
        {
            if (GetRawInputData(m.LParam, RID_INPUT, buf, ref size, headerSize) != size) return true;
            var header = Marshal.PtrToStructure<RAWINPUTHEADER>(buf);
            if (header.Type != RIM_TYPEKEYBOARD) return true;
            var kb = Marshal.PtrToStructure<RAWKEYBOARD>(buf + (int)headerSize);
            if (kb.MakeCode == 0 || kb.VKey == 0xFF || (kb.Flags & RI_KEY_E1) != 0) return true;   // Pause(E1 프리픽스 + 두 번째 패킷 VK 0xFF) 등은 건너뜀
            if ((kb.Flags & RI_KEY_E0) != 0 && (kb.MakeCode == 0x2A || kb.MakeCode == 0x36)) return true;  // 가짜 Shift
            var sc = (ushort)(((kb.Flags & RI_KEY_E0) != 0 ? 0xE000 : 0) | (kb.MakeCode & 0xFF));
            var name = DeviceName(header.Device);
            var isLeobog = name.Contains("VID_3554", StringComparison.OrdinalIgnoreCase);
            KeyEvent?.Invoke(new RawKeyEvent(ScancodeTable.Usage(sc), sc, (kb.Flags & RI_KEY_BREAK) == 0, name, isLeobog));
        }
        finally { Marshal.FreeHGlobal(buf); }
        return true;
    }

    string DeviceName(IntPtr device)
    {
        if (device == IntPtr.Zero) return "(알 수 없음)";
        if (_names.TryGetValue(device, out var n)) return n;
        uint size = 0;
        GetRawInputDeviceInfo(device, RIDI_DEVICENAME, IntPtr.Zero, ref size);
        var name = "(이름 없음)";
        if (size > 0)
        {
            var buf = Marshal.AllocHGlobal((int)size * 2);
            try { if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, buf, ref size) > 0) name = Marshal.PtrToStringUni(buf) ?? name; }
            finally { Marshal.FreeHGlobal(buf); }
        }
        _names[device] = name;
        return name;
    }

    public void Dispose()
    {
        if (_hwnd == IntPtr.Zero) return;
        var dev = new[] { new RAWINPUTDEVICE { UsagePage = 0x01, Usage = 0x06, Flags = RIDEV_REMOVE, Target = IntPtr.Zero } };
        RegisterRawInputDevices(dev, 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>());
        _hwnd = IntPtr.Zero;
    }
}
