$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Ocr')
. (Join-Path $here '_Load.ps1')

# 캡처 한 장(창 588x753)에서 본 실제 배치를 본뜬 가짜 OCR 줄이다. Top/Bottom 은 픽셀이다. 실제 화면은 건드리지 않는다.
function New-Line([string]$Text, [double]$Top, [double]$Bottom) { [pscustomobject]@{ Text = $Text; Top = $Top; Bottom = $Bottom } }
$H = 753
$searchBox = New-Line '테스트방' 144 168                       # 검색창 안의 글자(중심 0.21): 결과 영역 밖
$row1Name = New-Line '테스트방 1' 214 238                      # 첫 결과 줄의 방 이름 + 참여자 수(중심 0.30)
$row1Time = New-Line '오후 5:53' 230 248
$row1Prev1 = New-Line '새로운 채팅방이 생성되었습니다.' 245 267
$row1Prev2 = New-Line '생성되었습니다.' 268 290                 # 미리보기가 두 줄로 접힌 것(중심 0.37): 첫 줄 안
$row2Name = New-Line '다른방 5' 314 338                       # 둘째 결과 줄(중심 0.43)
$row3Prev = New-Line '아래쪽 어딘가의 글자' 400 420            # 셋째 줄 근처(중심 0.54)
$ad = New-Line '광고 문구' 636 660                             # 광고 영역(중심 0.86): 결과 영역 밖

Describe 'Ocr: Test-SingleResultLines (정확히 1건인가, 화면 없이 판정)' {
    It 'is true when the room name with its member count is the only result row' {
        $lines = @($searchBox, $row1Name, $row1Time, $row1Prev1, $row1Prev2)
        Test-SingleResultLines -Lines $lines -ExpectedName '테스트방' -ImageHeight $H | Should Be $true
    }

    It 'ignores the ad below the result area' {
        $lines = @($searchBox, $row1Name, $row1Time, $row1Prev1, $ad)
        Test-SingleResultLines -Lines $lines -ExpectedName '테스트방' -ImageHeight $H | Should Be $true
    }

    It 'is false when a second result row is present' {
        $lines = @($searchBox, $row1Name, $row1Time, $row1Prev1, $row2Name)
        Test-SingleResultLines -Lines $lines -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
    }

    It 'is false when any text sits below the first row, even a line that is not a name' {
        $lines = @($searchBox, $row1Name, $row1Prev1, $row3Prev)
        Test-SingleResultLines -Lines $lines -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
    }

    It 'is false when the only match is the text typed in the search box (no result row)' {
        Test-SingleResultLines -Lines @($searchBox) -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
    }

    It 'is false when the first row is another room' {
        $other = New-Line '다른방 5' 214 238
        Test-SingleResultLines -Lines @($searchBox, $other, $row1Prev1) -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
    }

    It 'is false when the expected name is only part of a longer room name' {
        foreach ($text in '테스트방방 1', 'AI 테스트방 3', '테스트방입니다') {
            $line = New-Line $text 214 238
            Test-SingleResultLines -Lines @($searchBox, $line) -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
        }
    }

    It 'ignores spaces that the text reader inserts or drops inside the name' {
        $spaced = New-Line '테스트 방 1' 214 238
        Test-SingleResultLines -Lines @($searchBox, $spaced) -ExpectedName '테스트방' -ImageHeight $H | Should Be $true
        $joined = New-Line '건축 AI방 12' 214 238
        Test-SingleResultLines -Lines @($searchBox, $joined) -ExpectedName '건축 AI방' -ImageHeight $H | Should Be $true
    }

    It 'accepts digits, punctuation and icon symbols after the name, but not letters' {
        $icon = New-Line '테스트방 1 ◉' 214 238
        Test-SingleResultLines -Lines @($icon) -ExpectedName '테스트방' -ImageHeight $H | Should Be $true
        $letters = New-Line '테스트방 1 abc' 214 238
        Test-SingleResultLines -Lines @($letters) -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
    }

    It 'is false (never throws) for no lines, a null list, an empty name or a bad image height' {
        Test-SingleResultLines -Lines @() -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
        Test-SingleResultLines -Lines $null -ExpectedName '테스트방' -ImageHeight $H | Should Be $false
        Test-SingleResultLines -Lines @($row1Name) -ExpectedName '' -ImageHeight $H | Should Be $false
        Test-SingleResultLines -Lines @($row1Name) -ExpectedName '테스트방' -ImageHeight 0 | Should Be $false
        Test-SingleResultLines -Lines @($row1Name) -ExpectedName '테스트방' -ImageHeight -5 | Should Be $false
    }
}

