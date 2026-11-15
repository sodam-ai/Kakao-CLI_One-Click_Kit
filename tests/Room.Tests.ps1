$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'InputProbe', 'Room')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 창 목록을 정해 둔 순서대로 돌려주고, 입력·닫기·확인 호출을 모두 기록한다. 실제 카카오톡은 건드리지 않는다.
# 메인 창 화면(Screen)은 상태를 가진다: 검색을 열면 'chat-search', Esc 로 닫으면 'chat-list' (실제 카카오톡처럼 Enter 로 방을 열어도 검색은 남는다).
function New-FakeRoomProvider {
    $s = @{
        Calls         = (New-Object System.Collections.ArrayList)
        WindowsQueue  = (New-Object System.Collections.Queue)
        Last          = @()
        Screen        = 'chat-list'
        SearchOpens   = $true
        EscWorks      = $true
        EscThrows     = $false
        EnterThrows   = $false
    }
    $s.Provider = @{
        Windows        = { [void]$s.Calls.Add('Windows'); if ($s.WindowsQueue.Count -gt 0) { $s.Last = @($s.WindowsQueue.Dequeue()) }; $s.Last }.GetNewClosure()
        WaitIdle       = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        # 첫 결과를 여는 Enter 하나(2026-11-15 확인: 클릭 없이 Enter 로 열린다). 마우스 클릭 자리는 없다.
        PressEnter     = { param($hwnd, $title) [void]$s.Calls.Add(('Enter:{0}:{1}' -f $hwnd, $title)); if ($s.EnterThrows) { throw 'enter broke' } }.GetNewClosure()
        PasteText      = { param($hwnd, $text, $title) [void]$s.Calls.Add(('Paste:{0}:{1}:{2}' -f $hwnd, $text, $title)) }.GetNewClosure()
        OpenSearch     = { param($hwnd, $title) [void]$s.Calls.Add(('OpenSearch:{0}:{1}' -f $hwnd, $title)); if ($s.SearchOpens) { $s.Screen = 'chat-search' } }.GetNewClosure()
        # 메인 창 화면을 구조 이름으로 읽는다(읽기만): 'chat-list' / 'chat-search' / 'other' / 'unknown'.
        MainScreen     = { param($hwnd) [void]$s.Calls.Add('Screen'); $s.Screen }.GetNewClosure()
        # 검색 닫기: Esc 한 번(메인 창 제목일 때만 가드가 보낸다).
        CloseSearch    = { param($hwnd, $title) [void]$s.Calls.Add(('Esc:{0}:{1}' -f $hwnd, $title)); if ($s.EscThrows) { throw 'esc broke' }; if ($s.EscWorks) { $s.Screen = 'chat-list' } }.GetNewClosure()
        CloseWindow    = { param($hwnd, $title) [void]$s.Calls.Add(('Close:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Sleep          = { param($ms) [void]$s.Calls.Add('Sleep') }.GetNewClosure()
    }
    return $s
}

function New-Win([long]$Hwnd, [string]$Title) { [pscustomobject]@{ Hwnd = $Hwnd; Title = $Title } }
function Set-TestRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-TestRoom([string]$Name, [bool]$AiRead = $false) { [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $true; canSend = $true; selfOnly = $true; aiRead = $AiRead; aiSend = $false } }
# 키·마우스·창 닫기처럼 "실제로 입력되는" 호출만 센다.
function Get-InputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Enter:*' -or $_ -like 'OpenSearch:*' -or $_ -like 'Paste:*' -or $_ -like 'Close:*' -or $_ -like 'Esc:*' }) }
function Get-Calls($s, [string]$Like) { return @($s.Calls | Where-Object { $_ -like $Like }) }

$MainWin = New-Win 10 '카카오톡'

# 정상 흐름: 메인 창 하나 -> 검색·붙여넣기·검색 열림 확인 -> 새 방 창이 두 번째 확인 때 나타난다.
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
            $e = Get-ThrownError { Open-KakaoRoom -Name '다른방' -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }

    It 'rejects near-miss names (trailing space, prefix, extra digit) without any call' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($name in '테스트방 ', '테스트', '테스트방1', ' 테스트방', '') {
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
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }).ExitCode | Should Be 1
            $f.Calls.Count | Should Be 0
        }
    }

    It 'rejects an AI caller when the room has no AI read switch, without any call' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' $false))
            $f = New-FakeRoomProvider
            (Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Caller ai -Provider $f.Provider }).ExitCode | Should Be 1
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

    It 'has no "open without checking" override any more (the check is a structure read, so there is nothing to skip)' {
        (Get-Command Open-KakaoRoom).Parameters.ContainsKey('AllowUnverifiedResult') | Should Be $false
    }
}

