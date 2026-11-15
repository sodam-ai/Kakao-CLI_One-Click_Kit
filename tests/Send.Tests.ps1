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
        PreKeyThrows = $null
        LockHeld    = $true
        CloseThrows = $false
        VerifyThrows = $false
        Verify      = $null
        EmptyAnswer = $true
        EmptyThrows = $false
        InputState  = 'unknown'
        InputThrows = $false
    }
    $s.Provider = @{
        Ready      = { [void]$s.Calls.Add('Ready'); $s.Ready }.GetNewClosure()
        Mode       = { [void]$s.Calls.Add('Mode'); $s.Mode }.GetNewClosure()
        Now        = { $s.Now }.GetNewClosure()
        OpenRoom   = { param($name, $caller) [void]$s.Calls.Add(('Open:{0}:{1}' -f $name, $caller)); if ($s.OpenThrows) { throw $s.OpenThrows }; [pscustomobject]@{ Hwnd = 20; Title = $name; OpenedByKit = $s.OpenedByKit } }.GetNewClosure()
        # 사람이 입력란이 비었다고 답하는 자리. 답은 시험이 정한다(EmptyAnswer). 던지게도 할 수 있다(EmptyThrows).
        ConfirmInputEmpty = { param($title) [void]$s.Calls.Add(('Confirm:{0}' -f $title)); if ($s.EmptyThrows) { throw 'confirm stopped' }; $s.EmptyAnswer }.GetNewClosure()
        WaitIdle   = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        # 입력란을 읽기만 해서 empty / draft / unknown 을 돌려주는 자리. 던지게도 할 수 있다(InputThrows).
        ReadInputState = { param($hwnd, $title) [void]$s.Calls.Add('ReadInput'); if ($s.InputThrows) { throw 'read failed' }; $s.InputState }.GetNewClosure()
        FocusInput = { param($hwnd, $title) [void]$s.Calls.Add(('Focus:{0}:{1}' -f $hwnd, $title)); if ($s.FocusThrows) { throw 'focus stopped' } }.GetNewClosure()
        LockHeld   = { [void]$s.Calls.Add('LockHeld'); $s.LockHeld }.GetNewClosure()
        # 키가 나가기 전에 멈추면 KeysSent 를 켜지 않고 던진다. 키가 나간 뒤 멈추면 KeysSent 를 켜고 던진다.
        PasteEnter = { param($hwnd, $text, $title, $progress) [void]$s.Bodies.Add($text); [void]$s.Calls.Add(('PasteEnter:{0}:{1}' -f $hwnd, $title)); if ($s.PreKeyThrows) { throw $s.PreKeyThrows }; $progress.KeysSent = $true; if ($s.PasteThrows) { throw 'paste interrupted' } }.GetNewClosure()
        VerifySent = { param($room, $text, $attemptId) [void]$s.Calls.Add('Verify'); if ($s.VerifyThrows) { throw 'verify broke' }; $s.Verify }.GetNewClosure()
        CloseRoom  = { param($opened) [void]$s.Calls.Add(('Close:{0}' -f $opened.Hwnd)); if ($s.CloseThrows) { throw 'close failed' } }.GetNewClosure()
    }
    return $s
}

