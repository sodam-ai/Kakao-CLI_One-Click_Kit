# rooms / read / search / status 명령 계층. 카카오톡을 조작하지 않는다(키·클릭 없음): 설정 파일, 보관된 내보내기, 설치 정보를 읽거나 설정을 바꿀 뿐이다.
# 규칙: 호출자는 --human 이 있고 키보드 입력이 막혀 있지 않을 때만 사람이고, 그 밖에는 AI 로 본다(기본이 더 엄격한 쪽).
# 허용 목록 변경(rooms add/remove/set)은 사람만 한다(Config.ps1 의 Assert-HumanPath). 대화 본문과 찾은 낱말은 기록(로그)에 남기지 않는다.

$script:UsageRooms = 'kakao rooms list | add <방> --type open|self|normal [--self-only] --human | remove <방> --human | set <방> <aiRead|aiSend|canSend> <on|off> --human'
$script:UsageRead = 'kakao read <방> [--since 7d|12h] [--last N] [--human]'
$script:UsageSearch = 'kakao search <낱말> [--room <방>] [--human]'
$script:UsageStatus = 'kakao status'
$script:SearchKeywordMax = 200

function Stop-InfoUsage {
    param([string]$Usage)
    $ErrorActionPreference = 'Stop'
    throw (New-KitError -Key 'cmd.argInvalid' -FormatArgs @($Usage) -ExitCode 1)
}

# 인자를 해석한다. 옵션 이름은 대소문자를 구분하고, 모르는 옵션·같은 옵션 두 번·값 없음·값이 --로 시작하면 사용법 오류(종료 코드 1)다.
# 돌려주는 값: Positional(옵션이 아닌 인자들), Values(값을 받는 옵션), Flags(켠 스위치 이름들).
function ConvertFrom-InfoArgv {
    param([string[]]$Argv = @(), [string[]]$ValueOptions = @(), [string[]]$FlagOptions = @(), [string]$Usage)
    $ErrorActionPreference = 'Stop'
    $positional = @()
    $values = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    $flags = @()
    $i = 0
    while ($i -lt $Argv.Count) {
        $a = [string]$Argv[$i]
        if ($a.StartsWith('--', [System.StringComparison]::Ordinal)) {
            if ($a -cin $FlagOptions) {
                if ($flags -ccontains $a) { Stop-InfoUsage -Usage $Usage }
                $flags += $a
                $i += 1
                continue
            }
            if ($a -cin $ValueOptions) {
                if ($values.ContainsKey($a) -or ($i + 1 -ge $Argv.Count)) { Stop-InfoUsage -Usage $Usage }
                $v = [string]$Argv[$i + 1]
                if ($v.StartsWith('--', [System.StringComparison]::Ordinal)) { Stop-InfoUsage -Usage $Usage }
                $values[$a] = $v
                $i += 2
                continue
            }
            Stop-InfoUsage -Usage $Usage
        }
        $positional += $a
        $i += 1
    }
    return @{ Positional = $positional; Values = $values; Flags = $flags }
}

# --human 이고 키보드 입력이 막혀 있지 않을 때만 사람이다. 아니면 사람 전용 작업은 멈춘다(Assert-HumanPath).
function Resolve-InfoCaller {
    param([bool]$Human)
    if ($Human) {
        Assert-HumanPath -Human
        return 'human'
    }
    return 'ai'
}

# 화면에 내기 전에 터미널 제어 문자와 글자 방향 조작 문자를 뺀다(탭·줄바꿈은 둔다).
function ConvertTo-SafeDisplay {
    param([AllowNull()][string]$Text)
    return [regex]::Replace([string]$Text, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F‪-‮⁦-⁩]', '')
}

function Write-InfoWarnings {
    foreach ($w in @(Get-KitWarnings)) { Write-Host $w }
    Clear-KitWarnings
}

# 명령 본문을 실행하고 종료 코드를 돌려준다. 키트 예외는 그 한글 문구와 종료 코드로, 알 수 없는 오류는 원문 없이 한 문장으로 보인다.
function Invoke-InfoGuarded {
    param([string]$Name, [scriptblock]$Body)
    $ErrorActionPreference = 'Stop'
    Clear-KitWarnings
    try {
        $out = @(& $Body)
        Write-InfoWarnings
        return [int]$out[$out.Count - 1]
    }
    catch [KakaoKitException] {
        Write-InfoWarnings
        Write-Host $_.Exception.Message
        Write-KitLog -Level 'warn' -Command $Name -Result ('stopped exit=' + $_.Exception.ExitCode)
        return [int]$_.Exception.ExitCode
    }
    catch {
        Write-InfoWarnings
        Write-Host (Get-Msg -Key 'error.unexpectedInfo')
        Write-KitLog -Level 'error' -Command $Name -Result 'stopped exit=error'
        return 3
    }
}

