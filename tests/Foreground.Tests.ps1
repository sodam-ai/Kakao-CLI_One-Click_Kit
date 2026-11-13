$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Foreground')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 시계는 Sleep 으로만 흐른다. FgFrom/FgUntil(밀리초) 사이에만 카카오톡이 맨 앞이다(여러 구간은 Windows 에 배열로).
function New-FakeFgProvider([object[]]$Windows, [int]$StartMs = 0) {
    $s = @{ Ms = $StartMs; Said = 0; Polls = 0; Windows = $Windows; Throw = $false }
    $s.Provider = @{
        NowMs        = { $s.Ms }.GetNewClosure()
        Sleep        = { param($ms) $s.Ms += $ms }.GetNewClosure()
        IsForeground = {
            param($hwnd)
            $s.Polls++
            if ($s.Throw) { throw 'win32 broke' }
            foreach ($w in $s.Windows) { if ($s.Ms -ge $w[0] -and $s.Ms -lt $w[1]) { return $true } }
            return $false
        }.GetNewClosure()
        Say          = { param($text) $s.Said++ }.GetNewClosure()
    }
    return $s
}

Describe 'Foreground: 카카오톡이 맨 앞이 될 때까지 입력 0 으로 기다린다 (설계서 13.8)' {
    It 'returns after the window has been in front for 2 seconds in a row, without any guidance when it was already in front' {
        $f = New-FakeFgProvider @(, @(0, 999999))
        $r = Wait-KakaoForeground -Hwnd 20 -Provider $f.Provider
        $r | Should Be $true
        ($f.Ms -ge 2000) | Should Be $true
        ($f.Ms -lt 2500) | Should Be $true
        $f.Said | Should Be 0
    }

    It 'prints the click guidance once while waiting and returns 2 seconds after the window comes to the front' {
        $f = New-FakeFgProvider @(, @(5000, 999999))
        (Wait-KakaoForeground -Hwnd 20 -Provider $f.Provider) | Should Be $true
        $f.Said | Should Be 1
        ($f.Ms -ge 7000) | Should Be $true
        ($f.Ms -lt 7500) | Should Be $true
    }

    It 'restarts the 2 seconds when the window leaves the front for a moment' {
        # 0~1.5초 맨 앞, 1.5~3초 아님, 3초부터 계속 맨 앞 => 5초 지나서야 끝난다
        $f = New-FakeFgProvider @(@(0, 1500), @(3000, 999999))
        (Wait-KakaoForeground -Hwnd 20 -Provider $f.Provider) | Should Be $true
        ($f.Ms -ge 5000) | Should Be $true
        ($f.Ms -lt 5500) | Should Be $true
    }

    It 'stops with a guard error (exit 2) after 120 seconds when it never comes to the front' {
        $f = New-FakeFgProvider @()
        $e = Get-ThrownError { Wait-KakaoForeground -Hwnd 20 -Provider $f.Provider }
        $e.GetType().Name | Should Be 'KakaoGuardException'
        $e.ExitCode | Should Be 2
        ($f.Ms -ge 120000) | Should Be $true
        ($f.Ms -lt 120500) | Should Be $true
        $f.Said | Should Be 1
    }

    It 'boundary: a window that is stable exactly at 120 seconds still succeeds, one that needs more time fails' {
        $ok = New-FakeFgProvider @(, @(118000, 999999))
        (Wait-KakaoForeground -Hwnd 20 -Provider $ok.Provider) | Should Be $true
        $late = New-FakeFgProvider @(, @(118500, 999999))
        (Get-ThrownError { Wait-KakaoForeground -Hwnd 20 -Provider $late.Provider }).ExitCode | Should Be 2
    }

    It 'a failing check stops the wait with the original error (nothing is typed, nothing is swallowed)' {
        $f = New-FakeFgProvider @(, @(0, 999999))
        $f.Throw = $true
        $e = Get-ThrownError { Wait-KakaoForeground -Hwnd 20 -Provider $f.Provider }
        $e.Message | Should Match 'win32 broke'
    }

    It 'refuses a missing window handle and a provider without the needed members' {
        (Get-ThrownError { Wait-KakaoForeground -Hwnd 0 -Provider (New-FakeFgProvider @()).Provider }).ExitCode | Should Be 2
        (Get-ThrownError { Wait-KakaoForeground -Hwnd 20 -Provider @{ NowMs = { 0 } } }).ExitCode | Should Be 2
    }

    It 'the source never sends keys or clicks: it only reads the foreground window' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\Foreground.ps1'))
        foreach ($bad in 'Send-KeyCombo', 'SendInput', 'SetForegroundWindow', 'SetForeground', 'Send-Click', 'SendKeys', 'Use-TextClipboard') {
            $text.IndexOf($bad, [System.StringComparison]::Ordinal) | Should Be -1
        }
    }

    It 'the real provider reads the real foreground window without changing anything' {
        $p = Get-DefaultForegroundProvider
        [void][bool](& $p.IsForeground 1)   # 존재하지 않는 창이면 거짓이어야 한다(던지지 않는다)
        (& $p.IsForeground 1) | Should Be $false
        ((& $p.NowMs) -is [long]) | Should Be $true
    }
}
