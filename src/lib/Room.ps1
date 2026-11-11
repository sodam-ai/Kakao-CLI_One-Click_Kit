# 방 열기. 허용 목록에 있는 방만 "검색으로만" 열고, 열기 전에 검색 결과가 정확히 1건임을 확인하며, 연 뒤 새 창의 제목이 방 이름과
# 글자 그대로 같을 때만 성공으로 본다. 하나라도 확인하지 못하면 열지 않는다(fail-closed): 방을 열면 읽음 처리가 되돌릴 수 없기 때문이다.
# 이 파일은 작업 전체를 감싸는 잠금(Enter-KitLock)을 잡지 않는다. 부르는 쪽(명령 계층)이 잡는다.
# 필요한 부품: Config(Test-RoomAllowed, Find-Room, Get-KitConfig), Log(Add-KitWarning), Guard, Win32, Clip, Ocr.

# 메인 창 제목과 결과 줄 클릭 위치(창 크기에 대한 비율, 0~1). 카카오톡 26.9.1.5339, 창 588x753(배율 150%), 오픈채팅 탭에서
# 스파이크 S2·S3 로 확인한 값이다. 다른 창 크기·배율·탭에서는 다시 측정해야 한다.
$script:RoomMainTitle = '카카오톡'
# 검색은 돋보기 좌표를 누르지 않고 Ctrl+F 로 연다: 같은 좌표가 탭에 따라 다른 버튼(친구 탭=친구 추가, 채팅 탭=새 채팅)이라 S5 에서 사고가 났다(D-25).
# 남은 클릭은 검색 결과 첫 줄 더블클릭 하나뿐이고, 그 앞에 결과가 정확히 1건임을 확인한다.
$script:RoomAnchors = @{
    FirstResultRow = @(0.45, 0.335)
}
$script:RoomResultRenderMs = 1200   # 붙여넣은 뒤 검색 결과가 그려질 때까지 기다리는 시간
$script:RoomPollCount = 40          # 방 창이 열리기를 기다리는 횟수
$script:RoomPollSleepMs = 200       # 40 x 200ms = 최대 8초

