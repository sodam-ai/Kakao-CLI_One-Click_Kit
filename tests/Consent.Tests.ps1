# 사용 동의 게이트와 kakao consent 명령. 카카오톡을 건드리지 않는다: 임시 폴더(KAKAO_KIT_HOME)만 쓴다.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config', 'Log', 'Consent')
. (Join-Path $here '_Load.ps1')

# 명령을 실행해 종료 코드와 화면 글자를 돌려준다.
function Invoke-Consent([string[]]$Argv, [hashtable]$Provider) {
    $all = if ($null -eq $Provider) { @(Invoke-ConsentCommand -Argv $Argv 6>&1) } else { @(Invoke-ConsentCommand -Argv $Argv -Provider $Provider 6>&1) }
    $code = @($all | Where-Object { $_ -is [int] })
    $text = (@($all | Where-Object { $_ -isnot [int] } | ForEach-Object { [string]$_ }) -join "`n")
    @{ Exit = $code[$code.Count - 1]; Out = $text }
}

# 답을 정해 주고 몇 번 물었는지 센다.
function New-AnswerProvider($Answer) {
    $s = @{ Asked = 0; Answer = $Answer }
    $s.Provider = @{ ReadAnswer = { param($prompt) $s.Asked++; $s.Answer }.GetNewClosure() }
    return $s
}

Describe 'Consent: 어떤 명령이 동의를 요구하는가 (Test-ConsentRequiredFor)' {
    It 'asks for consent before the commands that touch KakaoTalk or conversations, in any letter case' {
        foreach ($argv in @(
                @('open', '--room', '방'), @('OPEN', '--room', '방'), @('send', '--room', '방'), @('Send'),
                @('read', '방'), @('search', '낱말'),
                @('rooms', 'add', '방'), @('rooms', 'remove', '방'), @('rooms', 'set', '방', 'aiRead', 'on'), @('ROOMS', 'ADD', '방'))) {
            (Test-ConsentRequiredFor -Argv $argv) | Should Be $true
        }
    }

    It 'does not ask for consent for version, help, status, consent itself, rooms list, a bare rooms and unknown commands' {
        foreach ($argv in @(@(), @('version'), @('help'), @('status'), @('consent'), @('consent', '--human'), @('rooms'), @('rooms', 'list'), @('rooms', 'LIST'), @('nope'))) {
            (Test-ConsentRequiredFor -Argv $argv) | Should Be $false
        }
    }
}

Describe 'Consent: 게이트 (Invoke-ConsentGate)' {
    It 'stops with exit 1 and the consent message before consent, and lets the command through after consent' {
        Use-TempHome {
            $r = @(Invoke-ConsentGate 6>&1)
            ($r | Where-Object { $_ -is [int] })[0] | Should Be 1
            (@($r | Where-Object { $_ -isnot [int] }) -join "`n") | Should Match '동의'
            Test-Path -LiteralPath (Get-KitPaths).ConfigFile | Should Be $false
            Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = '2026-11-20T09:00:00'; lastRoom = $null; rooms = @() })
            @(Invoke-ConsentGate 6>&1).Count | Should Be 0
        }
    }

    It 'a damaged or hand-edited config never lets a command through (fail closed)' {
        Use-TempHome {
            $p = Get-KitPaths
            New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null
            foreach ($bad in 'not json', '"x"', '[]', '{"version":1,"consentAcceptedAt":false,"rooms":[]}', '{"version":1,"consentAcceptedAt":"yes","rooms":[]}') {
                [System.IO.File]::WriteAllText($p.ConfigFile, $bad, (New-Object System.Text.UTF8Encoding($false)))
                $r = @(Invoke-ConsentGate 6>&1)
                $code = @($r | Where-Object { $_ -is [int] })
                $code.Count | Should Be 1
                ($code[0] -ge 1) | Should Be $true
            }
        }
    }
}

