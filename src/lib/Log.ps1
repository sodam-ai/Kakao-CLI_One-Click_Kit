# 기록(로그)과 오류 보고서. 대화 본문은 절대 기록하지 않는다: Write-KitLog 에는 본문을 받는 매개변수가 아예 없다.

$script:KitWarnings = @()

# 상태 화면(status)에 보여줄 경고 모음. 같은 경고는 한 번만 담는다.
function Add-KitWarning {
    param([Parameter(Mandatory)][string]$Warning)
    if ($script:KitWarnings -cnotcontains $Warning) { $script:KitWarnings += $Warning }
}
function Get-KitWarnings { return @($script:KitWarnings) }
function Clear-KitWarnings { $script:KitWarnings = @() }

# 한 줄을 깨뜨리는 문자(줄바꿈, 구분자 |)를 없애고 길이를 자른다. 긴 글이 통째로 남지 않게 하는 안전망.
function ConvertTo-LogField {
    param([string]$Value, [int]$Max = 120)
    $s = ($Value -replace '[\r\n|]+', ' ').Trim()
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max) }
    if ($s.Length -eq 0) { $s = '-' }
    return $s
}

# 1MB를 넘으면 kakao.log -> .1 -> .2 -> .3 으로 밀고 가장 오래된 것은 지운다.
function Invoke-KitLogRotation {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ((Get-Item -LiteralPath $Path).Length -le 1048576) { return }
    if (Test-Path -LiteralPath ($Path + '.3')) { Remove-Item -LiteralPath ($Path + '.3') -Force }
    foreach ($n in 2, 1) {
        $from = $Path + '.' + $n
        if (Test-Path -LiteralPath $from) { Move-Item -LiteralPath $from -Destination ($Path + '.' + ($n + 1)) -Force }
    }
    Move-Item -LiteralPath $Path -Destination ($Path + '.1') -Force
}

function Write-KitLog {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Command,
        [string]$Room = '-',
        [Parameter(Mandatory)][string]$Result
    )
    $ErrorActionPreference = 'Stop'
    if ($Level -cnotin 'info', 'warn', 'error') { throw ('Unknown log level: ' + $Level) }
    try {
        $dir = (Get-KitPaths).LogsDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir 'kakao.log'
        Invoke-KitLogRotation -Path $file
        $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        $line = '{0} | {1} | {2} | {3} | {4}' -f $time, $Level, (ConvertTo-LogField $Command), (ConvertTo-LogField $Room), (ConvertTo-LogField $Result)
        [System.IO.File]::AppendAllText($file, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    catch { Add-KitWarning -Warning (Get-Msg -Key 'warn.logFailed') }
}

# 환경 정보 + 최근 기록 50줄. 사용자가 복사해서 개발자에게 보여주는 용도라 대화 내용이 들어갈 길이 없다.
function New-KitErrorReport {
    $kakao = Get-Msg -Key 'report.unknown'
    if (Get-Command Get-KakaoInstallInfo -ErrorAction SilentlyContinue) {
        try {
            $info = Get-KakaoInstallInfo
            if ($info -and $info.Version) { $kakao = [string]$info.Version }
        }
        catch { }
    }
    $yesNo = Get-Msg -Key 'report.no'
    if (Test-KitElevated) { $yesNo = Get-Msg -Key 'report.yes' }
    $logFile = Join-Path (Get-KitPaths).LogsDir 'kakao.log'
    $tail = @()
    if (Test-Path -LiteralPath $logFile) { $tail = @([System.IO.File]::ReadAllLines($logFile) | Select-Object -Last 50) }
    $lines = @(
        (Get-Msg -Key 'report.title'),
        (Get-Msg -Key 'report.kit' -FormatArgs @(Get-KitVersion)),
        (Get-Msg -Key 'report.kakao' -FormatArgs @($kakao)),
        (Get-Msg -Key 'report.os' -FormatArgs @([System.Environment]::OSVersion.VersionString)),
        (Get-Msg -Key 'report.ps' -FormatArgs @($PSVersionTable.PSVersion.ToString())),
        (Get-Msg -Key 'report.elevated' -FormatArgs @($yesNo)),
        (Get-Msg -Key 'report.recentLog')
    ) + $tail
    return ($lines -join "`r`n")
}