function Set-TestRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
# NoDraft 기본값이 참인 것은 기존 시험이 "초안 없음 표시가 된 방"에서 원래 뜻대로 돌게 하려는 것이다. 새 시험은 -NoDraft $false 를 직접 쓴다.
function New-TestRoom([string]$Name, [bool]$AiSend = $false, [bool]$Verified = $true, [bool]$CanSend = $true, [bool]$NoDraft = $true) {
    [pscustomobject]@{ name = $Name; type = 'open'; verified = $Verified; canRead = $true; canSend = $CanSend; selfOnly = $true; aiRead = $false; aiSend = $AiSend; noDraft = $NoDraft }
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
                $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text $bad -Yes -Provider $f.Provider }
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
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text ('가' * 1000) -DryRun -Provider $f.Provider).Status | Should Be 'preview'
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text ('가' * 1001) -DryRun -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'rejects hidden control characters (NUL, ESC, DEL) but allows tab, line breaks and ordinary symbols' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            foreach ($code in 0x00, 0x01, 0x08, 0x0B, 0x0C, 0x1B, 0x7F) {
                $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text ('a' + [char]$code + 'b') -DryRun -Provider $f.Provider }
                $e.ExitCode | Should Be 1
            }
            foreach ($ok in "a`tb", "a`nb", "a`r`nb", 'a"b&c|d^e%f!g', '😀 이모지') {
                (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text $ok -DryRun -Provider $f.Provider).Status | Should Be 'preview'
            }
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'rejects a room that is not on the allowed list, or cannot send, or is an unverified type (friend room), with exit 1' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'), (New-TestRoom '읽기전용' -CanSend $false), (New-TestRoom '친구방' -Verified $false))
            foreach ($name in '없는방', '테스트방 ', '읽기전용', '친구방', '') {
                $f = New-FakeSendProvider
                $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room $name -Text 'hi' -Yes -Provider $f.Provider }
                $e.ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'an AI caller needs the per-room AI-send switch; a person does not' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '꺼짐'), (New-TestRoom '켜짐' -AiSend $true))
            $f = New-FakeSendProvider
            (Get-ThrownError { Send-KakaoMessage -Room '꺼짐' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0001' -Provider $f.Provider }).ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
            (Send-KakaoMessage -Room '켜짐' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0002' -Provider $f.Provider).Sent | Should Be $true
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
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'the real provider is not ready: a real call stops with exit 3 before any input (this must change only together with a measured input-box position)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes }
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
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -DryRun -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AllowUnverified -Provider $f.Provider }).ExitCode | Should Be 4
            (Get-SendInputCalls $f).Count | Should Be 0
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -AllowUnverified -Provider $f.Provider).Sent | Should Be $true
        }
    }

    It 'a real send without the confirmation switch is refused with exit 1 and no input' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'a dry run only previews: no input call, nothing recorded, no confirmation needed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hello' -DryRun -Provider $f.Provider
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
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' -or $_ -like 'Close:*' }).Count | Should Be 0
        }
    }

    It 'rejects an attempt number with odd characters or more than 64 characters (exit 1, no input)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($bad in 'a b', 'a/b', "a`nb", "abc`n", "abc`r`n", ('x' * 65), 'a"b') {
                $f = New-FakeSendProvider
                (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -AttemptId $bad -Provider $f.Provider }).ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }
}