function Format-MessageLine {
    param($Message)
    $ts = if ($null -ne $Message.Timestamp) { ([datetime]$Message.Timestamp).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) } else { '?' }
    return ('[{0}] {1}: {2}' -f $ts, (ConvertTo-SafeDisplay $Message.Sender), (ConvertTo-SafeDisplay $Message.Text))
}

function Invoke-RoomsCommand {
    param([string[]]$Argv = @())
    $ErrorActionPreference = 'Stop'
    return (Invoke-InfoGuarded -Name 'rooms' -Body {
            $usage = $script:UsageRooms
            if ($Argv.Count -eq 0) { Stop-InfoUsage -Usage $usage }
            $rest = @($Argv | Select-Object -Skip 1)
            switch -CaseSensitive ([string]$Argv[0]) {
                'list' {
                    $o = ConvertFrom-InfoArgv -Argv $rest -Usage $usage
                    if ($o.Positional.Count -ne 0) { Stop-InfoUsage -Usage $usage }
                    $rooms = @(Get-ConfigRooms -Config (Get-KitConfig))
                    if ($rooms.Count -eq 0) { Write-Host (Get-Msg -Key 'rooms.empty'); return 0 }
                    Write-Host (Get-Msg -Key 'rooms.listHeader')
                    $yes = Get-Msg -Key 'report.yes'
                    $no = Get-Msg -Key 'report.no'
                    foreach ($r in $rooms) {
                        $cells = @((ConvertTo-SafeDisplay $r.name), (ConvertTo-SafeDisplay $r.type)) + @($r.canRead, $r.aiRead, $r.canSend, $r.aiSend | ForEach-Object { if (Test-RoomFlag $_) { $yes } else { $no } })
                        Write-Host ($cells -join ' | ')
                    }
                    return 0
                }
                'add' {
                    $o = ConvertFrom-InfoArgv -Argv $rest -ValueOptions @('--type') -FlagOptions @('--self-only', '--human') -Usage $usage
                    if ($o.Positional.Count -ne 1 -or -not $o.Values.ContainsKey('--type')) { Stop-InfoUsage -Usage $usage }
                    Add-AllowedRoom -Name $o.Positional[0] -Type $o.Values['--type'] -SelfOnly ([bool]($o.Flags -ccontains '--self-only')) -Human:([bool]($o.Flags -ccontains '--human'))
                    Write-Host (Get-Msg -Key 'rooms.added' -FormatArgs @(ConvertTo-SafeDisplay $o.Positional[0]))
                    Write-Host (Get-Msg -Key 'rooms.addNote')
                    return 0
                }
                'remove' {
                    $o = ConvertFrom-InfoArgv -Argv $rest -FlagOptions @('--human') -Usage $usage
                    if ($o.Positional.Count -ne 1) { Stop-InfoUsage -Usage $usage }
                    Remove-AllowedRoom -Name $o.Positional[0] -Human:([bool]($o.Flags -ccontains '--human'))
                    Write-Host (Get-Msg -Key 'rooms.removed' -FormatArgs @(ConvertTo-SafeDisplay $o.Positional[0]))
                    return 0
                }
                'set' {
                    $o = ConvertFrom-InfoArgv -Argv $rest -FlagOptions @('--human') -Usage $usage
                    if ($o.Positional.Count -ne 3 -or $o.Positional[2] -cnotin 'on', 'off') { Stop-InfoUsage -Usage $usage }
                    Set-RoomPermission -Name $o.Positional[0] -Permission $o.Positional[1] -Value ($o.Positional[2] -ceq 'on') -Human:([bool]($o.Flags -ccontains '--human'))
                    Write-Host (Get-Msg -Key 'rooms.permissionSet' -FormatArgs @(ConvertTo-SafeDisplay $o.Positional[0]))
                    return 0
                }
                default { Stop-InfoUsage -Usage $usage }
            }
        })
}

function Invoke-ReadCommand {
    param([string[]]$Argv = @(), [datetime]$Now = (Get-Date))
    $ErrorActionPreference = 'Stop'
    return (Invoke-InfoGuarded -Name 'read' -Body {
            $usage = $script:UsageRead
            $o = ConvertFrom-InfoArgv -Argv $Argv -ValueOptions @('--since', '--last') -FlagOptions @('--human') -Usage $usage
            if ($o.Positional.Count -ne 1) { Stop-InfoUsage -Usage $usage }
            $params = @{ Room = [string]$o.Positional[0]; Now = $Now }
            if ($o.Values.ContainsKey('--last')) {
                if ($o.Values['--last'] -cnotmatch '\A[1-9][0-9]{0,5}\z') { Stop-InfoUsage -Usage $usage }
                $params.Last = [int]$o.Values['--last']
            }
            if ($o.Values.ContainsKey('--since')) {
                $m = [regex]::Match($o.Values['--since'], '\A(?<n>[1-9][0-9]{0,3})(?<u>[dh])\z')
                if (-not $m.Success) { Stop-InfoUsage -Usage $usage }
                $n = [int]$m.Groups['n'].Value
                $params.Since = if ($m.Groups['u'].Value -ceq 'd') { [timespan]::FromDays($n) } else { [timespan]::FromHours($n) }
            }
            $params.Caller = Resolve-InfoCaller -Human ([bool]($o.Flags -ccontains '--human'))
            $messages = @(Read-KakaoRoom @params)
            if ($messages.Count -eq 0) { Write-Host (Get-Msg -Key 'read.none') }
            foreach ($m in $messages) { Write-Host (Format-MessageLine $m) }
            Write-KitLog -Level 'info' -Command 'read' -Room $params.Room -Result ('count=' + $messages.Count)
            return 0
        })
}

