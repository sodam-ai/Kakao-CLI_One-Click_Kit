$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'Status', 'Room', 'Send')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 모드·시계·방 열기·입력·확인을 시험이 정하고, 호출을 모두 기록한다. 실제 카카오톡은 건드리지 않는다.
function New-FakeSendProvider {
    $s = @{
        Calls       = (New-Object System.Collections.ArrayList)
        Bodies      = (New-Object System.Collections.ArrayList)
        Ready       = $true
        Mode        = 'full'
        Now         = ([datetime]::SpecifyKind([datetime]'2026-11-13T09:00:00', [System.DateTimeKind]::Utc))
        OpenedByKit = $true
        OpenThrows  = $null
        FocusThrows = $false
        PasteThrows = $false
        CloseThrows = $false
        VerifyThrows = $false
        Verify      = $null
    }
    $s.Provider = @{
        Ready      = { [void]$s.Calls.Add('Ready'); $s.Ready }.GetNewClosure()
        Mode       = { [void]$s.Calls.Add('Mode'); $s.Mode }.GetNewClosure()
        Now        = { $s.Now }.GetNewClosure()
        OpenRoom   = { param($name, $caller) [void]$s.Calls.Add(('Open:{0}:{1}' -f $name, $caller)); if ($s.OpenThrows) { throw $s.OpenThrows }; [pscustomobject]@{ Hwnd = 20; Title = $name; OpenedByKit = $s.OpenedByKit } }.GetNewClosure()
        FocusInput = { param($hwnd, $title) [void]$s.Calls.Add(('Focus:{0}:{1}' -f $hwnd, $title)); if ($s.FocusThrows) { throw 'focus stopped' } }.GetNewClosure()
        PasteEnter = { param($hwnd, $text, $title) [void]$s.Bodies.Add($text); [void]$s.Calls.Add(('PasteEnter:{0}:{1}' -f $hwnd, $title)); if ($s.PasteThrows) { throw 'paste interrupted' } }.GetNewClosure()
        VerifySent = { param($room, $text, $attemptId) [void]$s.Calls.Add('Verify'); if ($s.VerifyThrows) { throw 'verify broke' }; $s.Verify }.GetNewClosure()
        CloseRoom  = { param($opened) [void]$s.Calls.Add(('Close:{0}' -f $opened.Hwnd)); if ($s.CloseThrows) { throw 'close failed' } }.GetNewClosure()
    }
    return $s
}

function Set-TestRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-TestRoom([string]$Name, [bool]$AiSend = $false, [bool]$Verified = $true, [bool]$CanSend = $true) {
    [pscustomobject]@{ name = $Name; type = 'open'; verified = $Verified; canRead = $true; canSend = $CanSend; selfOnly = $true; aiRead = $false; aiSend = $AiSend }
}
# 방을 열거나 키를 누르는 "입력이 나가는" 호출만 센다(Ready·Mode·Verify 는 읽기라 세지 않는다).
function Get-SendInputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Open:*' -or $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' -or $_ -like 'Close:*' }) }
function Get-StateFilePath { return [System.IO.Path]::Combine((Get-KitPaths).DataDir, 'state', 'send-state.json') }

