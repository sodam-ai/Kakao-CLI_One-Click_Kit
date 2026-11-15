$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'Ocr', 'Room')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 창 목록을 정해 둔 순서대로 돌려주고, 입력·닫기·확인 호출을 모두 기록한다. 실제 카카오톡은 건드리지 않는다.
function New-FakeRoomProvider {
    $s = @{
        Calls        = (New-Object System.Collections.ArrayList)
        WindowsQueue = (New-Object System.Collections.Queue)
        Last         = @()
        OcrAvailable = $true
        ResultSingle = $true
        ResultThrows = $false
        Hint         = ''
        TabOpenChat  = $true
    }
    $s.Provider = @{
        Windows        = { [void]$s.Calls.Add('Windows'); if ($s.WindowsQueue.Count -gt 0) { $s.Last = @($s.WindowsQueue.Dequeue()) }; $s.Last }.GetNewClosure()
        WaitIdle       = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        # 결과가 1건일 때 첫 결과를 여는 Enter 하나(2026-11-15 확인: 클릭 없이 Enter 로 열린다). 마우스 클릭 자리는 없다.
        PressEnter     = { param($hwnd, $title) [void]$s.Calls.Add(('Enter:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Explain        = { param($hwnd) [void]$s.Calls.Add('Explain'); $s.Hint }.GetNewClosure()
        PasteText      = { param($hwnd, $text, $title) [void]$s.Calls.Add(('Paste:{0}:{1}:{2}' -f $hwnd, $text, $title)) }.GetNewClosure()
        OpenSearch     = { param($hwnd, $title) [void]$s.Calls.Add(('OpenSearch:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        TabIsOpenChat  = { param($hwnd) [void]$s.Calls.Add('TabCheck'); $s.TabOpenChat }.GetNewClosure()
        OcrAvailable   = { [void]$s.Calls.Add('OcrAvailable'); $s.OcrAvailable }.GetNewClosure()
        ResultIsSingle = { param($hwnd, $name, $clickY) [void]$s.Calls.Add(('ResultCheck:{0}:{1}:{2}' -f $hwnd, $name, $clickY)); if ($s.ResultThrows) { throw 'ocr broke' }; $s.ResultSingle }.GetNewClosure()
        CloseWindow    = { param($hwnd, $title) [void]$s.Calls.Add(('Close:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Sleep          = { param($ms) [void]$s.Calls.Add('Sleep') }.GetNewClosure()
    }
    return $s
}

function New-Win([long]$Hwnd, [string]$Title) { [pscustomobject]@{ Hwnd = $Hwnd; Title = $Title } }
function Set-TestRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-TestRoom([string]$Name, [bool]$AiRead = $false) { [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $true; canSend = $true; selfOnly = $true; aiRead = $AiRead; aiSend = $false } }
# 키·마우스·창 닫기처럼 "실제로 입력되는" 호출만 센다.
function Get-InputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Enter:*' -or $_ -like 'OpenSearch:*' -or $_ -like 'Paste:*' -or $_ -like 'Close:*' }) }

$MainWin = New-Win 10 '카카오톡'

# 정상 흐름: 메인 창 하나 -> 검색·붙여넣기·결과 확인 -> 새 방 창이 두 번째 확인 때 나타난다.
function New-OpenScenario {
    $f = New-FakeRoomProvider
    $f.WindowsQueue.Enqueue(@($MainWin))
    $f.WindowsQueue.Enqueue(@($MainWin))
    $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 20 '테스트방')))
    return $f
}

Describe 'Room: Open-KakaoRoom 허용 목록 (입력 전에 먼저)' {
    It 'rejects a room that is not on the allowed list with exit 1 and makes no call at all' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $e = Get-ThrownError { Open-KakaoRoom -Name '없는방' -Provider $f.Provider }
            $e.GetType().Name | Should Be 'KakaoKitException'
            $e.ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }

    It 'rejects near-miss names (trailing space, prefix, extra digit) without any call' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($name in '테스트방 ', '테스트', '테스트방2', '') {
                $f = New-FakeRoomProvider
                $e = Get-ThrownError { Open-KakaoRoom -Name $name -Provider $f.Provider }
                $e.ExitCode | Should Be 1
                $f.Calls.Count | Should Be 0
            }
        }
    }

    It 'rejects everything when there is no config at all' {
        Use-TempHome {
            $f = New-FakeRoomProvider
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }

    It 'rejects an AI caller when the room has no AI read switch, without any call' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' $false))
            $f = New-FakeRoomProvider
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Caller ai -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }

    It 'lets an AI caller past the list check when the AI read switch is on (then stops at the missing main window)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' $true))
            $f = New-FakeRoomProvider
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Caller ai -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            ($f.Calls -contains 'Windows') | Should Be $true
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'never lets an AI caller use the unverified-result override' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' $true))
            $f = New-FakeRoomProvider
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Caller ai -AllowUnverifiedResult -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }
}

