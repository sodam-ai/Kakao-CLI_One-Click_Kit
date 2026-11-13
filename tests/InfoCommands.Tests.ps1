# rooms / read / search / status 명령 계층. 카카오톡을 건드리지 않는다: 임시 폴더(KAKAO_KIT_HOME)와 합성 자료, 가짜 설치 정보만 쓴다.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config', 'Log', 'Parse', 'Export', 'Search', 'Status', 'Send', 'InfoCommands')
. (Join-Path $here '_Load.ps1')

$sample = Join-Path $here 'fixtures\export-sample.txt'   # 방 "테스트방", 메시지 4개(2026-10-21 00:05 ~ 2026-10-22 23:59)

function New-InfoRoom([string]$Name, [bool]$AiRead = $false, [bool]$CanRead = $true) {
    [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $CanRead; canSend = $true; selfOnly = $true; aiRead = $AiRead; aiSend = $false }
}
function Set-InfoRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = @($Rooms) }) }
function Get-InfoRooms { return , @(Get-ConfigRooms -Config (Get-KitConfig)) }   # 쉼표: 방이 하나여도 배열로 돌려준다(PS 5.1 은 한 개짜리 배열을 풀어 버린다)

# 명령을 실행해 종료 코드와 화면 글자를 돌려준다(Write-Host 는 정보 스트림 6 으로 잡는다).
function Run-Info([scriptblock]$Body) {
    $all = @(& $Body 6>&1)
    $codes = @($all | Where-Object { $_ -is [int] })
    $text = (@($all | Where-Object { $_ -isnot [int] } | ForEach-Object { [string]$_ }) -join "`n")
    @{ Exit = $codes[$codes.Count - 1]; Out = $text }
}
function Get-LogText { $f = Join-Path (Get-KitPaths).LogsDir 'kakao.log'; if (Test-Path -LiteralPath $f) { [System.IO.File]::ReadAllText($f) } else { '' } }
function Store-Sample([string]$Room = '테스트방') { Update-ExportStore -Room $Room -SourcePath $sample -Now ([datetime]'2026-10-27T04:10:00') | Out-Null }