Describe 'Send: 입력 전에 거절하는 것들 (입력 호출 0)' {
    It 'rejects an empty, blank or missing text with exit 1' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($bad in @($null, '', ' ', "`r`n", "  `t ")) {
                $f = New-FakeSendProvider
                $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text $bad -Yes -Provider $f.Provider }
                $e.GetType().Name | Should Be 'KakaoKitException'
                $e.ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'accepts exactly 1000 characters and rejects 1001 (dry run, so nothing is recorded)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            (Send-KakaoMessage -Room '테스트방' -Text ('가' * 1000) -DryRun -Provider $f.Provider).Status | Should Be 'preview'
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text ('가' * 1001) -DryRun -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'rejects hidden control characters (NUL, ESC, DEL) but allows tab, line breaks and ordinary symbols' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            foreach ($code in 0x00, 0x01, 0x08, 0x0B, 0x0C, 0x1B, 0x7F) {
                $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text ('a' + [char]$code + 'b') -DryRun -Provider $f.Provider }
                $e.ExitCode | Should Be 1
            }
            foreach ($ok in "a`tb", "a`nb", "a`r`nb", 'a"b&c|d^e%f!g', '😀 이모지') {
                (Send-KakaoMessage -Room '테스트방' -Text $ok -DryRun -Provider $f.Provider).Status | Should Be 'preview'
            }
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'rejects a room that is not on the allowed list, or cannot send, or is an unverified type (friend room), with exit 1' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'), (New-TestRoom '읽기전용' -CanSend $false), (New-TestRoom '친구방' -Verified $false))
            foreach ($name in '없는방', '테스트방 ', '읽기전용', '친구방', '') {
                $f = New-FakeSendProvider
                $e = Get-ThrownError { Send-KakaoMessage -Room $name -Text 'hi' -Yes -Provider $f.Provider }
                $e.ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'an AI caller needs the per-room AI-send switch; a person does not' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '꺼짐'), (New-TestRoom '켜짐' -AiSend $true))
            $f = New-FakeSendProvider
            (Get-ThrownError { Send-KakaoMessage -Room '꺼짐' -Text 'hi' -Yes -Caller 'ai' -Provider $f.Provider }).ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
            (Send-KakaoMessage -Room '켜짐' -Text 'hi' -Yes -Caller 'ai' -Provider $f.Provider).Sent | Should Be $true
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddSeconds(10)
            (Send-KakaoMessage -Room '꺼짐' -Text 'hi' -Yes -Caller 'human' -Provider $f2.Provider).Sent | Should Be $true
        }
    }

    It 'stops with exit 3 and makes no input call while sending is not connected (input box position not measured)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.Ready = $false
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'the real provider is not ready: a real call stops with exit 3 before any input (this must change only together with a measured input-box position)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes }
            $e.GetType().Name | Should Be 'KakaoKitException'
            $e.ExitCode | Should Be 3
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $false
        }
    }

    It 'stops with exit 4 in readonly mode, even for a dry run; only a person can lift it' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'), (New-TestRoom 'AI방' -AiSend $true))
            $f = New-FakeSendProvider
            $f.Mode = 'readonly'
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -DryRun -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AllowUnverified -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-SendInputCalls $f).Count | Should Be 0
            (Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -AllowUnverified -Provider $f.Provider).Sent | Should Be $true
        }
    }

    It 'a real send without the confirmation switch is refused with exit 1 and no input' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'a dry run only previews: no input call, nothing recorded, no confirmation needed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $r = Send-KakaoMessage -Room '테스트방' -Text 'hello' -DryRun -Provider $f.Provider
            $r.Status | Should Be 'preview'
            $r.Sent | Should Be $false
            $r.Room | Should Be '테스트방'
            (Get-SendInputCalls $f).Count | Should Be 0
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $false
        }
    }

    It 'refuses a window that was already open (not opened by the kit): no focus, no paste, and it is not closed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.OpenedByKit = $false
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' -or $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'rejects an attempt number with odd characters or more than 64 characters (exit 1, no input)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($bad in 'a b', 'a/b', "a`nb", ('x' * 65), 'a"b') {
                $f = New-FakeSendProvider
                (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -AttemptId $bad -Provider $f.Provider }).ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }
}

