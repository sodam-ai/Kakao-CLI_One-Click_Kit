# 메시지 보내기(M8)의 안전 틀. 이 파일은 "입력이 나가기 전에 거절해야 하는 것"과 "입력이 나간 뒤의 결과 분류"를 맡는다.
# 아직 어떤 명령에도 연결되지 않았다. 실제 제공자는 입력란 위치를 측정하기 전이라 일부러 잠겨 있다(Ready = 거짓): 부르면 입력 0 으로 멈춘다.
# 이 파일은 작업 전체를 감싸는 잠금(Enter-KitLock)을 잡지 않는다. 부르는 쪽(명령 계층, M11)이 잡아야 간격·시도 기록이 프로세스 사이에서 안전하다.
# 필요한 부품: Config(Test-RoomAllowed, Find-Room, Get-KitConfig), Status(Get-KitMode, Assert-SendAllowedByMode), Room, Clip, Guard, Log.
#
# 결과(설계서 13.7): 입력을 보내기 전에 멈추면 예외(종료 코드가 붙은 한글 설명 = "실패"). 입력을 보낸 뒤에는 예외가 아니라
# 결과 객체를 돌려준다: 'confirmed'(보낸 글이 방에 나타난 것을 확인) 또는 'unknown'(입력은 보냈지만 확인 못 함). 'preview'는 -DryRun.
# 불명일 때 자동 재시도는 없다: 같은 글을 다시 보내면 중복 전송이 되기 때문이다.

$script:SendMaxLength = 1000
$script:SendMinIntervalSeconds = 2
$script:SendAttemptKeep = 100
# 붙여넣기(Ctrl+V)와 Enter 를 보낸 뒤 클립보드를 되돌리기 전에 기다리는 시간. 카카오톡이 아직 붙여넣기 전인데 사용자의 원래 클립보드 글로 되돌리면
# 그 글이 대신 전송될 수 있다(위험 R-04). 값(0.8초)은 측정 전 추정이며 실제 시험에서 확인해야 한다.
$script:SendSettleMs = 800

# 실제 부품 묶음. 시험은 이 묶음을 가짜로 바꿔 끼운다(Room.ps1 의 제공자와 같은 방식).
function Get-DefaultSendProvider {
    $ErrorActionPreference = 'Stop'
    return @{
        # 입력란 위치(비례 좌표)를 아직 측정하지 않았으므로 거짓이다. 측정해서 FocusInput 을 구현한 뒤에만 참으로 바꾼다(사용자 승인 필요).
        Ready      = { $false }
        Mode       = { Get-KitMode }
        Now        = { [datetime]::UtcNow }
        OpenRoom   = { param($name, $caller) Open-KakaoRoom -Name $name -Caller $caller -Action 'send' }
        FocusInput = { param($hwnd, $title) throw (New-KitError -Key 'send.notReady' -ExitCode 3) }
        # 블록을 닫지 않는다(클로저 금지): 닫힌 블록은 전역 함수만 보여서 스크립트 안에서 불러온 실제 실행에서 Send-KeyCombo 를 못 찾는다(S5 에서 확인).
        PasteEnter = { param($hwnd, $text, $title)
            $settleMs = $script:SendSettleMs
            Use-TextClipboard -Text $text -Action {
                Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+V' -ExpectedTitle $title
                Send-KeyCombo -Hwnd $hwnd -Keys 'Enter' -ExpectedTitle $title
                Start-Sleep -Milliseconds $settleMs
            } }
        # 보낸 글이 방에 나타났는지 읽어서 확인하는 일은 읽기(M9 내보내기)가 연결된 뒤에 한다. 그전에는 확인하지 못한다(결과 = 불명).
        VerifySent = { param($room, $text, $attemptId) $null }
        CloseRoom  = { param($opened) [void](Close-KitOpenedWindow -Opened $opened) }
    }
}

# 보낼 글 검사: 비어 있지 않고(공백뿐인 글도 거절), 1000자 이하이고, 탭·줄바꿈 말고 보이지 않는 조작 문자가 없을 것.
function Assert-SendTextValid {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt $script:SendMaxLength -or $Text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
        throw (New-KitError -Key 'send.textInvalid' -ExitCode 1)
    }
}

function Get-SendStatePath {
    return [System.IO.Path]::Combine((Get-KitPaths).DataDir, 'state', 'send-state.json')
}

