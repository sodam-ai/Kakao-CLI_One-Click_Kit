# 메시지 보내기(M8)의 안전 틀. 이 파일은 "입력이 나가기 전에 거절해야 하는 것"과 "입력이 나간 뒤의 결과 분류"를 맡는다.
# 실제 제공자는 일부러 잠겨 있다: Ready 는 "VerifySent 구현"과 "사람 승인"이 모두 참일 때만 참이고 지금은 둘 다 거짓이라, 부르면 입력 0 으로 멈춘다(종료 코드 3).
# 이 파일은 작업 전체를 감싸는 잠금(Enter-KitLock)을 잡지 않는다. 부르는 쪽(명령 계층, M11)이 잡아야 하고, 잡지 않았으면 여기서 거절한다
# (간격·시도 기록의 읽기와 쓰기가 한 덩어리로 안전하려면 한 번에 하나의 실행만 있어야 한다).
# 필요한 부품: Config(Test-RoomAllowed, Find-Room, Get-KitConfig), Status(Get-KitMode, Assert-SendAllowedByMode), Room, Clip, Guard, Log.
#
# 결과(설계서 13.7): 키가 나가기 전에 멈추면 예외(종료 코드가 붙은 한글 설명 = "실패"). 키가 나간 뒤에는 예외가 아니라
# 결과 객체를 돌려준다: 'confirmed'(보낸 글이 방에 나타난 것을 확인) 또는 'unknown'(입력은 보냈지만 확인 못 함). 'preview'는 -DryRun.
# 불명일 때 자동 재시도는 없다: 같은 글을 다시 보내면 중복 전송이 되기 때문이다.
#
# 풀기 전의 관문(Ready 를 참으로 바꾸기 전에 실제 카카오톡으로 확인해야 하는 것, 모두 미확인):
#   (1) 시험 완료(2026-11-15, 5342): 키트가 Enter 로 연 방 창은 입력란이 이미 키보드 포커스를 갖고 있다. 그래서 좌표 클릭 없이 UI 자동화로 포커스를 읽어 확인한다(Confirm-InputFocus).
#       이 확인의 실제 카카오톡 시험은 열기→보내기→확인→닫기 끝까지 시험(④) 때 한다.
#   (2) 시험 완료(2026-11-14, 5342): 방 창을 닫았다 열어도 쓰다 만 글(초안)이 남는다. 그래서 위의 "입력란이 비었다는 확인"을 둔다:
#       사람이 보내면 방을 연 뒤 y/N 으로 묻고, AI 가 보내면 사람이 미리 noDraft 로 표시한 방에만 보낸다.
#   (3) 시험 완료(2026-11-14~15, 5342, 같은 방·배율 100%): 한 줄·여러 줄·이모지가 붙여넣기로 그대로 들어가고, 0.8초 대기 뒤 클립보드가 원래대로 돌아온다.

$script:SendMaxLength = 1000
$script:SendMinIntervalSeconds = 2
$script:SendAttemptKeep = 100
# 붙여넣기(Ctrl+V)를 보낸 뒤 클립보드를 되돌리기 전에 기다리는 시간. 카카오톡이 아직 붙여넣기 전인데 사용자의 원래 클립보드 글로 되돌리면
# 그 글이 대신 전송될 수 있다(위험 R-04). Enter 가 실패해도 기다린다. 값(0.8초)은 측정 전 추정이며 실제 시험에서 확인해야 한다.
$script:SendSettleMs = 800
# 입력란이 키보드 포커스를 갖기를 기다리는 시간과 확인 간격(밀리초). 포커스 확인은 읽기만 하며 키·클릭은 없다.
$script:SendFocusWaitMs = 2000
$script:SendFocusPollMs = 100
# Ready(실제 보내기 열기)의 두 조건. 둘 다 거짓으로 출고한다. 참으로 바꾸는 것은 사람 승인 뒤의 별도 작업이다.
#  - SendVerifySentImplemented: 보낸 글을 방에서 확인하는 일(VerifySent)이 만들어지고 실제로 시험된 뒤에만 참. 없으면 모든 전송이 "불명"이 되어 같은 글을 다시 보내게 된다.
#    (2026-11-20 참으로 바꿈: 내보내기 제공자를 명령 계층(SendCommand)에서 연결했고, 실제 카카오톡 D3 에서 "확인됨, 정확히 1건 일치"를 1회 확인했다.)
#  - SendReadyApproved: 방 열기 → 보내기 → 확인 → 닫기 전체를 사람 승인 아래 실제 카카오톡에서 끝까지 시험하고, 사람이 열기로 정한 뒤에만 참.
$script:SendVerifySentImplemented = $true
$script:SendReadyApproved = $false
# 보낸 글 확인에 쓸 내보내기 제공자(param($room, $since) 로 메시지 목록을 돌려주는 블록). 아직 없다($null) = 항상 불명. 시험이 가짜를 끼운다.
$script:SendExporter = $null