function Invoke-SearchCommand {
    param([string[]]$Argv = @())
    $ErrorActionPreference = 'Stop'
    return (Invoke-InfoGuarded -Name 'search' -Body {
            $usage = $script:UsageSearch
            $o = ConvertFrom-InfoArgv -Argv $Argv -ValueOptions @('--room') -FlagOptions @('--human') -Usage $usage
            if ($o.Positional.Count -ne 1 -or ([string]$o.Positional[0]).Length -gt $script:SearchKeywordMax) { Stop-InfoUsage -Usage $usage }
            $params = @{ Keyword = [string]$o.Positional[0] }
            if ($o.Values.ContainsKey('--room')) { $params.Room = $o.Values['--room'] }
            $params.Caller = Resolve-InfoCaller -Human ([bool]($o.Flags -ccontains '--human'))
            $found = @(Search-KakaoExports @params)
            if ($found.Count -eq 0) { Write-Host (Get-Msg -Key 'search.none') }
            foreach ($f in $found) { Write-Host ('[' + (ConvertTo-SafeDisplay $f.Room) + '] ' + (Format-MessageLine $f)) }
            # 찾은 낱말은 기록하지 않는다(개수만).
            Write-KitLog -Level 'info' -Command 'search' -Result ('count=' + $found.Count)
            return 0
        })
}

# 환경 점검(최소판): 읽기만 한다. 로그인 확인·모니터/DPI·최근 오류는 10단계에서 덧붙인다.
function Invoke-StatusCommand {
    param([string[]]$Argv = @(), [hashtable]$InstallProvider, [string[]]$VerifiedList, [hashtable]$SendProvider)
    $ErrorActionPreference = 'Stop'
    return (Invoke-InfoGuarded -Name 'status' -Body {
            if ($Argv.Count -ne 0) { Stop-InfoUsage -Usage $script:UsageStatus }
            $infoArgs = @{}
            if ($null -ne $InstallProvider) { $infoArgs.Provider = $InstallProvider }
            $modeArgs = @{} + $infoArgs
            if ($null -ne $VerifiedList) { $modeArgs.VerifiedList = $VerifiedList }
            $info = Get-KakaoInstallInfo @infoArgs
            $mode = Get-KitMode @modeArgs
            $send = if ($null -ne $SendProvider) { $SendProvider } else { Get-DefaultSendProvider }

            Write-Host (Get-Msg -Key 'report.kit' -FormatArgs @(Get-KitVersion))
            if ($info.Installed) {
                $v = if ($null -ne $info.Version) { $info.Version } else { Get-Msg -Key 'report.unknown' }
                Write-Host (Get-Msg -Key 'report.kakao' -FormatArgs @($v))
            }
            else { Write-Host (Get-Msg -Key 'status.notInstalled') }
            Write-Host (Get-Msg -Key 'status.running' -FormatArgs @($(if ($info.Running) { Get-Msg -Key 'report.yes' } else { Get-Msg -Key 'report.no' })))
            Write-Host (Get-Msg -Key $(if ($mode -ceq 'full') { 'status.mode.full' } else { 'status.mode.readonly' }))

            $names = @(Get-ConfigRooms -Config (Get-KitConfig) | ForEach-Object { [string]$_.name })
            $aiRead = @($names | Where-Object { Test-RoomAllowed -Name $_ -Action 'read' -Caller 'ai' }).Count
            $aiSend = @($names | Where-Object { Test-RoomAllowed -Name $_ -Action 'send' -Caller 'ai' }).Count
            Write-Host (Get-Msg -Key 'status.rooms' -FormatArgs @($names.Count))
            Write-Host (Get-Msg -Key 'status.aiRead' -FormatArgs @($aiRead))
            Write-Host (Get-Msg -Key 'status.aiSend' -FormatArgs @($aiSend))
            if (-not [bool](& $send.Ready)) { Write-Host (Get-Msg -Key 'status.sendLocked') }
            return 0
        })
}