Describe 'rooms: 목록은 누구나, 바꾸기는 사람만' {
    It 'list on an empty config says there are no rooms (exit 0)' {
        Use-TempHome {
            $r = Run-Info { Invoke-RoomsCommand -Argv @('list') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '허용된 방이 없습니다'
        }
    }

    It 'list shows each room with its kind and Yes/No flags, and treats a non-boolean flag as No' {
        Use-TempHome {
            $odd = New-InfoRoom '이상한방' $true
            $odd | Add-Member -NotePropertyName aiRead -NotePropertyValue 'true' -Force
            Set-InfoRooms @((New-InfoRoom '가방' $true), $odd)
            $r = Run-Info { Invoke-RoomsCommand -Argv @('list') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '가방 \| open'
            ($r.Out -split "`n" | Where-Object { $_ -like '이상한방*' }) | Should Match '아니오'
        }
    }

    It 'add, remove and set are refused without --human and change nothing' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '가방'))
            function Test-InputRedirected { return $false }
            foreach ($argv in @(@('add', '새방', '--type', 'open'), @('remove', '가방'), @('set', '가방', 'aiRead', 'on'))) {
                (Run-Info { Invoke-RoomsCommand -Argv $argv }).Exit | Should Be 1
            }
            (Get-InfoRooms).Count | Should Be 1
            (Get-InfoRooms)[0].aiRead | Should Be $false
        }
    }

    It 'add, remove and set are refused with --human when keyboard input is redirected (not a person)' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '가방'))
            function Test-InputRedirected { return $true }
            foreach ($argv in @(@('add', '새방', '--type', 'open', '--human'), @('remove', '가방', '--human'), @('set', '가방', 'aiRead', 'on', '--human'))) {
                (Run-Info { Invoke-RoomsCommand -Argv $argv }).Exit | Should Be 1
            }
            (Get-InfoRooms).Count | Should Be 1
        }
    }

    It 'add with --human creates the room with AI read and send both off, prints the unchecked-room note, and refuses a duplicate' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            $r = Run-Info { Invoke-RoomsCommand -Argv @('add', '새방', '--type', 'open', '--self-only', '--human') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '허용 목록에 넣었습니다: 새방'
            $r.Out | Should Match '직접 확인하세요'
            $room = (Get-InfoRooms)[0]
            $room.name | Should Be '새방'
            $room.type | Should Be 'open'
            $room.selfOnly | Should Be $true
            $room.aiRead | Should Be $false
            $room.aiSend | Should Be $false
            (Run-Info { Invoke-RoomsCommand -Argv @('add', '새방', '--type', 'open', '--human') }).Exit | Should Be 1
            (Get-InfoRooms).Count | Should Be 1
        }
    }

    It 'add rejects a missing or wrong --type, a bad room name and a wrong number of names (exit 1, nothing saved)' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            $long = 'a' * 101
            foreach ($argv in @(
                    @('add', '새방', '--human'),
                    @('add', '새방', '--type', 'x', '--human'),
                    @('add', '새방', '--type', 'OPEN', '--human'),
                    @('add', ' 앞공백', '--type', 'open', '--human'),
                    @('add', "탭`t방", '--type', 'open', '--human'),
                    @('add', $long, '--type', 'open', '--human'),
                    @('add', '--type', 'open', '--human'),
                    @('add', '하나', '둘', '--type', 'open', '--human'))) {
                (Run-Info { Invoke-RoomsCommand -Argv $argv }).Exit | Should Be 1
            }
            (Get-InfoRooms).Count | Should Be 0
        }
    }

    It 'remove deletes a room; an unknown room is exit 1' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            Set-InfoRooms @((New-InfoRoom '가방'), (New-InfoRoom '나방'))
            (Run-Info { Invoke-RoomsCommand -Argv @('remove', '가방', '--human') }).Exit | Should Be 0
            @(Get-InfoRooms | ForEach-Object { $_.name }) -join ',' | Should Be '나방'
            (Run-Info { Invoke-RoomsCommand -Argv @('remove', '없는방', '--human') }).Exit | Should Be 1
        }
    }

    It 'set changes one permission with on/off only (lower case); invalid permission, value and room are exit 1' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            Set-InfoRooms @((New-InfoRoom '가방'))
            (Run-Info { Invoke-RoomsCommand -Argv @('set', '가방', 'aiRead', 'on', '--human') }).Exit | Should Be 0
            (Get-InfoRooms)[0].aiRead | Should Be $true
            (Run-Info { Invoke-RoomsCommand -Argv @('set', '가방', 'aiRead', 'off', '--human') }).Exit | Should Be 0
            (Get-InfoRooms)[0].aiRead | Should Be $false
            foreach ($argv in @(@('set', '가방', 'aiRead', 'yes', '--human'), @('set', '가방', 'aiRead', 'ON', '--human'), @('set', '가방', 'nope', 'on', '--human'), @('set', '없는방', 'aiRead', 'on', '--human'), @('set', '가방', 'aiRead', '--human'))) {
                (Run-Info { Invoke-RoomsCommand -Argv $argv }).Exit | Should Be 1
            }
            (Get-InfoRooms)[0].aiRead | Should Be $false
        }
    }

    It 'a missing, unknown or differently-cased sub-command prints the usage (exit 1)' {
        Use-TempHome {
            foreach ($argv in @(@(), @('nope'), @('LIST'), @('list', 'extra'), @('list', '--nope'))) {
                $r = Run-Info { Invoke-RoomsCommand -Argv $argv }
                $r.Exit | Should Be 1
                $r.Out | Should Match '사용법'
            }
        }
    }
}

