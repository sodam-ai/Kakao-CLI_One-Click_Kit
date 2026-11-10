# Win32 호출을 한 곳(KakaoWin32 클래스)에 모은다. 창 정보 읽기, 확인과 입력을 한 번에 하는 키·클릭, 창 닫기 요청만 있다.
# 입력(SendCombo, ClickAt)은 C# 안에서 "대상 창 확인 -> 입력"을 한 번의 호출로 끝낸다. PowerShell에서 확인하고 따로 입력하면 그 사이에 창·마우스가 바뀔 수 있기 때문이다.
# 가드(Guard.ps1)를 거치지 않고 이 함수들을 직접 부르지 않는다.
if (-not ('KakaoWin32' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class KakaoWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION u; }
    delegate bool EnumProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    // 입력 결과 코드: 0 성공, 1 카카오톡 창 아님, 2 제목 다름, 3 맨 앞 아님, 4 사람 손 감지(또는 기준 없음), 5 다른 키 눌림,
    // 6 허용되지 않은 키 조합, 7 클릭 자리가 다른 창에 가림, 8 마우스 위치가 바뀜, 9 입력 전달 실패, 10 잘못된 인자
    static readonly byte[][] AllowedCombos = new byte[][] {
        new byte[] { 0x11, 0x53 }, new byte[] { 0x11, 0x56 }, new byte[] { 0x11, 0x41 }, new byte[] { 0x11, 0x43 }, new byte[] { 0x0D }
    };

    public static long[] TopLevelWindows() {
        List<long> list = new List<long>();
        EnumWindows(delegate (IntPtr h, IntPtr l) { list.Add(h.ToInt64()); return true; }, IntPtr.Zero);
        return list.ToArray();
    }
    public static bool IsVisible(long h) { return IsWindowVisible(new IntPtr(h)); }
    public static string Title(long h) {
        IntPtr p = new IntPtr(h);
        int n = GetWindowTextLengthW(p);
        if (n <= 0) return "";
        StringBuilder sb = new StringBuilder(n + 1);
        GetWindowTextW(p, sb, sb.Capacity);
        return sb.ToString();
    }
    public static string ClassName(long h) {
        StringBuilder sb = new StringBuilder(256);
        GetClassNameW(new IntPtr(h), sb, sb.Capacity);
        return sb.ToString();
    }
    public static int ProcessId(long h) {
        uint pid;
        GetWindowThreadProcessId(new IntPtr(h), out pid);
        return (int)pid;
    }
    public static string ProcessName(long h) {
        try { return Process.GetProcessById(ProcessId(h)).ProcessName; } catch { return ""; }
    }
    public static int[] Rect(long h) {
        RECT r = new RECT();
        if (!GetWindowRect(new IntPtr(h), out r)) return new int[] { 0, 0, 0, 0 };
        return new int[] { r.Left, r.Top, r.Right, r.Bottom };
    }
    public static long Foreground() { return GetForegroundWindow().ToInt64(); }
    // 창 자신이 따르는 DPI(96 = 100%, 144 = 150%). 카카오톡 창은 "시스템 DPI 인식"이라 150% 모니터에서도 96 이 나온다. 모르면 0. 읽기만 한다.
    public static int WindowDpi(long h) {
        if (h == 0) return 0;
        try { return (int)GetDpiForWindow(new IntPtr(h)); } catch (EntryPointNotFoundException) { return 0; }
    }
    // 창이 놓인 모니터의 실제 DPI. 화면에 보이는 창 크기는 이 값을 따른다. 창이 어느 모니터에도 없거나 읽지 못하면 0. 읽기만 한다.
    // 호출하는 쪽 프로세스가 모니터별 DPI 인식이어야 실제 값이 나온다(EnableDpiAwareness).
    public static int MonitorDpi(long h) {
        if (h == 0) return 0;
        try {
            IntPtr m = MonitorFromWindow(new IntPtr(h), 0); // 0 = 어느 모니터에도 없으면 NULL (가장 가까운 모니터로 짐작하지 않는다)
            if (m == IntPtr.Zero) return 0;
            uint x, y;
            if (GetDpiForMonitor(m, 0, out x, out y) != 0) return 0; // 0 = MDT_EFFECTIVE_DPI, 반환 0 = S_OK
            return (int)x;
        } catch (EntryPointNotFoundException) { return 0; } catch (DllNotFoundException) { return 0; }
    }
    public static long Root(long h) {
        if (h == 0) return 0;
        return GetAncestor(new IntPtr(h), 2).ToInt64();
    }
    public static long RootAtPoint(int x, int y) {
        POINT p = new POINT();
        p.X = x; p.Y = y;
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) return 0;
        return GetAncestor(h, 2).ToInt64();
    }
    public static void SetForeground(long h) {
        IntPtr p = new IntPtr(h);
        if (IsIconic(p)) ShowWindow(p, 9);
        SetForegroundWindow(p);
    }
    public static long LastInputTick() {
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref li);
        return li.dwTime;
    }
    public static long IdleMs() {
        LASTINPUTINFO li = new LASTINPUTINFO();
        li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref li);
        return unchecked((uint)Environment.TickCount - li.dwTime);
    }
    // 눌려 있어도 "사람이 키를 눌렀다"로 세지 않는 키. 한/영 키(VK_HANGUL 0x15)만 해당한다.
    // 키보드·입력기에 따라 이 키는 손을 떼도 계속 눌린 것으로 읽힌다(실측: 마지막 입력 후 30초가 지나도 20번 중 20번). 이 키를 막으면 그런 PC에서는 키트가 입력을 한 번도 못 보낸다.
    // 모드 전환 키라서 눌린 채 Ctrl+V·클릭이 가도 엉뚱한 단축키가 되지 않는다. 다른 키는 여기에 넣지 않는다(시험이 정확히 1개인지 확인한다).
    public static int[] IgnoredHeldKeys() { return new int[] { 0x15 }; }
    // isDown(vk) 로 키 상태를 물어 눌린 키 하나를 돌려준다(없으면 0). 시험이 가짜 isDown 을 끼워 넣을 수 있게 따로 뺐다.
    public static int HeldKeyFrom(Func<int, bool> isDown) {
        int[] ignored = IgnoredHeldKeys();
        for (int vk = 0x08; vk <= 0xDF; vk++) {
            if (Array.IndexOf(ignored, vk) >= 0) continue;
            if (isDown(vk)) return vk;
        }
        return 0;
    }
    // 지금 눌려 있는 키 하나(없으면 0). 사람이 키를 누른 채 키트가 Ctrl 조합을 보내면 엉뚱한 단축키가 되기 때문이다.
    public static int HeldKey() {
        return HeldKeyFrom(delegate (int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; });
    }
    public static void PostClose(long h) { PostMessageW(new IntPtr(h), 0x0010, IntPtr.Zero, IntPtr.Zero); }
    // 가장 좋은 DPI 설정(모니터마다 배율이 달라도 실제 픽셀 좌표)을 시도하고, 안 되면 기본 설정으로 되돌아간다.
    public static void EnableDpiAwareness() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }

    static bool ComboAllowed(byte[] vks) {
        if (vks == null) return false;
        foreach (byte[] allowed in AllowedCombos) {
            if (allowed.Length != vks.Length) continue;
            bool same = true;
            for (int i = 0; i < allowed.Length; i++) { if (allowed[i] != vks[i]) { same = false; break; } }
            if (same) return true;
        }
        return false;
    }

    // 입력 직전 확인: 카카오톡 창, 제목 정확 일치, 맨 앞, 사람 손 없음(기준 시각과 같음), 눌린 키 없음.
    static int CheckTarget(long hwnd, string expectedTitle, long baselineTick) {
        if (!string.Equals(ProcessName(hwnd), "KakaoTalk", StringComparison.OrdinalIgnoreCase)) return 1;
        if (string.IsNullOrEmpty(expectedTitle) || !string.Equals(Title(hwnd), expectedTitle, StringComparison.Ordinal)) return 2;
        if (Root(Foreground()) != hwnd) return 3;
        if (baselineTick < 0 || LastInputTick() != baselineTick) return 4;
        if (HeldKey() != 0) return 5;
        return 0;
    }

    static INPUT KeyInput(byte vk, bool up) {
        INPUT i = new INPUT();
        i.type = 1;
        i.u.ki.wVk = vk;
        i.u.ki.dwFlags = up ? 2u : 0u;
        return i;
    }
    static INPUT MouseInput(uint flags) {
        INPUT i = new INPUT();
        i.type = 0;
        i.u.mi.dwFlags = flags;
        return i;
    }

    // 확인과 키 입력을 한 번에. 눌렀다 떼는 전체를 SendInput 배열 하나로 보내므로 다른 입력이 끼어들 수 없고 Ctrl이 눌린 채 남지 않는다.
    public static int SendCombo(long hwnd, string expectedTitle, byte[] vks, long baselineTick) {
        if (!ComboAllowed(vks)) return 6;
        int status = CheckTarget(hwnd, expectedTitle, baselineTick);
        if (status != 0) return status;
        List<INPUT> list = new List<INPUT>();
        for (int i = 0; i < vks.Length; i++) list.Add(KeyInput(vks[i], false));
        for (int i = vks.Length - 1; i >= 0; i--) list.Add(KeyInput(vks[i], true));
        uint sent = SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT)));
        return sent == (uint)list.Count ? 0 : 9;
    }

    // 확인과 클릭을 한 번에. 커서를 옮긴 뒤 위치·가림·맨 앞·사람 손을 다시 확인하고, 누름/뗌 전체를 배열 하나로 보낸다.
    public static int ClickAt(long hwnd, string expectedTitle, int x, int y, int clicks, long baselineTick) {
        if (clicks < 1 || clicks > 2) return 10;
        int status = CheckTarget(hwnd, expectedTitle, baselineTick);
        if (status != 0) return status;
        SetCursorPos(x, y);
        POINT p = new POINT();
        GetCursorPos(out p);
        if (p.X != x || p.Y != y) return 8;
        if (RootAtPoint(x, y) != hwnd) return 7;
        status = CheckTarget(hwnd, expectedTitle, baselineTick);
        if (status != 0) return status;
        List<INPUT> list = new List<INPUT>();
        for (int i = 0; i < clicks; i++) { list.Add(MouseInput(0x0002)); list.Add(MouseInput(0x0004)); }
        uint sent = SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT)));
        return sent == (uint)list.Count ? 0 : 9;
    }
}
"@
}