Describe 'Room: 이미 열린 창과 메인 창' {
    It 'reuses a window whose title is exactly the room name: no input, no screen read, not opened by the kit' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 77 '테스트방')))
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $false
            $r.Hwnd | Should Be 77
            $r.Title | Should Be '테스트방'
            (Get-InputCalls $f).Count | Should Be 0
            ($f.Calls -contains 'Screen') | Should Be $false
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

Describe 'Room: 열기 전 화면 확인 (구조로 읽음, fail-closed)' {
    It 'does not touch anything when the main window is not on the chat list (friends tab etc.): exit 2, no input, no wait' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($screen in 'other', 'unknown') {
                $f = New-FakeRoomProvider
                $f.Screen = $screen
                $f.WindowsQueue.Enqueue(@($MainWin))
                $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
                $e.ExitCode | Should Be 2
                $e.Message | Should Match '채팅'
                (Get-InputCalls $f).Count | Should Be 0
                ($f.Calls -contains 'WaitIdle') | Should Be $false
            }
        }
    }

    It 'opens as usual when the chat list is showing (the screen is read before the first input)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $iScreen = $f.Calls.IndexOf('Screen')
            $iOpen = $f.Calls.IndexOf('OpenSearch:10:카카오톡')
            $iScreen | Should BeGreaterThan -1
            $iScreen | Should BeLessThan $iOpen
        }
    }

    It 'closes a search left open by an earlier job (one Esc) before it starts, and only then opens the search again' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $f.Screen = 'chat-search'
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $esc = @(Get-Calls $f 'Esc:*')
            $esc.Count | Should Be 2   # 시작 때 하나, 끝에서 하나
            $esc[0] | Should Be 'Esc:10:카카오톡'
            $iWait = $f.Calls.IndexOf('WaitIdle')
            $iEsc = $f.Calls.IndexOf($esc[0])
            $iOpen = $f.Calls.IndexOf('OpenSearch:10:카카오톡')
            $iWait | Should BeLessThan $iEsc
            $iEsc | Should BeLessThan $iOpen
        }
    }

    It 'stops with exit 2 and types nothing more when the old search cannot be closed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.Screen = 'chat-search'
            $f.EscWorks = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '검색'
            (Get-Calls $f 'Esc:*').Count | Should Be 1
            (Get-Calls $f 'OpenSearch:*').Count | Should Be 0
            (Get-Calls $f 'Paste:*').Count | Should Be 0
            (Get-Calls $f 'Enter:*').Count | Should Be 0
        }
    }

    It 'never sends Esc unless the screen reads as an open search (not on the chat list, not on other screens)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($screen in 'other', 'unknown') {
                $f = New-FakeRoomProvider
                $f.Screen = $screen
                $f.WindowsQueue.Enqueue(@($MainWin))
                $null = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
                (Get-Calls $f 'Esc:*').Count | Should Be 0
            }
        }
    }

    It 'never presses Enter when the search did not open (nothing is pasted into the void and then confirmed), and sends no Esc either' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.SearchOpens = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '검색'
            (Get-Calls $f 'Enter:*').Count | Should Be 0
            (Get-Calls $f 'OpenSearch:*').Count | Should Be 1
            (Get-Calls $f 'Esc:*').Count | Should Be 0
            (Get-Calls $f 'Close:*').Count | Should Be 0
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

    It 'opens a room in the documented order: read screen, wait for idle hands, Ctrl+F, paste the stored name, check the search is open, one Enter, then one Esc (no mouse click at all)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $r.Hwnd | Should Be 20
            $r.Title | Should Be '테스트방'
            $enter = @(Get-Calls $f 'Enter:*')
            $enter.Count | Should Be 1
            $enter[0] | Should Be 'Enter:10:카카오톡'
            @(Get-Calls $f 'OpenSearch:*').Count | Should Be 1
            $paste = @(Get-Calls $f 'Paste:*')
            $paste.Count | Should Be 1
            $paste[0] | Should Be 'Paste:10:테스트방:카카오톡'
            $esc = @(Get-Calls $f 'Esc:*')
            $esc.Count | Should Be 1
            $esc[0] | Should Be 'Esc:10:카카오톡'
            $iPaste = $f.Calls.IndexOf($paste[0])
            $iEnter = $f.Calls.IndexOf($enter[0])
            $iEsc = $f.Calls.IndexOf($esc[0])
            # 붙여넣은 뒤, Enter 전에 검색이 열렸는지 읽는다.
            $screensBetween = 0
            for ($i = $iPaste + 1; $i -lt $iEnter; $i++) { if ($f.Calls[$i] -eq 'Screen') { $screensBetween++ } }
            ($screensBetween -ge 1) | Should Be $true
            $iEnter | Should BeLessThan $iEsc
            @(Get-Calls $f 'Close:*').Count | Should Be 0
            $f.Screen | Should Be 'chat-list'
        }
    }
}