Describe 'Send: 검토에서 나온 빈틈 (호출자 구분·AI 시도 번호·실행 잠금·키 전 실패)' {
    It 'refuses a call that does not say exactly human or ai (a forgotten -Caller must not gain a person''s rights)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            foreach ($bad in @($null, '', 'HUMAN', 'Human', 'ai ', 'robot')) {
                $f = New-FakeSendProvider
                $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Caller $bad -Provider $f.Provider }
                $e.ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'an AI caller must give an attempt number for a real send (a re-run without one could send twice), but a dry run needs none' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom 'AI방' -AiSend $true))
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -Provider $f.Provider }
            $e.ExitCode | Should Be 1
            $e.Message | Should Match '시도 번호'
            (Get-SendInputCalls $f).Count | Should Be 0
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $false
            (Send-KakaoMessage -Room 'AI방' -Text 'hi' -DryRun -Caller 'ai' -Provider $f.Provider).Status | Should Be 'preview'
        }
    }

    It 'refuses a real send when this process does not hold the run lock, with exit 2 and no record and no input; a dry run does not need the lock' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.LockHeld = $false
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Caller 'human' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match '실행 잠금'
            (Get-SendInputCalls $f).Count | Should Be 0
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $false
            (Send-KakaoMessage -Room '테스트방' -Text 'hi' -DryRun -Caller 'human' -Provider $f.Provider).Status | Should Be 'preview'
        }
    }

    It 'a stop before the first key (for example the clipboard holds an image, or the guard refuses Ctrl+V) is a failure, not unknown, and the window is still closed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.PreKeyThrows = (New-KitError -Key 'room.openTimeout' -FormatArgs @('테스트방') -ExitCode 3)
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Caller 'human' -Provider $f.Provider }
            $e.ExitCode | Should Be 3
            @($f.Calls | Where-Object { $_ -like 'PasteEnter:*' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -eq 'Verify' }).Count | Should Be 0
        }
    }

    It 'rejects text made only of invisible characters, control characters from other ranges, and text-direction overrides, but allows emoji joiners' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            foreach ($bad in @(([string][char]0x200B), (([string][char]0x200B) * 5), "$([char]0xFEFF) $([char]0x2060)", "a$([char]0x0085)b", "a$([char]0x202E)b", "a$([char]0x2028)b", "a$([char]0x2029)b", "a$([char]0x2066)b", "a$([char]0x009F)b")) {
                (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text $bad -DryRun -Caller 'human' -Provider $f.Provider }).ExitCode | Should Be 1
            }
            $family = [string]::Concat([char]::ConvertFromUtf32(0x1F468), [char]0x200D, [char]::ConvertFromUtf32(0x1F469), [char]0x200D, [char]::ConvertFromUtf32(0x1F467))
            (Send-KakaoMessage -Room '테스트방' -Text $family -DryRun -Caller 'human' -Provider $f.Provider).Status | Should Be 'preview'
        }
    }

    It 'rejects a lone surrogate (broken UTF-16 would reach the clipboard damaged) but accepts a proper emoji pair' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $pair = [char]::ConvertFromUtf32(0x1F600)
            foreach ($bad in @("a$([char]0xD800)b", "a$([char]0xDC00)b", ([string][char]0xD83D), ([string][char]0xDE00), ($pair + [char]0xD800), ([char]0xDC00 + $pair), ($pair.Substring(1) + $pair.Substring(0, 1)))) {
                (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text $bad -DryRun -Caller 'human' -Provider $f.Provider }).ExitCode | Should Be 1
            }
            foreach ($ok in @($pair, "a${pair}b", ($pair + $pair))) {
                (Send-KakaoMessage -Room '테스트방' -Text $ok -DryRun -Caller 'human' -Provider $f.Provider).Status | Should Be 'preview'
            }
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'the reason for each exit-2 stop is the right one (the tests do not only look at the code)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            [void](Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Caller 'human' -AttemptId 'r-1' -Provider $f1.Provider)
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddMilliseconds(500)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -Caller 'human' -Provider $f2.Provider }).Message | Should Match '2초가 지나지 않았습니다'
            $f2.Now = $f1.Now.AddHours(-1)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -Caller 'human' -Provider $f2.Provider }).Message | Should Match '2초가 지나지 않았습니다'
            $f2.Now = $f1.Now.AddSeconds(10)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -Caller 'human' -AttemptId 'r-1' -Provider $f2.Provider }).Message | Should Match '같은 시도 번호'
            $f2.OpenedByKit = $false
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -Caller 'human' -AttemptId 'r-2' -Provider $f2.Provider }).Message | Should Match '이미 열려 있는 방'
            $path = Get-StateFilePath
            [System.IO.File]::WriteAllText($path, '{ broken', (New-Object System.Text.UTF8Encoding($false)))
            $f3 = New-FakeSendProvider
            $f3.Now = $f1.Now.AddSeconds(60)
            (Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'x' -Yes -Caller 'human' -Provider $f3.Provider }).Message | Should Match '기록을 읽거나 쓸 수 없어'
        }
    }

    It 'a leftover temporary record without the main record (a stop while replacing) is treated as a lost record: refuse, name the temporary file' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $path = Get-StateFilePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            [System.IO.File]::WriteAllText(($path + '.tmp'), '{"lastAttemptUtc":null,"attempts":[]}', (New-Object System.Text.UTF8Encoding($false)))
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Room '테스트방' -Text 'hi' -Yes -Caller 'human' -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            $e.Message | Should Match 'send-state\.json\.tmp'
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'replaces the record in place when it already exists, and leaves no temporary file behind' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            [void](Send-KakaoMessage -Room '테스트방' -Text 'one' -Yes -Caller 'human' -AttemptId 'p-1' -Provider $f.Provider)
            $f.Now = $f.Now.AddSeconds(10)
            [void](Send-KakaoMessage -Room '테스트방' -Text 'two' -Yes -Caller 'human' -AttemptId 'p-2' -Provider $f.Provider)
            (Test-Path -LiteralPath ((Get-StateFilePath) + '.tmp')) | Should Be $false
            $state = [System.IO.File]::ReadAllText((Get-StateFilePath), (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
            (@($state.attempts | ForEach-Object { $_.id }) -join ',') | Should Be 'p-1,p-2'
        }
    }
}