# 가드가 쓰는 "제공자": 창 정보·입력·대기를 함수 묶음 하나로 모은다. 시험은 이 묶음을 가짜로 바꿔 끼운다.
function Get-DefaultInputProvider {
    [KakaoWin32]::EnableDpiAwareness()
    return @{
        ProcessName   = { param($h) [KakaoWin32]::ProcessName($h) }
        Title         = { param($h) [KakaoWin32]::Title($h) }
        Foreground    = { [KakaoWin32]::Root([KakaoWin32]::Foreground()) }
        SetForeground = { param($h) [KakaoWin32]::SetForeground($h) }
        SendCombo     = { param($h, $title, $vks, $baseline) [KakaoWin32]::SendCombo([long]$h, [string]$title, [byte[]]$vks, [long]$baseline) }
        ClickAt       = { param($h, $title, $x, $y, $clicks, $baseline) [KakaoWin32]::ClickAt([long]$h, [string]$title, [int]$x, [int]$y, [int]$clicks, [long]$baseline) }
        Rect          = { param($h) $r = [KakaoWin32]::Rect($h); @{ Left = $r[0]; Top = $r[1]; Right = $r[2]; Bottom = $r[3] } }
        RootAtPoint   = { param($x, $y) [KakaoWin32]::RootAtPoint([int]$x, [int]$y) }
        LastInputTick = { [KakaoWin32]::LastInputTick() }
        IdleMs        = { [KakaoWin32]::IdleMs() }
        Sleep         = { param($ms) Start-Sleep -Milliseconds $ms }
        PostClose     = { param($h) [KakaoWin32]::PostClose($h) }
    }
}