Describe 'read: 보관된 내보내기에서 읽기 (카카오톡 조작 없음)' {
    It 'a person reads the last messages: oldest first within the selection, multi-line text and emoji intact' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            Set-InfoRooms @((New-InfoRoom '테스트방'))
            Store-Sample
            $r = Run-Info { Invoke-ReadCommand -Argv @('테스트방', '--last', '2', '--human') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '정오 직후'
            $r.Out | Should Match '여러 줄 메시지의 둘째 줄'
            $r.Out | Should Match '이모지 😀'
            $r.Out | Should Not Match '자정 지나서'
        }
    }

    It 'an AI (no --human) is refused until the room allows AI reading, and nothing leaks while refused' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $false))
            Store-Sample
            $r = Run-Info { Invoke-ReadCommand -Argv @('테스트방') }
            $r.Exit | Should Be 1
            $r.Out | Should Not Match '정오 직후'
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            $r = Run-Info { Invoke-ReadCommand -Argv @('테스트방', '--last', '1') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '이모지'
        }
    }

    It '--since keeps only the messages inside the period (fixed clock) and says so when none match' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            Store-Sample
            $now = [datetime]'2026-10-23T12:00:00'
            $r = Run-Info { Invoke-ReadCommand -Argv @('테스트방', '--since', '1d') -Now $now }
            $r.Exit | Should Be 0
            $r.Out | Should Match '이모지'
            $r.Out | Should Not Match '정오 직후'
            $none = Run-Info { Invoke-ReadCommand -Argv @('테스트방', '--since', '1h') -Now ([datetime]'2026-12-01T00:00:00') }
            $none.Exit | Should Be 0
            $none.Out | Should Match '조건에 맞는 메시지가 없습니다'
        }
    }

    It 'rejects bad options with the usage (exit 1) and reads nothing' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            Store-Sample
            foreach ($argv in @(
                    @(),
                    @('테스트방', '--last', '0'), @('테스트방', '--last', '-1'), @('테스트방', '--last', 'abc'), @('테스트방', '--last', '1000000'),
                    @('테스트방', '--since', '7w'), @('테스트방', '--since', '0d'), @('테스트방', '--since', '7'), @('테스트방', '--since', '7D'),
                    @('테스트방', '--since'), @('테스트방', '--last', '1', '--last', '2'), @('테스트방', '--nope'), @('테스트방', '다른방'))) {
                $r = Run-Info { Invoke-ReadCommand -Argv $argv }
                $r.Exit | Should Be 1
                $r.Out | Should Match '사용법'
                $r.Out | Should Not Match '정오 직후'
            }
        }
    }

    It 'says exit 3 when no export has been stored for the room' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            $r = Run-Info { Invoke-ReadCommand -Argv @('테스트방') }
            $r.Exit | Should Be 3
            $r.Out | Should Match '저장된 내보내기 파일이 아직 없습니다'
        }
    }

    It 'drops terminal control characters (such as ESC) from what it prints' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '제어방' $true))
            $esc = [string][char]27
            $p = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-ctl-' + [guid]::NewGuid().ToString('N') + '.txt')
            [System.IO.File]::WriteAllText($p, ("제어방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] 빨강" + $esc + "[31m글자`r`n"), (New-Object System.Text.UTF8Encoding($false)))
            try { Update-ExportStore -Room '제어방' -SourcePath $p -Now ([datetime]'2026-10-27T04:10:00') | Out-Null } finally { Remove-Item -LiteralPath $p -Force }
            $r = Run-Info { Invoke-ReadCommand -Argv @('제어방') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '빨강'
            $r.Out.Contains($esc) | Should Be $false
        }
    }

    It 'writes only the room and a count to the log, never the message text' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            Store-Sample
            [void](Run-Info { Invoke-ReadCommand -Argv @('테스트방') })
            $log = Get-LogText
            $log | Should Match 'read'
            $log | Should Match 'count=4'
            $log | Should Not Match '정오 직후'
            $log | Should Not Match '이모지'
        }
    }
}

Describe 'search: 보관된 내보내기에서 낱말 찾기' {
    It 'finds a word as plain text in every room the caller may read, naming the room' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            Set-InfoRooms @((New-InfoRoom '테스트방'))
            Store-Sample
            $r = Run-Info { Invoke-SearchCommand -Argv @('정오', '--human') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '\[테스트방\]'
            $r.Out | Should Match '정오 직후'
        }
    }

    It 'treats the word literally (no regular expression) and says so when nothing is found' {
        Use-TempHome {
            function Test-InputRedirected { return $false }
            Set-InfoRooms @((New-InfoRoom '테스트방'))
            Store-Sample
            $r = Run-Info { Invoke-SearchCommand -Argv @('.*', '--human') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '찾은 메시지가 없습니다'
            $r.Out | Should Not Match '정오 직후'
        }
    }

    It 'an AI only searches rooms that allow AI reading; naming a room that does not is exit 1' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $false))
            Store-Sample
            $r = Run-Info { Invoke-SearchCommand -Argv @('정오') }
            $r.Exit | Should Be 0
            $r.Out | Should Match '찾은 메시지가 없습니다'
            $r.Out | Should Not Match '정오 직후'
            (Run-Info { Invoke-SearchCommand -Argv @('정오', '--room', '테스트방') }).Exit | Should Be 1
        }
    }

    It 'rejects an empty or blank word, a word over 200 characters, a word that looks like an option and a missing word' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            Store-Sample
            foreach ($argv in @(@(), @(''), @('   '), @(('가' * 201)), @('--정오'), @('하나', '둘'), @('정오', '--room'), @('정오', '--room', 'a', '--room', 'b'))) {
                (Run-Info { Invoke-SearchCommand -Argv $argv }).Exit | Should Be 1
            }
            (Run-Info { Invoke-SearchCommand -Argv @(('가' * 200)) }).Exit | Should Be 0
        }
    }

    It 'keeps the searched word out of the log' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom '테스트방' $true))
            Store-Sample
            [void](Run-Info { Invoke-SearchCommand -Argv @('정오') })
            $log = Get-LogText
            $log | Should Match 'search'
            $log | Should Match 'count=1'
            $log | Should Not Match '정오'
        }
    }
}

