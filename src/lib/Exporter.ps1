# 보낸 글 확인(VerifySent)에 쓸 "내보내기" 부품. 열려 있는 방 창에서 카카오톡 공식 대화 내보내기(Ctrl+S)를 한 번 하고, 저장된 파일을 읽어 메시지 목록을 돌려준다.
# 실제 확인(2026-11-15 D1·D2, 카카오톡 26.9.2.5342, 100%, 채팅 탭, 한국어)에 맞춰 만들었다:
#   Ctrl+S → "다른 이름으로 저장" 창(#32770)이 0.8초쯤 뒤 뜸 → 파일 이름 칸(Edit, id 1001)에 처음부터 키보드 포커스가 있음 →
#   임시 경로를 붙여넣고(클립보드는 저장→복원) → 칸의 값을 읽어 같은지 확인 → Enter → 파일이 0.8초쯤 뒤 생김 → ConvertFrom-KakaoExport 로 읽음.
# 규칙(모두 fail-closed: 확인되지 않은 것에는 다음 키를 보내지 않고 멈춘다):
#   - 방을 열지 않는다. 이미 열려 있는 방 창이 정확히 하나일 때만 쓴다(방 열기는 Open-KakaoRoom 의 일).
#   - 쓰는 키는 Ctrl+S, Ctrl+V(붙여넣기), Enter 뿐이다. 클릭, 전체 선택, Esc, 지우기 키는 쓰지 않는다.
#   - 저장 경로는 키트 데이터 폴더 아래 영문·숫자·기호(ASCII) 임시 경로만 쓴다(한글 경로는 확인하지 못했다).
#   - 저장 창은 "제목과 종류가 정확히 맞고, 그것 하나만 새로 뜬" 경우에만 다룬다. 남은 저장 창은 그 창 자신의 제목으로만 닫는다.
#   - 제목이 비었거나 낯선 새 창은 어떤 경우에도 닫지 않는다(D2 에서 제목 확인 없이 닫기 요청을 보낸 일이 있었다). 경고만 남긴다.
#   - 읽은 뒤 임시 파일은 지운다(대화 내용을 디스크에 남기지 않는다).
# 이 파일은 작업 전체를 감싸는 잠금(Enter-KitLock)을 잡지 않는다. 부르는 쪽(명령 계층)이 잡는다. 아직 Send 에 연결하지 않았다.
# 필요한 부품: Errors, Messages, Paths(Get-KitPaths), Config(Test-SameRoomName), Log(Add-KitWarning), Guard, Win32, Clip, Parse.

$script:ExporterDialogTitle = '다른 이름으로 저장'
$script:ExporterDialogClass = '#32770'
$script:ExporterDialogPollCount = 30      # 저장 창이 뜨기를 기다리는 횟수
$script:ExporterDialogPollSleepMs = 100   # 30 x 100ms = 최대 3초
$script:ExporterFilePollCount = 100       # 파일이 생기기를 기다리는 횟수
$script:ExporterFilePollSleepMs = 100     # 100 x 100ms = 최대 10초

# 저장 창의 파일 이름 칸(Edit, id 1001)을 구조로 읽는다(읽기만). 정확히 하나일 때만 돌려준다.
function Get-ExporterFileNameBox {
    param([Parameter(Mandatory)][long]$Dialog)
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Dialog)
    $idCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, '1001')
    $clsCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Edit')
    $cond = New-Object System.Windows.Automation.AndCondition($idCond, $clsCond)
    $found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($found.Count -ne 1) { return $null }
    return $found[0]
}