# 아직 채워지지 않은 Ready 조건의 이름 목록('VerifySent', 'Approval'). 비어 있어야 Ready 가 참이다. 참/거짓은 진짜 불리언일 때만 인정한다("true" 글자나 1 은 아니다).
function Get-SendUnmetReadyConditions {
    $unmet = @()
    if (-not ($script:SendVerifySentImplemented -is [bool] -and $script:SendVerifySentImplemented -eq $true)) { $unmet += 'VerifySent' }
    if (-not ($script:SendReadyApproved -is [bool] -and $script:SendReadyApproved -eq $true)) { $unmet += 'Approval' }
    return $unmet
}

# 방 창을 앞으로 올리고 입력란에 키보드 포커스가 있는지 읽어 확인한다. 키도 클릭도 하지 않고, 포커스를 직접 옮기지도 않는다(읽기만).
# 순서: 창 올리기(키 없음) → 맨 앞이 아니면 Wait-KakaoForeground 로 사람이 창을 한 번 눌러 주기를 기다림(안 되면 정지) → 포커스를 짧게 기다리며 확인.
# 포커스가 확인되지 않으면 입력 0 으로 멈춘다(종료 코드 2). 확인 결과는 진짜 불리언 $true 하나일 때만 인정한다.
function Confirm-InputFocus {
    param([Parameter(Mandatory)][long]$Hwnd, [string]$Title, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultFocusProvider }
    $raised = @(& $Provider.Raise $Hwnd $Title)
    $front = ($raised.Count -eq 1 -and $raised[0] -is [bool] -and $raised[0] -eq $true)
    if (-not $front) { [void](& $Provider.WaitForeground $Hwnd) }
    $start = [long](& $Provider.NowMs)
    while ($true) {
        $focused = $false
        try {
            $seen = @(& $Provider.HasFocus $Hwnd)
            $focused = ($seen.Count -eq 1 -and $seen[0] -is [bool] -and $seen[0] -eq $true)
        }
        catch { $focused = $false }
        if ($focused) { return $true }
        if (([long](& $Provider.NowMs) - $start) -ge $script:SendFocusWaitMs) { throw (New-KitError -Key 'send.noInputFocus' -ExitCode 2) }
        & $Provider.Sleep $script:SendFocusPollMs
    }
}

function Get-DefaultFocusProvider {
    return @{
        Raise          = { param($hwnd, $title) Set-KakaoWindowFront -Hwnd ([long]$hwnd) -ExpectedTitle $title }
        WaitForeground = { param($hwnd) [void](Wait-KakaoForeground -Hwnd ([long]$hwnd)) }
        HasFocus       = { param($hwnd) Get-KakaoInputFocus -Hwnd ([long]$hwnd) }
        NowMs          = { [long]([System.Diagnostics.Stopwatch]::GetTimestamp() * 1000 / [System.Diagnostics.Stopwatch]::Frequency) }
        Sleep          = { param($ms) Start-Sleep -Milliseconds ([int]$ms) }
    }
}

