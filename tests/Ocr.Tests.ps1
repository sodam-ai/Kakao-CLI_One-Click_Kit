$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Ocr')
. (Join-Path $here '_Load.ps1')

# 캡처 한 장(창 588x753)에서 본 실제 배치를 본뜬 가짜 OCR 줄이다. Left/Top/Bottom 은 픽셀이다. 실제 화면은 건드리지 않는다.
function New-Line([string]$Text, [double]$Left, [double]$Top, [double]$Bottom) { [pscustomobject]@{ Text = $Text; Left = $Left; Right = $Left + 20 * $Text.Length; Top = $Top; Bottom = $Bottom } }
$W = 588
$H = 753
$ClickY = 0.335                                                  # 첫 결과 줄을 더블클릭할 높이(Room.ps1 의 값과 같다)
$searchBox = New-Line '테스트방' 188 144 168                      # 검색창 안의 글자(중심 0.21): 결과 영역 밖
$row1Name = New-Line '테스트방 1' 220 214 238                     # 첫 결과 줄의 방 이름 + 참여자 수(중심 0.30, 이름 칸)
$row1Time = New-Line '오후 5:53' 490 230 248                      # 시각(오른쪽 끝, 이름 칸 밖)
$row1Prev1 = New-Line '새로운 채팅방이 생성되었습니다.' 220 245 267
$row1Prev2 = New-Line '생성되었습니다.' 220 268 290                # 미리보기가 두 줄로 접힌 것(중심 0.37): 첫 줄 안
$row2Name = New-Line '다른방 5' 220 314 338                       # 둘째 결과 줄(중심 0.43)
$row3Prev = New-Line '아래쪽 어딘가의 글자' 220 400 420            # 셋째 줄 근처(중심 0.54)
$ad = New-Line '광고 문구' 60 636 660                              # 광고 영역(중심 0.86): 결과 영역 밖

# 판정 함수를 짧게 부르는 도우미(기본값은 위의 실제 배치).
function Test-Single($lines, [string]$name = '테스트방', [double]$clickY = $ClickY, [double]$width = $W, [double]$height = $H) {
    return (Test-SingleResultLines -Lines $lines -ExpectedName $name -ImageWidth $width -ImageHeight $height -ClickRelY $clickY)
}

