$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'Status', 'Room', 'Parse', 'Exporter', 'Send', 'SendCommand')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 방 열기·입력·확인을 시험이 정하고 호출을 기록한다. 실제 카카오톡은 건드리지 않는다.
function New-FakeCmdProvider {
    $s = @{
        Calls    = (New-Object System.Collections.ArrayList)
        Bodies   = (New-Object System.Collections.ArrayList)
        Verify   = $true
        LockSeen = $null
        Now      = ([datetime]::SpecifyKind([datetime]'2026-11-13T09:00:00', [System.DateTimeKind]::Utc))
    }
    $s.Provider = @{
        Ready      = { $true }.GetNewClosure()
        Mode       = { 'full' }.GetNewClosure()
        Now        = { $s.Now }.GetNewClosure()
        # GetNewClosure 로 만든 블록은 $script: 가 모듈 쪽을 가리켜 실행 잠금을 볼 수 없다. 그래서 일부러 닫지 않은 블록으로 만든다.
        LockHeld   = [scriptblock]::Create('$held = ($null -ne $script:KitLockMutex); $global:KitCmdTestLockSeen = $held; $held')
        OpenRoom   = { param($name, $caller) [void]$s.Calls.Add(('Open:{0}:{1}' -f $name, $caller)); [pscustomobject]@{ Hwnd = 20; Title = $name; OpenedByKit = $true } }.GetNewClosure()
        # 사람이 보낼 때 묻는 "입력란이 비었습니까?"에는 예로 답한다(이 파일의 시험은 명령 계층만 본다. 묻는 동작 자체는 Send.Tests 가 본다).
        ConfirmInputEmpty = { param($title) $true }.GetNewClosure()
        WaitIdle   = { }.GetNewClosure()
        FocusInput = { param($hwnd, $title) [void]$s.Calls.Add('Focus') }.GetNewClosure()
        PasteEnter = { param($hwnd, $text, $title, $progress) [void]$s.Bodies.Add($text); [void]$s.Calls.Add('PasteEnter'); $progress.KeysSent = $true }.GetNewClosure()
        VerifySent = { param($room, $text, $attemptId) $s.Verify }.GetNewClosure()
        CloseRoom  = { param($opened) [void]$s.Calls.Add('Close') }.GetNewClosure()
    }
    return $s
}

function Set-CmdRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-CmdRoom([string]$Name, [bool]$AiSend = $true) {
    [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $true; canSend = $true; selfOnly = $true; aiRead = $false; aiSend = $AiSend; noDraft = $true }
}
function Get-InputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Open:*' -or $_ -eq 'Focus' -or $_ -eq 'PasteEnter' -or $_ -eq 'Close' }) }

# 명령을 실행해 종료 코드와 화면 글자를 돌려준다.
function Invoke-Send([string[]]$Argv, [hashtable]$Provider) {
    $all = if ($null -eq $Provider) { @(Invoke-SendCommand -Argv $Argv 6>&1) } else { @(Invoke-SendCommand -Argv $Argv -Provider $Provider 6>&1) }
    $code = @($all | Where-Object { $_ -is [int] })
    $text = (@($all | Where-Object { $_ -isnot [int] } | ForEach-Object { [string]$_ }) -join "`n")
    @{ Exit = $code[$code.Count - 1]; Out = $text }
}

Describe 'SendCommand: 인자 검사 (입력 호출 0, 종료 코드 1)' {
    It 'prints the usage and exits 1 for no arguments, an unknown option, a missing value, a duplicate option and a missing room' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            foreach ($argv in @(
                    @(),
                    @('--room', '테스트방', '--text', 'hi', '--nope'),
                    @('--room', '테스트방', '--text'),
                    @('--room', '테스트방', '--room', '테스트방', '--text', 'hi'),
                    @('--text', 'hi'),
                    @('테스트방', 'hi'))) {
                $f = New-FakeCmdProvider
                $r = Invoke-Send $argv $f.Provider
                $r.Exit | Should Be 1
                $r.Out | Should Match '사용법'
                (Get-InputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'rejects --text together with --file, neither of them, and an option value that starts with --' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            foreach ($argv in @(
                    @('--room', '테스트방', '--text', 'hi', '--file', 'x.txt'),
                    @('--room', '테스트방', '--yes'),
                    @('--room', '테스트방', '--text', '--yes'))) {
                $f = New-FakeCmdProvider
                (Invoke-Send $argv $f.Provider).Exit | Should Be 1
                (Get-InputCalls $f).Count | Should Be 0
            }
        }
    }

    It 'is case sensitive for options: --ROOM and --Yes are unknown' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $f = New-FakeCmdProvider
            (Invoke-Send @('--ROOM', '테스트방', '--text', 'hi', '--dry-run') $f.Provider).Exit | Should Be 1
            (Invoke-Send @('--room', '테스트방', '--text', 'hi', '--Yes') $f.Provider).Exit | Should Be 1
            (Get-InputCalls $f).Count | Should Be 0
        }
    }
}

