# 화면 글자 읽기(OCR)와 "검색 결과가 정확히 1건인가" 판정. 읽기만 한다: 창을 캡처해 메모리에서만 읽고, 디스크에 쓰지 않으며, 입력을 보내지 않는다.
# 캡처에는 다른 방의 이름과 미리보기가 찍힌다. 그래서 읽은 글자는 판정에만 쓰고 기록하거나 화면에 내보내지 않는다.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# 검색 결과 영역과 첫 줄의 위치(창 크기에 대한 비율). 카카오톡 26.9.1.5339, 창 588x753(배율 150%), 오픈채팅 탭에서 실제 화면 2장(결과 1줄, 여러 줄)을 읽어 확인한 값이다.
# 검색창 안의 글자(중심 약 0.21)와 아래쪽 광고(중심 약 0.86)는 영역 밖이고, 첫 줄은 중심 0.30~0.37 사이에 있다. 행 간격은 약 0.139 다.
# 가로: 왼쪽 메뉴(알림·설정 아이콘이 글자 0 으로 읽힘)는 0~0.17, 목록은 0.17 부터다. ListLeftMin 보다 왼쪽 글자는 결과가 아니다.
# 방 이름 줄은 왼쪽에서 0.372 의 배지 아이콘(글자 한 개 0 으로 읽힘)으로 시작하고 이름 단어는 0.42(픽셀 247)에서 시작한다. 이름 앞부분이 안 읽히면 이름 단어가 0.46 에서 시작하므로 그것으로 알아챈다.
# 이름은 창 왼쪽 가장자리에서 일정한 픽셀(NameStartPx)에 있으므로 창 폭의 비율이 아니라 픽셀로 잰다(허용 오차 NameStartTolPx). 이름 시작 위치는 아이콘이 읽혔든 안 읽혔든 같은 좁은 범위여야 한다.
# 아이콘 단어가 있으면 이름 단어는 아이콘 바로 뒤(IconGapMaxPx, 실측 약 5)에서 시작해야 한다.
# 픽셀 값(NameStartPx 등)과 창 크기(RefWidth x RefHeight)는 모니터 배율 RefScale(150%)에서 잰 값이다. 같은 창이 배율 100%에서는 392x502, 150%에서는 588x753 으로 보이므로
# (배율만 다르고 창은 같다) 판정할 때 창이 놓인 모니터의 배율(Scale)을 RefScale 로 나눈 비율을 모든 픽셀 값에 곱한다. 그렇게 맞춘 창 크기에서
# SizeTolerance 이상 벗어나면 판정하지 않는다(거짓). 150% 에서만 실제 화면으로 확인했다. 다른 배율(100% 등)과 다른 창 크기·탭에서는 실제 화면으로 다시 확인해야 한다.
$script:ResultBand = @{
    RegionTop      = 0.25
    RegionBottom   = 0.79
    FirstRowBottom = 0.40
    ListLeftMin    = 0.18
    TitleLeftMin   = 0.30
    TitleLeftMax   = 0.50
    NameStartPx    = 247
    NameStartTolPx = 3
    IconGapMaxPx   = 8
    RefScale       = 1.5
    RefWidth       = 588
    RefHeight      = 753
    SizeTolerance  = 0.015
}

# 한국어 글자 읽기 엔진. 없으면 $null (이 PC 에 한국어 OCR 이 없는 경우).
function Get-OcrEngine {
    try {
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
        return [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'ko'))
    }
    catch { return $null }
}

function Test-OcrAvailable { return ($null -ne (Get-OcrEngine)) }

# 윈도우 비동기 작업(WinRT)이 끝나기를 기다려 결과를 돌려준다.
function Wait-WinRtOperation {
    param($Operation, [Type]$ResultType)
    $ErrorActionPreference = 'Stop'
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    if (-not $task.Wait(15000)) { throw (New-KitError -Key 'ocr.failed' -ExitCode 3) }
    return $task.Result
}