Describe 'Ocr: Test-SingleResultLines (정확히 1건인가, 화면 없이 판정)' {
    It 'is true when the room name with its member count is the only result row' {
        Test-Single @($searchBox, $row1Name, $row1Time, $row1Prev1, $row1Prev2) | Should Be $true
    }

    It 'ignores the ad below the result area' {
        Test-Single @($searchBox, $row1Name, $row1Time, $row1Prev1, $ad) | Should Be $true
    }

    It 'is false when a second result row is present' {
        Test-Single @($searchBox, $row1Name, $row1Time, $row1Prev1, $row2Name) | Should Be $false
    }

    It 'is false when any text sits below the first row, even a line that is not a name' {
        Test-Single @($searchBox, $row1Name, $row1Prev1, $row3Prev) | Should Be $false
    }

    It 'is false when the only match is the text typed in the search box (no result row)' {
        Test-Single @($searchBox) | Should Be $false
    }

    It 'is false when the first row is another room' {
        $other = New-Line '다른방 5' 220 214 238
        Test-Single @($searchBox, $other, $row1Prev1) | Should Be $false
    }

    It 'is false when only a PREVIEW line equals the room name (another room whose last message is the name)' {
        $otherName = New-Line '다른방 5' 220 214 238
        $spoofPreview = New-Line '테스트방' 220 245 267
        Test-Single @($searchBox, $otherName, $spoofPreview) | Should Be $false
        $spoofWithDigit = New-Line '테스트방 1' 220 245 267
        Test-Single @($searchBox, $otherName, $spoofWithDigit) | Should Be $false
    }

    It 'is false when the expected name is only part of a longer room name, including a digit glued to the name' {
        foreach ($text in '테스트방방 1', 'AI 테스트방 3', '테스트방입니다', '테스트방2 1', '테스트방2', '테스트방12') {
            $line = New-Line $text 220 214 238
            Test-Single @($searchBox, $line) | Should Be $false
        }
    }

    It 'ignores spaces that the text reader inserts or drops inside the name, and accepts a name without a count' {
        Test-Single @($searchBox, (New-Line '테스트 방 1' 220 214 238)) | Should Be $true
        Test-Single @($searchBox, (New-Line '건축 AI방 12' 220 214 238)) '건축 AI방' | Should Be $true
        Test-Single @($searchBox, (New-Line '테스트방' 220 214 238)) | Should Be $true
    }

    It 'accepts a count of up to 5 digits and icon symbols after the name, but not letters or a longer number' {
        Test-Single @((New-Line '테스트방 1 ◉' 220 214 238)) | Should Be $true
        Test-Single @((New-Line '테스트방 12345' 220 214 238)) | Should Be $true
        Test-Single @((New-Line '테스트방 123456' 220 214 238)) | Should Be $false
        Test-Single @((New-Line '테스트방 1 abc' 220 214 238)) | Should Be $false
    }

    It 'takes the title only from the name column (a matching line at the far right is not the title)' {
        Test-Single @($searchBox, (New-Line '테스트방 1' 450 214 238), $row1Prev1) | Should Be $false
    }

    It 'requires the double-click height to fall inside the first row text block' {
        Test-Single @($searchBox, $row1Name, $row1Prev1, $row1Prev2) | Should Be $true
        Test-Single @($searchBox, $row1Name, $row1Prev1, $row1Prev2) '테스트방' 0.20 | Should Be $false
        Test-Single @($searchBox, $row1Name, $row1Prev1, $row1Prev2) '테스트방' 0.60 | Should Be $false
    }

    It 'refuses a window size other than the measured 588x753 (1.5% tolerance), at the edges of the tolerance and just outside it' {
        $three = @($searchBox, $row1Name, $row1Prev1)
        Test-Single $three '테스트방' $ClickY 900 500 | Should Be $false
        Test-Single $three '테스트방' $ClickY 588 753 | Should Be $true
        foreach ($size in @(580, 753), @(596, 753), @(588, 742), @(588, 764)) { Test-Single $three '테스트방' $ClickY $size[0] $size[1] | Should Be $true }
        foreach ($size in @(579, 753), @(597, 753), @(588, 741), @(588, 765), @(560, 730), @(640, 753)) { Test-Single $three '테스트방' $ClickY $size[0] $size[1] | Should Be $false }
    }

    It 'is false (never throws) for no lines, a null list, an empty name, bad sizes or a bad click height' {
        Test-Single @() | Should Be $false
        Test-Single $null | Should Be $false
        Test-Single @($row1Name) '' | Should Be $false
        Test-Single @($row1Name) '테스트방' $ClickY $W 0 | Should Be $false
        Test-Single @($row1Name) '테스트방' $ClickY 0 $H | Should Be $false
        Test-Single @($row1Name) '테스트방' $ClickY $W -5 | Should Be $false
        Test-Single @($row1Name) '테스트방' 0 | Should Be $false
        Test-Single @($row1Name) '테스트방' 1.5 | Should Be $false
    }
}