Describe 'Send: 2초 간격과 시도 번호 (프로세스가 달라도 지켜진다)' {
    It 'refuses a second send within 2 seconds, even from a fresh provider (state is stored in the data folder), and allows it after 2 seconds' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider).Sent | Should Be $true
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddMilliseconds(1999)
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'two' -Yes -Provider $f2.Provider }
            $e.ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
            $f3 = New-FakeSendProvider
            $f3.Now = $f1.Now.AddSeconds(2)
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'three' -Yes -Provider $f3.Provider).Sent | Should Be $true
        }
    }

    It 'treats a clock that moved backwards as too soon (fail closed)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            [void](Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider)
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddHours(-1)
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'two' -Yes -Provider $f2.Provider }).ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
        }
    }

    It 'refuses the same attempt number a second time (no duplicate send), but a different number is fine' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0001' -Provider $f1.Provider
            $r.AttemptId | Should Be 'try-0001'
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddSeconds(10)
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0001' -Provider $f2.Provider }).ExitCode | Should Be 2
            (Get-SendInputCalls $f2).Count | Should Be 0
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -AttemptId 'try-0002' -Provider $f2.Provider).Sent | Should Be $true
        }
    }

    It 'makes a new attempt number by itself when none is given, and every number is different' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f1 = New-FakeSendProvider
            $a = (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -Provider $f1.Provider).AttemptId
            $f2 = New-FakeSendProvider
            $f2.Now = $f1.Now.AddSeconds(5)
            $b = (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'one' -Yes -Provider $f2.Provider).AttemptId
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
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
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
                (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
                (Get-SendInputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'the record is written before the room is opened (a crash after the input still blocks a repeat)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.OpenThrows = 'window stopped'
            [void](Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -AttemptId 'crash-1' -Provider $f.Provider })
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $true
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddSeconds(10)
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -AttemptId 'crash-1' -Provider $f2.Provider }).ExitCode | Should Be 2
        }
    }

    It 'keeps only the most recent attempt numbers so the record file does not grow forever' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            for ($i = 0; $i -lt 130; $i++) {
                $f.Now = $f.Now.AddSeconds(5)
                [void](Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'x' -Yes -AttemptId ('n' + $i) -Provider $f.Provider)
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
            $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
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
                $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
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
                (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider).Status | Should Be 'unknown'
            }
        }
    }

    It 'is unknown (not an error, not retried) when the input is interrupted after it started' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.PasteThrows = $true
            $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
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
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
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
            $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
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
            $r = Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider
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
                [void](Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text $body -Yes -Provider $f.Provider)
            }
            $f.Bodies.Count | Should Be $bodies.Count
            for ($i = 0; $i -lt $bodies.Count; $i++) { ($f.Bodies[$i] -ceq $bodies[$i]) | Should Be $true }
        }
    }
}

Describe 'Send: 붙여넣기 뒤에 기다린 다음 클립보드를 복원한다 (R-04)' {
    It 'real provider: sets the text, presses Ctrl+V then Enter, waits, and only then lets the clipboard be restored' {
        $script:ev = New-Object System.Collections.ArrayList
        # 진짜 Use-TextClipboard 처럼 오류가 나도 복원은 반드시 한다(finally).
        function Use-TextClipboard { param([string]$Text, [scriptblock]$Action) [void]$script:ev.Add('set:' + $Text); try { & $Action } finally { [void]$script:ev.Add('restore') } }
        function Send-KeyCombo { param([long]$Hwnd, [string]$Keys, [string]$ExpectedTitle) [void]$script:ev.Add('key:' + $Keys + ':' + $ExpectedTitle) }
        function Start-Sleep { param([int]$Milliseconds) [void]$script:ev.Add('sleep:' + $Milliseconds) }
        $p = Get-DefaultSendProvider
        $progress = @{ KeysSent = $false }
        & $p.PasteEnter 20 'a&b|c^d%e!' '테스트방' $progress
        ($script:ev -join ',') | Should Be 'set:a&b|c^d%e!,key:Ctrl+V:테스트방,key:Enter:테스트방,sleep:800,restore'
        $progress.KeysSent | Should Be $true
    }

    It 'real provider: still waits before restoring when Enter fails after Ctrl+V went out, and says keys were sent' {
        $script:ev = New-Object System.Collections.ArrayList
        function Use-TextClipboard { param([string]$Text, [scriptblock]$Action) [void]$script:ev.Add('set:' + $Text); try { & $Action } finally { [void]$script:ev.Add('restore') } }
        function Send-KeyCombo { param([long]$Hwnd, [string]$Keys, [string]$ExpectedTitle) [void]$script:ev.Add('key:' + $Keys); if ($Keys -eq 'Enter') { throw 'enter refused' } }
        function Start-Sleep { param([int]$Milliseconds) [void]$script:ev.Add('sleep:' + $Milliseconds) }
        $p = Get-DefaultSendProvider
        $progress = @{ KeysSent = $false }
        { & $p.PasteEnter 20 'hello' '테스트방' $progress } | Should Throw 'enter refused'
        ($script:ev -join ',') | Should Be 'set:hello,key:Ctrl+V,key:Enter,sleep:800,restore'
        $progress.KeysSent | Should Be $true
    }

    It 'real provider: when Ctrl+V itself is refused, no key went out, so the progress flag stays off (a failure, not unknown) and the clipboard is restored without waiting' {
        $script:ev = New-Object System.Collections.ArrayList
        function Use-TextClipboard { param([string]$Text, [scriptblock]$Action) [void]$script:ev.Add('set:' + $Text); try { & $Action } finally { [void]$script:ev.Add('restore') } }
        function Send-KeyCombo { param([long]$Hwnd, [string]$Keys, [string]$ExpectedTitle) [void]$script:ev.Add('key:' + $Keys); throw 'guard refused' }
        function Start-Sleep { param([int]$Milliseconds) [void]$script:ev.Add('sleep:' + $Milliseconds) }
        $p = Get-DefaultSendProvider
        $progress = @{ KeysSent = $false }
        { & $p.PasteEnter 20 'hello' '테스트방' $progress } | Should Throw 'guard refused'
        ($script:ev -join ',') | Should Be 'set:hello,key:Ctrl+V,restore'
        $progress.KeysSent | Should Be $false
    }
}