# 비트맵의 글자를 줄 단위로 읽는다. 각 줄: Text, Left, Top, Right, Bottom(픽셀, 비트맵 왼쪽 위가 기준)과 Words(단어마다 Text, Left, Right).
function Get-OcrLines {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)
    $ErrorActionPreference = 'Stop'
    $engine = Get-OcrEngine
    if ($null -eq $engine) { throw (New-KitError -Key 'room.ocrUnavailable' -ExitCode 3) }
    try {
        $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
        $memory = New-Object System.IO.MemoryStream
        try {
            $Bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            $memory.Position = 0
            $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memory)
            $decoder = Wait-WinRtOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $soft = Wait-WinRtOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
            $result = Wait-WinRtOperation ($engine.RecognizeAsync($soft)) ([Windows.Media.Ocr.OcrResult])
        }
        finally { $memory.Dispose() }
        $lines = @()
        foreach ($line in $result.Lines) {
            $left = [double]::MaxValue; $top = [double]::MaxValue; $right = 0.0; $bottom = 0.0
            $words = @()
            foreach ($word in $line.Words) {
                $box = $word.BoundingRect
                if ($box.X -lt $left) { $left = $box.X }
                if ($box.Y -lt $top) { $top = $box.Y }
                if (($box.X + $box.Width) -gt $right) { $right = $box.X + $box.Width }
                if (($box.Y + $box.Height) -gt $bottom) { $bottom = $box.Y + $box.Height }
                $words += [pscustomobject]@{ Text = [string]$word.Text; Left = [double]$box.X; Right = [double]($box.X + $box.Width) }
            }
            $lines += [pscustomobject]@{ Text = [string]$line.Text; Left = $left; Top = $top; Right = $right; Bottom = $bottom; Words = $words }
        }
        return $lines
    }
    catch {
        if ($_.Exception -is [KakaoKitException]) { throw }
        throw (New-KitError -Key 'ocr.failed' -ExitCode 3)
    }
}

# 판정 영역(검색 결과 부분)이 다른 창에 가려지지 않았는지 확인한다: 영역 안의 여러 지점(가로 3 x 세로 6)마다 그 자리의 맨 위 창이
# 메인 창인지 본다. 한 곳이라도 다르거나 모르면 거짓이다. 화면 캡처는 "보이는 대로" 읽으므로 가려진 부분의 글자를 놓치거나 가린 창의 글자를 읽을 수 있다.
function Test-MainWindowUncovered {
    param([Parameter(Mandatory)][long]$Hwnd, [Parameter(Mandatory)]$Rect, [hashtable]$Provider)
    if (-not $Provider) { $Provider = Get-DefaultInputProvider }
    $width = $Rect.Right - $Rect.Left
    $height = $Rect.Bottom - $Rect.Top
    foreach ($fx in 0.1, 0.5, 0.9) {
        foreach ($fy in 0.27, 0.35, 0.45, 0.55, 0.65, 0.75) {
            $x = [int][Math]::Round($Rect.Left + $fx * $width)
            $y = [int][Math]::Round($Rect.Top + $fy * $height)
            $owner = & $Provider.RootAtPoint $x $y
            if ($null -eq $owner -or [long]$owner -ne $Hwnd) { return $false }
        }
    }
    return $true
}

# 카카오톡 메인 창 화면을 캡처해(메모리에서만) 글자를 읽는다. 돌려주는 값: Lines(줄 목록), Width·Height(캡처 크기 픽셀), Scale(창이 놓인 모니터의 배율), Covered(가려져 있으면 참).
# 판정 영역이 가려져 있으면 읽지 않고 Covered 를 참으로 돌려준다(그러면 아래 판정은 거짓이 되어 방을 열지 않는다).
function Get-SearchResultLines {
    param([Parameter(Mandatory)][long]$Hwnd)
    $ErrorActionPreference = 'Stop'
    Enable-KitDpiAwareness
    $win = @(Get-KakaoWindows | Where-Object { [long]$_.Hwnd -eq $Hwnd }) | Select-Object -First 1
    if (-not $win) { throw (New-KitError -Key 'room.mainNotFound' -ExitCode 3) }
    $rect = $win.Rect
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) { throw (New-KitError -Key 'room.mainNotFound' -ExitCode 3) }
    $scale = Get-KitWindowScale -Hwnd $Hwnd
    if (-not (Test-MainWindowUncovered -Hwnd $Hwnd -Rect $rect)) {
        return [pscustomobject]@{ Lines = @(); Width = $width; Height = $height; Scale = $scale; Covered = $true }
    }
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $width, $height)) }
        finally { $graphics.Dispose() }
        $lines = Get-OcrLines -Bitmap $bitmap
    }
    finally { $bitmap.Dispose() }
    return [pscustomobject]@{ Lines = $lines; Width = $width; Height = $height; Scale = $scale; Covered = $false }
}