Describe 'Room: 이미 열린 창과 메인 창' {
    It 'reuses a window whose title is exactly the room name: no input, not opened by the kit' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 77 '테스트방')))
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $false
            $r.Hwnd | Should Be 77
            $r.Title | Should Be '테스트방'
            (Get-InputCalls $f).Count | Should Be 0
            ($f.Calls -contains 'OcrAvailable') | Should Be $false
        }
    }

    It 'refuses when two windows have exactly the room name (exit 2, no input)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 77 '테스트방'), (New-Win 78 '테스트방')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'does not treat a window with a merely similar title as the room (trailing space) and stops at the missing main window' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@((New-Win 77 '테스트방 ')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'stops with exit 3 and no input when the main window is missing or there are two' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $none = New-FakeRoomProvider
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $none.Provider }).ExitCode | Should Be 3
            (Get-InputCalls $none).Count | Should Be 0
            $two = New-FakeRoomProvider
            $two.WindowsQueue.Enqueue(@($MainWin, (New-Win 11 '카카오톡')))
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $two.Provider }).ExitCode | Should Be 3
            (Get-InputCalls $two).Count | Should Be 0
        }
    }
}

Describe 'Room: 열기 전 결과 확인 (fail-closed)' {
    It 'does not open when the text reader is unavailable and nobody allowed it (exit 3, no input at all)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.OcrAvailable = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            (Get-InputCalls $f).Count | Should Be 0
            ($f.Calls -contains 'WaitIdle') | Should Be $false
        }
    }

    It 'does not click anything when the open-chat tab is not showing (the icon spot is add-friend on the friends tab)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.TabOpenChat = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '오픈채팅'
            ($f.Calls -contains 'TabCheck') | Should Be $true
            (Get-InputCalls $f).Count | Should Be 0
            ($f.Calls -contains 'WaitIdle') | Should Be $false
        }
    }

    It 'checks the tab before the first click when the tab is right, then opens as before' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $tab = [array]::IndexOf(@($f.Calls), 'TabCheck')
            $click = [array]::IndexOf(@($f.Calls), @($f.Calls | Where-Object { $_ -like 'OpenSearch:*' })[0])
            ($tab -ge 0) | Should Be $true
            ($tab -lt $click) | Should Be $true
        }
    }

    It 'opens without the check only when a human allows it, and records a warning' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            Clear-KitWarnings
            $f = New-OpenScenario
            $f.OcrAvailable = $false
            $r = Open-KakaoRoom -Name '테스트방' -AllowUnverifiedResult -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            @($f.Calls | Where-Object { $_ -like 'ResultCheck:*' }).Count | Should Be 0
            @(Get-KitWarnings).Count | Should Be 1
            Clear-KitWarnings
        }
    }

    It 'never presses Enter when the result is not exactly one row (the search was opened with Ctrl+F only)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.ResultSingle = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Enter:*' }).Count | Should Be 0
            @($f.Calls | Where-Object { $_ -like 'OpenSearch:*' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'never presses Enter when the result check itself fails with an error' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.ResultThrows = $true
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.Message | Should Be 'ocr broke'
            @($f.Calls | Where-Object { $_ -like 'Enter:*' }).Count | Should Be 0
        }
    }

    It 'pastes right after opening the search (Ctrl+F) and sends no select-all: Ctrl+A is the add-friend shortcut in the KakaoTalk main window' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $null = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            @($f.Calls | Where-Object { $_ -like 'SelectAll*' }).Count | Should Be 0
            $iOpen = $f.Calls.IndexOf('OpenSearch:10:카카오톡')
            $iPaste = $f.Calls.IndexOf('Paste:10:테스트방:카카오톡')
            $iOpen | Should BeLessThan $iPaste
            $iOpen | Should BeGreaterThan -1
        }
    }

    It 'adds the reason hint to the stop message when the result is not exactly one row, and never asks for it on success' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.ResultSingle = $false
            $f.Hint = 'HINT-WINDOW-SIZE'
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '테스트방'
            $e.Message | Should Match 'HINT-WINDOW-SIZE'
            ($f.Calls -contains 'Explain') | Should Be $true
            $ok = New-OpenScenario
            $null = Open-KakaoRoom -Name '테스트방' -Provider $ok.Provider
            ($ok.Calls -contains 'Explain') | Should Be $false
        }
    }

    It 'still stops with exit 2 and the plain message when the hint is empty, fails, or the provider has no hint step' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $empty = New-FakeRoomProvider
            $empty.ResultSingle = $false
            $empty.WindowsQueue.Enqueue(@($MainWin))
            $e1 = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $empty.Provider }
            $e1.ExitCode | Should Be 2
            $e1.Message | Should Not Match 'HINT'
            $broken = New-FakeRoomProvider
            $broken.ResultSingle = $false
            $broken.Provider.Explain = { param($hwnd) throw 'hint broke' }
            $broken.WindowsQueue.Enqueue(@($MainWin))
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $broken.Provider }).ExitCode | Should Be 2
            $none = New-FakeRoomProvider
            $none.ResultSingle = $false
            $none.Provider.Remove('Explain')
            $none.WindowsQueue.Enqueue(@($MainWin))
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $none.Provider }).ExitCode | Should Be 2
        }
    }

    It 'opens a room in the documented order: Ctrl+F, paste the stored name, check that exactly one result shows, then one Enter (no mouse click at all)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $r.Hwnd | Should Be 20
            $r.Title | Should Be '테스트방'
            $clicks = @($f.Calls | Where-Object { $_ -like 'Enter:*' })
            $clicks.Count | Should Be 1
            $clicks[0] | Should Be 'Enter:10:카카오톡'
            @($f.Calls | Where-Object { $_ -eq 'OpenSearch:10:카카오톡' }).Count | Should Be 1
            $paste = @($f.Calls | Where-Object { $_ -like 'Paste:*' })
            $paste.Count | Should Be 1
            $paste[0] | Should Be 'Paste:10:테스트방:카카오톡'
            $iPaste = $f.Calls.IndexOf($paste[0])
            # 결과 확인은 더블클릭할 높이(0.335)를 함께 받는다: 확인한 줄과 클릭하는 줄이 같은 위치임을 확인에서 따진다.
            $iCheck = $f.Calls.IndexOf('ResultCheck:10:테스트방:0.335')
            $iDouble = $f.Calls.IndexOf($clicks[0])
            $iPaste | Should BeLessThan $iCheck
            $iCheck | Should BeLessThan $iDouble
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
        }
    }
}