# 마지막 시도 시각과 최근 시도 번호. 파일이 없으면 빈 기록. 있는데 읽을 수 없거나 모양이 틀리면 멈춘다(모르면 보내지 않는다).
function Read-SendState {
    $ErrorActionPreference = 'Stop'
    $path = Get-SendStatePath
    $empty = [pscustomobject]@{ LastAttemptUtc = $null; Attempts = @() }
    if (-not (Test-Path -LiteralPath $path)) { return $empty }
    try {
        $raw = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $json -or $json -isnot [System.Management.Automation.PSCustomObject]) { throw 'shape' }
        $names = @($json.PSObject.Properties.Name)
        if ($names -cnotcontains 'lastAttemptUtc' -or $names -cnotcontains 'attempts') { throw 'shape' }
        $last = $null
        if ($null -ne $json.lastAttemptUtc) {
            if ($json.lastAttemptUtc -isnot [string]) { throw 'shape' }
            $last = [datetime]::Parse($json.lastAttemptUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $last = $last.ToUniversalTime()
        }
        if ($null -ne $json.attempts -and $json.attempts -isnot [System.Array]) { throw 'shape' }
        $ids = @()
        foreach ($a in @($json.attempts)) {
            if ($a -isnot [System.Management.Automation.PSCustomObject] -or $a.id -isnot [string] -or $a.id.Length -eq 0) { throw 'shape' }
            $ids += [string]$a.id
        }
        return [pscustomobject]@{ LastAttemptUtc = $last; Attempts = @($ids) }
    }
    catch { throw (New-KitError -Key 'send.stateUnusable' -FormatArgs @($path) -ExitCode 2) }
}

# 기록을 임시 파일에 쓴 뒤 바꿔치기한다. 쓰지 못하면 멈춘다(기록 없이 보내지 않는다).
function Save-SendState {
    param([Parameter(Mandatory)][datetime]$LastAttemptUtc, [Parameter(Mandatory)][string[]]$Ids)
    $ErrorActionPreference = 'Stop'
    $path = Get-SendStatePath
    try {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $keep = @($Ids | Select-Object -Last $script:SendAttemptKeep)
        $attempts = @($keep | ForEach-Object { [ordered]@{ id = $_ } })
        $doc = [ordered]@{ lastAttemptUtc = $LastAttemptUtc.ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture); attempts = $attempts }
        $json = ConvertTo-Json -InputObject $doc -Depth 4
        $tmp = $path + '.tmp'
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
    }
    catch { throw (New-KitError -Key 'send.stateUnusable' -FormatArgs @($path) -ExitCode 2) }
}