Describe 'Send: 2초 간격과 시도 번호 (프로세스가 달라도 지켜진다)' {
    It 'refuses a second send within 2 seconds, even from a fresh provider (state is stored in the data folder), and allows it after 2 seconds' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            (Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider).Sent | Should Be $true
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddMilliseconds(1999)
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'two' -Yes -Provider $f2.Provider }
            $e.ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
            $f3 = New-FakeSendProvider
            $f3.Now = $f1.Now.AddSeconds(2)
            (Send-KakaoMessage -Room '테스트방' -Text 'three' -Yes -Provider $f3.Provider).Sent | Should Be $true
        }
    }

    It 'treats a clock that moved backwards as too soon (fail closed)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            [void](Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider)
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddHours(-1)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'two' -Yes -Provider $f2.Provider }).ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
        }
    }

    It 'refuses the same attempt number a second time (no duplicate send), but a different number is fine' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            $r = Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0001' -Provider $f1.Provider
            $r.AttemptId | Should Be 'try-0001'
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddSeconds(10)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0001' -Provider $f2.Provider }).ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
            (Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0002' -Provider $f2.Provider).Sent | Should Be $true
        }
    }

    It 'makes a new attempt number by itself when none is given, and every number is different' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            $a = (Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider).AttemptId
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddSeconds(5)
            $b = (Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Provider $f2.Provider).AttemptId
            $a | Should Match '^[A-Za-z0-9_-]{1,64}$'
            $b | Should Match '^[A-Za-z0-9_-]{1,64}$'
            $a | Should Not Be $b
        }
    }

    It 'refuses (fail closed, exit 2) when the record file is damaged, and the record is made before any input' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $path = Get-StateFilePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [System.IO.File]::WriteAllText($path, '{ this is not json', (New-Object System.Text.UTF8Encoding($false)))
            $f = New-FakeSendProvider
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'refuses (fail closed) when the record file has the wrong shape, for example an array or a wrong date' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $path = Get-StateFilePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            foreach ($bad in '[]', '{"lastAttemptUtc":"not a date","attempts":[]}', '{"lastAttemptUtc":null,"attempts":"x"}', '42') {
                [System.IO.File]::WriteAllText($path, $bad, (New-Object System.Text.UTF8Encoding($false)))
                $f = New-FakeSendProvider
                (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'the record is written before the room is opened (a crash after the input still blocks a repeat)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.OpenThrows = 'window stopped'
            [void](Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -AttemptId 'crash-1' -Provider $f.Provider })
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $true
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddSeconds(10)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -AttemptId 'crash-1' -Provider $f2.Provider }).ExitCode | Should Be 2
        }
    }

    It 'keeps only the most recent attempt numbers so the record file does not grow forever' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            for ($i = 0; $i -lt 130; $i++) {
                $f.Now = $f.Now.AddSeconds(5)
                [void](Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -AttemptId ('n' + $i) -Provider $f.Provider)
            }
            $state = [System.IO.File]::ReadAllText((Get-StateFilePath), (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
            @($state.attempts).Count | Should Be 100
            @($state.attempts | Where-Object { $_.id -eq 'n129' }).Count | Should Be 1
            @($state.attempts | Where-Object { $_.id -eq 'n0' }).Count | Should Be 0
        }
    }
}

Describe 'Send: 결과는 확인됨·불명 둘 중 하나이고 자동 재시도는 없다' {
    It 'is confirmed only when the check finds the sent text; the text is pasted exactly once' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.Verify = $true
            $r = Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
            $r.Status | Should Be 'confirmed'
            $r.Sent | Should Be $true
            @($f.Calls | Where-Object { $_ -like 'PasteEnter:*' }).Count | Should Be 1
        }
    }

    It 'is unknown when the check finds nothing, cannot run, or throws; the input is still sent exactly once (no retry)' {
        foreach ($case in @(@{ V = $null; T = $false }, @{ V = $false; T = $false }, @{ V = $null; T = $true })) {
            Use-TempHome {
                Set-TestRooms @((New-TestRoom '테스트방'))
                $f = New-FakeSendProvider
                $f.Verify = $case.V
                $f.VerifyThrows = $case.T
                $r = Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
                $r.Status | Should Be 'unknown'
                $r.Sent | Should Be $true
                $r.Message | Should Match '확인하지 못했습니다'
                @($f.Calls | Where-Object { $_ -like 'PasteEnter:*' }).Count | Should Be 1
            }
        }
    }

    It 'a truthy value that is not exactly one real true (the number 1, the text "true", two results) does not count as confirmed' {
        foreach ($v in @(1, 'true', 'yes', @($true, $true))) {
            Use-TempHome {
                Set-TestRooms @((New-TestRoom '테스트방'))
                $f = New-FakeSendProvider
                $f.Verify = $v
                (Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider).Status | Should Be 'unknown'
            }
        }
    }

    It 'is unknown (not an error, not retried) when the input is interrupted after it started' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.PasteThrows = $true
            $r = Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
            $r.Status | Should Be 'unknown'
            $r.Sent | Should Be $true
            @($f.Calls | Where-Object { $_ -like 'PasteEnter:*' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -eq 'Verify' }).Count | Should Be 0
        }
    }

    It 'a stop before any key (the input box could not be focused) is an error with no paste, and the kit-opened window is closed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.FocusThrows = $true
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e | Should Not BeNullOrEmpty
            @($f.Calls | Where-Object { $_ -like 'PasteEnter:*' }).Count | Should Be 0
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
        }
    }

    It 'a stop while opening the room is an error with no focus and no paste' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.OpenThrows = (New-KitError -Key 'room.openTimeout' -FormatArgs @('테스트방') -ExitCode 3)
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            @($f.Calls | Where-Object { $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' -or $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'closes the window the kit opened after sending, and a failure to close does not change the result (it becomes a warning)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            Clear-KitWarnings
            $f = New-FakeSendProvider
            $f.CloseThrows = $true
            $r = Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
            $r.Status | Should Be 'unknown'
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            @(Get-KitWarnings).Count | Should Be 1
            Clear-KitWarnings
        }
    }
}