# 창 좌표를 실제 화면 픽셀로 읽어야 하는 곳(화면 캡처, Ocr.ps1)이 DPI 설정을 켤 때 쓴다. [KakaoWin32]:: 호출은 이 파일에만 둔다.
function Enable-KitDpiAwareness { [KakaoWin32]::EnableDpiAwareness() }

# 창 DPI 와 모니터 DPI 중 쓸 값을 고른다. 모니터 값이 우선이다: 카카오톡 창은 "시스템 DPI 인식"이라 150% 모니터에서도 창 DPI 가 96 으로 나오지만 화면에는 150% 크기로 보인다(D-24).
# 모니터 값을 모르면(0 이하) 창 값, 그것도 모르면 96(100%).
function Select-KitDpi {
    param([int]$WindowDpi, [int]$MonitorDpi)
    if ($MonitorDpi -gt 0) { return $MonitorDpi }
    if ($WindowDpi -gt 0) { return $WindowDpi }
    return 96
}

# 창이 놓인 모니터의 배율(1.0 = 100%, 1.5 = 150%). 알 수 없으면 1.0. DPI 설정을 켠 뒤에 불러야 실제 값이 나온다.
function Get-KitWindowScale {
    param([long]$Hwnd)
    $dpi = Select-KitDpi -WindowDpi ([KakaoWin32]::WindowDpi($Hwnd)) -MonitorDpi ([KakaoWin32]::MonitorDpi($Hwnd))
    return ($dpi / 96.0)
}

# 카카오톡 프로세스가 가진 보이는 최상위 창(저장 대화상자 같은 모달 창 포함). 읽기 전용.
function Get-KakaoWindows {
    $kakaoPids = @(Get-Process -Name KakaoTalk -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    if ($kakaoPids.Count -eq 0) { return @() }
    $found = @()
    foreach ($h in [KakaoWin32]::TopLevelWindows()) {
        if ($kakaoPids -notcontains [KakaoWin32]::ProcessId($h)) { continue }
        if (-not [KakaoWin32]::IsVisible($h)) { continue }
        $r = [KakaoWin32]::Rect($h)
        $found += [pscustomobject]@{
            Hwnd        = [long]$h
            Class       = [KakaoWin32]::ClassName($h)
            Title       = [KakaoWin32]::Title($h)
            ProcessName = [KakaoWin32]::ProcessName($h)
            Rect        = [pscustomobject]@{ Left = $r[0]; Top = $r[1]; Right = $r[2]; Bottom = $r[3] }
        }
    }
    return $found
}