Describe 'Send: 기록에 본문이 남지 않는다' {
    It 'neither the log nor the record file contains the text of the message' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방'))
            $f = New-FakeSendProvider
            $f.Verify = $true
            [void](Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f.Provider)
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddSeconds(10)
            $f2.PasteThrows = $true
            [void](Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f2.Provider)
            $f3 = New-FakeSendProvider
            $f3.Now = $f.Now.AddSeconds(20)
            $f3.OpenThrows = 'stopped ZZZ-BODY-7731'
            [void](Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'ZZZ-BODY-7731' -Yes -Provider $f3.Provider })
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


Describe 'Send: 입력란이 비었다는 확인 (4번 시험: 닫았다 열어도 초안이 남는다)' {
    It 'an AI caller is refused (exit 1, no input, nothing recorded) in a room the person has not marked as draft-free' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom 'AI방' -AiSend $true -NoDraft $false))
            $f = New-FakeSendProvider
            $e = Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0100' -Provider $f.Provider }
            $e.GetType().Name | Should Be 'KakaoKitException'
            $e.ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
            (Test-Path -LiteralPath (Get-StateFilePath)) | Should Be $false
        }
    }

    It 'the dry run of an AI caller is refused too, so a preview never promises what a real send would refuse' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom 'AI방' -AiSend $true -NoDraft $false))
            $f = New-FakeSendProvider
            (Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -DryRun -Caller 'ai' -AttemptId 'ai-0101' -Provider $f.Provider }).ExitCode | Should Be 1
            (Get-SendInputCalls $f).Count | Should Be 0
        }
    }

    It 'an AI caller sends in a draft-free room and nobody is asked' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom 'AI방' -AiSend $true -NoDraft $true))
            $f = New-FakeSendProvider
            (Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0102' -Provider $f.Provider).Sent | Should Be $true
            @($f.Calls | Where-Object { $_ -like 'Confirm:*' }).Count | Should Be 0
        }
    }

    It 'only a real JSON true counts as draft-free ("true", 1 and missing do not)' {
        Use-TempHome {
            foreach ($bad in '"true"', '1', '[true]', 'null') {
                $raw = '{"version":1,"rooms":[{"name":"AI방","type":"open","verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":true,"noDraft":' + $bad + '}]}'
                $p = Get-KitPaths
                New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
                [System.IO.File]::WriteAllText($p.ConfigFile, $raw, (New-Object System.Text.UTF8Encoding($false)))
                $f = New-FakeSendProvider
                (Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0103' -Provider $f.Provider }).ExitCode | Should Be 1
                (Get-SendInputCalls $f).Count | Should Be 0
            }
            # 항목이 아예 없는(예전에 만든) 방도 막힌다.
            $raw = '{"version":1,"rooms":[{"name":"AI방","type":"open","verified":true,"canRead":true,"canSend":true,"selfOnly":true,"aiRead":false,"aiSend":true}]}'
            [System.IO.File]::WriteAllText((Get-KitPaths).ConfigFile, $raw, (New-Object System.Text.UTF8Encoding($false)))
            $f = New-FakeSendProvider
            (Get-ThrownError { Send-KakaoMessage -Room 'AI방' -Text 'hi' -Yes -Caller 'ai' -AttemptId 'ai-0104' -Provider $f.Provider }).ExitCode | Should Be 1
        }
    }

    It 'a person is asked after the room is opened and before the input box is touched; "yes" goes on to send' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' -NoDraft $false))
            $f = New-FakeSendProvider
            (Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider).Sent | Should Be $true
            $order = @($f.Calls | Where-Object { $_ -like 'Open:*' -or $_ -like 'Confirm:*' -or $_ -eq 'WaitIdle' -or $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' })
            ($order -join '|') | Should Be 'Open:테스트방:human|Confirm:테스트방|WaitIdle|Focus:20:테스트방|PasteEnter:20:테스트방'
        }
    }

    It 'anything but a real true answer stops with exit 2: no focus, no keys, and the window the kit opened is closed' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' -NoDraft $false))
            $minutes = 0
            foreach ($answer in $false, $null, 'y', 'true', 1, @($true, $true)) {
                $f = New-FakeSendProvider
                $f.Now = $f.Now.AddMinutes($minutes); $minutes += 5
                $f.EmptyAnswer = $answer
                $e = Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }
                $e.GetType().Name | Should Be 'KakaoKitException'
                $e.ExitCode | Should Be 2
                @($f.Calls | Where-Object { $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' }).Count | Should Be 0
                @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            }
        }
    }

    It 'a question that fails (no keyboard, error) stops before any key, and the person is not treated as having said yes' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' -NoDraft $false))
            $f = New-FakeSendProvider
            $f.EmptyThrows = $true
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }) | Should Not BeNullOrEmpty
            @($f.Calls | Where-Object { $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' }).Count | Should Be 0
        }
    }

    It 'a window that was already open is still refused before anybody is asked' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '테스트방' -NoDraft $false))
            $f = New-FakeSendProvider
            $f.OpenedByKit = $false
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '테스트방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Confirm:*' }).Count | Should Be 0
        }
    }

    It 'the real provider asks a person, with a keyboard, and takes only y or Y as yes' {
        $p = Get-DefaultSendProvider
        $p.ContainsKey('ConfirmInputEmpty') | Should Be $true
        $p.ContainsKey('WaitIdle') | Should Be $true
        $p.ContainsKey('NoDraftRoom') | Should Be $false
    }
}