Describe 'Room: 연 뒤 확인' {
    It 'closes a new window whose title differs, and then stops with exit 2 without touching windows that were already open' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $other = New-Win 30 '다른 채팅'
            $f.WindowsQueue.Enqueue(@($MainWin, $other))
            $f.WindowsQueue.Enqueue(@($MainWin, $other, (New-Win 40 '엉뚱한방')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $closes = @($f.Calls | Where-Object { $_ -like 'Close:*' })
            $closes.Count | Should Be 1
            $closes[0] | Should Be 'Close:40:엉뚱한방'
        }
    }

    It 'waits through a new window that has no title yet and never closes it' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin))
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 41 '')))
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 41 ''), (New-Win 20 '테스트방')))
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.Hwnd | Should Be 20
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'times out with exit 3 when no room window appears, and closes nothing' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
            @($f.Calls | Where-Object { $_ -like 'Enter:*' }).Count | Should Be 1
        }
    }

    It 'refuses (exit 2) and closes nothing when two new windows both have the room name' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin))
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 20 '테스트방'), (New-Win 21 '테스트방')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
        }
    }
}

Describe 'Room: Close-KitOpenedWindow' {
    It 'does nothing for a window the kit did not open' {
        $f = New-FakeRoomProvider
        $opened = [pscustomobject]@{ Hwnd = 77; Title = '테스트방'; OpenedByKit = $false }
        Close-KitOpenedWindow -Opened $opened -Provider $f.Provider | Should Be $false
        $f.Calls.Count | Should Be 0
    }

    It 'closes only the window the kit opened, once, with its own handle and title' {
        $f = New-FakeRoomProvider
        $opened = [pscustomobject]@{ Hwnd = 20; Title = '테스트방'; OpenedByKit = $true }
        Close-KitOpenedWindow -Opened $opened -Provider $f.Provider | Should Be $true
        $f.Calls.Count | Should Be 1
        $f.Calls[0] | Should Be 'Close:20:테스트방'
    }
}