# 실제 화면(588x753, 오픈채팅 탭)을 한국어 글자 읽기로 읽은 결과를 본뜬 가짜 줄이다. 값은 픽셀이고 개인정보는 없다.
# 실제로 확인한 것: 방 이름 앞의 배지 아이콘이 숫자 0 한 글자로 읽히고, 왼쪽 메뉴 아이콘도 0 으로 읽히며,
# 어떤 행은 이름 앞부분이 통째로 안 읽혀 이름 단어가 오른쪽(0.46)에서 시작했다. 이름 단어는 보통 0.42 에서 시작한다.
function New-WordLine([object[]]$Words, [double]$Top, [double]$Bottom) {
    $objs = @($Words | ForEach-Object { [pscustomobject]@{ Text = [string]$_[0]; Left = [double]$_[1]; Right = [double]$_[2] } })
    [pscustomobject]@{
        Text   = (($objs | ForEach-Object { $_.Text }) -join ' ')
        Left   = ($objs | Measure-Object -Property Left -Minimum).Minimum
        Right  = ($objs | Measure-Object -Property Right -Maximum).Maximum
        Top    = $Top
        Bottom = $Bottom
        Words  = $objs
    }
}
$realTitle = New-WordLine @(@('0', 219, 242), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
$realTime = New-WordLine @(@('오후', 485, 517), @('553', 525, 553)) 229 245
$realPrev1 = New-WordLine @(@('새로운', 220, 272), @('재팅방이', 280, 349), @('생성듸었습니', 358, 463)) 247 264
$realPrev2 = New-WordLine @(,@('다.', 221, 240)) 270 286
$leftMenuBell = New-WordLine @(,@('0', 37, 60)) 472 498
$leftMenuGear = New-WordLine @(,@('0', 43, 54)) 541 552
$oneResult = @($realTitle, $realTime, $realPrev1, $realPrev2, $leftMenuBell, $leftMenuGear)

Describe 'Ocr: 실제 화면에서 본 배치(글자 상자 위치로 판정)' {
    It 'is true for the real one-result screen: the icon read as a stray 0 and the left-menu icons read as characters' {
        Test-Single $oneResult | Should Be $true
    }

    It 'ignores text in the left menu column but not a stray glyph inside the result list below the first row' {
        Test-Single @($realTitle, $realTime, $realPrev1, $leftMenuBell) | Should Be $true
        $strayInList = New-WordLine @(,@('0', 160, 180)) 480 500
        Test-Single @($realTitle, $realTime, $realPrev1, $strayInList) | Should Be $false
    }

    It 'does not care about a glyph from the avatar picture inside the first row, but a glyph below it is a second row' {
        $avatarInRow = New-WordLine @(,@('들', 151, 164)) 225 240
        $avatarBelow = New-WordLine @(,@('들', 151, 164)) 555 572
        Test-Single @($realTitle, $realTime, $avatarInRow) | Should Be $true
        Test-Single @($realTitle, $realTime, $avatarBelow) | Should Be $false
    }

    It 'ignores exactly one single-character word in the icon slot, whatever character the reader made of the icon' {
        foreach ($glyph in '0', 'o', 'O', '©') {
            $line = New-WordLine @(@($glyph, 219, 242), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
            Test-Single @($line, $realTime, $realPrev1) | Should Be $true
        }
    }

    It 'is false when the icon slot holds two characters or two words' {
        $twoChars = New-WordLine @(@('AI', 219, 242), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
        $twoWords = New-WordLine @(@('0', 219, 230), @('o', 232, 242), @('테스트방', 247, 318)) 216 239
        Test-Single @($twoChars, $realTime, $realPrev1) | Should Be $false
        Test-Single @($twoWords, $realTime, $realPrev1) | Should Be $false
    }

    It 'is false when the reader dropped the front of the name so the name word starts too far right (another room that ends with this name)' {
        $prefixDropped = New-WordLine @(@('0', 219, 242), @('테스트방', 271, 342)) 216 239
        Test-Single @($prefixDropped, $realTime, $realPrev1) | Should Be $false
        $noIconPrefixDropped = New-WordLine @(@('테스트방', 271, 342), @('1', 349, 355)) 216 239
        Test-Single @($noIconPrefixDropped, $realTime, $realPrev1) | Should Be $false
    }

    It 'accepts the name start only within 3 pixels of the measured 247, with or without an icon word, at every allowed window width' {
        foreach ($width in 580, 588, 596) {
            foreach ($start in 244, 247, 250) {
                $withIcon = New-WordLine @(@('0', 219, 242), @('테스트방', $start, ($start + 71)), @('1', ($start + 78), ($start + 84))) 216 239
                $noIcon = New-WordLine @(@('테스트방', $start, ($start + 71)), @('1', ($start + 78), ($start + 84))) 216 239
                foreach ($line in $withIcon, $noIcon) {
                    Test-Single @($line, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $true
                }
            }
            foreach ($start in 243, 251, 252, 254, 255, 262) {
                $withIcon = New-WordLine @(@('0', 219, 242), @('테스트방', $start, ($start + 71)), @('1', ($start + 78), ($start + 84))) 216 239
                $noIcon = New-WordLine @(@('테스트방', $start, ($start + 71)), @('1', ($start + 78), ($start + 84))) 216 239
                foreach ($line in $withIcon, $noIcon) {
                    Test-Single @($line, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $false
                }
            }
        }
    }

    It 'accepts at most 8 pixels between the icon word and the name (the measured gap is about 5), so an icon far from the name is refused' {
        $gap8 = New-WordLine @(@('0', 219, 239), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
        $gap9 = New-WordLine @(@('0', 219, 238), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
        $farIcon = New-WordLine @(@('0', 219, 226), @('테스트방', 247, 318), @('1', 325, 331)) 216 239
        foreach ($width in 580, 588, 596) {
            Test-Single @($gap8, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $true
            Test-Single @($gap9, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $false
            Test-Single @($farIcon, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $false
            Test-Single @($realTitle, $realTime, $realPrev1) '테스트방' $ClickY $width $H | Should Be $true
        }
    }

    It 'is false when something is glued to or in front of the name, so it is another room' {
        foreach ($spoof in @(
                @(@('0', 219, 242), @('0테스트방', 247, 330)),
                @(@('0', 219, 242), @('내테스트방', 247, 350)),
                @(@('0', 219, 242), @('A', 247, 260), @('테스트방', 266, 337)),
                @(@('0', 219, 242), @('테스트방입니다', 247, 380)))) {
            $line = New-WordLine $spoof 216 239
            Test-Single @($line, $realTime, $realPrev1) | Should Be $false
        }
    }

    It 'accepts the name without an icon word when it starts at the name position, not when it starts at the icon position' {
        $noIcon = New-WordLine @(@('테스트방', 247, 318), @('1', 325, 331)) 216 239
        $atIconPosition = New-WordLine @(@('테스트방', 219, 290), @('1', 297, 303)) 216 239
        Test-Single @($noIcon, $realTime, $realPrev1) | Should Be $true
        Test-Single @($atIconPosition, $realTime, $realPrev1) | Should Be $false
    }

    It 'keeps the rule that only a count and symbols may follow the name' {
        $symbol = New-WordLine @(@('0', 219, 242), @('테스트방', 247, 318), @('1', 325, 331), @('◉', 337, 350)) 216 239
        $letters = New-WordLine @(@('0', 219, 242), @('테스트방', 247, 318), @('1', 325, 331), @('abc', 337, 365)) 216 239
        Test-Single @($symbol, $realTime, $realPrev1) | Should Be $true
        Test-Single @($letters, $realTime, $realPrev1) | Should Be $false
    }

    It 'is false for the real multi-row screen, even when a second row has exactly the same title' {
        $row2Title = New-WordLine @(@('0', 219, 242), @('다른방', 271, 383)) 321 344
        $row2Time = New-WordLine @(@('오후', 485, 517), @('849', 525, 553)) 334 350
        Test-Single ($oneResult + @($row2Title, $row2Time)) | Should Be $false
        $row2Same = New-WordLine @(@('0', 219, 242), @('테스트방', 247, 318), @('1', 325, 331)) 321 344
        Test-Single ($oneResult + @($row2Same)) | Should Be $false
    }

    It 'stays strict for lines that carry no word boxes: the whole line text must be the name, so a stray icon character fails' {
        Test-Single @((New-Line '0 테스트방 1' 220 214 238)) | Should Be $false
        Test-Single @((New-Line '테스트방 1' 220 214 238)) | Should Be $true
    }
}

Describe 'Ocr: Test-MainWindowUncovered (판정 영역이 가려지지 않았는가)' {
    $rect = [pscustomobject]@{ Left = 100; Top = 200; Right = 688; Bottom = 953 }
    function New-OwnerProvider($owner) { return @{ RootAtPoint = { param($x, $y) $owner }.GetNewClosure() } }

    It 'is true when every sampled point of the result area belongs to the window' {
        Test-MainWindowUncovered -Hwnd 55 -Rect $rect -Provider (New-OwnerProvider 55) | Should Be $true
    }

    It 'is false when another window covers even one sampled point' {
        $seen = New-Object System.Collections.ArrayList
        $provider = @{ RootAtPoint = { param($x, $y) [void]$seen.Add(1); if ($seen.Count -eq 7) { 99 } else { 55 } }.GetNewClosure() }
        Test-MainWindowUncovered -Hwnd 55 -Rect $rect -Provider $provider | Should Be $false
    }

    It 'is false when the window at a point is unknown' {
        Test-MainWindowUncovered -Hwnd 55 -Rect $rect -Provider (New-OwnerProvider $null) | Should Be $false
        Test-MainWindowUncovered -Hwnd 55 -Rect $rect -Provider (New-OwnerProvider 0) | Should Be $false
    }
}

Describe 'Ocr: Test-SearchResultSingle (캡처 -> 판정 연결)' {
    It 'passes the window handle to the capture and decides from its lines, size and the click height' {
        # GetNewClosure 는 파일 최상위 변수를 붙잡지 못하므로 지역 변수로 복사해 둔다.
        $seen = New-Object System.Collections.ArrayList
        $shotLines = @($searchBox, $row1Name, $row1Prev1)
        $shotW = $W
        $shotH = $H
        $capture = { param($h) [void]$seen.Add($h); [pscustomobject]@{ Lines = $shotLines; Width = $shotW; Height = $shotH } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 4242 -ExpectedName '테스트방' -ClickRelY 0.335 -Capture $capture | Should Be $true
        $seen.Count | Should Be 1
        $seen[0] | Should Be 4242
        Test-SearchResultSingle -Hwnd 4242 -ExpectedName '테스트방' -ClickRelY 0.90 -Capture $capture | Should Be $false
    }

    It 'is false when the captured lines show two rows (with a control that is true)' {
        $shotW = $W
        $shotH = $H
        $two = @($row1Name, $row2Name)
        $one = @($row1Name)
        $captureTwo = { param($h) [pscustomobject]@{ Lines = $two; Width = $shotW; Height = $shotH } }.GetNewClosure()
        $captureOne = { param($h) [pscustomobject]@{ Lines = $one; Width = $shotW; Height = $shotH } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.30 -Capture $captureOne | Should Be $true
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.30 -Capture $captureTwo | Should Be $false
    }

    It 'is false when the capture says the window was covered, even if the lines look right' {
        $shotLines = @($searchBox, $row1Name, $row1Prev1)
        $shotW = $W
        $shotH = $H
        $capture = { param($h) [pscustomobject]@{ Lines = $shotLines; Width = $shotW; Height = $shotH; Covered = $true } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.335 -Capture $capture | Should Be $false
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

    It 'returns the word boxes of every line, each inside its line (passes trivially without the Korean reader)' {
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
        @($lines[0].Words).Count | Should BeGreaterThan 0
        foreach ($word in @($lines[0].Words)) {
            $word.Text.Length | Should BeGreaterThan 0
            $word.Right | Should BeGreaterThan $word.Left
            $word.Left | Should BeGreaterThan ($lines[0].Left - 0.5)
            $word.Right | Should BeLessThan ($lines[0].Right + 0.5)
        }
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