Describe 'Send: 입력란을 읽어서 초안이 보이면 멈춘다 (UI 자동화, 읽기만)' {
    It 'stops with exit 2 when the box holds a draft: nobody is asked, no focus, no keys, the window the kit opened is closed (person and AI alike)' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false), (New-TestRoom 'AI방' -AiSend $true -NoDraft $true))
            $minutes = 0
            foreach ($case in @(@('human', '사람방'), @('ai', 'AI방'))) {
                $f = New-FakeSendProvider
                $f.Now = $f.Now.AddMinutes($minutes); $minutes += 5
                $f.InputState = 'draft'
                $e = Get-ThrownError { Send-KakaoMessage -Caller $case[0] -Room $case[1] -Text 'hi' -Yes -AttemptId ('draft-' + $case[0]) -Provider $f.Provider }
                $e.GetType().Name | Should Be 'KakaoKitException'
                $e.ExitCode | Should Be 2
                @($f.Calls | Where-Object { $_ -like 'Confirm:*' -or $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' }).Count | Should Be 0
                @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            }
        }
    }

    It 'goes on when the box reads empty or cannot be read: a person is still asked, an AI still needs the draft-free mark' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false), (New-TestRoom 'AI방' -AiSend $true -NoDraft $true), (New-TestRoom '표시없음' -AiSend $true -NoDraft $false))
            $minutes = 0
            foreach ($state in 'empty', 'unknown') {
                $f = New-FakeSendProvider
                $f.Now = $f.Now.AddMinutes($minutes); $minutes += 5
                $f.InputState = $state
                (Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f.Provider).Sent | Should Be $true
                @($f.Calls | Where-Object { $_ -like 'Confirm:*' }).Count | Should Be 1
                $f2 = New-FakeSendProvider
                $f2.Now = $f.Now.AddMinutes(2)
                $f2.InputState = $state
                (Send-KakaoMessage -Caller 'ai' -Room 'AI방' -Text 'hi' -Yes -AttemptId ('ok-' + $state) -Provider $f2.Provider).Sent | Should Be $true
                $f3 = New-FakeSendProvider
                $f3.InputState = $state
                (Get-ThrownError { Send-KakaoMessage -Caller 'ai' -Room '표시없음' -Text 'hi' -Yes -AttemptId ('no-' + $state) -Provider $f3.Provider }).ExitCode | Should Be 1
                (Get-SendInputCalls $f3).Count | Should Be 0
            }
        }
    }

    It 'a failing or odd read is the same as unknown: it never stops a send by itself and never lets a draft-free check be skipped' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false))
            $f = New-FakeSendProvider
            $f.InputThrows = $true
            (Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f.Provider).Sent | Should Be $true
            @($f.Calls | Where-Object { $_ -like 'Confirm:*' }).Count | Should Be 1
            $f2 = New-FakeSendProvider
            $f2.Now = $f.Now.AddMinutes(5)
            $f2.InputState = $true
            (Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f2.Provider).Sent | Should Be $true
            @($f2.Calls | Where-Object { $_ -like 'Confirm:*' }).Count | Should Be 1
        }
    }

    It 'a draft is never missed because of stray output: if any returned value says draft, it stops' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false))
            $minutes = 0
            foreach ($odd in @(@('noise', 'draft'), @('draft', 'empty'), @('empty', 'draft', 'unknown'), @(1, 'draft'))) {
                $f = New-FakeSendProvider
                $f.Now = $f.Now.AddMinutes($minutes); $minutes += 5
                $f.InputState = $odd
                (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
                @($f.Calls | Where-Object { $_ -like 'Confirm:*' -or $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' }).Count | Should Be 0
            }
        }
    }

    It 'reads the box after the room is opened and before anybody is asked or any key is sent' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false))
            $f = New-FakeSendProvider
            $f.InputState = 'empty'
            (Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f.Provider).Sent | Should Be $true
            $order = @($f.Calls | Where-Object { $_ -like 'Open:*' -or $_ -eq 'ReadInput' -or $_ -like 'Confirm:*' -or $_ -like 'Focus:*' -or $_ -like 'PasteEnter:*' })
            ($order -join '|') | Should Be 'Open:사람방:human|ReadInput|Confirm:사람방|Focus:20:사람방|PasteEnter:20:사람방'
        }
    }

    It 'a window that was already open is still refused before the box is read' {
        Use-TempHome {
            Set-TestRooms @((New-TestRoom '사람방' -NoDraft $false))
            $f = New-FakeSendProvider
            $f.OpenedByKit = $false
            (Get-ThrownError { Send-KakaoMessage -Caller 'human' -Room '사람방' -Text 'hi' -Yes -Provider $f.Provider }).ExitCode | Should Be 2
            @($f.Calls | Where-Object { $_ -eq 'ReadInput' }).Count | Should Be 0
        }
    }

    It 'the real provider reads the box through the read-only helper' {
        $p = Get-DefaultSendProvider
        $p.ContainsKey('ReadInputState') | Should Be $true
        ($p.ReadInputState.ToString()).Contains('Get-KakaoInputState') | Should Be $true
    }
}