Describe 'Room: 연 뒤 확인' {
    It 'closes a new window whose title differs, closes the search, and then stops with exit 2 without touching windows that were already open' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $other = New-Win 30 '다른 채팅'
            $f.WindowsQueue.Enqueue(@($MainWin, $other))
            $f.WindowsQueue.Enqueue(@($MainWin, $other, (New-Win 40 '엉뚱한방')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $closes = @(Get-Calls $f 'Close:*')
            $closes.Count | Should Be 1
            $closes[0] | Should Be 'Close:40:엉뚱한방'
            (Get-Calls $f 'Esc:*').Count | Should Be 1
            $f.Screen | Should Be 'chat-list'
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
            @(Get-Calls $f 'Close:*').Count | Should Be 0
        }
    }

    It 'times out with exit 3 when no room window appears, closes no window, and still closes the search' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            @(Get-Calls $f 'Close:*').Count | Should Be 0
            @(Get-Calls $f 'Enter:*').Count | Should Be 1
            @(Get-Calls $f 'Esc:*').Count | Should Be 1
        }
    }

    It 'refuses (exit 2) and closes no window when two new windows both have the room name, but still closes the search' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.WindowsQueue.Enqueue(@($MainWin))
            $f.WindowsQueue.Enqueue(@($MainWin, (New-Win 20 '테스트방'), (New-Win 21 '테스트방')))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            @(Get-Calls $f 'Close:*').Count | Should Be 0
            @(Get-Calls $f 'Esc:*').Count | Should Be 1
        }
    }

    It 'closes the search even when Enter fails, and keeps the original error' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.EnterThrows = $true
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.Message | Should Be 'enter broke'
            @(Get-Calls $f 'Esc:*').Count | Should Be 1
        }
    }

    It 'still returns the opened window and records a warning when the search cannot be closed afterwards (Esc fails or does not work)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($mode in 'throws', 'noeffect') {
                Clear-KitWarnings
                $f = New-OpenScenario
                if ($mode -eq 'throws') { $f.EscThrows = $true } else { $f.EscWorks = $false }
                $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
                $r.OpenedByKit | Should Be $true
                $r.Hwnd | Should Be 20
                @(Get-KitWarnings).Count | Should Be 1
                Clear-KitWarnings
            }
        }
    }

    It 'does not add a warning when everything went fine' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            Clear-KitWarnings
            $f = New-OpenScenario
            $null = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            @(Get-KitWarnings).Count | Should Be 0
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
    It 'PasteText and CloseSearch find Send-KeyCombo when the libraries are dot-sourced inside a script file (a closure cannot see script-scope functions)' {
        # 실제 사고: 스크립트 파일 안에서 라이브러리를 불러오면 함수가 스크립트 범위에 생긴다. .GetNewClosure() 로 만든 블록은 전역만 보여서
        # Send-KeyCombo 를 못 찾는다(S5 에서 Ctrl+F·Ctrl+A 뒤 붙여넣기에서 멈춤). 시험은 키 전송과 클립보드를 가짜로 바꿔 입력 없이 확인한다.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('room-scope-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $body = @"
`$ErrorActionPreference = 'Stop'
foreach (`$n in 'Messages.ko', 'Paths', 'Errors', 'Config', 'Log', 'Win32', 'Guard', 'Clip', 'InputProbe', 'Room') { . (Join-Path '$kitLibDir' "`$n.ps1") }
`$script:seen = @()
function Send-KeyCombo { param(`$Hwnd, `$Keys, `$ExpectedTitle) `$script:seen += (`$Keys + '@' + `$ExpectedTitle) }
function Use-TextClipboard { param(`$Text, [scriptblock]`$Action) & `$Action }
`$p = Get-DefaultRoomProvider
& `$p.PasteText 1 'abc' 'title'
& `$p.CloseSearch 1 '카카오톡'
'SEEN=' + (`$script:seen -join ',')
"@
        try {
            [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($true)))
            # -File 은 스크립트가 전역 범위에서 돌아 함수가 전역이 된다(사고를 못 잡는다). 실제 실행처럼 호출 연산자(&)로 부른다.
            $out = (& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command "& '$tmp'" 2>&1 | Out-String)
            $out | Should Match 'SEEN=Ctrl\+V@title,Esc@카카오톡'
        }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Room: 소스 규칙' {
    It 'Room.ps1 sends only Ctrl+F, Ctrl+V, Enter and Esc as keys (never Ctrl+A, the add-friend shortcut), closes windows only through Close-KakaoWindow, and does not call Win32 directly' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $keys = @([regex]::Matches($src, "-Keys '([^']*)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        ($keys -join ',') | Should Be 'Ctrl+F,Ctrl+V,Enter,Esc'
        # Enter 는 검색이 열렸음을 확인한 뒤 딱 한 곳에서만, Esc 도 딱 한 곳(검색 닫기 제공자)에서만 보낸다. Delete·Backspace·Ctrl+A 는 방 열기에서 절대 보내지 않는다.
        @([regex]::Matches($src, "-Keys 'Enter'")).Count | Should Be 1
        @([regex]::Matches($src, "-Keys 'Esc'")).Count | Should Be 1
        $src | Should Not Match "-Keys '(Delete|Backspace|Ctrl\+A)"
        $src | Should Not Match '\[KakaoWin32\]::'
        $src | Should Not Match 'PostClose|SendInput|mouse_event'
    }

    It 'Esc is sent only from the search-closing helper after it read that a search is open, and the helper is the only caller of the provider step' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $code = (($src -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        @([regex]::Matches($code, '& \$Provider\.CloseSearch')).Count | Should Be 1
        $start = $code.IndexOf('function Close-KakaoMainSearch')
        $start | Should BeGreaterThan -1
        $helper = $code.Substring($start)
        $helperEnd = $helper.IndexOf("`nfunction ", 10)
        if ($helperEnd -gt 0) { $helper = $helper.Substring(0, $helperEnd) }
        $helper.IndexOf('& $Provider.CloseSearch') | Should BeGreaterThan $helper.IndexOf('chat-search')
        $helper | Should Match "-cne 'chat-search'"
    }

    It 'no longer uses the screen text reader (OCR) or fixed pixel positions to decide anything' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $code = (($src -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        $code | Should Not Match 'Test-OpenChatTab|Test-SearchResultSingle|Test-OcrAvailable|Get-RoomFailureHint|OcrAvailable|ResultIsSingle|TabIsOpenChat|FirstResultRow|RoomAnchors'
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
    }

    It 'the real provider presses keys only with the guarded key sender, reads the screen with the structure reader, and has no click or OCR member' {
        $p = Get-DefaultRoomProvider
        $p.ContainsKey('PressEnter') | Should Be $true
        $p.ContainsKey('Click') | Should Be $false
        foreach ($gone in 'OcrAvailable', 'ResultIsSingle', 'TabIsOpenChat', 'Explain') { $p.ContainsKey($gone) | Should Be $false }
        ($p.PressEnter.ToString()).Contains("'Enter'") | Should Be $true
        ($p.CloseSearch.ToString()).Contains("'Esc'") | Should Be $true
        ($p.MainScreen.ToString()).Contains('Get-KakaoMainScreen') | Should Be $true
    }
}