Describe 'SendCommand: 글 파일 (--file)' {
    function New-TextFile([byte[]]$Bytes) {
        $p = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-sendfile-' + [guid]::NewGuid().ToString('N') + '.txt')
        [System.IO.File]::WriteAllBytes($p, $Bytes)
        return $p
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    It 'reads a UTF-8 file (with or without BOM) and drops only the trailing line break' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $plain = New-TextFile ($utf8.GetBytes("안녕`r`n둘째 줄`r`n"))
            $bom = New-TextFile (@(0xEF, 0xBB, 0xBF) + [byte[]]$utf8.GetBytes('BOM글'))
            try {
                $f = New-FakeCmdProvider
                $r = Invoke-Send @('--room', '테스트방', '--file', $plain, '--attempt-id', 'a1', '--yes') $f.Provider
                $r.Exit | Should Be 0
                $f.Bodies[0] | Should Be "안녕`r`n둘째 줄"
                $f2 = New-FakeCmdProvider
                $f2.Now = $f2.Now.AddMinutes(5)
                (Invoke-Send @('--room', '테스트방', '--file', $bom, '--attempt-id', 'a2', '--yes') $f2.Provider).Exit | Should Be 0
                $f2.Bodies[0] | Should Be 'BOM글'
            }
            finally { Remove-Item -LiteralPath $plain, $bom -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'exits 1 with no input for a missing file, an oversized file, invalid UTF-8 and an empty file' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $big = New-TextFile ($utf8.GetBytes('a' * 9000))
            $bad = New-TextFile ([byte[]](0x61, 0xFF, 0xFE, 0x62))
            $empty = New-TextFile ([byte[]]@())
            try {
                foreach ($path in @((Join-Path ([System.IO.Path]::GetTempPath()) 'kakaokit-no-such-file.txt'), $big, $bad, $empty)) {
                    $f = New-FakeCmdProvider
                    (Invoke-Send @('--room', '테스트방', '--file', $path, '--attempt-id', 'x1', '--yes') $f.Provider).Exit | Should Be 1
                    (Get-InputCalls $f).Count | Should Be 0
                }
            }
            finally { Remove-Item -LiteralPath $big, $bad, $empty -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'SendCommand: 호출자 구분 (사람/AI)' {
    It 'treats a call without --human as ai: sending needs --attempt-id and the room must allow ai sending' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom 'AI허용방' $true), (New-CmdRoom 'AI금지방' $false))
            $f = New-FakeCmdProvider
            (Invoke-Send @('--room', 'AI허용방', '--text', 'hi', '--yes') $f.Provider).Exit | Should Be 1
            (Get-InputCalls $f).Count | Should Be 0
            (Invoke-Send @('--room', 'AI금지방', '--text', 'hi', '--attempt-id', 'a1', '--yes') $f.Provider).Exit | Should Be 1
            (Get-InputCalls $f).Count | Should Be 0
            $r = Invoke-Send @('--room', 'AI허용방', '--text', 'hi', '--attempt-id', 'a1', '--yes') $f.Provider
            $r.Exit | Should Be 0
            $f.Calls -contains 'Open:AI허용방:ai' | Should Be $true
        }
    }

    It 'refuses --human when the keyboard input is redirected (not a person at a console): exit 1, no input' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            function Test-InputRedirected { return $true }
            $f = New-FakeCmdProvider
            $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--human', '--dry-run') $f.Provider
            $r.Exit | Should Be 1
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'passes the caller human to the sender when --human is given at a real console' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방' $false))
            function Test-InputRedirected { return $false }
            $f = New-FakeCmdProvider
            $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--human', '--yes') $f.Provider
            $r.Exit | Should Be 0
            $f.Calls -contains 'Open:테스트방:human' | Should Be $true
        }
    }
}

