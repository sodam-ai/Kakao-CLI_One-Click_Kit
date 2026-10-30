# 화면 글자 읽기(OCR)와 "검색 결과가 정확히 1건인가" 판정. 읽기만 한다: 창을 캡처해 메모리에서만 읽고, 디스크에 쓰지 않으며, 입력을 보내지 않는다.
# 캡처에는 다른 방의 이름과 미리보기가 찍힌다. 그래서 읽은 글자는 판정에만 쓰고 기록하거나 화면에 내보내지 않는다.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# 검색 결과 영역과 첫 줄의 위치(이미지 높이에 대한 비율). 카카오톡 26.9.1.5339, 창 588x753(배율 150%), 오픈채팅 탭의 캡처에서 잡은 값이다(가설).
# 검색창 안의 글자(중심 약 0.21)와 아래쪽 광고(중심 약 0.86)는 영역 밖이고, 첫 줄은 중심 0.30~0.37 사이에 있다. 다른 조건에서는 다시 측정해야 한다.
$script:ResultBand = @{ RegionTop = 0.25; RegionBottom = 0.79; FirstRowBottom = 0.40 }

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

# 비트맵의 글자를 줄 단위로 읽는다. 각 줄: Text, Left, Top, Right, Bottom(픽셀, 비트맵 왼쪽 위가 기준).
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
            foreach ($word in $line.Words) {
                $box = $word.BoundingRect
                if ($box.X -lt $left) { $left = $box.X }
                if ($box.Y -lt $top) { $top = $box.Y }
                if (($box.X + $box.Width) -gt $right) { $right = $box.X + $box.Width }
                if (($box.Y + $box.Height) -gt $bottom) { $bottom = $box.Y + $box.Height }
            }
            $lines += [pscustomobject]@{ Text = [string]$line.Text; Left = $left; Top = $top; Right = $right; Bottom = $bottom }
        }
        return $lines
    }
    catch {
        if ($_.Exception -is [KakaoKitException]) { throw }
        throw (New-KitError -Key 'ocr.failed' -ExitCode 3)
    }
}

# 카카오톡 메인 창 화면을 캡처해(메모리에서만) 글자를 읽는다. 돌려주는 값: Lines(줄 목록), Height(캡처 높이 픽셀).
# 창이 다른 창에 가려져 있으면 가린 창의 글자를 읽게 되고, 그러면 아래 판정이 거짓이 되어 방을 열지 않는다(안전 쪽).
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
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $width, $height)) }
        finally { $graphics.Dispose() }
        $lines = Get-OcrLines -Bitmap $bitmap
    }
    finally { $bitmap.Dispose() }
    return [pscustomobject]@{ Lines = $lines; Height = $height }
}

function Remove-AllWhitespace([string]$Text) { return ($Text -replace '\s', '') }

# 읽은 줄들이 "기대한 방 하나뿐인 검색 결과"인지 판정한다(화면 없이 시험할 수 있는 순수 함수).
# 참(true)이 되려면 모두 맞아야 한다: ① 결과 영역 안에 방 이름으로 시작하는 줄이 있고, 그 뒤에는 참여자 수 같은 숫자·기호만 있다
# ② 결과 영역 안의 모든 글자가 첫 줄의 높이 안에 있다(둘째 줄이 있으면 거짓). 확인하지 못하면 항상 거짓이다.
function Test-SingleResultLines {
    param([object[]]$Lines = @(), [string]$ExpectedName, [double]$ImageHeight)
    if ([string]::IsNullOrEmpty($ExpectedName) -or $ImageHeight -le 0) { return $false }
    $region = @()
    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        $center = (([double]$line.Top + [double]$line.Bottom) / 2) / $ImageHeight
        if ($center -ge $script:ResultBand.RegionTop -and $center -le $script:ResultBand.RegionBottom) {
            $region += [pscustomobject]@{ Text = [string]$line.Text; Center = $center }
        }
    }
    if ($region.Count -eq 0) { return $false }
    if (@($region | Where-Object { $_.Center -gt $script:ResultBand.FirstRowBottom }).Count -gt 0) { return $false }
    $want = Remove-AllWhitespace $ExpectedName
    foreach ($item in $region) {
        $text = Remove-AllWhitespace $item.Text
        if ($text.StartsWith($want, [System.StringComparison]::Ordinal) -and $text.Substring($want.Length) -match '^[\d\p{P}\p{S}]*$') { return $true }
    }
    return $false
}

# 메인 창의 검색 결과가 방 이름 하나뿐인지 확인한다. -Capture 는 시험이 가짜 캡처를 끼우는 자리다.
function Test-SearchResultSingle {
    param([Parameter(Mandatory)][long]$Hwnd, [string]$ExpectedName, [scriptblock]$Capture)
    if (-not $Capture) { $Capture = { param($h) Get-SearchResultLines -Hwnd $h } }
    $shot = & $Capture $Hwnd
    return (Test-SingleResultLines -Lines $shot.Lines -ExpectedName $ExpectedName -ImageHeight $shot.Height)
}