Describe 'Consent: kakao consent (동의 확인과 받기)' {
    Mock Test-InputRedirected { $false }

    It 'without options it only shows the state: nothing is asked and nothing is written' {
        Use-TempHome {
            $a = New-AnswerProvider '동의합니다'
            $r = Invoke-Consent @() $a.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '아직 동의하지 않았습니다'
            $a.Asked | Should Be 0
            Test-KitConsent | Should Be $false
            Test-Path -LiteralPath (Get-KitPaths).ConfigFile | Should Be $false
        }
    }

    It 'any other option or word is a usage error (exit 1) and nothing is written' {
        Use-TempHome {
            foreach ($argv in @(@('--nope'), @('yes'), @('--human', '--human'), @('--human', 'x'))) {
                $a = New-AnswerProvider '동의합니다'
                $r = Invoke-Consent $argv $a.Provider
                $r.Exit | Should Be 1
                $r.Out | Should Match '사용법'
                $a.Asked | Should Be 0
                Test-KitConsent | Should Be $false
            }
        }
    }

    It 'records consent only for the exact answer, after showing the notice' {
        Use-TempHome {
            $a = New-AnswerProvider '동의합니다'
            $r = Invoke-Consent @('--human') $a.Provider
            $r.Exit | Should Be 0
            $a.Asked | Should Be 1
            $r.Out | Should Match '비공식'
            $r.Out | Should Match '동의를 기록했습니다'
            Test-KitConsent | Should Be $true
            $r2 = Invoke-Consent @() $a.Provider
            $r2.Exit | Should Be 0
            $r2.Out | Should Match '동의했습니다'
        }
    }

    It 'any other answer is not consent: exit 1, nothing recorded' {
        Use-TempHome {
            foreach ($answer in @($null, '', '  ', '동의', 'y', 'yes', '네', '동의합니다.', '동의합니다 동의합니다')) {
                $a = New-AnswerProvider $answer
                $r = Invoke-Consent @('--human') $a.Provider
                $r.Exit | Should Be 1
                $r.Out | Should Match '동의하지 않아'
                Test-KitConsent | Should Be $false
            }
        }
    }

    It 'when consent already exists it does not ask again and changes nothing' {
        Use-TempHome {
            Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = '2026-11-20T09:00:00'; lastRoom = $null; rooms = @() })
            $a = New-AnswerProvider '동의합니다'
            $r = Invoke-Consent @('--human') $a.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '이미 동의'
            $a.Asked | Should Be 0
            (Get-KitConfig).consentAcceptedAt | Should Be '2026-11-20T09:00:00'
        }
    }
}

Describe 'Consent: 사람만 동의할 수 있다 (입력이 막힌 곳에서는 거부)' {
    Mock Test-InputRedirected { $true }

    It 'kakao consent --human is refused when the keyboard is not attached: exit 1, no question, nothing recorded' {
        Use-TempHome {
            $a = New-AnswerProvider '동의합니다'
            $r = Invoke-Consent @('--human') $a.Provider
            $r.Exit | Should Be 1
            $r.Out | Should Match '키보드'
            $a.Asked | Should Be 0
            Test-KitConsent | Should Be $false
        }
    }
}

Describe 'Consent: 소스 안전 점검' {
    It 'the only place that records consent is behind the human path, and the notice never names a room or personal data' {
        $src = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'Consent.ps1'), (New-Object System.Text.UTF8Encoding($false)))
        $src | Should Match 'Assert-HumanPath -Human'
        ([regex]::Matches($src, 'Set-KitConsent')).Count | Should Be 1
        $src | Should Not Match '(?i)SendInput|Remove-Item|Send-KeyCombo|Invoke-RelClick'
    }
}

Describe 'Consent: 라우터와 kakao.cmd (새 프로세스)' {
    function Invoke-RealConsentCli([string]$CliArgs) {
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

    It 'before consent: open, send, read, search and rooms add stop with exit 1 and the consent message; version, help, status, rooms list and consent still work' {
        Use-TempHome {
            foreach ($c in 'open --room x', 'send --room x --text hi --dry-run', 'read x', 'search x', 'rooms add x --type open --human') {
                $r = Invoke-RealConsentCli $c
                $r.ExitCode | Should Be 1
                $r.Out | Should Match '사용 동의가 필요합니다'
            }
            foreach ($c in 'version', 'help', 'status', 'rooms list', 'consent') {
                (Invoke-RealConsentCli $c).ExitCode | Should Be 0
            }
            (Invoke-RealConsentCli 'consent').Out | Should Match '아직 동의하지 않았습니다'
            (Invoke-RealConsentCli 'consent --human').ExitCode | Should Be 1
            Test-Path -LiteralPath (Get-KitPaths).ConfigFile | Should Be $false
        }
    }

    It 'after consent the gate lets the command through: send reaches its own lock (exit 3) and read reaches its own usage check (exit 1)' {
        Use-TempHome {
            Set-TestConsent
            $r = Invoke-RealConsentCli 'send --room 없는방 --text hello --dry-run'
            $r.ExitCode | Should Be 3
            $r.Out | Should Match '아직 열리지 않았습니다'
            $r.Out | Should Not Match '사용 동의가 필요합니다'
            $u = Invoke-RealConsentCli 'read'
            $u.ExitCode | Should Be 1
            $u.Out | Should Match '사용법'
        }
    }
}