# ③: 클릭 없는 입력란 포커스 확인(Confirm-InputFocus)과 Ready 조건. 가짜 부품만 쓰고 카카오톡은 건드리지 않는다.
function New-FakeFocusProvider {
    $stopErr = New-KitError -Key 'guard.notForeground' -ExitCode 2
    $s = @{ Calls = (New-Object System.Collections.ArrayList); Ms = 0; Front = $true; WaitThrows = $false; RaiseThrows = $false; FocusOnPoll = 1; HasFocusThrows = $false; FocusValue = $true; Polls = 0 }
    $s.Provider = @{
        Raise          = { param($hwnd, $title) [void]$s.Calls.Add('Raise'); if ($s.RaiseThrows) { throw $stopErr }; $s.Front }.GetNewClosure()
        WaitForeground = { param($hwnd) [void]$s.Calls.Add('Wait'); if ($s.WaitThrows) { throw $stopErr } }.GetNewClosure()
        HasFocus       = { param($hwnd)
            [void]$s.Calls.Add('HasFocus'); $s.Polls++
            if ($s.HasFocusThrows) { throw 'uia broke' }
            if ($s.FocusOnPoll -gt 0 -and $s.Polls -ge $s.FocusOnPoll) { return $s.FocusValue }
            return $false }.GetNewClosure()
        NowMs          = { $s.Ms }.GetNewClosure()
        Sleep          = { param($ms) $s.Ms += $ms }.GetNewClosure()
    }
    return $s
}

