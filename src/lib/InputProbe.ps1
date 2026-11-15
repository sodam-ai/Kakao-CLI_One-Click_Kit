# 방 창의 입력란을 "읽기만" 해서 비었는지 판정한다(Windows UI 자동화). 키·클릭·값 쓰기·포커스 이동은 하지 않는다. 읽은 글은 화면·기록·파일에 내지 않는다.
# 2026-11-15 읽기 전용 조사(카카오톡 26.9.2.5342): 입력란은 방 창의 직계 자식인 RICHEDIT50W 컨트롤 하나이고, 값 패턴과 글 패턴으로 읽힌다.
# 비어 있을 때는 안내 문구 "메시지 입력" 이 그대로 글로 읽히고(값은 끝에 줄바꿈 하나가 더 붙는다), 초안이 있으면 그 글이 읽힌다.
# 판정은 안전한 쪽으로 한다: 확실히 비었을 때만 empty, 그 밖의 글은 draft, 못 읽거나 애매하면 unknown(= 이 확인 하나만 건너뛰고, 다른 안전장치는 그대로 적용).
# 이 부품이 empty 라고 해서 사람 확인이나 방 표시(noDraft)를 건너뛰지 않는다. draft 일 때 멈추는 것만 더한다.

# 비어 있을 때 보이는 안내 문구. 카카오톡 화면 언어가 다르면 이 글이 달라 draft 로 읽혀 보내기가 멈춘다(안전한 쪽).
$script:KakaoInputPlaceholders = @('메시지 입력')
# 방 창의 직계 자식 중 입력란의 컨트롤 종류 이름. 정확히 하나일 때만 읽는다.
$script:KakaoInputClassName = 'RICHEDIT50W'

# 읽은 글 하나를 판정한다. 글이 아니면 unknown. 끝의 줄바꿈은 한 번만 뗀다(값은 안내 문구 뒤에 줄바꿈 하나가 붙어 읽힌다).
function ConvertTo-InputState {
    param([AllowNull()]$Text)
    if ($null -eq $Text -or $Text -isnot [string]) { return 'unknown' }
    $s = [string]$Text
    if ($s.EndsWith("`r`n", [System.StringComparison]::Ordinal)) { $s = $s.Substring(0, $s.Length - 2) }
    elseif ($s.EndsWith("`r", [System.StringComparison]::Ordinal) -or $s.EndsWith("`n", [System.StringComparison]::Ordinal)) { $s = $s.Substring(0, $s.Length - 1) }
    if ($s.Length -eq 0) { return 'empty' }
    foreach ($p in $script:KakaoInputPlaceholders) {
        if ([string]::Equals($s, $p, [System.StringComparison]::Ordinal)) { return 'empty' }
    }
    return 'draft'
}

# 두 가지 읽기(값, 글)를 합친다. 둘 다 empty 일 때만 empty, 하나라도 draft 면 draft, 그 밖에는 unknown.
function Merge-InputStates {
    param([AllowNull()]$A, [AllowNull()]$B)
    if ($A -ceq 'draft' -or $B -ceq 'draft') { return 'draft' }
    if ($A -ceq 'empty' -and $B -ceq 'empty') { return 'empty' }
    return 'unknown'
}

# 방 창(핸들)의 입력란을 읽어 empty / draft / unknown 을 돌려준다. 어떤 실패도 던지지 않고 unknown 으로 돌려준다.
function Get-KakaoInputState {
    param([long]$Hwnd)
    $ErrorActionPreference = 'Stop'
    try {
        if ($Hwnd -le 0) { return 'unknown' }
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([System.IntPtr]$Hwnd)
        if ($null -eq $root) { return 'unknown' }
        $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ClassNameProperty), $script:KakaoInputClassName
        $found = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        if ($found.Count -ne 1) { return 'unknown' }
        $el = $found[0]
        $valueState = 'unknown'
        $textState = 'unknown'
        $vp = $null
        if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
            $valueState = ConvertTo-InputState -Text ([string]$vp.Current.Value)
        }
        $tp = $null
        if ($el.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
            $textState = ConvertTo-InputState -Text ([string]$tp.DocumentRange.GetText(5000))
        }
        return (Merge-InputStates -A $valueState -B $textState)
    }
    catch { return 'unknown' }
}

