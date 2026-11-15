# 방 열기. 허용 목록에 있는 방만 "검색으로만" 열고, 연 뒤 새 창의 제목이 방 이름과 글자 그대로 같을 때만 성공으로 본다.
# 하나라도 확인하지 못하면 계속하지 않는다(fail-closed). 방을 열면 읽음 처리가 되돌릴 수 없으므로, 보내기 직전의 하드 관문은 "열린 창 제목이 정확히 같은가"다.
# 2026-11-15 구조 기반으로 바꿨다: 화면 글자 읽기(OCR)와 고정 픽셀 위치를 더는 쓰지 않는다(다른 화면 배율·창 크기에서 못 쓰는 문제).
#   - 어떤 화면인지는 메인 창의 컨테이너 이름(구조)으로 읽는다(InputProbe.ps1 의 Get-KakaoMainScreen). 채팅 목록 화면에서만 연다.
#   - 검색이 열렸는지도 같은 방식으로 읽는다. 열린 것이 확인되지 않으면 Enter 를 보내지 않는다.
#   - 연 뒤에는 검색을 Esc 로 닫아 다음 사용을 막지 않게 한다(검색창에 글자가 남으면 다음 검색어가 덧붙어 열리지 않는다, 2026-11-15 T3).
#     Esc 는 메인 창 제목일 때만 가드가 보내고, 이 파일은 "검색이 열려 있다고 읽힐 때만" 보낸다(Close-KakaoMainSearch).
# 이 파일은 작업 전체를 감싸는 잠금(Enter-KitLock)을 잡지 않는다. 부르는 쪽(명령 계층)이 잡는다.
# 필요한 부품: Config(Test-RoomAllowed, Find-Room, Get-KitConfig), Log(Add-KitWarning), Guard, Win32, Clip, InputProbe(Get-KakaoMainScreen).

$script:RoomMainTitle = '카카오톡'
# 검색은 돋보기 좌표를 누르지 않고 Ctrl+F 로 연다: 같은 좌표가 탭에 따라 다른 버튼(친구 탭=친구 추가, 채팅 탭=새 채팅)이라 S5 에서 사고가 났다(D-25).
# 방은 마우스 클릭 없이 연다: Enter 하나로 첫 결과가 열린다(2026-11-15 확인). 클릭 좌표는 쓰지 않는다.
$script:RoomResultRenderMs = 1200   # 붙여넣은 뒤 검색 결과가 그려질 때까지 기다리는 시간
$script:RoomSearchCloseMs = 600     # Esc 를 보낸 뒤 화면이 바뀌기를 기다리는 시간
$script:RoomPollCount = 40          # 방 창이 열리기를 기다리는 횟수
$script:RoomPollSleepMs = 200       # 40 x 200ms = 최대 8초