# 실제 부품 묶음. 시험은 이 묶음을 가짜로 바꿔 끼운다(Room.ps1 의 제공자와 같은 방식).
function Get-DefaultSendProvider {
    $ErrorActionPreference = 'Stop'
    return @{
        # 두 조건(VerifySent 구현, 사람 승인)이 모두 채워질 때만 참이다. 지금은 사람 승인이 거짓이라 실제 보내기는 잠겨 있다(Get-SendUnmetReadyConditions).
        Ready      = { @(Get-SendUnmetReadyConditions).Count -eq 0 }
        Mode       = { Get-KitMode }
        Now        = { [datetime]::UtcNow }
        # 명령 계층이 Enter-KitLock 으로 잡은 실행 잠금을 이 프로세스가 쥐고 있는가.
        LockHeld   = { $null -ne $script:KitLockMutex }
        OpenRoom   = { param($name, $caller) Open-KakaoRoom -Name $name -Caller $caller -Action 'send' }
        # 입력란을 읽기만 해서 empty / draft / unknown 을 돌려준다(키·클릭·쓰기 없음). 읽지 못하면 unknown 이다.
        ReadInputState = { param($hwnd, $title) Get-KakaoInputState -Hwnd ([long]$hwnd) }
        # 사람에게 "입력란이 비었습니까?"를 묻는다. 사람이 키보드 앞에 있을 때만 통과하고, y/Y 만 "예"다(그 밖의 모든 답은 "아니오").
        # 카카오톡은 방 창을 닫았다 열어도 쓰다 만 글을 남기고(2026-11-14 시험), 키트는 지우는 키를 쓸 수 없어서 비어 있는지 스스로 알 수 없다.
        ConfirmInputEmpty = { param($title)
            Assert-HumanPath -Human
            $answer = Read-Host (Get-Msg -Key 'send.askEmpty' -FormatArgs @($title))
            return ([string]$answer -ceq 'y' -or [string]$answer -ceq 'Y') }
        # 사람에게 물은 뒤에는 키보드 사용 기준이 어긋나므로(답을 친 것이 "사람 손"으로 잡힌다) 다시 손이 떨어질 때까지 기다려 기준을 잡는다.
        WaitIdle   = { Wait-UserIdle -Seconds 2 -TimeoutSeconds 10 }
        # 클릭 없이 입력란 포커스를 읽어 확인한다(Confirm-InputFocus). 확인되지 않으면 입력 0 으로 멈춘다.
        FocusInput = { param($hwnd, $title) [void](Confirm-InputFocus -Hwnd ([long]$hwnd) -Title $title) }
        # 블록을 닫지 않는다(클로저 금지): 닫힌 블록은 전역 함수만 보여서 스크립트 안에서 불러온 실제 실행에서 Send-KeyCombo 를 못 찾는다(S5 에서 확인).
        # $progress.KeysSent 는 Ctrl+V 가 실제로 나간 뒤에만 참이 된다. 그 전에 멈추면 "실패", 그 뒤에 멈추면 "불명"이다.
        PasteEnter = { param($hwnd, $text, $title, $progress)
            $settleMs = $script:SendSettleMs
            Use-TextClipboard -Text $text -Action {
                Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+V' -ExpectedTitle $title
                $progress.KeysSent = $true
                try { Send-KeyCombo -Hwnd $hwnd -Keys 'Enter' -ExpectedTitle $title }
                finally { Start-Sleep -Milliseconds $settleMs }
            } }
        # 보낸 글이 방에 나타났는지 확인하는 판정(Confirm-SentMessage). 메시지 목록은 $script:SendExporter 가 준다.
        # 내보내기 제공자는 아직 없다(Ctrl+S 저장 창 실측 D1·D2 뒤에 만든다): 그전에는 항상 못 읽으므로 결과는 불명이다. 판정은 보낸 분 이후의 정확히 1개 일치일 때만 확인됨이다.
        # 블록을 닫지 않는다(클로저 금지, 위와 같은 이유).
        VerifySent = { param($room, $text, $attemptId, $sentAt)
            $cfgRoom = Find-Room -Config (Get-KitConfig) -Name $room
            $self = ($null -ne $cfgRoom -and $cfgRoom.selfOnly -is [bool] -and $cfgRoom.selfOnly -eq $true)
            Confirm-SentMessage -Room $room -Text $text -Since $sentAt -SelfOnly $self -Export $script:SendExporter }
        CloseRoom  = { param($opened) [void](Close-KitOpenedWindow -Opened $opened) }
    }
}