# 읽은 제목 줄이 "기대한 방 이름 + (공백 뒤 최대 5자리 참여자 수) + (기호)"로만 이루어졌는지 본다.
# 이름 안의 공백은 읽기 오차로 보고 무시하지만, 이름 바로 뒤에 붙은 숫자·글자는 다른 이름(예: 테스트방2)이므로 거절한다.
function Test-RoomTitleText {
    param([string]$Text, [string]$ExpectedName)
    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($ExpectedName)) { return $false }
    $chars = @($ExpectedName.ToCharArray() | Where-Object { -not [char]::IsWhiteSpace($_) } | ForEach-Object { [regex]::Escape([string]$_) })
    if ($chars.Count -eq 0) { return $false }
    $pattern = '^' + ($chars -join '\s*') + '(?:\s+[0-9]{1,5})?(?:\s*[\p{S}\p{P}])*\s*$'
    return [regex]::IsMatch($Text.Trim(), $pattern)
}

# 창 크기가 측정한 크기(RefWidth x RefHeight, 배율 RefScale 기준)를 현재 배율(Scale)로 맞춘 크기에서 SizeTolerance 안인지 본다. 읽기만 하는 순수 함수.
function Test-WindowSizeMatches {
    param([double]$Width, [double]$Height, [double]$Scale = 1.0)
    if ($Width -le 0 -or $Height -le 0 -or $Scale -le 0) { return $false }
    $factor = $Scale / $script:ResultBand.RefScale
    $refWidth = $script:ResultBand.RefWidth * $factor
    $refHeight = $script:ResultBand.RefHeight * $factor
    if ([Math]::Abs($Width - $refWidth) / $refWidth -gt $script:ResultBand.SizeTolerance) { return $false }
    if ([Math]::Abs($Height - $refHeight) / $refHeight -gt $script:ResultBand.SizeTolerance) { return $false }
    return $true
}

# 방 열기가 "검색 결과가 정확히 1건인지 확인하지 못함"으로 멈췄을 때 사용자에게 알려 줄 원인의 종류를 고른다: 창 크기가 다르면 'size',
# 그렇지 않고 가려져 있으면 'covered', 둘 다 아니면 ''(원인을 알 수 없음). 크기가 다르면 가림 확인의 위치도 맞지 않으므로 크기를 먼저 본다.
function Get-RoomFailureReasonKey {
    param([double]$Width, [double]$Height, [double]$Scale = 1.0, [bool]$Covered = $false)
    if (-not (Test-WindowSizeMatches -Width $Width -Height $Height -Scale $Scale)) { return 'size' }
    if ($Covered) { return 'covered' }
    return ''
}

# 멈춘 이유를 사용자에게 알려 줄 문구. 메인 창의 크기·배율·가려짐만 읽고(입력하지 않는다), 원인을 모르면 빈 글자를 돌려준다. 오류를 던지지 않는다.
function Get-RoomFailureHint {
    param([long]$Hwnd)
    try {
        Enable-KitDpiAwareness
        $win = @(Get-KakaoWindows | Where-Object { [long]$_.Hwnd -eq $Hwnd }) | Select-Object -First 1
        if (-not $win) { return '' }
        $rect = $win.Rect
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        $scale = Get-KitWindowScale -Hwnd $Hwnd
        $covered = -not (Test-MainWindowUncovered -Hwnd $Hwnd -Rect $rect)
        $key = Get-RoomFailureReasonKey -Width $width -Height $height -Scale $scale -Covered $covered
        if ($key -eq 'size') {
            $factor = $scale / $script:ResultBand.RefScale
            return (Get-Msg -Key 'room.hint.size' -FormatArgs @([int]$width, [int]$height, [int][Math]::Round($scale * 100), [int][Math]::Round($script:ResultBand.RefWidth * $factor), [int][Math]::Round($script:ResultBand.RefHeight * $factor)))
        }
        if ($key -eq 'covered') { return (Get-Msg -Key 'room.hint.covered') }
        return ''
    }
    catch { return '' }
}