# 실제 부품 묶음. 시험은 이 묶음을 가짜로 바꿔 끼운다(Guard.ps1 의 제공자와 같은 방식).
function Get-DefaultRoomProvider {
    return @{
        Windows        = { Get-KakaoWindows }
        WaitIdle       = { Wait-UserIdle -Seconds 2 -TimeoutSeconds 10 }
        # 첫 결과를 여는 Enter 하나. 2026-11-15 에 실제로 확인했다: 클릭 없이 Enter 로 방 창이 열린다(200ms).
        # 키 하나도 가드를 거친다(대상 창·제목·맨 앞·사람 손 확인).
        PressEnter     = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Enter' -ExpectedTitle $title }
        # 검색을 Ctrl+F 로 연다(좌표 클릭 없음). 채팅 탭에서 검색이 열리는 것을 2026-11-15 에 구조 읽기로 확인했다(다른 탭은 미확인이라 열지 않는다).
        OpenSearch     = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+F' -ExpectedTitle $title }
        PasteText      = { param($hwnd, $text, $title)
            # .GetNewClosure() 를 쓰지 않는다: 닫힌 블록은 전역 함수만 보여서, 라이브러리를 스크립트 안에서 불러온 실제 실행에서는 Send-KeyCombo 를 못 찾는다(S5 에서 확인).
            # 여기서는 $hwnd·$title 이 호출 스택으로 보이므로 닫지 않아도 된다.
            Use-TextClipboard -Text $text -Action { Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+V' -ExpectedTitle $title } }
        # 메인 창 화면을 구조 이름으로 읽는다(읽기만, 배율·창 크기와 무관): 'chat-list' / 'chat-search' / 'other' / 'unknown'.
        MainScreen     = { param($hwnd) Get-KakaoMainScreen -Hwnd ([long]$hwnd) }
        # 검색 닫기: Esc 한 번. 가드가 메인 창 제목("카카오톡")일 때만 보낸다. 부르는 곳은 Close-KakaoMainSearch 하나뿐이고, 거기서 검색이 열려 있다고 읽힌 뒤에만 부른다.
        CloseSearch    = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Esc' -ExpectedTitle $title }
        CloseWindow    = { param($hwnd, $title) Close-KakaoWindow -Hwnd $hwnd -ExpectedTitle $title }
        Sleep          = { param($ms) Start-Sleep -Milliseconds $ms }
    }
}

# 메인 창의 검색을 닫는다. 검색이 열려 있다고 읽힐 때만 Esc 를 한 번 보내고, 보낸 뒤 채팅 목록으로 돌아왔는지 읽어 돌려준다(참 = 닫힘 또는 원래 열려 있지 않음).
# 검색이 열려 있다고 읽히지 않으면 아무 키도 보내지 않는다: Esc 는 방 창을 닫기 때문에, 확인되지 않은 화면에는 절대 보내지 않는다.
function Close-KakaoMainSearch {
    param([Parameter(Mandatory)][long]$Main, [Parameter(Mandatory)][hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    $screen = [string](& $Provider.MainScreen $Main)
    if ($screen -cne 'chat-search') { return ($screen -ceq 'chat-list') }
    & $Provider.CloseSearch $Main $script:RoomMainTitle
    & $Provider.Sleep $script:RoomSearchCloseMs
    return ([string](& $Provider.MainScreen $Main) -ceq 'chat-list')
}

# 방을 연다. 돌려주는 값: Hwnd, Title(설정에 저장된 방 이름), OpenedByKit(키트가 연 창이면 참).
function Open-KakaoRoom {
    param(
        [string]$Name,
        [string]$Caller = 'human',
        [string]$Action = 'read',
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    # 허용 목록 확인이 먼저다. 통과하지 못하면 창 목록을 읽는 것을 포함해 아무 호출도 하지 않는다.
    if (-not (Test-RoomAllowed -Name $Name -Action $Action -Caller $Caller)) {
        throw (New-KitError -Key 'room.notAllowed' -FormatArgs @($Name) -ExitCode 1)
    }
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
    $mainTitle = $script:RoomMainTitle

    # 첫 입력 전에 메인 창이 채팅 목록(또는 이전 작업이 남긴 검색) 화면인지 구조로 읽는다. 그 밖의 화면에서는 아무것도 입력하지 않는다.
    # (다른 탭에서 Ctrl+F 가 같은 검색창을 여는지는 확인하지 못했다. 확인된 화면에서만 연다.)
    $screen = [string](& $Provider.MainScreen $main)
    if ($screen -cne 'chat-list' -and $screen -cne 'chat-search') { throw (New-KitError -Key 'room.unknownScreen' -ExitCode 2) }
    & $Provider.WaitIdle
    if ($screen -ceq 'chat-search') {
        # 이전 작업이 남긴 검색 화면: 검색창에 글자가 남아 있어 새 검색어가 덧붙으므로, 먼저 닫는다. 닫히지 않으면 더 입력하지 않는다.
        if (-not (Close-KakaoMainSearch -Main $main -Provider $Provider)) { throw (New-KitError -Key 'room.searchNotClosed' -ExitCode 2) }
    }

    try {
        & $Provider.OpenSearch $main $mainTitle
        # 전체 선택(Ctrl+A)은 하지 않는다: 카카오톡 메인 창에서 Ctrl+A 는 "친구 추가" 창을 연다(2026-11-12 확인). 검색창은 위에서 이미 닫아 비웠다.
        & $Provider.PasteText $main $title $mainTitle
        & $Provider.Sleep $script:RoomResultRenderMs
        # Enter 직전의 관문: 검색이 열린 것이 구조로 읽히지 않으면 Enter 를 보내지 않는다.
        if ([string](& $Provider.MainScreen $main) -cne 'chat-search') { throw (New-KitError -Key 'room.searchNotOpened' -ExitCode 2) }
        & $Provider.PressEnter $main $mainTitle

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
    finally {
        # 성공하든 멈추든 메인 창의 검색을 닫아 다음 사용을 막지 않는다. 여기서 실패해도 원래의 결과(성공 또는 멈춘 이유)를 바꾸지 않고 경고만 남긴다.
        $closed = $false
        try { $closed = [bool](Close-KakaoMainSearch -Main $main -Provider $Provider) } catch { $closed = $false }
        if (-not $closed) { [void](Add-KitWarning -Warning (Get-Msg -Key 'room.searchLeftOpen')) }
    }
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