Describe 'Room: 기본 제공자는 라이브러리를 스크립트 범위로 불러온 환경에서도 동작한다' {
    It 'PasteText finds Send-KeyCombo when the libraries are dot-sourced inside a script file (a closure cannot see script-scope functions)' {
        # 실제 사고: 스크립트 파일 안에서 라이브러리를 불러오면 함수가 스크립트 범위에 생긴다. .GetNewClosure() 로 만든 블록은 전역만 보여서
        # Send-KeyCombo 를 못 찾는다(S5 에서 Ctrl+F·Ctrl+A 뒤 붙여넣기에서 멈춤). 시험은 키 전송과 클립보드를 가짜로 바꿔 입력 없이 확인한다.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('room-scope-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $body = @"
`$ErrorActionPreference = 'Stop'
foreach (`$n in 'Messages.ko', 'Paths', 'Errors', 'Config', 'Log', 'Win32', 'Guard', 'Clip', 'Ocr', 'Room') { . (Join-Path '$kitLibDir' "`$n.ps1") }
`$script:seen = @()
function Send-KeyCombo { param(`$Hwnd, `$Keys, `$ExpectedTitle) `$script:seen += `$Keys }
function Use-TextClipboard { param(`$Text, [scriptblock]`$Action) & `$Action }
`$p = Get-DefaultRoomProvider
& `$p.PasteText 1 'abc' 'title'
'SEEN=' + (`$script:seen -join ',')
"@
        try {
            [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($true)))
            # -File 은 스크립트가 전역 범위에서 돌아 함수가 전역이 된다(사고를 못 잡는다). 실제 실행처럼 호출 연산자(&)로 부른다.
            $out = (& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command "& '$tmp'" 2>&1 | Out-String)
            $out | Should Match 'SEEN=Ctrl\+V'
        }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Room: 소스 규칙' {
    It 'Room.ps1 sends only Ctrl+F (open the search) and Ctrl+V as keys (never Ctrl+A, the add-friend shortcut), closes windows only through Close-KakaoWindow, and does not call Win32 directly' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $keys = @([regex]::Matches($src, "-Keys '([^']*)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $keys.Count | Should Be 3
        $keys[0] | Should Be 'Ctrl+F'
        $keys[1] | Should Be 'Ctrl+V'
        $keys[2] | Should Be 'Enter'
        # Enter 는 검색 결과가 정확히 1건임을 확인한 뒤 딱 한 곳에서만 보낸다. Delete·Backspace·Esc·Ctrl+A 는 방 열기에서 절대 보내지 않는다.
        @([regex]::Matches($src, "-Keys 'Enter'")).Count | Should Be 1
        $src | Should Not Match "-Keys '(Delete|Backspace|Esc|Ctrl\+A)"
        $src | Should Not Match '\[KakaoWin32\]::'
        $src | Should Not Match 'PostClose|SendInput|mouse_event'
    }

    It 'opens the search with Ctrl+F and has no click on a search-icon spot (the same spot is a different button on other tabs)' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $src | Should Match "-Keys 'Ctrl\+F'"
        $src | Should Not Match 'SearchIcon'
        $src | Should Not Match '0\.714'
    }

    It 'has no mouse click anywhere in room opening (the first result is opened with Enter, so no click position is needed)' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $code = (($src -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        $code | Should Not Match 'Invoke-RelClick|ClickAt|DoubleClick|mouse_event|SendInput|\bClick\s*='
        $code | Should Not Match '& \$Provider\.Click'
        $code | Should Not Match 'FirstResultRow\[0\]'
    }

    It 'the real provider presses Enter with the guarded key sender and has no click member' {
        $p = Get-DefaultRoomProvider
        $p.ContainsKey('PressEnter') | Should Be $true
        $p.ContainsKey('Click') | Should Be $false
        ($p.PressEnter.ToString()).Contains("'Enter'") | Should Be $true
    }
}
