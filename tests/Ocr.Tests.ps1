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

    It 'refuses a window shape other than the measured one, but tolerates a small size difference' {
        Test-Single @($searchBox, $row1Name, $row1Prev1) '테스트방' $ClickY 900 500 | Should Be $false
        Test-Single @($searchBox, $row1Name, $row1Prev1) '테스트방' $ClickY 560 730 | Should Be $true
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
