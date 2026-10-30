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
    }
    $s.Provider = @{
        Windows        = { [void]$s.Calls.Add('Windows'); if ($s.WindowsQueue.Count -gt 0) { $s.Last = @($s.WindowsQueue.Dequeue()) }; $s.Last }.GetNewClosure()
        WaitIdle       = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        Click          = { param($hwnd, $relX, $relY, $double, $title) [void]$s.Calls.Add(('Click:{0}:{1},{2}:{3}:{4}' -f $hwnd, $relX, $relY, $double, $title)) }.GetNewClosure()
        PasteText      = { param($hwnd, $text, $title) [void]$s.Calls.Add(('Paste:{0}:{1}:{2}' -f $hwnd, $text, $title)) }.GetNewClosure()
        OcrAvailable   = { [void]$s.Calls.Add('OcrAvailable'); $s.OcrAvailable }.GetNewClosure()
        ResultIsSingle = { param($hwnd, $name) [void]$s.Calls.Add(('ResultCheck:{0}:{1}' -f $hwnd, $name)); if ($s.ResultThrows) { throw 'ocr broke' }; $s.ResultSingle }.GetNewClosure()
        CloseWindow    = { param($hwnd, $title) [void]$s.Calls.Add(('Close:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Sleep          = { param($ms) [void]$s.Calls.Add('Sleep') }.GetNewClosure()
    }
    return $s
}

function New-Win([long]$Hwnd, [string]$Title) { [pscustomobject]@{ Hwnd = $Hwnd; Title = $Title } }
function Set-TestRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-TestRoom([string]$Name, [bool]$AiRead = $false) { [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $true; canSend = $true; selfOnly = $true; aiRead = $AiRead; aiSend = $false } }
# 키·마우스·창 닫기처럼 "실제로 입력되는" 호출만 센다.
function Get-InputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Click:*' -or $_ -like 'Paste:*' -or $_ -like 'Close:*' }) }

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

    It 'never double-clicks when the result is not exactly one row (only the search icon was clicked)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.ResultSingle = $false
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $clicks = @($f.Calls | Where-Object { $_ -like 'Click:*' })
            $clicks.Count | Should Be 1
            $clicks[0] | Should Match ':False:'
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'never double-clicks when the result check itself fails with an error' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeRoomProvider
            $f.ResultThrows = $true
            $f.WindowsQueue.Enqueue(@($MainWin))
            $e = Get-ThrownError { Open-KakaoRoom -Name '테스트방' -Provider $f.Provider }
            $e.Message | Should Be 'ocr broke'
            @($f.Calls | Where-Object { $_ -like 'Click:*' }).Count | Should Be 1
        }
    }

    It 'opens a room in the documented order: search icon, paste the stored name, check, then double-click the first row' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-OpenScenario
            $r = Open-KakaoRoom -Name '테스트방' -Provider $f.Provider
            $r.OpenedByKit | Should Be $true
            $r.Hwnd | Should Be 20
            $r.Title | Should Be '테스트방'
            $clicks = @($f.Calls | Where-Object { $_ -like 'Click:*' })
            $clicks.Count | Should Be 2
            $clicks[0] | Should Be 'Click:10:0.714,0.116:False:카카오톡'
            $clicks[1] | Should Be 'Click:10:0.45,0.335:True:카카오톡'
            $paste = @($f.Calls | Where-Object { $_ -like 'Paste:*' })
            $paste.Count | Should Be 1
            $paste[0] | Should Be 'Paste:10:테스트방:카카오톡'
            $iPaste = $f.Calls.IndexOf($paste[0])
            $iCheck = $f.Calls.IndexOf('ResultCheck:10:테스트방')
            $iDouble = $f.Calls.IndexOf($clicks[1])
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
            @($f.Calls | Where-Object { $_ -like 'Click:*' }).Count | Should Be 2
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

Describe 'Room: 소스 규칙' {
    It 'Room.ps1 sends only Ctrl+V as a key, closes windows only through Close-KakaoWindow, and does not call Win32 directly' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Room.ps1') -Raw -Encoding UTF8
        $keys = @([regex]::Matches($src, "-Keys '([^']*)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $keys.Count | Should Be 1
        $keys[0] | Should Be 'Ctrl+V'
        $src | Should Not Match '\[KakaoWin32\]::'
        $src | Should Not Match 'PostClose|SendInput|mouse_event'
    }
}