# 실제 부품 묶음. 시험은 이 묶음을 가짜로 바꿔 끼운다(Room.ps1 의 제공자와 같은 방식).
function Get-DefaultExporterProvider {
    return @{
        Windows       = { Get-KakaoWindows }
        MakePath      = {
            $dir = [System.IO.Path]::Combine((Get-KitPaths).DataDir, 'verify')
            [void][System.IO.Directory]::CreateDirectory($dir)
            [System.IO.Path]::Combine($dir, ('v' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.txt')) }
        WaitIdle      = { Wait-UserIdle -Seconds 2 -TimeoutSeconds 10 }
        # 키 하나도 가드를 거친다(대상 창·제목·맨 앞·사람 손 확인).
        PressCtrlS    = { param($hwnd, $title) Send-KeyCombo -Hwnd $hwnd -Keys 'Ctrl+S' -ExpectedTitle $title }
        FileNameFocus = { param($dlg) $box = Get-ExporterFileNameBox -Dialog ([long]$dlg); return ($null -ne $box -and $box.Current.HasKeyboardFocus -eq $true) }
        # 닫지 않은 블록(.GetNewClosure() 없음): 라이브러리를 스크립트 안에서 불러온 실제 실행에서 함수를 찾아야 한다(Room.ps1 와 같은 이유).
        PasteText     = { param($dlg, $text, $title) Use-TextClipboard -Text $text -Action { Send-KeyCombo -Hwnd $dlg -Keys 'Ctrl+V' -ExpectedTitle $title } }
        # 칸의 UIA 이름이 현재 값(붙여넣은 전체 경로)을 그대로 보여 준다(2026-11-15 D2 확인).
        FileNameValue = { param($dlg) $box = Get-ExporterFileNameBox -Dialog ([long]$dlg); if ($null -eq $box) { return $null }; return [string]$box.Current.Name }
        PressEnter    = { param($dlg, $title) Send-KeyCombo -Hwnd $dlg -Keys 'Enter' -ExpectedTitle $title }
        # 파일이 있고, 비어 있지 않고, 잠깐 사이에 크기가 변하지 않으면(쓰기가 끝났으면) 참.
        FileReady     = { param($p)
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $false }
            $a = (Get-Item -LiteralPath $p).Length
            if ($a -le 0) { return $false }
            Start-Sleep -Milliseconds 150
            return ((Get-Item -LiteralPath $p).Length -eq $a) }
        ReadExport    = { param($p) ConvertFrom-KakaoExport -Path $p }
        DeleteFile    = { param($p) [System.IO.File]::Delete($p) }
        CloseWindow   = { param($hwnd, $title) Close-KakaoWindow -Hwnd $hwnd -ExpectedTitle $title }
        Sleep         = { param($ms) Start-Sleep -Milliseconds $ms }
    }
}

function Stop-Export {
    param([Parameter(Mandatory)][string]$Reason)
    $ErrorActionPreference = 'Stop'
    throw (New-KitError -Key 'export.stopped' -FormatArgs @($Reason) -ExitCode 2)
}

# 방 창 하나에서 내보내기를 해 메시지 목록을 돌려준다. 어느 단계든 확인되지 않으면 던진다(종료 코드 2). 잠금은 부르는 쪽이 잡는다.
function Export-KakaoRoomMessages {
    param([string]$Room, [hashtable]$Provider)
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrEmpty($Room)) { Stop-Export '방 이름이 비어 있습니다' }
    if (-not $Provider) { $Provider = Get-DefaultExporterProvider }

    $windows = @(& $Provider.Windows)
    $roomWins = @($windows | Where-Object { Test-SameRoomName $_.Title $Room })
    if ($roomWins.Count -ne 1) { Stop-Export '열려 있는 방 창을 정확히 하나만 찾지 못했습니다' }
    $roomHwnd = [long]$roomWins[0].Hwnd
    $path = & $Provider.MakePath
    if ($path -isnot [string] -or $path -cnotmatch '^[\x20-\x7E]+\.txt$') { Stop-Export '임시 저장 경로가 영문·숫자·기호만으로 된 .txt 경로가 아닙니다' }
    $before = @($windows | ForEach-Object { [long]$_.Hwnd })
    $dlgTitle = $script:ExporterDialogTitle
    $dlg = $null

    & $Provider.WaitIdle
    try {
        & $Provider.PressCtrlS $roomHwnd $Room
        # 새로 생긴 창만 본다. 저장 창은 1초 안에 뜬다.
        $new = @(); $dialogs = @()
        for ($i = 0; $i -lt $script:ExporterDialogPollCount; $i++) {
            & $Provider.Sleep $script:ExporterDialogPollSleepMs
            $new = @(@(& $Provider.Windows) | Where-Object { $before -notcontains [long]$_.Hwnd })
            $dialogs = @($new | Where-Object { [string]$_.Title -ceq $dlgTitle -and [string]$_.Class -ceq $script:ExporterDialogClass -and [string]$_.ProcessName -ieq 'KakaoTalk' })
            if ($dialogs.Count -gt 0) { break }
        }
        if ($dialogs.Count -ne 1) { Stop-Export '저장 창이 확인되지 않았습니다' }
        $dlg = [long]$dialogs[0].Hwnd
        if ($new.Count -ne 1) { Stop-Export '저장 창 말고 다른 새 창이 함께 떴습니다' }

        $focus = & $Provider.FileNameFocus $dlg
        if ($focus -isnot [bool] -or -not $focus) { Stop-Export '파일 이름 칸에 키보드 포커스가 확인되지 않았습니다' }
        & $Provider.PasteText $dlg $path $dlgTitle
        $shown = & $Provider.FileNameValue $dlg
        if ($shown -isnot [string] -or -not [string]::Equals($shown, $path, [System.StringComparison]::Ordinal)) { Stop-Export '파일 이름 칸의 값이 붙여넣은 경로와 다릅니다' }
        & $Provider.PressEnter $dlg $dlgTitle

        $ready = $false
        for ($i = 0; $i -lt $script:ExporterFilePollCount; $i++) {
            $r = & $Provider.FileReady $path
            if ($r -is [bool] -and $r) { $ready = $true; break }
            & $Provider.Sleep $script:ExporterFilePollSleepMs
        }
        if (-not $ready) { Stop-Export '저장된 파일이 시간 안에 생기지 않았습니다' }
        $parsed = & $Provider.ReadExport $path
        if ($null -eq $parsed -or -not (Test-SameRoomName $parsed.Room $Room)) { Stop-Export '내보낸 파일의 방 이름이 요청한 방과 다릅니다' }
        return @($parsed.Messages)
    }
    catch {
        if ($_.Exception -is [KakaoKitException]) { throw }
        Stop-Export ('예상하지 못한 오류(' + $_.Exception.GetType().Name + ')')
    }
    finally {
        # 정리: 남은 저장 창은 그 창 자신의 제목으로만 닫는다. 그 밖의 새 창은 닫지 않고 경고만 남긴다(제목이 비어 있어도 마찬가지).
        try {
            $now = @(& $Provider.Windows)
            if ($null -ne $dlg -and @($now | Where-Object { [long]$_.Hwnd -eq $dlg }).Count -gt 0) { & $Provider.CloseWindow $dlg $dlgTitle }
            $strays = @($now | Where-Object { $before -notcontains [long]$_.Hwnd -and ($null -eq $dlg -or [long]$_.Hwnd -ne $dlg) })
            if ($strays.Count -gt 0) { [void](Add-KitWarning -Warning (Get-Msg -Key 'export.strayWindow')) }
        }
        catch { }
        try { & $Provider.DeleteFile $path } catch { }
    }
}

# 보내기(Send)의 내보내기 훅($script:SendExporter)에 넣을 스크립트 블록: 방 이름과 보낸 분을 받아 그 방의 메시지 목록을 돌려준다.
# 지금은 Send 에 연결하지 않는다(실제 확인 라운드 D3 를 거친 뒤에 연결한다).
function Get-DefaultSendExporter {
    return { param($room, $since) Export-KakaoRoomMessages -Room ([string]$room) }
}