# 메인 창이 어떤 화면인지 "컨테이너 창의 이름"(카카오톡 내부 화면 이름)으로 판정한다. 픽셀·글자 읽기(OCR)가 아니라서 화면 배율·창 크기와 무관하다.
# 2026-11-15 실제 읽은 값(26.9.2.5342): 채팅 탭은 ChatRoomListView_0x… 아래 ChatRoomListCtrl_0x…, 검색을 열면 같은 자리가 SearchListCtrl_0x…,
# 친구 탭은 ContactListView_0x… 이다. 이름 뒤의 번호는 실행마다 다를 수 있어 앞부분(접두사)만 정확히(대소문자 포함) 비교한다.
# 결과: 'chat-list'(채팅 목록) / 'chat-search'(채팅 탭에서 검색이 열림) / 'other'(그 밖의 화면, 예: 친구 탭) / 'unknown'(못 읽음·애매함).
# 메인 창 루트 이름(OnlineMainView_)이 보일 때만 판정하고, 아니면 'unknown' 이다(처음 보는 버전에서는 멈추는 쪽).
$script:MainScreenRootPrefix = 'OnlineMainView_'
$script:MainScreenChatViewPrefix = 'ChatRoomListView_'
$script:MainScreenChatListPrefix = 'ChatRoomListCtrl_'
$script:MainScreenSearchListPrefix = 'SearchListCtrl_'

function ConvertTo-MainScreenState {
    param([AllowNull()]$Names)
    $list = @($Names | Where-Object { $_ -is [string] })
    $has = { param([string]$prefix) @($list | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::Ordinal) }).Count -gt 0 }
    if (-not (& $has $script:MainScreenRootPrefix)) { return 'unknown' }
    if (& $has $script:MainScreenChatViewPrefix) {
        $chat = [bool](& $has $script:MainScreenChatListPrefix)
        $search = [bool](& $has $script:MainScreenSearchListPrefix)
        if ($chat -and $search) { return 'unknown' }
        if ($search) { return 'chat-search' }
        if ($chat) { return 'chat-list' }
        return 'unknown'
    }
    return 'other'
}

# 메인 창(핸들)의 화면을 읽는다. 속성 읽기만 한다(키·클릭·포커스 이동·값 쓰기 없음). 어떤 실패도 던지지 않고 'unknown' 을 돌려준다.
function Get-KakaoMainScreen {
    param([long]$Hwnd)
    $ErrorActionPreference = 'Stop'
    try {
        if ($Hwnd -le 0) { return 'unknown' }
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([System.IntPtr]$Hwnd)
        if ($null -eq $root) { return 'unknown' }
        $names = New-Object System.Collections.ArrayList
        $stack = New-Object System.Collections.Stack
        $stack.Push(@($root, 0))
        $visited = 0
        while ($stack.Count -gt 0 -and $visited -lt 400) {
            $item = $stack.Pop()
            $el = $item[0]; $depth = [int]$item[1]
            $visited++
            $cls = [string]$el.Current.ClassName
            # 광고 영역(내장 브라우저)과 그림 창은 화면 판정과 무관하고 크므로 들어가 보지 않는다.
            if ($cls.StartsWith('Chrome_', [System.StringComparison]::Ordinal) -or $cls.StartsWith('Afx:', [System.StringComparison]::Ordinal)) { continue }
            if ($cls.StartsWith('EVA_', [System.StringComparison]::Ordinal)) {
                $name = [string]$el.Current.Name
                if (-not [string]::IsNullOrEmpty($name)) { [void]$names.Add($name) }
            }
            if ($depth -ge 6) { continue }
            $child = $walker.GetFirstChild($el)
            while ($null -ne $child) { $stack.Push(@($child, ($depth + 1))); $child = $walker.GetNextSibling($child) }
        }
        return (ConvertTo-MainScreenState -Names @($names))
    }
    catch { return 'unknown' }
}

# 방 창(핸들)의 입력란이 지금 키보드 포커스를 갖고 있는지 "읽기만" 한다(HasKeyboardFocus 속성). 포커스를 옮기거나 누르거나 쓰지 않는다.
# 입력란이 정확히 하나이고 포커스가 있다고 읽힐 때만 $true 다. 못 읽거나 애매하면 $false(= 입력하지 않는 쪽). 어떤 실패도 던지지 않는다.
# 2026-11-15 확인(5342): 키트가 Enter 로 연 새 방 창은 입력란이 이미 키보드 포커스를 갖고 있었다(클릭 불필요).
function Get-KakaoInputFocus {
    param([long]$Hwnd)
    $ErrorActionPreference = 'Stop'
    try {
        if ($Hwnd -le 0) { return $false }
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([System.IntPtr]$Hwnd)
        if ($null -eq $root) { return $false }
        $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ClassNameProperty), $script:KakaoInputClassName
        $found = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        if ($found.Count -ne 1) { return $false }
        $has = $found[0].GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::HasKeyboardFocusProperty)
        return ($has -is [bool] -and $has -eq $true)
    }
    catch { return $false }
}