Describe 'status: 읽기만 하는 점검' {
    function New-FakeInstall([string]$Version, [bool]$Running = $false) {
        @{
            RegistryVersion = { $Version }.GetNewClosure()
            Processes       = { if ($Running) { @(@{ Version = $Version; ExePath = 'C:\fake\KakaoTalk.exe' }) } else { @() } }.GetNewClosure()
        }
    }
    function New-FakeSend([bool]$Ready) { @{ Ready = { $Ready }.GetNewClosure() } }

    It 'shows the kit version, the kakao version, full mode for a verified version and the room counts' {
        Use-TempHome {
            Set-InfoRooms @((New-InfoRoom 'a방' $true), (New-InfoRoom 'b방' $false))
            $r = Run-Info { Invoke-StatusCommand -Argv @() -InstallProvider (New-FakeInstall '26.9.0.5337' $true) -VerifiedList @('26.9.0.5337') -SendProvider (New-FakeSend $true) }
            $r.Exit | Should Be 0
            $r.Out | Should Match '키트 버전: 1\.0\.0'
            $r.Out | Should Match '카카오톡 버전: 26\.9\.0\.5337'
            $r.Out | Should Match '카카오톡 실행 중: 예'
            $r.Out | Should Match '보내기 모드: 전체'
            $r.Out | Should Match '허용된 방: 2개'
            $r.Out | Should Match 'AI 가 읽을 수 있는 방: 1개'
            $r.Out | Should Match 'AI 가 보낼 수 있는 방: 0개'
            $r.Out | Should Not Match '실제 보내기는 아직 잠겨'
        }
    }

    It 'an untested version is read-only mode, and a locked sender is stated' {
        Use-TempHome {
            $r = Run-Info { Invoke-StatusCommand -Argv @() -InstallProvider (New-FakeInstall '26.9.2.5342') -VerifiedList @('26.9.0.5337') -SendProvider (New-FakeSend $false) }
            $r.Exit | Should Be 0
            $r.Out | Should Match '보내기 모드: 읽기 전용'
            $r.Out | Should Match '카카오톡 실행 중: 아니오'
            $r.Out | Should Match '실제 보내기는 아직 잠겨'
        }
    }

    It 'not installed prints the not-installed line, unknown version and read-only mode' {
        Use-TempHome {
            $r = Run-Info { Invoke-StatusCommand -Argv @() -InstallProvider (New-FakeInstall $null) -VerifiedList @('26.9.0.5337') -SendProvider (New-FakeSend $false) }
            $r.Exit | Should Be 0
            $r.Out | Should Match '설치되어 있지 않거나'
            $r.Out | Should Match '보내기 모드: 읽기 전용'
        }
    }

    It 'takes no arguments (usage, exit 1) and writes no config file' {
        Use-TempHome {
            $r = Run-Info { Invoke-StatusCommand -Argv @('extra') -InstallProvider (New-FakeInstall '1') -SendProvider (New-FakeSend $false) }
            $r.Exit | Should Be 1
            $r.Out | Should Match '사용법'
            [void](Run-Info { Invoke-StatusCommand -Argv @() -InstallProvider (New-FakeInstall '1') -VerifiedList @() -SendProvider (New-FakeSend $false) })
            Test-Path -LiteralPath (Get-KitPaths).ConfigFile | Should Be $false
        }
    }
}

Describe 'InfoCommands: kakao.cmd 로 실제 실행 (새 프로세스)' {
    function Invoke-RealInfoCli([string]$CliArgs) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/c ""' + (Join-Path $kitRoot 'kakao.cmd') + '" ' + $CliArgs + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $out = $proc.StandardOutput.ReadToEnd()
        [void]$proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        @{ ExitCode = $proc.ExitCode; Out = $out }
    }

    It 'rooms list, status, and the usage errors of read, search and rooms run for real' {
        Use-TempHome {
            $r = Invoke-RealInfoCli 'rooms list'
            $r.ExitCode | Should Be 0
            $r.Out | Should Match '허용된 방이 없습니다'
            $s = Invoke-RealInfoCli 'status'
            $s.ExitCode | Should Be 0
            $s.Out | Should Match '키트 버전: 1\.0\.0'
            $s.Out | Should Match '실제 보내기는 아직 잠겨'
            foreach ($c in 'read', 'search', 'rooms', 'status extra') {
                $x = Invoke-RealInfoCli $c
                $x.ExitCode | Should Be 1
                $x.Out | Should Match '사용법'
            }
            (Invoke-RealInfoCli 'rooms add 새방 --type open --human').ExitCode | Should Be 1
        }
    }
}
