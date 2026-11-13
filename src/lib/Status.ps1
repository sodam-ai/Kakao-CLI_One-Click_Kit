# 카카오톡 설치·버전 정보(최소판). 읽기만 한다: 레지스트리 값과 실행 중인 프로세스를 읽을 뿐 아무것도 쓰거나 누르거나 열지 않는다.
# 보내기 잠금(Get-KitMode·Test-SendAllowedByMode·Assert-SendAllowedByMode)은 M8 보다 먼저 여기에 있다. M10 이 로그인 상태와 전체 점검을 덧붙인다.

# 실제 읽기 동작을 모은 제공자. 시험은 이 해시테이블을 가짜로 바꿔 끼운다(Guard.ps1 의 제공자 방식과 같은 생각).
#   RegistryVersion : 버전 글자를 돌려준다. 어디에도 없으면 $null. 읽다가 실패하면 예외를 던진다.
#   Processes       : 실행 중인 KakaoTalk 프로세스마다 @{ Version; ExePath } 를 돌려준다. 못 읽은 값은 $null.
function Get-KakaoInstallProvider {
    return @{
        RegistryVersion = {
            # 확인된 위치는 첫 번째(32비트 설치 정보)뿐이다. 나머지 둘은 없을 때를 위한 보험이며 이 PC 에는 없다.
            $keys = @(
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\KakaoTalk',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KakaoTalk',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KakaoTalk'
            )
            foreach ($key in $keys) {
                if (-not (Test-Path -LiteralPath $key)) { continue }
                $value = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).DisplayVersion
                if (-not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
            }
            return $null
        }
        Processes = {
            @(Get-Process -Name 'KakaoTalk' -ErrorAction SilentlyContinue | ForEach-Object {
                    $version = $null
                    $path = $null
                    # 권한이 없거나 프로세스가 막 끝났으면 못 읽는다. 못 읽은 값은 $null 로 두고 호출자가 "확인 불가"로 처리한다.
                    try { $version = $_.MainModule.FileVersionInfo.FileVersion; $path = $_.MainModule.FileName } catch { }
                    @{ Version = $version; ExePath = $path }
                })
        }
    }
}