# 제목 줄의 단어 상자로 제목 글자를 만든다. 만들 수 없으면 $null(그러면 판정은 거짓이다).
#  - 이름 시작 위치(NameStartPx - NameStartTolPx) 앞에 있는 단어는 배지 아이콘 칸이다. 글자 한 개짜리 단어 하나만 버린다(아이콘이 0·o 같은 글자로 읽힌다).
#    글자 내용으로 허용하는 것이 아니라 위치로 구분한다: 이름 안의 0 은 이름 시작 위치에 있다.
#  - 남은 첫 단어는 이름 시작 위치(NameStartPx ± NameStartTolPx 픽셀) 안에서 시작해야 한다(아이콘이 읽혔든 아니든 같다). 아니면 이름 앞부분이 안 읽힌 것(다른 방일 수 있다)이거나 다른 줄이다.
function Get-TitleTextFromWords {
    # Factor: 현재 배율 / 측정 배율(RefScale). 측정한 픽셀 값에 곱해 현재 화면의 픽셀로 바꾼다.
    param([object[]]$Words = @(), [double]$ImageWidth, [double]$Factor = 1.0)
    $sorted = @($Words | Where-Object { $null -ne $_ } | Sort-Object -Property Left)
    if ($sorted.Count -eq 0 -or $ImageWidth -le 0 -or $Factor -le 0) { return $null }
    $nameMin = ($script:ResultBand.NameStartPx - $script:ResultBand.NameStartTolPx) * $Factor
    $nameMax = ($script:ResultBand.NameStartPx + $script:ResultBand.NameStartTolPx) * $Factor
    $iconGapMax = $script:ResultBand.IconGapMaxPx * $Factor
    $nameWords = $sorted
    $iconRight = $null
    if ([double]$sorted[0].Left -lt $nameMin) {
        if (([string]$sorted[0].Text).Length -ne 1) { return $null }
        if ($sorted.Count -lt 2) { return $null }
        $iconRight = [double]$sorted[0].Right
        $nameWords = @($sorted[1..($sorted.Count - 1)])
    }
    $start = [double]$nameWords[0].Left
    if ($start -lt $nameMin -or $start -gt $nameMax) { return $null }
    # 아이콘이 있으면 이름은 그 바로 뒤에서 시작한다. 사이에 읽히지 않은 글자가 있으면 이름 앞부분이 빠진 것이다.
    if ($null -ne $iconRight -and ($start - $iconRight) -gt $iconGapMax) { return $null }
    return (($nameWords | ForEach-Object { [string]$_.Text }) -join ' ')
}