Describe 'Send: Confirm-InputFocus (③-a, 클릭 없이 창을 올리고 입력란 포커스를 읽어 확인)' {
    It 'passes when the window is in front and the input box already has keyboard focus (no waiting for a person)' {
        $f = New-FakeFocusProvider
        (Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider) | Should Be $true
        ($f.Calls -join ',') | Should Be 'Raise,HasFocus'
    }

    It 'falls back to waiting for the window only when raising did not bring it to the front' {
        $f = New-FakeFocusProvider
        $f.Front = $false
        (Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider) | Should Be $true
        ($f.Calls -join ',') | Should Be 'Raise,Wait,HasFocus'
    }

    It 'stops (exit 2) when the window never comes to the front, and never reads the box' {
        $f = New-FakeFocusProvider
        $f.Front = $false
        $f.WaitThrows = $true
        (Get-ThrownError { Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider }).ExitCode | Should Be 2
        @($f.Calls | Where-Object { $_ -eq 'HasFocus' }).Count | Should Be 0
    }

    It 'lets an error from raising pass through unchanged' {
        $f = New-FakeFocusProvider
        $f.RaiseThrows = $true
        (Get-ThrownError { Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider }).ExitCode | Should Be 2
        @($f.Calls | Where-Object { $_ -eq 'HasFocus' }).Count | Should Be 0
    }

    It 'waits a short while for the focus to arrive (focus on the 5th look is still fine)' {
        $f = New-FakeFocusProvider
        $f.FocusOnPoll = 5
        (Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider) | Should Be $true
        $f.Polls | Should Be 5
    }

    It 'stops with exit 2 and a clear message when the box never gets focus, after a bounded number of looks' {
        $f = New-FakeFocusProvider
        $f.FocusOnPoll = 0
        $e = Get-ThrownError { Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $e.Message | Should Match '포커스'
        $e.Message | Should Match '입력하지 않았습니다'
        ($f.Polls -ge 2) | Should Be $true
        ($f.Polls -le 40) | Should Be $true
        ($f.Ms -le 3000) | Should Be $true
    }

    It 'treats a failing read as "no focus" (stops with exit 2, never crashes in another way)' {
        $f = New-FakeFocusProvider
        $f.HasFocusThrows = $true
        (Get-ThrownError { Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider }).ExitCode | Should Be 2
    }

    It 'counts only a real boolean true as focus (a text "true", 1 or stray output does not pass)' {
        foreach ($junk in 'true', 1, 'yes', @('noise', $true)) {
            $f = New-FakeFocusProvider
            $f.FocusValue = $junk
            (Get-ThrownError { Confirm-InputFocus -Hwnd 100 -Title '방' -Provider $f.Provider }).ExitCode | Should Be 2
        }
    }

    It 'the real provider uses it (no longer the always-stop stub) and the code never moves focus itself, clicks or sends keys' {
        $p = Get-DefaultSendProvider
        ($p.FocusInput.ToString()).Contains('Confirm-InputFocus') | Should Be $true
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\Send.ps1'))
        $start = $text.IndexOf('function Confirm-InputFocus')
        $start | Should BeGreaterThan -1
        $body = $text.Substring($start)
        $end = $body.IndexOf("`nfunction ", 10)
        if ($end -gt 0) { $body = $body.Substring(0, $end) }
        $code = (($body -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        foreach ($bad in 'SetFocus', 'Send-KeyCombo', 'Invoke-RelClick', 'SendKeys', 'mouse_event') {
            $code.IndexOf($bad, [System.StringComparison]::OrdinalIgnoreCase) | Should Be -1
        }
    }
}

Describe 'Send: Ready 조건 함수 (③-b, 기본은 계속 꺼 둔다)' {
    It 'lists what is still missing, and real sending stays locked while anything is missing' {
        $unmet = @(Get-SendUnmetReadyConditions)
        ($unmet -contains 'VerifySent') | Should Be $true
        ($unmet -contains 'Approval') | Should Be $true
        $p = Get-DefaultSendProvider
        [bool](& $p.Ready) | Should Be $false
    }

    It 'stays locked when only one of the two conditions is met, and opens only when both are' {
        $oldV = $script:SendVerifySentImplemented
        $oldA = $script:SendReadyApproved
        try {
            $p = Get-DefaultSendProvider
            $script:SendVerifySentImplemented = $true; $script:SendReadyApproved = $false
            [bool](& $p.Ready) | Should Be $false
            $script:SendVerifySentImplemented = $false; $script:SendReadyApproved = $true
            [bool](& $p.Ready) | Should Be $false
            $script:SendVerifySentImplemented = $true; $script:SendReadyApproved = $true
            [bool](& $p.Ready) | Should Be $true
            @(Get-SendUnmetReadyConditions).Count | Should Be 0
        }
        finally { $script:SendVerifySentImplemented = $oldV; $script:SendReadyApproved = $oldA }
    }

    It 'only the exact boolean true opens it (text "true" or 1 does not)' {
        $oldV = $script:SendVerifySentImplemented
        $oldA = $script:SendReadyApproved
        try {
            $p = Get-DefaultSendProvider
            $script:SendVerifySentImplemented = 'true'; $script:SendReadyApproved = 1
            [bool](& $p.Ready) | Should Be $false
        }
        finally { $script:SendVerifySentImplemented = $oldV; $script:SendReadyApproved = $oldA }
    }

    It 'both switches ship as false in the source' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\Send.ps1'))
        $text | Should Match '\$script:SendVerifySentImplemented\s*=\s*\$false'
        $text | Should Match '\$script:SendReadyApproved\s*=\s*\$false'
    }
}
