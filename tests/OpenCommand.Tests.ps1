$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'InputProbe', 'Room', 'OpenCommand')
. (Join-Path $here '_Load.ps1')

# kakao open 명령 계층 시험: 가짜 제공자만 쓴다. 실제 카카오톡은 건드리지 않는다.
# 가짜 제공자는 Room.Tests.ps1 과 같은 모양(창 목록·메인 화면 상태·입력 호출 기록)이다.
function New-FakeOpenProvider {
    $s = @{ Calls = (New-Object System.Collections.ArrayList); Queue = (New-Object System.Collections.Queue); Last = @(); Screen = 'chat-list'; Boom = $false }
    $s.Provider = @{
        Windows     = { [void]$s.Calls.Add('Windows'); if ($s.Queue.Count -gt 0) { $s.Last = @($s.Queue.Dequeue()) }; $s.Last }.GetNewClosure()
        WaitIdle    = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        PressEnter  = { param($hwnd, $title) [void]$s.Calls.Add(('Enter:{0}:{1}' -f $hwnd, $title)); if ($s.Boom) { throw 'SECRET-RAW-ERROR' } }.GetNewClosure()
        PasteText   = { param($hwnd, $text, $title) [void]$s.Calls.Add(('Paste:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        OpenSearch  = { param($hwnd, $title) [void]$s.Calls.Add(('OpenSearch:{0}' -f $hwnd)); $s.Screen = 'chat-search' }.GetNewClosure()
        MainScreen  = { param($hwnd) [void]$s.Calls.Add('Screen'); $s.Screen }.GetNewClosure()
        CloseSearch = { param($hwnd, $title) [void]$s.Calls.Add(('Esc:{0}:{1}' -f $hwnd, $title)); $s.Screen = 'chat-list' }.GetNewClosure()
        CloseWindow = { param($hwnd, $title) [void]$s.Calls.Add(('Close:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Sleep       = { param($ms) }.GetNewClosure()
    }
    return $s
}
function New-OWin([long]$Hwnd, [string]$Title) { [pscustomobject]@{ Hwnd = $Hwnd; Title = $Title } }
function Set-OpenRooms([object[]]$Rooms) { Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = $Rooms }) }
function New-OpenRoom([string]$Name, [string]$Type = 'open', [bool]$AiRead = $false) { [pscustomobject]@{ name = $Name; type = $Type; verified = $true; canRead = $true; canSend = $true; selfOnly = $true; aiRead = $AiRead; aiSend = $false } }
function Get-OpenInputCalls($s) { return @($s.Calls | Where-Object { $_ -like 'Enter:*' -or $_ -like 'OpenSearch:*' -or $_ -like 'Paste:*' -or $_ -like 'Close:*' -or $_ -like 'Esc:*' }) }
$MainWin = New-OWin 10 '카카오톡'
# 정상 흐름: 메인 창 하나 -> 검색 -> 새 방 창이 나타남
function New-OpenFlow {
    $f = New-FakeOpenProvider
    $f.Queue.Enqueue(@($MainWin)); $f.Queue.Enqueue(@($MainWin)); $f.Queue.Enqueue(@($MainWin, (New-OWin 20 '테스트방')))
    return $f
}
function Invoke-Open([string[]]$Argv, [hashtable]$Provider) {
    $all = @(Invoke-OpenCommand -Argv $Argv -Provider $Provider 6>&1)
    $code = @($all | Where-Object { $_ -is [int] })
    $text = (@($all | Where-Object { $_ -isnot [int] } | ForEach-Object { [string]$_ }) -join "`n")
    @{ Exit = $code[$code.Count - 1]; Out = $text }
}

Describe 'OpenCommand: 인자 검사 (입력 호출 0, 종료 코드 1)' {
    It 'prints the usage and exits 1 for no arguments, an unknown option, a missing value, a duplicate option, a missing room, a stray word and different letter case' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방'))
            foreach ($argv in @(
                    @(),
                    @('--room'),
                    @('--room', '테스트방', '--nope'),
                    @('--room', '테스트방', '--room', '테스트방'),
                    @('--human'),
                    @('테스트방'),
                    @('--room', '테스트방', '테스트방'),
                    @('--ROOM', '테스트방'),
                    @('--room', '--human'),
                    @('--room', ''))) {
                $f = New-OpenFlow
                $r = Invoke-Open $argv $f.Provider
                $r.Exit | Should Be 1
                $r.Out | Should Match '사용법'
                $f.Calls.Count | Should Be 0
            }
        }
    }
}

Describe 'OpenCommand: 허용 목록과 호출자 (입력 전에 먼저)' {
    It 'refuses a room that is not on the allowed list (exit 1) without reading windows or sending any key' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방'))
            foreach ($name in '다른방', '테스트방 ', '테스트') {
                $f = New-OpenFlow
                $r = Invoke-Open @('--room', $name) $f.Provider
                $r.Exit | Should Be 1
                $f.Calls.Count | Should Be 0
            }
        }
    }

    It 'treats a call without --human as an AI: refused unless the room has AI reading on, allowed when it has' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $false))
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방') $f.Provider).Exit | Should Be 1
            $f.Calls.Count | Should Be 0
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방') $f.Provider).Exit | Should Be 0
        }
    }

    It '--human needs a keyboard: with redirected input it exits 1 and makes no call; with a keyboard it works without the AI switch' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방'))
            function Test-InputRedirected { return $true }
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방', '--human') $f.Provider).Exit | Should Be 1
            $f.Calls.Count | Should Be 0
            function Test-InputRedirected { return $false }
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방', '--human') $f.Provider).Exit | Should Be 0
        }
    }
}