# 보낼 글 검사: 눈에 보이는 글자가 있어야 하고(공백·보이지 않는 글자뿐이면 거절), 1000자 이하이고(UTF-16 단위로 센다, 이모지는 2),
# 탭·줄바꿈 말고 조작 문자(C0·C1, 줄/문단 구분자, 글자 방향 조작)가 없을 것. 이모지 이음 글자(U+200D 등)는 허용한다.
function Assert-SendTextValid {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $ErrorActionPreference = 'Stop'
    if ($null -eq $Text -or $Text.Length -gt $script:SendMaxLength) { throw (New-KitError -Key 'send.textInvalid' -ExitCode 1) }
    $visible = $Text -replace '[\s​-‍⁠﻿]', ''
    if ($visible.Length -eq 0 -or $Text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F  ‪-‮⁦-⁩]') {
        throw (New-KitError -Key 'send.textInvalid' -ExitCode 1)
    }
    # 짝이 없는 서로게이트(깨진 UTF-16)는 클립보드를 거치며 다른 글자로 바뀌거나 깨질 수 있어 거절한다. 정상적인 이모지 짝은 통과한다.
    if ($Text -match '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]') {
        throw (New-KitError -Key 'send.textInvalid' -ExitCode 1)
    }
}

function Get-SendStatePath {
    return [System.IO.Path]::Combine((Get-KitPaths).DataDir, 'state', 'send-state.json')
}

# 마지막 시도 시각과 최근 시도 번호. 파일이 없으면 빈 기록. 있는데 읽을 수 없거나 모양이 틀리면 멈춘다(모르면 보내지 않는다).
# 본 파일은 없고 임시 파일(.tmp)만 있으면 교체 도중 멈춘 흔적일 수 있어 기록이 사라진 것으로 보고 멈춘다.
function Read-SendState {
    $ErrorActionPreference = 'Stop'
    $path = Get-SendStatePath
    $empty = [pscustomobject]@{ LastAttemptUtc = $null; Attempts = @() }
    if (-not (Test-Path -LiteralPath $path)) {
        if (Test-Path -LiteralPath ($path + '.tmp')) { throw (New-KitError -Key 'send.stateUnusable' -FormatArgs @($path + '.tmp') -ExitCode 2) }
        return $empty
    }
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

# 기록을 임시 파일에 쓴 뒤 교체한다. 기존 파일이 있으면 File.Replace(한 번에 교체)를 쓴다: Move-Item -Force 는 먼저 지우고 옮겨서
# 그 사이에 멈추면 기록이 사라진다. 쓰지 못하면 멈춘다(기록 없이 보내지 않는다).
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
        # 백업 경로는 진짜 null 이어야 한다. PowerShell 5.1 은 .NET 문자열 인자에 $null 을 넘겨도 빈 글자("")로 바꿔 "경로 형식이 올바르지 않다"는 오류가 난다
        # (직접 재현해 확인함). [NullString]::Value 를 쓰면 진짜 null 이 전달된다.
        if (Test-Path -LiteralPath $path) { [System.IO.File]::Replace($tmp, $path, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $path) }
    }
    catch { throw (New-KitError -Key 'send.stateUnusable' -FormatArgs @($path) -ExitCode 2) }
}