Describe 'SendCommand: 실행 잠금과 결과 표시' {
    It 'holds the run lock while sending and releases it afterwards (also after a stop)' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $f = New-FakeCmdProvider
            $global:KitCmdTestLockSeen = $null
            (Invoke-Send @('--room', '테스트방', '--text', 'hi', '--attempt-id', 'l1', '--yes') $f.Provider).Exit | Should Be 0
            $global:KitCmdTestLockSeen | Should Be $true
            Remove-Variable -Name KitCmdTestLockSeen -Scope Global -ErrorAction SilentlyContinue
            $null -eq $script:KitLockMutex | Should Be $true
            # 멈춘 뒤에도 놓는다: 같은 시도 번호를 다시 쓰면 멈춘다
            $f.Now = $f.Now.AddMinutes(5)
            (Invoke-Send @('--room', '테스트방', '--text', 'hi', '--attempt-id', 'l1', '--yes') $f.Provider).Exit | Should Be 2
            $null -eq $script:KitLockMutex | Should Be $true
        }
    }

    It 'exits 2 with no input when another run already holds the lock' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            Enter-KitLock
            try {
                $f = New-FakeCmdProvider
                $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--attempt-id', 'k1', '--yes') $f.Provider
                $r.Exit | Should Be 2
                (Get-InputCalls $f).Count | Should Be 0
            }
            finally { Exit-KitLock }
        }
    }

    It 'confirmed exits 0 and unknown exits 2 with the check-by-hand message; the screen never shows the message body' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $f = New-FakeCmdProvider
            $r = Invoke-Send @('--room', '테스트방', '--text', '비밀본문XYZ', '--attempt-id', 'c1', '--yes') $f.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '확인했습니다'
            $r.Out | Should Not Match '비밀본문XYZ'
            $f.Verify = $null
            $f.Now = $f.Now.AddMinutes(5)
            $r = Invoke-Send @('--room', '테스트방', '--text', '비밀본문XYZ', '--attempt-id', 'c2', '--yes') $f.Provider
            $r.Exit | Should Be 2
            $r.Out | Should Match '확인하지 못했습니다'
            $r.Out | Should Not Match '비밀본문XYZ'
        }
    }

    It 'dry run prints the preview, exits 0 and does no input' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $f = New-FakeCmdProvider
            $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--dry-run') $f.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '미리보기'
            (Get-InputCalls $f).Count | Should Be 0
        }
    }

    It 'shows an unexpected error as a generic Korean message with exit 3, without the raw error text' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $f = New-FakeCmdProvider
            $f.Provider.OpenRoom = { param($n, $c) throw 'RAW-INTERNAL-ERROR-TEXT' }
            $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--yes', '--attempt-id', 'e2') $f.Provider
            $r.Exit | Should Be 3
            $r.Out | Should Match '예상하지 못한 오류'
            $r.Out | Should Not Match 'RAW-INTERNAL-ERROR-TEXT'
        }
    }
}

Describe 'SendCommand: kakao.cmd 로 실제 실행 (새 프로세스)' {
    function Invoke-RealCli([string]$CliArgs) {
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

    It 'kakao send with no options prints the usage and exits 1' {
        Use-TempHome {
            Set-TestConsent   # 동의 게이트(Consent.Tests 가 따로 봄)를 지나가게 한다
            $r = Invoke-RealCli 'send'
            $r.ExitCode | Should Be 1
            $r.Out | Should Match '사용법'
        }
    }

    It 'kakao send with valid options stops at the locked sender: exit 3, nothing sent, no state file' {
        Use-TempHome {
            Set-TestConsent
            $r = Invoke-RealCli 'send --room 없는방 --text hello --dry-run'
            $r.ExitCode | Should Be 3
            $r.Out | Should Match '아직 열리지 않았습니다'
            Test-Path -LiteralPath ([System.IO.Path]::Combine((Get-KitPaths).DataDir, 'state')) | Should Be $false
        }
    }

    It 'kakao version still works and the no-command help now names send as locked' {
        (Invoke-RealCli 'version').ExitCode | Should Be 0
        $r = Invoke-RealCli ''
        $r.ExitCode | Should Be 1
        $r.Out | Should Match 'send'
        $r.Out | Should Match '잠겨 있음'
    }
}

Describe 'SendCommand: 실제 제공자는 잠겨 있다 (입력 0)' {
    It 'with the real provider every send call, even a dry run, stops with exit 3 and no state file is written' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            foreach ($argv in @(
                    @('--room', '테스트방', '--text', 'hi', '--dry-run'),
                    @('--room', '테스트방', '--text', 'hi', '--attempt-id', 'r1', '--yes'))) {
                $r = Invoke-Send $argv $null
                $r.Exit | Should Be 3
                $r.Out | Should Match '아직 열리지 않았습니다'
            }
            Test-Path -LiteralPath ([System.IO.Path]::Combine((Get-KitPaths).DataDir, 'state', 'send-state.json')) | Should Be $false
        }
    }
}