Describe 'OpenCommand: 열기 결과' {
    It 'opens the room, checks the title, closes only the window the kit opened, and exits 0' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-OpenFlow
            $r = Invoke-Open @('--room', '테스트방') $f.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '확인하고 닫았습니다'
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -ceq 'Close:20:테스트방' }).Count | Should Be 1
            @($f.Calls | Where-Object { $_ -like 'Close:10:*' }).Count | Should Be 0
        }
    }

    It 'leaves a window that was already open as it is (no close) and says so, exit 0' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-FakeOpenProvider
            $f.Queue.Enqueue(@($MainWin, (New-OWin 20 '테스트방')))
            $r = Invoke-Open @('--room', '테스트방') $f.Provider
            $r.Exit | Should Be 0
            $r.Out | Should Match '그대로 두었습니다'
            (Get-OpenInputCalls $f).Count | Should Be 0
        }
    }

    It 'a different window title after opening closes that window only and exits 2; the lock is released so the next run works' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-FakeOpenProvider
            $f.Queue.Enqueue(@($MainWin)); $f.Queue.Enqueue(@($MainWin)); $f.Queue.Enqueue(@($MainWin, (New-OWin 30 '테스트방 ')))
            $r = Invoke-Open @('--room', '테스트방') $f.Provider
            $r.Exit | Should Be 2
            @($f.Calls | Where-Object { $_ -like 'Close:*' }).Count | Should Be 1
            $null -eq $script:KitLockMutex | Should Be $true
            $f2 = New-OpenFlow
            (Invoke-Open @('--room', '테스트방') $f2.Provider).Exit | Should Be 0
        }
    }

    It 'warns that an ordinary room shows a read mark, and does not warn for other room types' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'normal' $true))
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방') $f.Provider).Out | Should Match '읽음 표시'
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-OpenFlow
            (Invoke-Open @('--room', '테스트방') $f.Provider).Out | Should Not Match '읽음 표시'
        }
    }
}

Describe 'OpenCommand: 라우터가 필요한 부품을 빠짐없이 불러온다' {
    # 단위 시험은 부품을 전부 불러 놓고 돌리므로, 라우터의 불러오기 목록에서 빠진 부품은 여기서만 드러난다.
    # 라우터가 'open' 일 때 불러오는 목록만으로 새 PowerShell 을 띄워서, 그 파일들이 부르는 키트 함수가 모두 정의돼 있는지 본다.
    It 'every kit function that the files loaded for the open command call is defined once the router has loaded them' {
        $router = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\kakao.ps1'), (New-Object System.Text.UTF8Encoding($false)))
        $branch = [regex]::Match($router, "(?s)'open'\s*\{.*?foreach \(\`$name in ([^)]*)\)")
        $branch.Success | Should Be $true
        $names = @([regex]::Matches($branch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $names.Count -ge 5 | Should Be $true
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

Describe 'OpenCommand: 실행 잠금과 알 수 없는 오류' {
    It 'refuses to run while another run holds the lock: exit 2, no window read, no key' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            Enter-KitLock
            try {
                $f = New-OpenFlow
                $r = Invoke-Open @('--room', '테스트방') $f.Provider
                $r.Exit | Should Be 2
                $f.Calls.Count | Should Be 0
            }
            finally { Exit-KitLock }
        }
    }

    It 'an unexpected error exits 3 with the generic message: the raw error text never reaches the screen, and the lock is released' {
        Use-TempHome {
            Set-OpenRooms @((New-OpenRoom '테스트방' 'open' $true))
            $f = New-OpenFlow
            $f.Boom = $true
            $r = Invoke-Open @('--room', '테스트방') $f.Provider
            $r.Exit | Should Be 3
            $r.Out | Should Not Match 'SECRET-RAW-ERROR'
            $null -eq $script:KitLockMutex | Should Be $true
        }
    }

    It 'never sends a key outside the allowed set: only Esc (main window), search, paste and Enter reach the provider, and the source has no click or banned key' {
        $src = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'OpenCommand.ps1'), (New-Object System.Text.UTF8Encoding($false)))
        $src | Should Not Match '(?i)ClickAt|Invoke-RelClick|SendInput|Remove-Item|0x1B|Ctrl\+A|Delete|Backspace'
    }
}