# 한 방에 한 글을 보낸다. 키가 나가기 전의 모든 검사는 "하나라도 틀리면 입력 0"이다.
#   -Caller         : human 또는 ai. 반드시 정확히 써야 한다(기본값 없음): 빠뜨린 호출이 사람 권한을 얻으면 안 되기 때문이다.
#   -DryRun         : 검사만 하고 미리보기 결과를 돌려준다(입력·기록 없음).
#   -Yes            : 실제로 보내는 데 필요한 확인. 없으면 거절한다.
#   -AllowUnverified: 시험 안 한 카카오톡 버전에서도 보내기를 허용한다. 사람만 쓸 수 있다.
#   -AttemptId      : 시도 번호(영문·숫자·밑줄·붙임표 64자 이내). 같은 번호로 다시 보낼 수 없다. AI 호출에는 반드시 필요하다:
#                     번호가 없으면 같은 명령을 다시 실행했을 때 중복 전송을 막을 수 없다. 사람 호출은 없으면 새로 만든다.
function Send-KakaoMessage {
    param(
        [string]$Room,
        [AllowNull()][AllowEmptyString()][string]$Text,
        [string]$Caller,
        [switch]$DryRun,
        [switch]$Yes,
        [switch]$AllowUnverified,
        [string]$AttemptId,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultSendProvider }

    try {
        # --- 입력 전의 검사(여기서 멈추면 입력 0) ---
        if ($Caller -cne 'human' -and $Caller -cne 'ai') { throw (New-KitError -Key 'send.callerRequired' -ExitCode 1) }
        Assert-SendTextValid -Text $Text
        $hasId = $PSBoundParameters.ContainsKey('AttemptId') -and -not [string]::IsNullOrEmpty($AttemptId)
        # \A ... \z: 끝에 줄바꿈이 붙은 번호("abc`n")를 통과시키지 않는다($ 는 마지막 줄바꿈 앞에서도 맞는다).
        if ($PSBoundParameters.ContainsKey('AttemptId') -and $AttemptId -cnotmatch '\A[A-Za-z0-9_-]{1,64}\z') {
            throw (New-KitError -Key 'send.attemptInvalid' -ExitCode 1)
        }
        if (-not [bool](& $Provider.Ready)) { throw (New-KitError -Key 'send.notReady' -ExitCode 3) }
        Assert-SendAllowedByMode -Mode ([string](& $Provider.Mode)) -AllowUnverified:$AllowUnverified -Caller $Caller
        if (-not (Test-RoomAllowed -Name $Room -Action 'send' -Caller $Caller)) {
            throw (New-KitError -Key 'room.notAllowed' -FormatArgs @($Room) -ExitCode 1)
        }
        # AI 는 사람에게 "입력란이 비었습니까?"를 물을 수 없다. 그래서 사람이 미리 "이 방에는 쓰다 만 글을 남기지 않는다"고 표시한 방에만 보낸다.
        if ($Caller -ceq 'ai' -and -not (Test-RoomNoDraft -Name $Room)) { throw (New-KitError -Key 'send.draftUnknown' -ExitCode 1) }
        # 부르는 쪽이 넘긴 글자가 아니라 설정에 저장된 방 이름을 쓴다.
        $title = [string](Find-Room -Config (Get-KitConfig) -Name $Room).name

        if ($DryRun) {
            return [pscustomobject]@{ Status = 'preview'; Sent = $false; Reason = 'dryRun'; AttemptId = $null; Room = $title; Message = $null }
        }
        if (-not $Yes) { throw (New-KitError -Key 'send.confirmRequired' -ExitCode 1) }
        if ($Caller -ceq 'ai' -and -not $hasId) { throw (New-KitError -Key 'send.attemptInvalid' -ExitCode 1) }
        if (-not [bool](& $Provider.LockHeld)) { throw (New-KitError -Key 'send.lockNotHeld' -ExitCode 2) }

        # --- 간격과 시도 번호: 입력 전에 기록한다(입력 뒤에 멈춰도 같은 시도가 반복되지 않게) ---
        $now = ([datetime](& $Provider.Now)).ToUniversalTime()
        $state = Read-SendState
        if ($null -ne $state.LastAttemptUtc) {
            # 시계가 거꾸로 갔으면(차이가 음수) 안전 쪽으로 너무 이르다고 본다.
            if (($now - $state.LastAttemptUtc).TotalSeconds -lt $script:SendMinIntervalSeconds) { throw (New-KitError -Key 'send.tooSoon' -ExitCode 2) }
        }
        $id = if ($hasId) { $AttemptId } else { [guid]::NewGuid().ToString('N') }
        if ($state.Attempts -ccontains $id) { throw (New-KitError -Key 'send.attemptRepeated' -ExitCode 2) }
        Save-SendState -LastAttemptUtc $now -Ids (@($state.Attempts) + $id)

        # --- 방 열기와 입력 ---
        $opened = & $Provider.OpenRoom $title $Caller
        try {
            # 이미 열려 있던 창에는 보내지 않는다: 입력란에 쓰다 만 글이 있는지 확인할 방법이 없다(설계서 13.2). 그 창은 닫지도 않는다.
            if (-not $opened.OpenedByKit) { throw (New-KitError -Key 'send.alreadyOpen' -ExitCode 2) }
            # 입력란을 읽어서 쓰다 만 글이 보이면 사람·AI 모두 키를 하나도 보내지 않고 멈춘다. 못 읽으면(unknown) 이 확인만 건너뛰고 아래 확인은 그대로 한다.
            # 돌려준 값 중 하나라도 draft 면 멈춘다(앞에 다른 출력이 끼어도 초안을 놓치지 않게 첫 값만 보지 않는다).
            $inputStates = @()
            try { $inputStates = @(& $Provider.ReadInputState ([long]$opened.Hwnd) $title) } catch { $inputStates = @() }
            # 글자일 때만 비교한다: 배열 비교는 다른 형(예: 참/거짓)을 글자로 바꿔 우연히 같다고 볼 수 있다.
            if (@($inputStates | Where-Object { $_ -is [string] -and [string]::Equals($_, 'draft', [System.StringComparison]::Ordinal) }).Count -gt 0) { throw (New-KitError -Key 'send.draftFound' -ExitCode 2) }
            # 키트가 새로 연 창에도 이전 초안이 남아 있을 수 있다. 사람이 보내면 방을 연 뒤, 입력란을 건드리기 전에 사람에게 묻는다.
            # 진짜 true 하나일 때만 "예"다. 물음이 실패하거나(키보드 없음 등) 다른 답이면 키를 하나도 보내지 않고 멈춘다.
            if ($Caller -ceq 'human') {
                $emptyAnswer = @(& $Provider.ConfirmInputEmpty $title)
                if ($emptyAnswer.Count -ne 1 -or $emptyAnswer[0] -isnot [bool] -or $emptyAnswer[0] -ne $true) {
                    throw (New-KitError -Key 'send.draftNotConfirmed' -ExitCode 2)
                }
                & $Provider.WaitIdle
            }
            [void](& $Provider.FocusInput ([long]$opened.Hwnd) $title)

            # 키가 하나라도 나갔으면 중간에 멈춰도 오류가 아니라 '불명'이고 다시 시도하지 않는다. 하나도 안 나갔으면 "실패"(예외)다.
            # 보낸 분(내보낸 시각은 지역 시각의 분 단위). 키가 나가기 바로 전에 잡는다.
            $sentAt = ([datetime](& $Provider.Now)).ToLocalTime()
            $progress = @{ KeysSent = $false }
            try { [void](& $Provider.PasteEnter ([long]$opened.Hwnd) $Text $title $progress) }
            catch {
                if (-not $progress.KeysSent) { throw }
                return (New-SendResult -Status 'unknown' -Reason 'inputInterrupted' -AttemptId $id -Room $title)
            }

            # 확인은 "진짜 true 하나"일 때만 확인됨이다. 아무것도 못 돌려주거나 예외가 나거나 true 가 아닌 값(1, 글자 "true", 둘 이상)이면 불명이다.
            $verified = @()
            try { $verified = @(& $Provider.VerifySent $title $Text $id $sentAt) } catch { $verified = @() }
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

# 키가 나간 뒤의 결과 객체를 만들고 기록한다(본문 없음).
function New-SendResult {
    param([string]$Status, [string]$Reason, [string]$AttemptId, [string]$Room)
    $message = $null
    if ($Status -ceq 'unknown') { $message = Get-Msg -Key 'send.unknownResult' }
    Write-KitLog -Level 'info' -Command 'send' -Room $Room -Result ('{0} id={1}' -f $Status, $AttemptId)
    return [pscustomobject]@{ Status = $Status; Sent = $true; Reason = $Reason; AttemptId = $AttemptId; Room = $Room; Message = $message }
}