# 돌려주는 값: Installed, Version, Source, Running, ExePath.
# Version 은 믿을 수 있을 때만 글자이고, 확인이 안 되면 $null 이다(= 검증 안 됨 취급).
# Source: registry | registry+process | process | mismatch | none | error. error 일 때 Running 은 믿지 말 것.
function Get-KakaoInstallInfo {
    param([hashtable]$Provider = (Get-KakaoInstallProvider))
    $ErrorActionPreference = 'Stop'

    try {
        $registryVersion = & $Provider.RegistryVersion
        $processes = @(& $Provider.Processes)
    }
    catch {
        return [pscustomobject]@{ Installed = $false; Version = $null; Source = 'error'; Running = $false; ExePath = $null }
    }

    $registryVersion = if ([string]::IsNullOrWhiteSpace([string]$registryVersion)) { $null } else { [string]$registryVersion }

    if ($processes.Count -eq 0) {
        if ($null -eq $registryVersion) {
            return [pscustomobject]@{ Installed = $false; Version = $null; Source = 'none'; Running = $false; ExePath = $null }
        }
        return [pscustomobject]@{ Installed = $true; Version = $registryVersion; Source = 'registry'; Running = $false; ExePath = $null }
    }

    # 실행 중이다. 실행 파일이 실제로 가진 버전과 레지스트리 값을 대조한다.
    $exePath = $null
    foreach ($p in $processes) {
        if (-not $exePath -and -not [string]::IsNullOrWhiteSpace([string]$p.ExePath)) { $exePath = [string]$p.ExePath }
    }
    $processVersion = [string]$processes[0].Version
    $unreadable = $false
    $disagree = $false
    foreach ($p in $processes) {
        $v = [string]$p.Version
        if ([string]::IsNullOrWhiteSpace($v)) { $unreadable = $true }
        elseif (-not [string]::Equals($v, $processVersion, [System.StringComparison]::Ordinal)) { $disagree = $true }
    }

    if ($unreadable) {
        return [pscustomobject]@{ Installed = $true; Version = $null; Source = 'error'; Running = $true; ExePath = $exePath }
    }
    if ($disagree) {
        return [pscustomobject]@{ Installed = $true; Version = $null; Source = 'mismatch'; Running = $true; ExePath = $exePath }
    }
    if ($null -eq $registryVersion) {
        return [pscustomobject]@{ Installed = $true; Version = $processVersion; Source = 'process'; Running = $true; ExePath = $exePath }
    }
    if (-not [string]::Equals($registryVersion, $processVersion, [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ Installed = $true; Version = $null; Source = 'mismatch'; Running = $true; ExePath = $exePath }
    }
    return [pscustomobject]@{ Installed = $true; Version = $registryVersion; Source = 'registry+process'; Running = $true; ExePath = $exePath }
}

# 동작 모드: 설치된(실행 중이면 실행 파일과 대조한) 버전이 시험해 본 목록에 있으면 'full', 아니면 'readonly'.
# 설치 안 됨·읽기 실패·레지스트리와 프로세스 불일치·목록 비어 있음/읽기 실패는 전부 'readonly'(모르면 잠금).
function Get-KitMode {
    param([hashtable]$Provider, [string[]]$VerifiedList)
    $ErrorActionPreference = 'Stop'

    $info = if ($PSBoundParameters.ContainsKey('Provider')) { Get-KakaoInstallInfo -Provider $Provider } else { Get-KakaoInstallInfo }
    $verified = if ($PSBoundParameters.ContainsKey('VerifiedList')) {
        Test-KakaoVersionVerified -Version $info.Version -VerifiedList $VerifiedList
    }
    else {
        Test-KakaoVersionVerified -Version $info.Version
    }
    if ($verified) { return 'full' }
    return 'readonly'
}

# 이 모드에서 보내기가 허용되는가. 'full' 이면 허용. 'readonly' 는 사람이 -AllowUnverified 를 직접 줬을 때만 허용하고
# AI 호출자는 그 스위치로도 풀 수 없다. 'full'·'readonly' 가 아닌 값(null·빈 값·대소문자나 공백이 다른 값)은 모두 잠금이다.
# -Caller 를 사람/AI 중 어느 쪽으로 넘길지는 명령 계층(M11)이 정한다: 입력이 리다이렉트된 호출은 AI 로 취급한다.
function Test-SendAllowedByMode {
    param(
        [AllowNull()][AllowEmptyString()][string]$Mode,
        [switch]$AllowUnverified,
        [ValidateSet('human', 'ai')][string]$Caller = 'human'
    )
    $ErrorActionPreference = 'Stop'

    if ([string]::Equals($Mode, 'full', [System.StringComparison]::Ordinal)) { return $true }
    if ([string]::Equals($Mode, 'readonly', [System.StringComparison]::Ordinal) -and $AllowUnverified -and $Caller -eq 'human') { return $true }
    return $false
}

# 허용이 아니면 종료 코드 4 로 멈춘다(입력을 보내기 전에 호출할 것).
function Assert-SendAllowedByMode {
    param(
        [AllowNull()][AllowEmptyString()][string]$Mode,
        [switch]$AllowUnverified,
        [ValidateSet('human', 'ai')][string]$Caller = 'human'
    )
    $ErrorActionPreference = 'Stop'

    if (-not (Test-SendAllowedByMode -Mode $Mode -AllowUnverified:$AllowUnverified -Caller $Caller)) {
        throw (New-KitError -Key 'error.sendLocked' -ExitCode 4)
    }
}

# 이 버전이 "실제로 시험해 본 버전 목록"에 글자 그대로 있는가. 모르면(없음·비어 있음·목록을 못 읽음) $false — 안전 쪽.
function Test-KakaoVersionVerified {
    param([AllowNull()][AllowEmptyString()][string]$Version, [string[]]$VerifiedList)
    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($Version)) { return $false }
    try {
        $list = if ($PSBoundParameters.ContainsKey('VerifiedList')) { @($VerifiedList) } else { @(Get-VerifiedKakaoVersions) }
    }
    catch { return $false }
    foreach ($item in $list) {
        if ($item -is [string] -and [string]::Equals($item, $Version, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}
