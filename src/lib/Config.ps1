# 설정 파일(config.json): 허용 목록, 방별 권한, 사용 동의.
# 허용 목록 변경·동의는 사람만 할 수 있다: -Human 스위치 + 키보드 입력이 막혀 있지 않을 것.

# 시험이 가짜로 바꿀 수 있게 얇은 함수로 분리했다.
function Test-InputRedirected { return [Console]::IsInputRedirected }

function Assert-HumanPath {
    param([switch]$Human)
    $ErrorActionPreference = 'Stop'
    if (-not $Human) { throw (New-KitError -Key 'error.humanOnly' -ExitCode 1) }
    if (Test-InputRedirected) { throw (New-KitError -Key 'error.humanNeedsConsole' -ExitCode 1) }
}

function Get-KitConfig {
    $ErrorActionPreference = 'Stop'
    $file = (Get-KitPaths).ConfigFile
    if (-not (Test-Path -LiteralPath $file)) {
        return [pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = @() }
    }
    try {
        $text = [System.IO.File]::ReadAllText($file, (New-Object System.Text.UTF8Encoding($false)))
        $cfg = $text | ConvertFrom-Json
        # -is [pscustomobject] 는 숫자·글자에도 참이라 쓸 수 없다. 정확한 타입 이름으로 "JSON 객체"인지 확인한다.
        if ($null -eq $cfg -or $cfg.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { throw 'not an object' }
    }
    catch { throw (New-KitError -Key 'error.configCorrupt' -FormatArgs @($file) -ExitCode 3) }
    return $cfg
}

function Save-KitConfig {
    param([Parameter(Mandatory)]$Config)
    $ErrorActionPreference = 'Stop'
    $paths = Get-KitPaths
    $tmp = $paths.ConfigFile + '.tmp'
    try {
        if (-not (Test-Path -LiteralPath $paths.DataDir)) { New-Item -ItemType Directory -Path $paths.DataDir -Force | Out-Null }
        $json = ConvertTo-Json -InputObject $Config -Depth 5
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $paths.ConfigFile -Force
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw (New-KitError -Key 'error.configSaveFailed' -FormatArgs @($paths.ConfigFile) -ExitCode 3)
    }
}

function Get-ConfigRooms {
    param([Parameter(Mandatory)]$Config)
    return @($Config.rooms | Where-Object { $null -ne $_ })
}

function Set-ConfigRooms {
    param([Parameter(Mandatory)]$Config, [object[]]$Rooms = @())
    $Config | Add-Member -NotePropertyName rooms -NotePropertyValue @($Rooms) -Force
}

# 방 이름은 글자 그대로(Ordinal) 비교한다. PowerShell 5.1 의 -ceq 는 문화권 비교라
# 너비 0 글자·소프트 하이픈·BOM 이 끼어 있어도 같은 이름으로 보기 때문에 쓰지 않는다.
function Test-SameRoomName {
    param($A, $B)
    return [string]::Equals([string]$A, [string]$B, [System.StringComparison]::Ordinal)
}

# 이름이 정확히 하나만 맞을 때만 돌려준다(없거나 중복이면 $null). 대소문자 구분.
function Find-Room {
    param([Parameter(Mandatory)]$Config, [string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    $hits = @(Get-ConfigRooms -Config $Config | Where-Object { Test-SameRoomName $_.name $Name })
    if ($hits.Count -ne 1) { return $null }
    return $hits[0]
}

function Assert-RoomNameValid {
    param([string]$Name)
    $ErrorActionPreference = 'Stop'
    # 보이지 않는 글자(제어 문자 Cc, 너비 0·방향 바꾸기 같은 서식 문자 Cf, 줄·문단 구분자)와 너무 긴 이름은 거부한다.
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ne $Name.Trim() -or $Name.Length -gt 100 -or $Name -match '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]') {
        throw (New-KitError -Key 'error.roomNameInvalid' -ExitCode 1)
    }
}

function Add-AllowedRoom {
    param(
        [string]$Name,
        [string]$Type,
        [Parameter(Mandatory)][bool]$SelfOnly,
        [switch]$Human
    )
    $ErrorActionPreference = 'Stop'
    Assert-HumanPath -Human:$Human
    Assert-RoomNameValid -Name $Name
    if ($Type -cnotin 'open', 'self', 'normal') { throw (New-KitError -Key 'error.roomTypeInvalid' -FormatArgs @($Type) -ExitCode 1) }
    $cfg = Get-KitConfig
    if (Find-Room -Config $cfg -Name $Name) { throw (New-KitError -Key 'error.roomExists' -FormatArgs @($Name) -ExitCode 1) }
    $verified = ($Type -ne 'normal')
    $room = [pscustomobject]@{
        name     = $Name
        type     = $Type
        verified = $verified
        canRead  = $true
        canSend  = $verified
        selfOnly = $SelfOnly
        aiRead   = $false
        aiSend   = $false
    }
    Set-ConfigRooms -Config $cfg -Rooms (@(Get-ConfigRooms -Config $cfg) + $room)
    Save-KitConfig -Config $cfg
}

function Remove-AllowedRoom {
    param([string]$Name, [switch]$Human)
    $ErrorActionPreference = 'Stop'
    Assert-HumanPath -Human:$Human
    $cfg = Get-KitConfig
    # 손으로 고쳐 같은 이름이 둘이 된 경우에도 지울 수 있어야 한다(지우는 것은 권한을 줄이는 방향이라 안전하다).
    $same = @(Get-ConfigRooms -Config $cfg | Where-Object { Test-SameRoomName $_.name $Name })
    if ([string]::IsNullOrEmpty($Name) -or $same.Count -eq 0) { throw (New-KitError -Key 'error.roomNotFound' -FormatArgs @($Name) -ExitCode 1) }
    Set-ConfigRooms -Config $cfg -Rooms @(Get-ConfigRooms -Config $cfg | Where-Object { -not (Test-SameRoomName $_.name $Name) })
    Save-KitConfig -Config $cfg
}

function Set-RoomPermission {
    param(
        [string]$Name,
        [string]$Permission,
        [Parameter(Mandatory)][bool]$Value,
        [switch]$Human
    )
    $ErrorActionPreference = 'Stop'
    Assert-HumanPath -Human:$Human
    if ($Permission -cnotin 'aiRead', 'aiSend', 'canSend') { throw (New-KitError -Key 'error.permissionInvalid' -FormatArgs @($Permission) -ExitCode 1) }
    $cfg = Get-KitConfig
    $room = Find-Room -Config $cfg -Name $Name
    if (-not $room) { throw (New-KitError -Key 'error.roomNotFound' -FormatArgs @($Name) -ExitCode 1) }
    $room | Add-Member -NotePropertyName $Permission -NotePropertyValue $Value -Force
    Save-KitConfig -Config $cfg
}

# 권한 값은 JSON 의 진짜 true 일 때만 켜진 것으로 본다. 손으로 고친 "true"(글자)·1(숫자)·[true](배열) 같은 값은 모두 꺼진 것으로 취급한다.
# (PowerShell 에서 "true" -ne $true 는 거짓이라 글자 "true" 가 통과해 버리는 함정이 있었다)
function Test-RoomFlag {
    param($Value)
    return (($Value -is [bool]) -and ($Value -eq $true))
}

# 허용 목록에 정확히 있는 방만 $true. 모르는 동작·호출자는 전부 $false(안전 쪽으로 닫힘).
function Test-RoomAllowed {
    param(
        [string]$Name,
        [string]$Action,
        [string]$Caller = 'human',
        [switch]$AllowUnverifiedRoom
    )
    if ($Caller -cne 'human' -and $Caller -cne 'ai') { return $false }
    $room = Find-Room -Config (Get-KitConfig) -Name $Name
    if (-not $room) { return $false }
    switch -CaseSensitive ($Action) {
        'read' {
            if (-not (Test-RoomFlag $room.canRead)) { return $false }
            if ($Caller -ceq 'ai' -and -not (Test-RoomFlag $room.aiRead)) { return $false }
            return $true
        }
        'send' {
            if (-not (Test-RoomFlag $room.canSend)) { return $false }
            if (-not (Test-RoomFlag $room.verified)) {
                # 미검증 유형(친구 방)은 사람이 -AllowUnverifiedRoom 으로 풀어야만 보낼 수 있고, AI는 풀 수 없다.
                if ($Caller -ceq 'ai' -or -not $AllowUnverifiedRoom) { return $false }
            }
            if ($Caller -ceq 'ai' -and -not (Test-RoomFlag $room.aiSend)) { return $false }
            return $true
        }
        default { return $false }
    }
}

function Set-KitConsent {
    param([switch]$Human)
    $ErrorActionPreference = 'Stop'
    Assert-HumanPath -Human:$Human
    $cfg = Get-KitConfig
    $cfg | Add-Member -NotePropertyName consentAcceptedAt -NotePropertyValue ((Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')) -Force
    Save-KitConfig -Config $cfg
}

# 동의는 키트가 적는 날짜 글자(yyyy-MM-ddTHH:mm:ss)일 때만 인정한다. 손으로 고친 false·0·"no" 는 글자로 바꾸면
# 비어 있지 않아 통과해 버리므로 "비어 있지 않음"으로 판단하지 않는다.
function Test-KitConsent {
    $value = (Get-KitConfig).consentAcceptedAt
    if ($value -is [datetime]) { return $true }
    if ($value -isnot [string]) { return $false }
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact($value, 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
}

function Assert-KitReady {
    $ErrorActionPreference = 'Stop'
    if (-not (Test-KitConsent)) { throw (New-KitError -Key 'error.consentRequired' -ExitCode 1) }
}

# 검증된(실제로 시험해 본) 카카오톡 버전 목록. 파일이 없으면 빈 목록(= 읽기 전용 모드).
function Get-VerifiedKakaoVersions {
    $file = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\config\verified-versions.json'))
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $json = [System.IO.File]::ReadAllText($file, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
    return @($json.verified)
}
