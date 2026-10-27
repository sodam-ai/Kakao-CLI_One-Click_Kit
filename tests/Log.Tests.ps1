$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Log')
. (Join-Path $here '_Load.ps1')

# Task 8/10 에서 진짜가 생기기 전까지, 보고서가 카카오톡 버전을 묻는 함수를 이 시험 안에서만 흉내 낸다.
function Get-KakaoInstallInfo { [pscustomobject]@{ Version = '26.9.0.5337' } }

Describe 'Log: 본문은 기록하지 않는다' {
    It 'Write-KitLog has no parameter that could carry a message body' {
        $names = @((Get-Command Write-KitLog).Parameters.Keys)
        ($names -match '^(Text|Body|Message|Content)') | Should BeNullOrEmpty
    }

    It 'cuts long fields so a pasted body cannot be logged in full' {
        Use-TempHome {
            Write-KitLog -Level info -Command 'send' -Room 'r' -Result ('A' * 1000)
            $line = [System.IO.File]::ReadAllText((Join-Path (Get-KitPaths).LogsDir 'kakao.log'))
            $line.Length | Should BeLessThan 400
            $line | Should Not Match ('A' * 300)
        }
    }
}

Describe 'Log: 한 줄 형식' {
    It 'writes "time | level | command | room | result"' {
        Use-TempHome {
            Write-KitLog -Level info -Command 'send' -Room '비밀방' -Result 'ok'
            $lines = @([System.IO.File]::ReadAllLines((Join-Path (Get-KitPaths).LogsDir 'kakao.log')))
            $lines.Count | Should Be 1
            $lines[0] | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| info \| send \| 비밀방 \| ok$'
        }
    }

    It 'keeps one line and five fields even if fields contain newlines or pipes' {
        Use-TempHome {
            Write-KitLog -Level warn -Command 'a|b' -Room "x`ny" -Result "r1`r`nr2"
            $lines = @([System.IO.File]::ReadAllLines((Join-Path (Get-KitPaths).LogsDir 'kakao.log')))
            $lines.Count | Should Be 1
            @($lines[0] -split ' \| ').Count | Should Be 5
        }
    }

    It 'rejects an unknown level' {
        Use-TempHome {
            { Write-KitLog -Level debug -Command 'x' -Room 'r' -Result 'ok' } | Should Throw 'Unknown log level'
        }
    }

    It 'the log file is UTF-8 without BOM' {
        Use-TempHome {
            Write-KitLog -Level info -Command 'send' -Room '비밀방' -Result 'ok'
            $b = [System.IO.File]::ReadAllBytes((Join-Path (Get-KitPaths).LogsDir 'kakao.log'))
            ('{0:X2}{1:X2}' -f $b[0], $b[1]) | Should Not Be 'EFBB'
        }
    }
}

Describe 'Log: 회전' {
    It 'does not rotate a small log' {
        Use-TempHome {
            1..3 | ForEach-Object { Write-KitLog -Level info -Command 'send' -Room 'r' -Result 'ok' }
            $main = Join-Path (Get-KitPaths).LogsDir 'kakao.log'
            @([System.IO.File]::ReadAllLines($main)).Count | Should Be 3
            Test-Path ($main + '.1') | Should Be $false
        }
    }

    It 'rotates past 1 MB into .1 .. .3 and drops older ones' {
        Use-TempHome {
            $logs = (Get-KitPaths).LogsDir
            New-Item -ItemType Directory -Path $logs -Force | Out-Null
            $main = Join-Path $logs 'kakao.log'
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            for ($i = 1; $i -le 5; $i++) {
                [System.IO.File]::WriteAllText($main, ('x' * 1048577), $utf8)
                Write-KitLog -Level info -Command 'test' -Room 'r' -Result ('run' + $i)
            }
            Test-Path ($main + '.1') | Should Be $true
            Test-Path ($main + '.2') | Should Be $true
            Test-Path ($main + '.3') | Should Be $true
            Test-Path ($main + '.4') | Should Be $false
            @([System.IO.File]::ReadAllLines($main)).Count | Should Be 1
            [System.IO.File]::ReadAllText($main) | Should Match 'run5'
        }
    }
}

Describe 'Log: 오류 보고서' {
    It 'has the kit/Kakao/OS versions and only the last 50 log lines' {
        Use-TempHome {
            1..60 | ForEach-Object { Write-KitLog -Level info -Command 'send' -Room 'r' -Result ('entry-{0:000}' -f $_) }
            $body = 'ZZZ-BODY'
            $rep = New-KitErrorReport
            $rep | Should Match '26\.9\.0\.5337'
            $rep | Should Match '1\.0\.0'
            $rep | Should Match 'Windows'
            $rep | Should Match 'entry-060'
            $rep | Should Match 'entry-011'
            $rep | Should Not Match 'entry-010'
            $rep | Should Not Match $body
        }
    }

    It 'works before anything was logged' {
        Use-TempHome {
            $rep = New-KitErrorReport
            $rep | Should Match '카카오톡 키트'
        }
    }
}

Describe 'Log: 경고 모음' {
    It 'collects distinct warnings and can be cleared' {
        Clear-KitWarnings
        Add-KitWarning -Warning '글자 확인(OCR) 없음'
        Add-KitWarning -Warning '글자 확인(OCR) 없음'
        Add-KitWarning -Warning '미검증 버전'
        @(Get-KitWarnings).Count | Should Be 2
        Clear-KitWarnings
        @(Get-KitWarnings).Count | Should Be 0
    }
}
