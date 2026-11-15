$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 창 정보를 정해 둔 값으로 돌려주고, 입력·닫기 호출을 기록한다. 실제 카카오톡은 건드리지 않는다.
# SendCombo/ClickAt 은 진짜에서는 "확인 + 입력"을 한 번에 하고 결과 코드(0 성공)를 돌려준다. 가짜는 정해 둔 코드를 돌려준다.
function New-FakeProvider {
    $state = @{
        Calls       = (New-Object System.Collections.ArrayList)
        Process     = 'KakaoTalk'
        Title       = '비밀방'
        Foreground  = 100
        RootAtPoint = 100
        Tick        = 1000
        Idle        = 5000
        SetCount    = 0
        RaiseOn     = 0
        TickOnSet   = $null
        IdleQueue   = (New-Object 'System.Collections.Generic.Queue[int]')
        SendStatus  = 0
        ClickStatus = 0
        Rect        = @{ Left = 100; Top = 200; Right = 500; Bottom = 600 }
    }
    $state.Provider = @{
        ProcessName   = { param($h) $state.Process }.GetNewClosure()
        Title         = { param($h) $state.Title }.GetNewClosure()
        Foreground    = { $state.Foreground }.GetNewClosure()
        # RaiseOn: n번째 SetForeground 부터 대상 창이 맨 앞이 된다(0 이면 맨 앞이 바뀌지 않음). TickOnSet: 이 호출 뒤 "마지막 입력 시각"을 바꿔 사람 손을 흉내 낸다.
        SetForeground = { param($h)
            [void]$state.Calls.Add('SetForeground')
            $state.SetCount++
            if ($state.RaiseOn -gt 0 -and $state.SetCount -ge $state.RaiseOn) { $state.Foreground = $h }
            if ($null -ne $state.TickOnSet) { $state.Tick = $state.TickOnSet } }.GetNewClosure()
        SendCombo     = { param($h, $title, $vks, $baseline)
            [void]$state.Calls.Add(('Combo:{0}:{1}' -f $h, (($vks | ForEach-Object { '{0:X2}' -f $_ }) -join ',')))
            $state.SendStatus }.GetNewClosure()
        ClickAt       = { param($h, $title, $x, $y, $clicks, $baseline)
            [void]$state.Calls.Add(('Click:{0},{1},{2}' -f $x, $y, $clicks))
            $state.ClickStatus }.GetNewClosure()
        Rect          = { param($h) $state.Rect }.GetNewClosure()
        RootAtPoint   = { param($x, $y) $state.RootAtPoint }.GetNewClosure()
        LastInputTick = { $state.Tick }.GetNewClosure()
        IdleMs        = { if ($state.IdleQueue.Count -gt 0) { $state.IdleQueue.Dequeue() } else { $state.Idle } }.GetNewClosure()
        Sleep         = { param($ms) }.GetNewClosure()
        PostClose     = { param($h) [void]$state.Calls.Add(('Close:{0}' -f $h)) }.GetNewClosure()
    }
    return $state
}

# 작업 시작 때 하는 "손 떼기 확인 + 기준 시각 잡기"를 흉내 낸다.
function Initialize-Guard($state) {
    Reset-InputBaseline
    Set-InputBaseline -Provider $state.Provider
}

# 키·마우스·닫기처럼 "실제로 입력되는" 호출만 센다.
function Get-InputCalls($state) {
    return @($state.Calls | Where-Object { $_ -like 'Combo:*' -or $_ -like 'Click:*' -or $_ -like 'Close:*' })
}

$kakaoWindow = @(Get-KakaoWindows | Select-Object -First 1)
$noKakaoWindow = ($kakaoWindow.Count -eq 0)