Describe 'SendCommand: 보낸 글 확인용 내보내기 연결 (Z3, 보내기는 계속 잠김)' {
    It 'a real run (no test provider) wires the real exporter into the verification hook, and still stops at the sending lock: exit 3, nothing sent' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $script:SendExporter = $null
            try {
                $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--dry-run') $null
                $r.Exit | Should Be 3
                $r.Out | Should Match '아직 열리지 않았습니다'
                ($script:SendExporter -is [scriptblock]) | Should Be $true
            }
            finally { $script:SendExporter = $null }
        }
    }

    It 'a test provider keeps the hook untouched (the fake decides what verification does)' {
        Use-TempHome {
            Set-CmdRooms @((New-CmdRoom '테스트방'))
            $sentinel = { 'sentinel' }
            $script:SendExporter = $sentinel
            try {
                $f = New-FakeCmdProvider
                $r = Invoke-Send @('--room', '테스트방', '--text', 'hi', '--dry-run') $f.Provider
                $r.Exit | Should Be 0
                [object]::ReferenceEquals($script:SendExporter, $sentinel) | Should Be $true
            }
            finally { $script:SendExporter = $null }
        }
    }

    It 'the router loads the parser and the exporter for the send command' {
        $router = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\kakao.ps1'), (New-Object System.Text.UTF8Encoding($false)))
        $branch = [regex]::Match($router, "(?s)'send'\s*\{.*?foreach \(\`$name in ([^)]*)\)")
        $branch.Success | Should Be $true
        $names = @([regex]::Matches($branch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        ($names -contains 'Parse') | Should Be $true
        ($names -contains 'Exporter') | Should Be $true
    }

    It 'every kit function that the files loaded for the send command call is defined once the router has loaded them' {
        $router = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\kakao.ps1'), (New-Object System.Text.UTF8Encoding($false)))
        $branch = [regex]::Match($router, "(?s)'send'\s*\{.*?foreach \(\`$name in ([^)]*)\)")
        $branch.Success | Should Be $true
        $names = @([regex]::Matches($branch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $script = @'
$ErrorActionPreference = 'Stop'
$lib = '__LIB__'
$names = '__NAMES__' -split ','
foreach ($n in @('Messages.ko', 'Paths') + $names) { . (Join-Path $lib ($n + '.ps1')) }
$all = @{}
foreach ($f in (Get-ChildItem -LiteralPath $lib -Filter '*.ps1')) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
    foreach ($fd in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $all[$fd.Name] = $true }
}
$missing = @()
foreach ($n in $names) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $lib ($n + '.ps1')), [ref]$null, [ref]$null)
    foreach ($c in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cn = $c.GetCommandName()
        if ($cn -and $all.ContainsKey($cn) -and -not (Get-Command -Name $cn -CommandType Function -ErrorAction SilentlyContinue)) { $missing += ($n + ' -> ' + $cn) }
    }
}
'MISSING=' + (($missing | Sort-Object -Unique) -join '; ')
'@
        $script = $script.Replace('__LIB__', $kitLibDir).Replace('__NAMES__', ($names -join ','))
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
        $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1 | ForEach-Object { [string]$_ })
        $line = @($out | Where-Object { $_ -like 'MISSING=*' })
        $line.Count | Should Be 1
        $line[0] | Should Be 'MISSING='
    }
}