# 읽은 줄들이 "기대한 방 하나뿐인 검색 결과"인지 판정한다(화면 없이 시험할 수 있는 순수 함수). 확인하지 못하면 항상 거짓이다.
# 참(true)이 되려면 모두 맞아야 한다:
#  ① 창 크기가 측정한 크기(150% 에서 588x753)를 현재 배율(Scale)로 맞춘 크기에서 1.5% 안이다(100% 라면 392x502) ② 목록 칸(왼쪽 메뉴 제외)의 결과 영역 안의 모든 글자가 첫 줄의 높이 안에 있다(둘째 줄이 있으면 거짓)
#  ③ 더블클릭할 높이(ClickRelY)가 첫 줄 안(이름 줄 맨 위 ~ 첫 줄 아래 끝)에 있다 ④ 방 이름 칸(왼쪽에서 0.30~0.50)에서 맨 위에 있는 줄 하나가
#    방 이름 모양이다. 미리보기·시각 줄은 보지 않는다: 다른 방의 미리보기가 우연히 방 이름과 같아도 통과하지 못한다.
#  ⑤ 줄에 단어 상자(Words)가 있으면 제목은 단어 위치로 만든다(Get-TitleTextFromWords). 단어 상자가 없는 줄은 줄 전체 글자가 이름이어야 한다.
function Test-SingleResultLines {
    # Scale: 창이 놓인 모니터의 배율(1.0 = 100%). 모르면 1.0 으로 보며, 그러면 크기가 맞지 않아 거짓이 된다.
    param([object[]]$Lines = @(), [string]$ExpectedName, [double]$ImageWidth, [double]$ImageHeight, [double]$ClickRelY, [double]$Scale = 1.0)
    if ([string]::IsNullOrWhiteSpace($ExpectedName) -or $ImageWidth -le 0 -or $ImageHeight -le 0 -or $Scale -le 0) { return $false }
    if ($ClickRelY -le 0 -or $ClickRelY -ge 1) { return $false }
    $factor = $Scale / $script:ResultBand.RefScale
    if (-not (Test-WindowSizeMatches -Width $ImageWidth -Height $ImageHeight -Scale $Scale)) { return $false }
    $region = @()
    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        # 왼쪽 메뉴 칸의 글자는 결과가 아니다(메뉴 아이콘이 글자로 읽히기도 한다).
        if (([double]$line.Left / $ImageWidth) -lt $script:ResultBand.ListLeftMin) { continue }
        $center = (([double]$line.Top + [double]$line.Bottom) / 2) / $ImageHeight
        if ($center -ge $script:ResultBand.RegionTop -and $center -le $script:ResultBand.RegionBottom) {
            $wordsProp = $line.PSObject.Properties['Words']
            $region += [pscustomobject]@{
                Words  = $(if ($wordsProp) { $wordsProp.Value } else { $null })
                Text   = [string]$line.Text
                Left   = [double]$line.Left / $ImageWidth
                Top    = [double]$line.Top / $ImageHeight
                Bottom = [double]$line.Bottom / $ImageHeight
                Center = $center
            }
        }
    }
    if ($region.Count -eq 0) { return $false }
    if (@($region | Where-Object { $_.Center -gt $script:ResultBand.FirstRowBottom }).Count -gt 0) { return $false }
    # 첫 줄은 이름 줄의 맨 위에서 시작해 FirstRowBottom 에서 끝난다. 미리보기가 비어 이름 줄만 있는 방도 있으므로 글자 덩어리의 아래 끝이 아니라 이 줄 끝을 쓴다.
    $blockTop = ($region | Measure-Object -Property Top -Minimum).Minimum
    if ($ClickRelY -lt $blockTop -or $ClickRelY -gt $script:ResultBand.FirstRowBottom) { return $false }
    $column = @($region | Where-Object { $_.Left -ge $script:ResultBand.TitleLeftMin -and $_.Left -le $script:ResultBand.TitleLeftMax })
    if ($column.Count -eq 0) { return $false }
    $title = $column | Sort-Object -Property Top, Left | Select-Object -First 1
    $titleText = $title.Text
    if ($null -ne $title.Words) {
        $titleText = Get-TitleTextFromWords -Words $title.Words -ImageWidth $ImageWidth -Factor $factor
        if ($null -eq $titleText) { return $false }
    }
    return (Test-RoomTitleText -Text $titleText -ExpectedName $ExpectedName)
}

# 메인 창의 검색 결과가 방 이름 하나뿐인지 확인한다. ClickRelY 는 이어서 더블클릭할 높이다(확인한 줄과 클릭하는 줄이 같은 위치여야 한다).
# -Capture 는 시험이 가짜 캡처를 끼우는 자리다.
function Test-SearchResultSingle {
    param([Parameter(Mandatory)][long]$Hwnd, [string]$ExpectedName, [double]$ClickRelY, [scriptblock]$Capture)
    if (-not $Capture) { $Capture = { param($h) Get-SearchResultLines -Hwnd $h } }
    $shot = & $Capture $Hwnd
    if ($null -eq $shot -or $shot.Covered) { return $false }
    # 캡처가 배율을 알려 주지 않으면 1.0 으로 본다(안전: 150% 크기의 캡처는 크기가 맞지 않아 거짓이 된다).
    $scale = 1.0
    $scaleProp = $shot.PSObject.Properties['Scale']
    if ($scaleProp -and $null -ne $scaleProp.Value) { $scale = [double]$scaleProp.Value }
    return (Test-SingleResultLines -Lines $shot.Lines -ExpectedName $ExpectedName -ImageWidth $shot.Width -ImageHeight $shot.Height -ClickRelY $ClickRelY -Scale $scale)
}