# 한 방에 한 글을 보낸다. 입력이 나가기 전의 모든 검사는 "하나라도 틀리면 입력 0"이다.
#   -DryRun         : 검사만 하고 미리보기 결과를 돌려준다(입력·기록 없음).
#   -Yes            : 실제로 보내는 데 필요한 확인. 없으면 거절한다.
#   -AllowUnverified: 시험 안 한 카카오톡 버전에서도 보내기를 허용한다. 사람만 쓸 수 있다.
#   -AttemptId      : 시도 번호(영문·숫자·밑줄·붙임표 64자 이내). 같은 번호로 다시 보낼 수 없다. 없으면 새로 만든다.
function Send-KakaoMessage {
    param(
        [string]$Room,
        [AllowNull()][AllowEmptyString()][string]$Text,
        [switch]$DryRun,
        [switch]$Yes,
        [ValidateSet('human', 'ai')][string]$Caller = 'human',
        [switch]$AllowUnverified,
        [string]$AttemptId,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultSendProvider }

    try {
        # --- 입력 전의 검사(여기서 멈추면 입력 0) ---
        Assert-SendTextValid -Text $Text
        if ($PSBoundParameters.ContainsKey('AttemptId') -and $AttemptId -cnotmatch '^[A-Za-z0-9_-]{1,64}$') {
            throw (New-KitError -Key 'send.attemptInvalid' -ExitCode 1)
        }
        if (-not [bool](& $Provider.Ready)) { throw (New-KitError -Key 'send.notReady' -ExitCode 3) }
        Assert-SendAllowedByMode -Mode ([string](& $Provider.Mode)) -AllowUnverified:$AllowUnverified -Caller $Caller
        if (-not (Test-RoomAllowed -Name $Room -Action 'send' -Caller $Caller)) {
            throw (New-KitError -Key 'room.notAllowed' -FormatArgs @($Room) -ExitCode 1)
        }
        # 부르는 쪽이 넘긴 글자가 아니라 설정에 저장된 방 이름을 쓴다.
        $title = [string](Find-Room -Config (Get-KitConfig) -Name $Room).name

        if ($DryRun) {
            return [pscustomobject]@{ Status = 'preview'; Sent = $false; Reason = 'dryRun'; AttemptId = $null; Room = $title; Message = $null }
        }
        if (-not $Yes) { throw (New-KitError -Key 'send.confirmRequired' -ExitCode 1) }

        # --- 간격과 시도 번호: 입력 전에 기록한다(입력 뒤에 멈춰도 같은 시도가 반복되지 않게) ---
        $now = ([datetime](& $Provider.Now)).ToUniversalTime()
        $state = Read-SendState
        if ($null -ne $state.LastAttemptUtc) {
            # 시계가 거꾸로 갔으면(차이가 음수) 안전 쪽으로 너무 이르다고 본다.
            if (($now - $state.LastAttemptUtc).TotalSeconds -lt $script:SendMinIntervalSeconds) { throw (New-KitError -Key 'send.tooSoon' -ExitCode 2) }
        }
        $id = if ($PSBoundParameters.ContainsKey('AttemptId')) { $AttemptId } else { [guid]::NewGuid().ToString('N') }
        if ($state.Attempts -ccontains $id) { throw (New-KitError -Key 'send.attemptRepeated' -ExitCode 2) }
        Save-SendState -LastAttemptUtc $now -Ids (@($state.Attempts) + $id)

        # --- 방 열기와 입력 ---
        $opened = & $Provider.OpenRoom $title $Caller
        try {
            # 이미 열려 있던 창에는 보내지 않는다: 입력란에 쓰다 만 글이 있는지 확인할 방법이 없다(설계서 13.2). 그 창은 닫지도 않는다.
            if (-not $opened.OpenedByKit) { throw (New-KitError -Key 'send.alreadyOpen' -ExitCode 2) }
            & $Provider.FocusInput ([long]$opened.Hwnd) $title

            # 여기부터는 입력이 나갔을 수 있다. 중간에 멈춰도 오류가 아니라 '불명'이고 다시 시도하지 않는다.
            try { & $Provider.PasteEnter ([long]$opened.Hwnd) $Text $title }
            catch { return (New-SendResult -Status 'unknown' -Reason 'inputInterrupted' -AttemptId $id -Room $title) }

            # 확인은 "진짜 true 하나"일 때만 확인됨이다. 아무것도 못 돌려주거나 예외가 나거나 true 가 아닌 값(1, 글자 "true", 둘 이상)이면 불명이다.
            $verified = @()
            try { $verified = @(& $Provider.VerifySent $title $Text $id) } catch { $verified = @() }
            if ($verified.Count -eq 1 -and $verified[0] -is [bool] -and $verified[0] -eq $true) {
                return (New-SendResult -Status 'confirmed' -Reason 'verified' -AttemptId $id -Room $title)
            }
            return (New-SendResult -Status 'unknown' -Reason 'notVerified' -AttemptId $id -Room $title)
        }
        finally {
            if ($opened.OpenedByKit) {
                try { & $Provider.CloseRoom $opened } catch { Add-KitWarning -Warning (Get-Msg -Key 'send.closeFailed') }
            }
        }
    }
    catch {
        # 멈춘 이유를 기록한다(본문은 기록하지 않는다). 기록 실패는 Write-KitLog 가 경고로 처리한다.
        $code = if ($_.Exception -is [KakaoKitException]) { $_.Exception.ExitCode } else { 'error' }
        Write-KitLog -Level 'warn' -Command 'send' -Room ([string]$Room) -Result ('stopped exit=' + $code)
        throw
    }
}

# 입력이 나간 뒤의 결과 객체를 만들고 기록한다(본문 없음).
function New-SendResult {
    param([string]$Status, [string]$Reason, [string]$AttemptId, [string]$Room)
    $message = $null
    if ($Status -ceq 'unknown') { $message = Get-Msg -Key 'send.unknownResult' }
    Write-KitLog -Level 'info' -Command 'send' -Room $Room -Result ('{0} id={1}' -f $Status, $AttemptId)
    return [pscustomobject]@{ Status = $Status; Sent = $true; Reason = $Reason; AttemptId = $AttemptId; Room = $Room; Message = $message }
}
