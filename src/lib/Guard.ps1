# 입력 가드. 카카오톡에 키·마우스를 보내는 길은 이 파일의 함수뿐이고, 모두 입력 직전에 대상 창을 확인한다.
# 하나라도 틀리면 입력을 한 번도 보내지 않고 KakaoGuardException(종료 코드 2)을 던진다.
#
# 규칙: 안전 정지를 throw 로 하는 모든 함수는 첫 줄에 `$ErrorActionPreference = 'Stop'` 을 둔다.
#       호출하는 쪽이 -ErrorAction SilentlyContinue 를 쓰거나 그런 설정을 물려줘도 throw 가 무시되어 입력이 나가는 일이 없게 하기 위해서다.
#       (tests/Bootstrap.Tests.ps1 이 소스를 구문 분석해 이 규칙을 강제한다)

# 허용하는 키는 이 다섯 개뿐이다. Esc는 카카오톡에서 채팅 창을 닫으므로 표에 없고, 표에 없는 키는 거부된다. (C# 쪽에도 같은 표가 한 번 더 있다)
# Ctrl+A 도 표에 없다: 카카오톡 메인 창에서 Ctrl+A 는 "전체 선택"이 아니라 "친구 추가" 창을 여는 단축키다(2026-11-12 화면의 툴팁으로 확인, D-25).
# Ctrl+F(검색 열기)는 2026-11-12 에 사용자가 승인해 추가했다: 좌표 클릭은 탭마다 같은 자리가 다른 버튼이라 사고가 났다(D-25).
$script:AllowedKeyCodes = @{
    'Ctrl+S' = @(0x11, 0x53)
    'Ctrl+V' = @(0x11, 0x56)
    'Ctrl+C' = @(0x11, 0x43)
    'Ctrl+F' = @(0x11, 0x46)
    'Enter'  = @(0x0D)
}

# C# 입력 함수가 돌려주는 결과 코드를 한글 메시지 키로 옮긴다.
$script:GuardStatusKeys = @{
    1  = 'guard.processMismatch'
    2  = 'guard.titleMismatch'
    3  = 'guard.notForeground'
    4  = 'guard.userInterference'
    5  = 'guard.keysHeld'
    6  = 'guard.keyNotAllowedNative'
    7  = 'guard.clickCovered'
    8  = 'guard.cursorMoved'
    9  = 'guard.sendFailed'
    10 = 'guard.sendFailed'
}

$script:KitInputBaseline = $null
$script:KitLockMutex = $null
# 대상 창을 앞으로 올리는 시도 횟수(입력 직전). 한 번도 안 올라오면 입력 0 으로 멈춘다.
$script:ForegroundRaiseTries = 3

function New-GuardError {
    param([Parameter(Mandatory)][string]$Key, [object[]]$FormatArgs = @())
    return New-Object KakaoGuardException -ArgumentList @(Get-Msg -Key $Key -FormatArgs $FormatArgs)
}

function New-GuardStatusError {
    param([Parameter(Mandatory)][int]$Status, [string]$ExpectedTitle)
    $key = $script:GuardStatusKeys[$Status]
    if (-not $key) { $key = 'guard.sendFailed' }
    return (New-GuardError -Key $key -FormatArgs @($ExpectedTitle))
}

# 표에서 정확히(대소문자·공백 포함) 같은 키만 찾는다. PowerShell 해시테이블은 대소문자를 가리지 않으므로 직접 비교한다.
function Get-AllowedKeyCodes {
    param([string]$Keys)
    $ErrorActionPreference = 'Stop'
    foreach ($name in $script:AllowedKeyCodes.Keys) {
        if ([string]::Equals($name, $Keys, [System.StringComparison]::Ordinal)) { return $script:AllowedKeyCodes[$name] }
    }
    throw (New-GuardError -Key 'guard.keyNotAllowed' -FormatArgs @($Keys))
}

function Assert-InputTarget {
    param(
        [Parameter(Mandatory)][long]$Hwnd,
        [string]$ExpectedTitle,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrEmpty($ExpectedTitle)) { throw (New-GuardError -Key 'guard.noExpectedTitle') }
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    if ((& $Provider.ProcessName $Hwnd) -ine 'KakaoTalk') { throw (New-GuardError -Key 'guard.processMismatch') }
    if (-not [string]::Equals([string](& $Provider.Title $Hwnd), $ExpectedTitle, [System.StringComparison]::Ordinal)) {
        throw (New-GuardError -Key 'guard.titleMismatch' -FormatArgs @($ExpectedTitle))
    }
    if ([long](& $Provider.Foreground) -ne $Hwnd) { throw (New-GuardError -Key 'guard.notForeground') }
}

