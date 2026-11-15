# 포그라운드(맨 앞 창) 대기: 설계서 13.8. 키트는 카카오톡을 맨 앞으로 가져오지 못하므로, 사람이 창을 한 번 클릭할 때까지 입력 0 으로 기다린다.
# 이 파일은 맨 앞 창을 "읽기만" 한다. 키·클릭·포커스 변경은 하지 않는다(시험이 소스를 검사해 강제한다).
# 규칙: 카카오톡이 2초 연속 맨 앞이면 진행하고, 최대 120초 안에 안 되면 입력 0 으로 멈춘다(종료 코드 2).
# [연결됨, 2026-11-15] 보내기의 입력란 포커스 확인(Send.ps1 의 Confirm-InputFocus)이 창을 키 없이 올려 본 뒤에도 맨 앞이 아닐 때만 이 대기로 넘어온다(마지막 수단).

$script:ForegroundStableMs = 2000
$script:ForegroundMaxWaitMs = 120000
$script:ForegroundPollMs = 200

function Get-DefaultForegroundProvider {
    return @{
        NowMs        = { [long]([System.Diagnostics.Stopwatch]::GetTimestamp() * 1000 / [System.Diagnostics.Stopwatch]::Frequency) }
        Sleep        = { param($ms) Start-Sleep -Milliseconds ([int]$ms) }
        # Guard 와 같은 읽기: 맨 앞 창의 최상위 창 번호. 네이티브 호출은 Win32.ps1 한 곳에만 둔다(시험이 강제).
        IsForeground = { param($hwnd) [long](& (Get-DefaultInputProvider).Foreground) -eq [long]$hwnd }
        Say          = { param($text) Write-Host $text }
    }
}

# 대상 창($Hwnd)이 2초 연속 맨 앞이 될 때까지 기다린다. 성공하면 $true, 시간 안에 안 되면 가드 예외(종료 코드 2).
# 확인이 실패하거나 던지면 그대로 멈춘다(삼키지 않는다). 안내 문구는 기다리기 시작할 때 한 번만 보인다.
function Wait-KakaoForeground {
    param([long]$Hwnd, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultForegroundProvider }
    foreach ($member in 'NowMs', 'Sleep', 'IsForeground', 'Say') {
        if (-not $Provider.ContainsKey($member)) { throw (New-GuardError -Key 'guard.notForeground') }
    }
    if ($Hwnd -le 0) { throw (New-GuardError -Key 'guard.notForeground') }

    $start = [long](& $Provider.NowMs)
    $stableSince = $null
    $said = $false
    while ($true) {
        $now = [long](& $Provider.NowMs)
        $front = [bool](& $Provider.IsForeground $Hwnd)
        if ($front) {
            if ($null -eq $stableSince) { $stableSince = $now }
            if (($now - $stableSince) -ge $script:ForegroundStableMs) { return $true }
        }
        else {
            $stableSince = $null
            if (-not $said) {
                $said = $true
                & $Provider.Say (Get-Msg -Key 'wait.clickKakao' -FormatArgs @([int]($script:ForegroundMaxWaitMs / 1000)))
            }
        }
        if (($now - $start) -ge $script:ForegroundMaxWaitMs) { throw (New-GuardError -Key 'guard.notForeground') }
        & $Provider.Sleep $script:ForegroundPollMs
    }
}