# 실제 부품 묶음. 시험은 이 묶음을 가짜로 바꿔 끼운다(Guard.ps1 의 제공자와 같은 방식).
function Get-DefaultRoomProvider {
    return @{
        Windows        = { Get-KakaoWindows }
        WaitIdle       = { Wait-UserIdle -Seconds 2 -TimeoutSeconds 10 }
        Click          = { param($hwnd, $relX, $relY, $double, $title)
            if ($double) { Invoke-RelClick -Hwnd $hwnd -RelX $relX -RelY $relY -Double -ExpectedTitle $title }
            else { Invoke-RelClick -Hwnd $hwnd -RelX $relX -RelY $relY -ExpectedTitle $title } }
        # 검색을 Ctrl+F 로 연다(좌표 클릭 없음). 오픈채팅 화면에서 검색창이 열리는 것을 2026-11-12 에 실제로 확인했다(다른 탭은 미확인).
        OpenSearch     = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+F' -ExpectedTitle $title }
        # 검색창에 남은 글자를 붙여넣기가 덮어쓰도록 전체 선택(Ctrl+A)을 한다. 선택만 하고 지우거나 보내지 않는다.
        SelectAll      = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+A' -ExpectedTitle $title }
        PasteText      = { param($hwnd, $text, $title)
            Use-TextClipboard -Text $text -Action { Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+V' -ExpectedTitle $title }.GetNewClosure() }
        # 결과를 확인하지 못했을 때 사용자에게 원인(창 크기·배율·가려짐)을 알려 주기 위해 창 상태를 읽는다. 읽기만 하고 입력하지 않는다.
        Explain        = { param($hwnd) Get-RoomFailureHint -Hwnd $hwnd }
        TabIsOpenChat  = { param($hwnd) Test-OpenChatTab -Hwnd $hwnd }
        OcrAvailable   = { Test-OcrAvailable }
        ResultIsSingle = { param($hwnd, $name, $clickY) Test-SearchResultSingle -Hwnd $hwnd -ExpectedName $name -ClickRelY $clickY }
        CloseWindow    = { param($hwnd, $title) Close-KakaoWindow -Hwnd $hwnd -ExpectedTitle $title }
        Sleep          = { param($ms) Start-Sleep -Milliseconds $ms }
    }
}

# 방을 연다. 돌려주는 값: Hwnd, Title(설정에 저장된 방 이름), OpenedByKit(키트가 연 창이면 참).
# -AllowUnverifiedResult 는 사람만 쓸 수 있다: 한국어 OCR 이 없는 PC 에서 결과 확인 없이 여는 것을 허용한다(경고가 남는다).
function Open-KakaoRoom {
    param(
        [string]$Name,
        [string]$Caller = 'human',
        [string]$Action = 'read',
        [switch]$AllowUnverifiedResult,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    # 허용 목록 확인이 먼저다. 통과하지 못하면 창 목록을 읽는 것을 포함해 아무 호출도 하지 않는다.
    if (-not (Test-RoomAllowed -Name $Name -Action $Action -Caller $Caller)) {
        throw (New-KitError -Key 'room.notAllowed' -FormatArgs @($Name) -ExitCode 1)
    }
    if ($AllowUnverifiedResult -and $Caller -cne 'human') { throw (New-KitError -Key 'error.humanOnly' -ExitCode 1) }
    $room = Find-Room -Config (Get-KitConfig) -Name $Name
    if (-not $room) { throw (New-KitError -Key 'room.notAllowed' -FormatArgs @($Name) -ExitCode 1) }
    # 부르는 쪽이 넘긴 글자가 아니라 설정에 저장된 방 이름을 제목 확인에 쓴다.
    $title = [string]$room.name
    if (-not $Provider) { $Provider = Get-DefaultRoomProvider }

    $windows = @(& $Provider.Windows)
    $same = @($windows | Where-Object { Test-SameRoomName $_.Title $title })
    if ($same.Count -gt 1) { throw (New-KitError -Key 'room.ambiguousWindows' -FormatArgs @($title) -ExitCode 2) }
    if ($same.Count -eq 1) {
        # 이미 열려 있는 창은 재사용한다. 키트가 연 것이 아니므로 닫지 않는다.
        return [pscustomobject]@{ Hwnd = [long]$same[0].Hwnd; Title = $title; OpenedByKit = $false }
    }
    $mains = @($windows | Where-Object { Test-SameRoomName $_.Title $script:RoomMainTitle })
    if ($mains.Count -ne 1) { throw (New-KitError -Key 'room.mainNotFound' -ExitCode 3) }
    $main = [long]$mains[0].Hwnd
    $beforeHwnds = @($windows | ForEach-Object { [long]$_.Hwnd })

    # 검색 결과를 확인할 수 없으면 열지 않는다. 사람이 명시적으로 허용했을 때만 확인 없이 연다.
    $check = $true
    if (-not [bool](& $Provider.OcrAvailable)) {
        if (-not $AllowUnverifiedResult) { throw (New-KitError -Key 'room.ocrUnavailable' -ExitCode 3) }
        $check = $false
        Add-KitWarning -Warning (Get-Msg -Key 'room.unverifiedWarning')
    }

    # 첫 입력(Ctrl+F) 전에 오픈채팅 화면인지 확인한다. 다른 탭에서 Ctrl+F 가 같은 검색창을 여는지는 확인하지 못해, 확인된 화면에서만 연다.
    # 글자를 읽을 수 없어 사람이 확인 없이 열기를 허용한 경우($check 가 거짓)에는 확인하지 않는다.
    if ($check -and $Provider.ContainsKey('TabIsOpenChat') -and -not [bool](& $Provider.TabIsOpenChat $main)) {
        throw (New-KitError -Key 'room.notOpenChatTab' -ExitCode 2)
    }

    $mainTitle = $script:RoomMainTitle
    $rowX = $script:RoomAnchors.FirstResultRow[0]
    $rowY = $script:RoomAnchors.FirstResultRow[1]
    & $Provider.WaitIdle
    & $Provider.OpenSearch $main $mainTitle
    # 검색창에 이전에 넣은 글자가 남아 있어도 붙여넣기가 덮어쓰도록 전체 선택을 먼저 한다(실제 카카오톡에서의 동작은 시험으로 확인한다).
    & $Provider.SelectAll $main $mainTitle
    & $Provider.PasteText $main $title $mainTitle
    & $Provider.Sleep $script:RoomResultRenderMs
    # 더블클릭 직전의 관문: 결과가 정확히 1건이 아니거나 확인 중 오류가 나면 더블클릭하지 않는다.
    # 더블클릭할 높이(rowY)를 확인에 함께 넘겨, 확인한 첫 줄과 클릭하는 줄이 같은 위치인지도 따진다.
    if ($check -and -not [bool](& $Provider.ResultIsSingle $main $title $rowY)) {
        # 멈춘 이유를 알려 준다(창 크기·배율이 다르거나 가려진 경우). 설명을 못 얻어도 멈춤 자체는 그대로다.
        $hint = ''
        if ($Provider.ContainsKey('Explain')) { try { $hint = [string](& $Provider.Explain $main) } catch { $hint = '' } }
        throw (New-KitError -Key 'room.resultNotSingle' -FormatArgs @($title, $hint) -ExitCode 2)
    }
    & $Provider.Click $main $rowX $rowY $true $mainTitle

    # 방 창은 1~3초 늦게 생긴다. 새로 생긴 창만 본다. 제목이 아직 없는 새 창은 만드는 중일 수 있으므로 기다리고 닫지 않는다.
    $hit = @(); $others = @()
    for ($i = 0; $i -lt $script:RoomPollCount; $i++) {
        & $Provider.Sleep $script:RoomPollSleepMs
        $new = @(@(& $Provider.Windows) | Where-Object { $beforeHwnds -notcontains [long]$_.Hwnd })
        $hit = @($new | Where-Object { Test-SameRoomName $_.Title $title })
        $others = @($new | Where-Object { -not [string]::IsNullOrEmpty([string]$_.Title) -and -not (Test-SameRoomName $_.Title $title) })
        if ($hit.Count -gt 0 -or $others.Count -gt 0) { break }
    }
    if ($others.Count -gt 0) {
        # 제목이 다른 새 창은 키트가 만든 것이므로 그 창 자신의 제목으로 닫고 멈춘다. 원래 열려 있던 창은 건드리지 않는다.
        foreach ($window in (@($others) + @($hit))) { & $Provider.CloseWindow ([long]$window.Hwnd) ([string]$window.Title) }
        throw (New-KitError -Key 'room.openedWrongTitle' -ExitCode 2)
    }
    if ($hit.Count -gt 1) { throw (New-KitError -Key 'room.ambiguousWindows' -FormatArgs @($title) -ExitCode 2) }
    if ($hit.Count -eq 0) { throw (New-KitError -Key 'room.openTimeout' -FormatArgs @($title) -ExitCode 3) }
    return [pscustomobject]@{ Hwnd = [long]$hit[0].Hwnd; Title = $title; OpenedByKit = $true }
}

# 키트가 연 창만 닫는다(닫기 요청 하나만 보낸다). 원래 열려 있던 창은 닫지 않고 거짓을 돌려준다.
function Close-KitOpenedWindow {
    param([Parameter(Mandatory)]$Opened, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if (-not $Opened.OpenedByKit) { return $false }
    if (-not $Provider) { $Provider = Get-DefaultRoomProvider }
    & $Provider.CloseWindow ([long]$Opened.Hwnd) ([string]$Opened.Title)
    return $true
}