function Reset-InputBaseline { $script:KitInputBaseline = $null }

# 키트가 마지막으로 입력한 직후의 "마지막 입력 시각"을 기억해 둔다. 다음 입력 때 값이 바뀌었으면 사람이 손 댄 것이다.
function Set-InputBaseline {
    param([Parameter(Mandatory)][hashtable]$Provider)
    & $Provider.Sleep 30
    $script:KitInputBaseline = [long](& $Provider.LastInputTick)
}

# 기준 시각이 없으면 사람 손 감지가 꺼진 채로 입력하게 되므로 입력을 거부한다. (작업 시작 때 Wait-UserIdle 로 기준을 잡는다)
function Assert-NoUserInterference {
    param([Parameter(Mandatory)][hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if ($null -eq $script:KitInputBaseline) { throw (New-GuardError -Key 'guard.noBaseline') }
    if ([long](& $Provider.LastInputTick) -ne $script:KitInputBaseline) { throw (New-GuardError -Key 'guard.userInterference') }
}

# 작업을 시작하기 전에 사람이 키보드·마우스에서 손을 뗄 때까지 잠깐 기다리고 기준 시각을 잡는다. 끝내 안 떼면 시작하지 않는다.
# 사람에게 질문(확인 Y/N 등)한 뒤에는 입력 기준이 어긋나므로 다시 호출해야 한다.
function Wait-UserIdle {
    param([int]$Seconds = 2, [int]$TimeoutSeconds = 5, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    $needMs = $Seconds * 1000
    $polls = [Math]::Max(1, [int]($TimeoutSeconds * 1000 / 200))
    for ($i = 0; $i -le $polls; $i++) {
        if ([long](& $Provider.IdleMs) -ge $needMs) {
            Set-InputBaseline -Provider $Provider
            return
        }
        & $Provider.Sleep 200
    }
    throw (New-GuardError -Key 'guard.userBusy')
}

function Send-KeyCombo {
    param(
        [Parameter(Mandatory)][long]$Hwnd,
        [string]$Keys,
        [string]$ExpectedTitle,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    $codes = Get-AllowedKeyCodes -Keys $Keys
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    Assert-NoUserInterference -Provider $Provider
    # 터미널이 포커스를 자주 되가져가므로 입력 직전마다 다시 앞으로 가져오고, 가져왔는지 확인한다.
    # 한 번에 안 올라오면 최대 3번까지 다시 올린다(2026-11-14 시험에서 같은 조건인데 앞 3번만 멈췄고 원인은 못 찾았다).
    # 다시 올리기 전마다 사람이 손댔는지 본다: 손댔으면 창을 다시 빼앗지 않고 멈춘다. 마지막 확인(Assert-InputTarget)은 그대로다.
    for ($try = 1; $try -le $script:ForegroundRaiseTries; $try++) {
        & $Provider.SetForeground $Hwnd
        & $Provider.Sleep 80
        if ([long](& $Provider.Foreground) -eq $Hwnd) { break }
        Assert-NoUserInterference -Provider $Provider
    }
    Assert-InputTarget -Hwnd $Hwnd -ExpectedTitle $ExpectedTitle -Provider $Provider
    Assert-NoUserInterference -Provider $Provider
    # 마지막 확인과 입력은 C# 한 번의 호출 안에서 이어서 한다(그 사이에 끼어들 틈이 없다).
    $status = [int](& $Provider.SendCombo $Hwnd $ExpectedTitle ([byte[]]$codes) $script:KitInputBaseline)
    if ($status -ne 0) { throw (New-GuardStatusError -Status $status -ExpectedTitle $ExpectedTitle) }
    Set-InputBaseline -Provider $Provider
}

# 키도 클릭도 없이 창만 맨 앞으로 올린다(입력란 포커스 확인 전에 쓴다). 맨 앞이 되면 $true, 3번 올려도 안 되면 $false(오류 아님).
# 올리기 전에 프로세스·제목이 맞는지 보고(다르면 올리지 않고 멈춤), 다시 올리기 전마다 사람이 손댔는지 본다(손댔으면 창을 다시 빼앗지 않고 멈춤).
function Set-KakaoWindowFront {
    param(
        [Parameter(Mandatory)][long]$Hwnd,
        [string]$ExpectedTitle,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrEmpty($ExpectedTitle)) { throw (New-GuardError -Key 'guard.noExpectedTitle') }
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    Assert-NoUserInterference -Provider $Provider
    if ((& $Provider.ProcessName $Hwnd) -ine 'KakaoTalk') { throw (New-GuardError -Key 'guard.processMismatch') }
    if (-not [string]::Equals([string](& $Provider.Title $Hwnd), $ExpectedTitle, [System.StringComparison]::Ordinal)) {
        throw (New-GuardError -Key 'guard.titleMismatch' -FormatArgs @($ExpectedTitle))
    }
    for ($try = 1; $try -le $script:ForegroundRaiseTries; $try++) {
        & $Provider.SetForeground $Hwnd
        & $Provider.Sleep 80
        if ([long](& $Provider.Foreground) -eq $Hwnd) { return $true }
        Assert-NoUserInterference -Provider $Provider
    }
    return $false
}

# 창 크기에 비례한 위치(0~1)를 왼쪽 버튼으로 클릭한다. 그 자리의 맨 위 창이 대상 창이 아니면 아무것도 하지 않는다.
function Invoke-RelClick {
    param(
        [Parameter(Mandatory)][long]$Hwnd,
        [Parameter(Mandatory)][double]$RelX,
        [Parameter(Mandatory)][double]$RelY,
        [switch]$Double,
        [string]$ExpectedTitle,
        [hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    if ([double]::IsNaN($RelX) -or [double]::IsNaN($RelY) -or $RelX -lt 0 -or $RelX -gt 1 -or $RelY -lt 0 -or $RelY -gt 1) {
        throw (New-GuardError -Key 'guard.clickRange')
    }
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    Assert-NoUserInterference -Provider $Provider
    & $Provider.SetForeground $Hwnd
    & $Provider.Sleep 80
    Assert-InputTarget -Hwnd $Hwnd -ExpectedTitle $ExpectedTitle -Provider $Provider
    $r = & $Provider.Rect $Hwnd
    $x = [int][Math]::Round($r.Left + $RelX * ($r.Right - $r.Left))
    $y = [int][Math]::Round($r.Top + $RelY * ($r.Bottom - $r.Top))
    if ([long](& $Provider.RootAtPoint $x $y) -ne $Hwnd) { throw (New-GuardError -Key 'guard.clickCovered') }
    Assert-NoUserInterference -Provider $Provider
    $clicks = 1
    if ($Double) { $clicks = 2 }
    # 커서 이동, 위치·가림·맨 앞·사람 손 재확인, 클릭은 C# 한 번의 호출 안에서 이어서 한다.
    $status = [int](& $Provider.ClickAt $Hwnd $ExpectedTitle $x $y $clicks $script:KitInputBaseline)
    if ($status -ne 0) { throw (New-GuardStatusError -Status $status -ExpectedTitle $ExpectedTitle) }
    Set-InputBaseline -Provider $Provider
}

# 창 닫기 요청(WM_CLOSE)만 보낸다. 카카오톡 창이 아니거나 제목이 지정과 다르면 닫지 않는다. 키를 누르지 않는다.
function Close-KakaoWindow {
    param([Parameter(Mandatory)][long]$Hwnd, [string]$ExpectedTitle, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    if ((& $Provider.ProcessName $Hwnd) -ine 'KakaoTalk') { throw (New-GuardError -Key 'guard.closeNotKakao') }
    if ($PSBoundParameters.ContainsKey('ExpectedTitle') -and -not [string]::Equals([string](& $Provider.Title $Hwnd), $ExpectedTitle, [System.StringComparison]::Ordinal)) {
        throw (New-GuardError -Key 'guard.titleMismatch' -FormatArgs @($ExpectedTitle))
    }
    & $Provider.PostClose $Hwnd
}

# 키트 작업은 한 번에 하나만. 같은 프로세스의 두 번째 호출과 다른 프로세스 모두 거부한다.
# 이름은 환경과 상관없이 고정이다(환경변수로 바꿔 우회하지 못하게). 시험만 -Name 으로 따로 지정한다.
function Enter-KitLock {
    param([string]$Name = 'Local\KakaoKit.InputLock')
    $ErrorActionPreference = 'Stop'
    if ($null -ne $script:KitLockMutex) { throw (New-GuardError -Key 'guard.locked') }
    $mutex = New-Object System.Threading.Mutex($false, $Name)
    $acquired = $false
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        $mutex.Dispose()
        throw (New-GuardError -Key 'guard.locked')
    }
    $script:KitLockMutex = $mutex
}

function Exit-KitLock {
    if ($null -ne $script:KitLockMutex) {
        try { $script:KitLockMutex.ReleaseMutex() } catch { }
        $script:KitLockMutex.Dispose()
        $script:KitLockMutex = $null
    }
    Reset-InputBaseline
}