Describe 'Send: 본문은 변형 없이 붙여넣기까지 전달된다' {
    It 'passes quotes, & | ^ % !, emoji, tabs and multiple lines through letter for letter' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.Now = $f.Now.AddSeconds(-100)
            $bodies = @('"a&b|c^d%e!"', '😀 한글 + emoji', "line1`r`nline2`nline3`tTab", '  앞뒤 공백  ', '`$(Get-Date) ; calc.exe', '%PATH% ^& echo hi')
            foreach ($body in $bodies) {
                $f.Now = $f.Now.AddSeconds(10)
                [void](Send-KakaoMessage -Room '테스트방' -Text $body -Yes -Provider $f.Provider)
            }
            $f.Bodies.Count | Should Be $bodies.Count
            for ($i = 0; $i -lt $bodies.Count; $i++) { ($f.Bodies[$i] -ceq $bodies[$i]) | Should Be $true }
        }
    }
}

Describe 'Send: 붙여넣기 뒤에 기다린 다음 클립보드를 복원한다 (R-04)' {
    It 'real provider: sets the text, presses Ctrl+V then Enter, waits, and only then lets the clipboard be restored' {
        $script:ev = New-Object System.Collections.ArrayList
        function Use-TextClipboard { param([string]$Text, [scriptblock]$Action) [void]$script:ev.Add('set:' + $Text); & $Action; [void]$script:ev.Add('restore') }
        function Send-KeyCombo { param([long]$Hwnd, [string]$Keys, [string]$ExpectedTitle) [void]$script:ev.Add('key:' + $Keys + ':' + $ExpectedTitle) }
        function Start-Sleep { param([int]$Milliseconds) [void]$script:ev.Add('sleep') }
        $p = Get-DefaultSendProvider
        & $p.PasteEnter 20 'a&b|c^d%e!' '테스트방'
        ($script:ev -join ',') | Should Be 'set:a&b|c^d%e!,key:Ctrl+V:테스트방,key:Enter:테스트방,sleep,restore'
    }
}

Describe 'Send: 기록에 본문이 남지 않는다' {
    It 'neither the log nor the record file contains the text of the message' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.Verify = $true
            [void](Send-KakaoMessage -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f.Provider)
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddSeconds(10)
            $f2.PasteThrows = $true
            [void](Send-KakaoMessage -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f2.Provider)
            $f3 = New-FakeSendProvider
            $f3.Now = $f.Now.AddSeconds(20)
            $f3.OpenThrows = 'stopped ZZZ-BODY-7731'
            [void](Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f3.Provider })
            $dir = (Get-KitPaths).DataDir
            $texts = @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, (New-Object System.Text.UTF8Encoding($false))) })
            $texts.Count | Should BeGreaterThan 1
            foreach ($t in $texts) { $t | Should Not Match 'ZZZ-BODY-7731' }
            @(Get-ChildItem -LiteralPath (Get-KitPaths).LogsDir -File).Count | Should BeGreaterThan 0
        }
    }
}

Describe 'Send: 소스 규칙 (키·클릭·창 닫기)' {
    BeforeAll { $script:sendText = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'Send.ps1')) }

    It 'sends only Ctrl+V and Enter, and never Esc, Alt, Delete, Ctrl+A or any other key' {
        $keys = @([regex]::Matches($script:sendText, "-Keys\s+'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        ($keys -join ',') | Should Be 'Ctrl+V,Enter'
        $script:sendText | Should Not Match '(?i)Esc|Alt\+|Delete|Ctrl\+A|VK_|0x1B'
    }

    It 'does not click anywhere yet (the input box position has not been measured)' {
        $script:sendText | Should Not Match 'Invoke-RelClick|ClickAt|SendInput|mouse_event'
    }

    It 'does not use .GetNewClosure() (a closed block cannot see script-scope functions in a real run; found in S5)' {
        $script:sendText | Should Not Match 'GetNewClosure'
    }

    It 'has no parameter that takes the message body into the log (the log call has no text)' {
        $script:sendText | Should Not Match 'Write-KitLog[^\r\n]*\$Text'
    }
}