Describe 'Guard: Assert-InputTarget' {
    It 'passes when process, title and foreground all match' {
        $f = New-FakeProvider
        { Assert-InputTarget -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider } | Should Not Throw
    }

    It 'throws KakaoGuardException (exit 2) on a title mismatch, even a trailing space' {
        $f = New-FakeProvider
        foreach ($expected in '다른방', '비밀방 ', '비밀') {
            $e = Get-ThrownError { Assert-InputTarget -Hwnd 100 -ExpectedTitle $expected -Provider $f.Provider }
            $e.GetType().Name | Should Be 'KakaoGuardException'
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '제목'
        }
    }

    It 'throws when the window does not belong to KakaoTalk' {
        $f = New-FakeProvider
        $f.Process = 'notepad'
        $e = Get-ThrownError { Assert-InputTarget -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '카카오톡이 아닙니다'
    }

    It 'throws when the window is not in the foreground' {
        $f = New-FakeProvider
        $f.Foreground = 999
        $e = Get-ThrownError { Assert-InputTarget -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '맨 앞'
    }

    It 'throws when no expected title is given' {
        $f = New-FakeProvider
        (Get-ThrownError { Assert-InputTarget -Hwnd 100 -ExpectedTitle '' -Provider $f.Provider }).ExitCode | Should Be 2
    }
}

Describe 'Guard: Send-KeyCombo' {
    It 'sends nothing when the title, process or foreground check fails' {
        foreach ($case in 'Title', 'Process', 'Foreground') {
            $f = New-FakeProvider
            Initialize-Guard $f
            if ($case -eq 'Title') { $f.Title = '다른방' }
            if ($case -eq 'Process') { $f.Process = 'notepad' }
            if ($case -eq 'Foreground') { $f.Foreground = 999 }
            $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+V' -ExpectedTitle '비밀방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'sends each whitelisted combo as ONE native call (Ctrl+key, or Enter)' {
        $expected = @{ 'Ctrl+S' = '11,53'; 'Ctrl+V' = '11,56'; 'Ctrl+C' = '11,43'; 'Ctrl+F' = '11,46'; 'Enter' = '0D' }
        foreach ($combo in $expected.Keys) {
            $f = New-FakeProvider
            Initialize-Guard $f
            Send-KeyCombo -Hwnd 100 -Keys $combo -ExpectedTitle '비밀방' -Provider $f.Provider
            ((Get-InputCalls $f) -join '|') | Should Be ('Combo:100:' + $expected[$combo])
        }
    }

    It 'refuses every key outside the whitelist before touching anything (Esc closes the chat window)' {
        foreach ($bad in 'Esc', 'Escape', 'Alt+F4', 'Delete', 'Ctrl+W', 'Ctrl+Shift+S', 'ctrl+s', 'ctrl+f', 'Ctrl+A', 'Ctrl+Shift+F', 'Ctrl+S ', 'F5', '') {
            $f = New-FakeProvider
            Initialize-Guard $f
            $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys $bad -ExpectedTitle '비밀방' -Provider $f.Provider }
            $e.GetType().Name | Should Be 'KakaoGuardException'
            $e.ExitCode | Should Be 2
            $f.Calls.Count | Should Be 0
        }
    }

    It 'refuses to send without a baseline (the "hands off" check was skipped)' {
        $f = New-FakeProvider
        Reset-InputBaseline
        $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '먼저 필요'
        $f.Calls.Count | Should Be 0
    }

    It 'turns every native status code into a Korean guard error' {
        $expected = @{ 1 = '카카오톡이 아닙니다'; 2 = '제목'; 3 = '맨 앞'; 4 = '키보드나 마우스'; 5 = '다른 키가 눌려'; 6 = '허용되지 않은'; 9 = '입력을 보내지 못' }
        foreach ($code in $expected.Keys) {
            $f = New-FakeProvider
            Initialize-Guard $f
            $f.SendStatus = $code
            $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+S' -ExpectedTitle '비밀방' -Provider $f.Provider }
            $e.GetType().Name | Should Be 'KakaoGuardException'
            $e.ExitCode | Should Be 2
            $e.Message | Should Match $expected[$code]
        }
    }

    It 'stops before any input when the user touched the keyboard or mouse after the baseline' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Tick = 2500
        $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+S' -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '키보드나 마우스'
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'stays closed when the caller says -ErrorAction SilentlyContinue (a throw must never be skipped)' {
        foreach ($case in 'Title', 'Process', 'Foreground', 'Interference', 'NoBaseline', 'BadKey') {
            $f = New-FakeProvider
            Initialize-Guard $f
            $keys = 'Enter'
            if ($case -eq 'Title') { $f.Title = '다른방' }
            if ($case -eq 'Process') { $f.Process = 'notepad' }
            if ($case -eq 'Foreground') { $f.Foreground = 999 }
            if ($case -eq 'Interference') { $f.Tick = 2500 }
            if ($case -eq 'NoBaseline') { Reset-InputBaseline }
            if ($case -eq 'BadKey') { $keys = 'Esc' }
            $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys $keys -ExpectedTitle '비밀방' -Provider $f.Provider -ErrorAction SilentlyContinue }
            $e.ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'stays closed when the caller sets $ErrorActionPreference to SilentlyContinue' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Title = '다른방'
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try { $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider } }
        finally { $ErrorActionPreference = $old }
        $e.ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 0
    }
}

Describe 'Guard: Invoke-RelClick' {
    It 'clicks at a point proportional to the window rectangle, in one native call' {
        $f = New-FakeProvider
        Initialize-Guard $f
        Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.25 -ExpectedTitle '비밀방' -Provider $f.Provider
        ((Get-InputCalls $f) -join '|') | Should Be 'Click:300,300,1'
    }

    It 'double-clicks with clicks=2' {
        $f = New-FakeProvider
        Initialize-Guard $f
        Invoke-RelClick -Hwnd 100 -RelX 0.1 -RelY 0.1 -Double -ExpectedTitle '비밀방' -Provider $f.Provider
        ((Get-InputCalls $f) -join '|') | Should Be 'Click:140,240,2'
    }

    It 'does nothing when another window covers the click point' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.RootAtPoint = 777
        $e = Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.5 -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '가려'
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'does nothing when the guard fails or the baseline is missing' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Title = '다른방'
        (Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.5 -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
        $f.Title = '비밀방'
        Reset-InputBaseline
        (Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.5 -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'refuses positions outside the window, including NaN' {
        foreach ($pos in @(-0.1, 0.5), @(1.5, 0.5), @(0.5, -1), @(0.5, 2), @([double]::NaN, 0.5), @(0.5, [double]::NaN)) {
            $f = New-FakeProvider
            Initialize-Guard $f
            $e = Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX $pos[0] -RelY $pos[1] -ExpectedTitle '비밀방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'turns every native click status code into a Korean guard error' {
        $expected = @{ 3 = '맨 앞'; 4 = '키보드나 마우스'; 7 = '가려'; 8 = '마우스 위치'; 9 = '입력을 보내지 못' }
        foreach ($code in $expected.Keys) {
            $f = New-FakeProvider
            Initialize-Guard $f
            $f.ClickStatus = $code
            $e = Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.5 -ExpectedTitle '비밀방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match $expected[$code]
        }
    }

    It 'stays closed when the caller says -ErrorAction SilentlyContinue' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.RootAtPoint = 777
        $e = Get-ThrownError { Invoke-RelClick -Hwnd 100 -RelX 0.5 -RelY 0.5 -ExpectedTitle '비밀방' -Provider $f.Provider -ErrorAction SilentlyContinue }
        $e.ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 0
    }
}

Describe 'Guard: Close-KakaoWindow' {
    It 'asks a KakaoTalk window to close' {
        $f = New-FakeProvider
        Close-KakaoWindow -Hwnd 100 -Provider $f.Provider
        ((Get-InputCalls $f) -join ',') | Should Be 'Close:100'
    }

    It 'refuses to close a window that is not KakaoTalk' {
        $f = New-FakeProvider
        $f.Process = 'notepad'
        (Get-ThrownError { Close-KakaoWindow -Hwnd 100 -Provider $f.Provider }).ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'with -ExpectedTitle, closes only when the title matches exactly' {
        $f = New-FakeProvider
        (Get-ThrownError { Close-KakaoWindow -Hwnd 100 -ExpectedTitle '다른방' -Provider $f.Provider }).ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 0
        Close-KakaoWindow -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider
        ((Get-InputCalls $f) -join ',') | Should Be 'Close:100'
    }
}

Describe 'Guard: 사용자 간섭' {
    It 'lets two kit inputs follow each other when nobody else touched anything' {
        $f = New-FakeProvider
        Initialize-Guard $f
        Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+S' -ExpectedTitle '비밀방' -Provider $f.Provider
        Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+C' -ExpectedTitle '비밀방' -Provider $f.Provider
        (Get-InputCalls $f).Count | Should Be 2
    }

    It 'stops the second input when the user touched something between two kit inputs' {
        $f = New-FakeProvider
        Initialize-Guard $f
        Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+S' -ExpectedTitle '비밀방' -Provider $f.Provider
        (Get-InputCalls $f).Count | Should Be 1
        $f.Tick = 2500
        $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Ctrl+C' -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-InputCalls $f).Count | Should Be 1
    }

    It 'Wait-UserIdle throws if the user never becomes idle' {
        $f = New-FakeProvider
        $f.Idle = 300
        $e = Get-ThrownError { Wait-UserIdle -Seconds 2 -TimeoutSeconds 1 -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '키보드나 마우스'
    }

    It 'Wait-UserIdle also throws under -ErrorAction SilentlyContinue' {
        $f = New-FakeProvider
        $f.Idle = 300
        (Get-ThrownError { Wait-UserIdle -Seconds 2 -TimeoutSeconds 1 -Provider $f.Provider -ErrorAction SilentlyContinue }).ExitCode | Should Be 2
    }

    It 'Wait-UserIdle returns once the user has been idle long enough, and sets the baseline for the next input' {
        $f = New-FakeProvider
        Reset-InputBaseline
        foreach ($ms in 100, 300, 2500) { $f.IdleQueue.Enqueue($ms) }
        { Wait-UserIdle -Seconds 2 -TimeoutSeconds 5 -Provider $f.Provider } | Should Not Throw
        Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider
        (Get-InputCalls $f).Count | Should Be 1
    }
}

Describe 'Guard: 소스에 위험한 키 코드가 없다' {
    It 'src has no SendKeys, raw key messages or Esc other than the one title-restricted entry (Win32.ps1 and Guard.ps1 only)' {
        $patterns = 'VK_ESCAPE', 'SendKeys', 'WM_KEYDOWN', '\{ESC\}', 'keybd_event'
        $hits = @()
        foreach ($f in (Get-ChildItem -Path (Join-Path $kitRoot 'src') -Recurse -File -Include *.ps1)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            foreach ($pat in $patterns) { if ($text -match $pat) { $hits += ($f.Name + ':' + $pat) } }
        }
        ($hits -join ', ') | Should BeNullOrEmpty
        # Esc(0x1B)는 메인 창 제목일 때만 허용한다(2026-11-15 사용자 승인: 검색을 닫는 용도). 코드에 나오는 곳은 이 두 파일의 정해진 자리뿐이다.
        $esc = @{}
        foreach ($f in (Get-ChildItem -Path (Join-Path $kitRoot 'src') -Recurse -File -Include *.ps1)) {
            $n = [regex]::Matches([System.IO.File]::ReadAllText($f.FullName), '(?i)\b0x0*1B\b').Count
            if ($n -gt 0) { $esc[$f.Name] = $n }
        }
        (@($esc.Keys | Sort-Object) -join ',') | Should Be 'Guard.ps1,Win32.ps1'
        $esc['Guard.ps1'] | Should Be 1
        $esc['Win32.ps1'] | Should Be 2
    }

    It 'only Win32.ps1 talks to the native input class' {
        $hits = @()
        foreach ($f in (Get-ChildItem -Path (Join-Path $kitRoot 'src') -Recurse -File -Include *.ps1)) {
            if ($f.Name -eq 'Win32.ps1') { continue }
            if ([System.IO.File]::ReadAllText($f.FullName) -match 'KakaoWin32\]::') { $hits += $f.Name }
        }
        ($hits -join ', ') | Should BeNullOrEmpty
    }
}

Describe 'Guard: 동시 실행 잠금' {
    function Invoke-LockChild([string]$LockName) {
        $script = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-lockchild-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $lib = $kitLibDir
        $body = @(
            '$ErrorActionPreference = ''Stop'''
            ('. ''' + $lib + '\Messages.ko.ps1''')
            ('. ''' + $lib + '\Paths.ps1''')
            ('. ''' + $lib + '\Errors.ps1''')
            ('. ''' + $lib + '\Win32.ps1''')
            ('. ''' + $lib + '\Guard.ps1''')
            ('try { Enter-KitLock -Name ''' + $LockName + '''; Exit-KitLock; exit 0 } catch { $c = $_.Exception.ExitCode; if ($c) { exit [int]$c } else { exit 99 } }')
        )
        # BOM 이 있어야 한다: 없으면 PowerShell 5.1 이 한글이 든 경로($lib)를 cp949 로 잘못 읽어 자식 프로세스가 엉뚱하게 끝난다.
        [System.IO.File]::WriteAllLines($script, $body, (New-Object System.Text.UTF8Encoding($true)))
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'powershell.exe'
            $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"'
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            [void]$proc.StandardOutput.ReadToEnd()
            [void]$proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            return $proc.ExitCode
        }
        finally { Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue }
    }

    It 'the real lock name is fixed and does not depend on KAKAO_KIT_HOME' {
        $old = $env:KAKAO_KIT_HOME
        try {
            $env:KAKAO_KIT_HOME = 'C:\SomewhereElse'
            $a = (Get-KitPaths).LockName
            $env:KAKAO_KIT_HOME = $null
            $b = (Get-KitPaths).LockName
            $a | Should Be $b
        }
        finally { $env:KAKAO_KIT_HOME = $old }
    }

    It 'a second Enter-KitLock in the same process throws, and works again after Exit-KitLock' {
        $name = 'Local\KakaoKitTest.' + [guid]::NewGuid().ToString('N')
        Enter-KitLock -Name $name
        try {
            $e = Get-ThrownError { Enter-KitLock -Name $name }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '이미 실행 중'
        }
        finally { Exit-KitLock }
        { Enter-KitLock -Name $name } | Should Not Throw
        Exit-KitLock
    }

    It 'another process cannot take the lock while this one holds it, but can after it is released' {
        $name = 'Local\KakaoKitTest.' + [guid]::NewGuid().ToString('N')
        Enter-KitLock -Name $name
        try { Invoke-LockChild $name | Should Be 2 }
        finally { Exit-KitLock }
        Invoke-LockChild $name | Should Be 0
    }
}

Describe 'Guard: 실제 Win32 (입력은 보내지 않는다)' {
    It 'the default provider exposes every call the guard layer needs' {
        $p = Get-DefaultInputProvider
        foreach ($name in 'ProcessName', 'Title', 'Foreground', 'SetForeground', 'SendCombo', 'ClickAt', 'Rect', 'RootAtPoint', 'LastInputTick', 'IdleMs', 'Sleep', 'PostClose') {
            ($p[$name] -is [scriptblock]) | Should Be $true
        }
    }

    It 'Get-KakaoWindows returns only KakaoTalk windows with the documented fields' {
        foreach ($w in @(Get-KakaoWindows)) {
            $w.ProcessName | Should Be 'KakaoTalk'
            ($w.Hwnd -is [long]) | Should Be $true
            ($w.Title -is [string]) | Should Be $true
            ($w.Class -is [string]) | Should Be $true
            ($w.Rect.Right -ge $w.Rect.Left) | Should Be $true
        }
    }

    It 'the native layer refuses Esc, Alt+F4, Delete, Ctrl+W and Shift combos by itself (status 6)' {
        # 이 시험은 입력을 보내지 않는다: 허용 표에 없으면 창을 확인하기도 전에 6을 돌려준다.
        # Ctrl+A(0x11, 0x41)는 카카오톡 메인 창에서 "친구 추가" 단축키라서 막는다(2026-11-12 화면에서 확인).
        foreach ($combo in @(27), @(0x11, 0x57), @(0x11, 0x41), @(0x12, 0x73), @(0x2E), @(0x11, 0x10, 0x53), @(0x11, 0x53, 0x0D), @()) {
            [KakaoWin32]::SendCombo(0, 'x', [byte[]]$combo, 0) | Should Be 6
        }
    }

    It 'the native layer allows Ctrl+F (it gets past the key table and stops at the window check, status 1) and still refuses Ctrl+Shift+F' {
        # 입력을 보내지 않는다: 창 번호 0 은 카카오톡 창이 아니라서 허용 표를 통과한 뒤 1 에서 멈춘다.
        [KakaoWin32]::SendCombo(0, 'x', [byte[]](0x11, 0x46), 0) | Should Be 1
        [KakaoWin32]::SendCombo(0, 'x', [byte[]](0x11, 0x10, 0x46), 0) | Should Be 6
    }

    It 'the native layer refuses a window that is not KakaoTalk (status 1) and bad click counts (status 10)' {
        [KakaoWin32]::SendCombo(0, 'x', [byte[]](0x11, 0x53), 0) | Should Be 1
        [KakaoWin32]::ClickAt(0, 'x', 0, 0, 1, 0) | Should Be 1
        [KakaoWin32]::ClickAt(0, 'x', 0, 0, 5, 0) | Should Be 10
    }

    It 'the native layer refuses a real KakaoTalk window whose title does not match (status 2)' -Skip:$noKakaoWindow {
        [KakaoWin32]::SendCombo($kakaoWindow[0].Hwnd, 'definitely-not-this-title', [byte[]](0x11, 0x53), 0) | Should Be 2
        [KakaoWin32]::ClickAt($kakaoWindow[0].Hwnd, 'definitely-not-this-title', 0, 0, 1, 0) | Should Be 2
    }

    It 'HeldKey runs without throwing' {
        ([KakaoWin32]::HeldKey() -is [int]) | Should Be $true
    }

    # 한/영 키(0x15)는 키보드·입력기에 따라 손을 떼도 계속 눌린 것으로 읽힌다(이 PC 실측). 그 키만 "손이 닿음"으로 세지 않는다.
    It 'HeldKeyFrom does not count the Hangul key (0x15) as a held key' {
        $down = @(0x15)
        [KakaoWin32]::HeldKeyFrom([Func[int, bool]]({ param($vk) $down -contains $vk }.GetNewClosure())) | Should Be 0
    }

    It 'HeldKeyFrom still reports any other key even while the Hangul key is down' {
        $down = @(0x15, 0x11)
        [KakaoWin32]::HeldKeyFrom([Func[int, bool]]({ param($vk) $down -contains $vk }.GetNewClosure())) | Should Be 0x11
    }

    It 'HeldKeyFrom reports every other scanned key one by one (Ctrl, Shift, Alt, Esc, Delete, Win, letters, Enter ...)' {
        $wrong = @()
        foreach ($key in 0x08..0xDF) {
            if ($key -eq 0x15) { continue }
            $down = @($key)
            $got = [KakaoWin32]::HeldKeyFrom([Func[int, bool]]({ param($vk) $down -contains $vk }.GetNewClosure()))
            if ($got -ne $key) { $wrong += $key }
        }
        ($wrong -join ',') | Should Be ''
    }

    It 'the ignore list is exactly the Hangul key and nothing else' {
        $ignored = @([KakaoWin32]::IgnoredHeldKeys())
        $ignored.Count | Should Be 1
        $ignored[0] | Should Be 0x15
    }
}


Describe 'Guard: 창 올리기 재시도 (2번 시험 앞 3회 "맨 앞에 없음" 정지의 원인을 모른 채 보강)' {
    It 'raises the window again when the first try did not bring it to the front, up to 3 tries, then sends once' {
        foreach ($raiseOn in 1, 2, 3) {
            $f = New-FakeProvider
            Initialize-Guard $f
            $f.Foreground = 999
            $f.RaiseOn = $raiseOn
            Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider
            $f.SetCount | Should Be $raiseOn
            ((Get-InputCalls $f) -join '|') | Should Be 'Combo:100:0D'
        }
    }

    It 'gives up after 3 tries with exit 2 and sends nothing' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Foreground = 999
        $f.RaiseOn = 4
        $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '맨 앞'
        $f.SetCount | Should Be 3
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'does not retry when the window is already in front (one raise, as before)' {
        $f = New-FakeProvider
        Initialize-Guard $f
        Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider
        $f.SetCount | Should Be 1
    }

    It 'stops at once, without raising again, when a person touched the keyboard or mouse during a try' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Foreground = 999
        $f.RaiseOn = 3
        $f.TickOnSet = 2500
        $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '키보드나 마우스'
        $f.SetCount | Should Be 1
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'a window that comes to the front but is not the expected room still sends nothing (the checks after the retries are unchanged)' {
        foreach ($case in 'Title', 'Process') {
            $f = New-FakeProvider
            Initialize-Guard $f
            $f.Foreground = 999
            $f.RaiseOn = 2
            if ($case -eq 'Title') { $f.Title = '다른방' } else { $f.Process = 'notepad' }
            (Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Enter' -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }
}
Describe 'Guard: Set-KakaoWindowFront (③, 키·클릭 없이 창만 앞으로)' {
    It 'raises the window and reports true, sending no key, click or close' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Foreground = 999
        $f.RaiseOn = 1
        (Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider) | Should Be $true
        $f.SetCount | Should Be 1
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'retries up to 3 times and reports false (not an error) when it never reaches the front' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Foreground = 999
        $f.RaiseOn = 4
        (Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider) | Should Be $false
        $f.SetCount | Should Be 3
        (Get-InputCalls $f).Count | Should Be 0
    }

    It 'does not raise at all when the process or the title is wrong (exit 2)' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Process = 'notepad'
        (Get-ThrownError { Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
        $f.SetCount | Should Be 0
        $f2 = New-FakeProvider
        Initialize-Guard $f2
        (Get-ThrownError { Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '다른방' -Provider $f2.Provider }).ExitCode | Should Be 2
        (Get-ThrownError { Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '' -Provider $f2.Provider }).ExitCode | Should Be 2
        $f2.SetCount | Should Be 0
    }

    It 'stops without taking the window back again when the person touched the keyboard or mouse' {
        $f = New-FakeProvider
        Initialize-Guard $f
        $f.Foreground = 999
        $f.RaiseOn = 3
        $f.TickOnSet = 2222
        (Get-ThrownError { Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
        $f.SetCount | Should Be 1
    }

    It 'refuses to run without the human-hand baseline' {
        $f = New-FakeProvider
        Reset-InputBaseline
        (Get-ThrownError { Set-KakaoWindowFront -Hwnd 100 -ExpectedTitle '비밀방' -Provider $f.Provider }).ExitCode | Should Be 2
        $f.SetCount | Should Be 0
    }
}

# Esc 는 메인 창 제목("카카오톡")일 때만 보낼 수 있다(2026-11-15 사용자 승인). 방 창에서는 창을 닫기 때문에 절대 가면 안 된다. PowerShell 쪽과 C# 쪽 양쪽에서 막는다.
Describe 'Guard: Esc 는 메인 창 제목일 때만 (검색을 닫는 용도)' {
    It 'sends Esc to the main window (title exactly 카카오톡) like any allowed key' {
        $f = New-FakeProvider
        $f.Title = '카카오톡'
        Initialize-Guard $f
        Send-KeyCombo -Hwnd 100 -Keys 'Esc' -ExpectedTitle '카카오톡' -Provider $f.Provider
        ((Get-InputCalls $f) -join '|') | Should Be 'Combo:100:1B'
    }

    It 'refuses Esc for any other title (a room window!) before touching the window at all (exit 2)' {
        foreach ($title in '비밀방', '카카오톡 ', '카카오톡방', '카카오', '', '카카오톡톡', ('카카오톡' + [char]0x200B)) {
            $f = New-FakeProvider
            $f.Title = $title
            Initialize-Guard $f
            $e = Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys 'Esc' -ExpectedTitle $title -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $f.SetCount | Should Be 0
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'matches the key name exactly: only the name Esc is allowed (not Escape, ESC, esc, Esc+Esc)' {
        foreach ($name in 'Escape', 'ESC', 'esc', 'Esc+Esc', ' Esc', 'Esc ') {
            $f = New-FakeProvider
            $f.Title = '카카오톡'
            Initialize-Guard $f
            (Get-ThrownError { Send-KeyCombo -Hwnd 100 -Keys $name -ExpectedTitle '카카오톡' -Provider $f.Provider }).ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'the native sender also refuses Esc for any title but the main window, before any check or input (status 6)' {
        [KakaoWin32]::SendCombo(0, '비밀방', [byte[]]@(0x1B), 0) | Should Be 6
        [KakaoWin32]::SendCombo(0, '', [byte[]]@(0x1B), 0) | Should Be 6
        [KakaoWin32]::SendCombo(0, '카카오톡 ', [byte[]]@(0x1B), 0) | Should Be 6
        [KakaoWin32]::SendCombo(0, $null, [byte[]]@(0x1B), 0) | Should Be 6
        # 제목이 메인 창이어도 창이 카카오톡이 아니면(번호 0) 입력 전에 멈춘다: 6 이 아니라 1(프로세스 불일치).
        [KakaoWin32]::SendCombo(0, '카카오톡', [byte[]]@(0x1B), 0) | Should Be 1
    }

    It 'the native sender still refuses every key that is not on the table (digits, Delete, Backspace, Ctrl+A)' {
        foreach ($combo in @(@(0x11, 0x41), @(0x2E), @(0x08), @(0x11, 0x31), @(0x1B, 0x1B), @(0x11, 0x1B))) {
            [KakaoWin32]::SendCombo(0, '카카오톡', [byte[]]$combo, 0) | Should Be 6
        }
    }
}