Describe 'Ocr: Test-SearchResultSingle (캡처 -> 판정 연결)' {
    It 'passes the window handle to the capture and decides from its lines and height' {
        # GetNewClosure 는 파일 최상위 변수를 붙잡지 못하므로 지역 변수로 복사해 둔다.
        $seen = New-Object System.Collections.ArrayList
        $shotLines = @($searchBox, $row1Name, $row1Prev1)
        $shotHeight = $H
        $capture = { param($h) [void]$seen.Add($h); [pscustomobject]@{ Lines = $shotLines; Height = $shotHeight } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 4242 -ExpectedName '테스트방' -Capture $capture | Should Be $true
        $seen.Count | Should Be 1
        $seen[0] | Should Be 4242
    }

    It 'is false when the captured lines show two rows' {
        $shotLines = @($row1Name, $row2Name)
        $shotHeight = $H
        $capture = { param($h) [pscustomobject]@{ Lines = $shotLines; Height = $shotHeight } }.GetNewClosure()
        # 대조군: 같은 연결에서 둘째 줄만 빼면 참이어야 한다(그래야 아래 거짓이 "캡처가 비어서"가 아니라 "둘째 줄 때문"임이 보인다).
        $onlyFirst = @($row1Name)
        $controlCapture = { param($h) [pscustomobject]@{ Lines = $onlyFirst; Height = $shotHeight } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -Capture $controlCapture | Should Be $true
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -Capture $capture | Should Be $false
    }
}

Describe 'Ocr: 화면 글자 읽기 엔진' {
    It 'Test-OcrAvailable returns a plain boolean and never throws' {
        $e = Get-ThrownError { [void](Test-OcrAvailable) }
        $e | Should BeNullOrEmpty
        (Test-OcrAvailable) -is [bool] | Should Be $true
    }

    It 'reads a Korean room name from a synthetic bitmap (passes trivially on a PC without the Korean reader)' {
        if (-not (Test-OcrAvailable)) { return }
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap 520, 140
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.Clear([System.Drawing.Color]::White)
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                $font = New-Object System.Drawing.Font 'Malgun Gothic', 36, ([System.Drawing.FontStyle]::Bold)
                $g.DrawString('테스트방 1', $font, [System.Drawing.Brushes]::Black, 20, 30)
            }
            finally { $g.Dispose() }
            $lines = @(Get-OcrLines -Bitmap $bmp)
        }
        finally { $bmp.Dispose() }
        $lines.Count | Should BeGreaterThan 0
        (($lines | ForEach-Object { $_.Text }) -join ' ') -replace '\s', '' | Should Match '테스트방'
        $lines[0].Bottom | Should BeGreaterThan $lines[0].Top
    }
}

Describe 'Ocr: 읽기만 하는 파일' {
    It 'Ocr.ps1 never writes to disk, so what was on screen cannot leak (capture stays in memory)' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Ocr.ps1') -Raw -Encoding UTF8
        $src | Should Not Match 'Set-Content|Out-File|Add-Content|New-Item|\[System\.IO\.File\]::|\.Save\(\s*\$path'
    }

    It 'Ocr.ps1 sends no keys, clicks or window-close requests' {
        $src = Get-Content -LiteralPath (Join-Path $kitLibDir 'Ocr.ps1') -Raw -Encoding UTF8
        $src | Should Not Match 'Send-KeyCombo|Invoke-RelClick|Close-KakaoWindow|SendInput|PostClose|mouse_event'
    }
}
