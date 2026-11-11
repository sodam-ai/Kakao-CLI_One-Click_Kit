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
function Test-Single($lines, [string]$name = '테스트방', [double]$clickY = $ClickY, [double]$width = $W, [double]$height = $H, [double]$scale = 1.5) {
    return (Test-SingleResultLines -Lines $lines -ExpectedName $name -ImageWidth $width -ImageHeight $height -ClickRelY $clickY -Scale $scale)
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

# 배율이 다른 모니터: 같은 카카오톡 창이 배율 150% 에서는 588x753, 100% 에서는 392x502 로 보인다(588 / 1.5 = 392).
# 줄의 픽셀 값에 배율 비율을 곱해 다른 배율에서 읽힌 것처럼 만든다.
function Convert-LinesScale($Lines, [double]$Factor) {
    @(foreach ($l in $Lines) {
        $o = [pscustomobject]@{ Text = $l.Text; Left = $l.Left * $Factor; Right = $l.Right * $Factor; Top = $l.Top * $Factor; Bottom = $l.Bottom * $Factor }
        if ($l.PSObject.Properties['Words'] -and $null -ne $l.Words) {
            $o | Add-Member -NotePropertyName Words -NotePropertyValue @($l.Words | ForEach-Object { [pscustomobject]@{ Text = $_.Text; Left = $_.Left * $Factor; Right = $_.Right * $Factor } })
        }
        $o
    })
}

Describe 'Ocr: 배율이 다른 모니터(같은 창을 배율로 나눠 판정)' {
    It 'judges the same real screen at 100%, 125%, 150% and 200% window scale' {
        foreach ($s in 1.0, 1.25, 1.5, 2.0) {
            $factor = $s / 1.5
            $lines = Convert-LinesScale $oneResult $factor
            Test-Single $lines '테스트방' $ClickY ([Math]::Round(588 * $factor)) ([Math]::Round(753 * $factor)) $s | Should Be $true
        }
    }

    It 'refuses the same lines when the stated scale does not match the window size' {
        $lines100 = Convert-LinesScale $oneResult (1.0 / 1.5)
        Test-Single $lines100 '테스트방' $ClickY 392 502 1.0 | Should Be $true
        Test-Single $lines100 '테스트방' $ClickY 392 502 1.5 | Should Be $false
        Test-Single $oneResult '테스트방' $ClickY 588 753 1.5 | Should Be $true
        Test-Single $oneResult '테스트방' $ClickY 588 753 1.0 | Should Be $false
    }

    It 'scales the name-start tolerance too: at 100% the name must start within 2 pixels of 164.7 and the icon gap is at most 5.3' {
        $time100 = Convert-LinesScale @($realTime, $realPrev1) (1.0 / 1.5)
        foreach ($start in 163, 165, 166) {
            $title = New-WordLine @(@('0', 146, 161), @('테스트방', $start, ($start + 47)), @('1', ($start + 52), ($start + 56))) 144 159
            Test-Single (@($title) + $time100) '테스트방' $ClickY 392 502 1.0 | Should Be $true
        }
        foreach ($start in 162, 167, 170, 180) {
            $title = New-WordLine @(@('0', 146, 161), @('테스트방', $start, ($start + 47)), @('1', ($start + 52), ($start + 56))) 144 159
            Test-Single (@($title) + $time100) '테스트방' $ClickY 392 502 1.0 | Should Be $false
        }
    }

    It 'Test-SearchResultSingle uses the scale the capture reports, and a capture that does not report one is judged as 100%' {
        $one150 = $oneResult
        $one100 = Convert-LinesScale $oneResult (1.0 / 1.5)
        $capture100 = { param($h) [pscustomobject]@{ Lines = $one100; Width = 392; Height = 502; Scale = 1.0 } }.GetNewClosure()
        $capture150 = { param($h) [pscustomobject]@{ Lines = $one150; Width = 588; Height = 753; Scale = 1.5 } }.GetNewClosure()
        $capture150NoScale = { param($h) [pscustomobject]@{ Lines = $one150; Width = 588; Height = 753 } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.335 -Capture $capture100 | Should Be $true
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.335 -Capture $capture150 | Should Be $true
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.335 -Capture $capture150NoScale | Should Be $false
    }

    It 'Get-KitWindowScale never throws and answers 1.0 when the window scale is unknown' {
        $e = Get-ThrownError { [void](Get-KitWindowScale -Hwnd 0) }
        $e | Should BeNullOrEmpty
        (Get-KitWindowScale -Hwnd 0) | Should Be 1
    }

    # D-24: 카카오톡 창은 "시스템 DPI 인식"이라 150% 모니터에서도 창 DPI 가 96 으로 나온다(2026-11-10 실측). 화면에 보이는 크기는 모니터 배율을 따르므로 모니터 값을 우선한다.
    It 'Select-KitDpi prefers the monitor DPI, because a system-aware window reports 96 on a 150% monitor (D-24)' {
        Select-KitDpi -WindowDpi 96 -MonitorDpi 144 | Should Be 144
        Select-KitDpi -WindowDpi 144 -MonitorDpi 144 | Should Be 144
        Select-KitDpi -WindowDpi 144 -MonitorDpi 96 | Should Be 96
        Select-KitDpi -WindowDpi 96 -MonitorDpi 96 | Should Be 96
    }

    It 'Select-KitDpi falls back to the window DPI and then to 96 when a value is unknown' {
        Select-KitDpi -WindowDpi 144 -MonitorDpi 0 | Should Be 144
        Select-KitDpi -WindowDpi 0 -MonitorDpi 120 | Should Be 120
        Select-KitDpi -WindowDpi 0 -MonitorDpi 0 | Should Be 96
        Select-KitDpi -WindowDpi -1 -MonitorDpi -1 | Should Be 96
    }

    It 'Get-KitWindowScale answers a plausible scale (1.0 to 3.0) for every visible window on this PC' {
        Enable-KitDpiAwareness
        foreach ($h in [KakaoWin32]::TopLevelWindows()) {
            if (-not [KakaoWin32]::IsVisible($h)) { continue }
            $s = Get-KitWindowScale -Hwnd $h
            ($s -ge 1.0 -and $s -le 3.0) | Should Be $true
        }
    }

    # D-24 보강(2026-11-11, Codex 검증 지적): 모니터 DPI 는 이 프로세스가 모니터별 DPI 인식(2)일 때만 믿을 수 있다.
    # 아니면(시스템 인식 1, 비인식 0, 모름 -1) 모니터 값도 시스템 값으로 나와 같은 결함이 조용히 되살아나므로 믿지 않고 창 값을 쓴다(= 고치기 전 동작, 안전하게 거절하는 쪽).
    It 'Select-KitDpi trusts the monitor DPI only when the process is per-monitor aware (awareness 2)' {
        Select-KitDpi -WindowDpi 96 -MonitorDpi 144 -Awareness 2 | Should Be 144
        Select-KitDpi -WindowDpi 96 -MonitorDpi 144 -Awareness 1 | Should Be 96
        Select-KitDpi -WindowDpi 96 -MonitorDpi 144 -Awareness 0 | Should Be 96
        Select-KitDpi -WindowDpi 96 -MonitorDpi 144 -Awareness -1 | Should Be 96
        Select-KitDpi -WindowDpi 0 -MonitorDpi 144 -Awareness 1 | Should Be 96
        Select-KitDpi -WindowDpi 120 -MonitorDpi 144 -Awareness 1 | Should Be 120
    }

    It 'Enable-KitDpiAwareness makes a fresh process per-monitor aware (the DPI fix depends on it)' {
        $win32 = Join-Path $kitLibDir 'Win32.ps1'
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ". '$win32'; Enable-KitDpiAwareness; [KakaoWin32]::ProcessDpiAwareness()"
        ([string]($out | Select-Object -Last 1)).Trim() | Should Be '2'
    }

    It 'Get-KitWindowScale hands the real process awareness to Select-KitDpi' {
        Enable-KitDpiAwareness
        $expected = [KakaoWin32]::ProcessDpiAwareness()
        Mock Select-KitDpi { return 96 }
        [void](Get-KitWindowScale -Hwnd 0)
        Assert-MockCalled Select-KitDpi -Exactly 1 -ParameterFilter ([scriptblock]::Create('$Awareness -eq ' + $expected))
    }
}

Describe 'Ocr: 창 크기 확인과 멈춘 이유 (읽기만 하는 도우미)' {
    It 'Test-WindowSizeMatches accepts the measured size at its own scale and refuses other sizes' {
        Test-WindowSizeMatches -Width 588 -Height 753 -Scale 1.5 | Should Be $true
        Test-WindowSizeMatches -Width 392 -Height 502 -Scale 1.0 | Should Be $true
        Test-WindowSizeMatches -Width 392 -Height 502 -Scale 1.5 | Should Be $false
        Test-WindowSizeMatches -Width 588 -Height 753 -Scale 1.0 | Should Be $false
        Test-WindowSizeMatches -Width 0 -Height 753 -Scale 1.5 | Should Be $false
        Test-WindowSizeMatches -Width 588 -Height 753 -Scale 0 | Should Be $false
        Test-WindowSizeMatches -Width 580 -Height 753 -Scale 1.5 | Should Be $true
        Test-WindowSizeMatches -Width 579 -Height 753 -Scale 1.5 | Should Be $false
    }

    It 'Get-RoomFailureReasonKey names the size problem first, then a covered window, and nothing when both are fine' {
        Get-RoomFailureReasonKey -Width 392 -Height 502 -Scale 1.5 -Covered $false | Should Be 'size'
        Get-RoomFailureReasonKey -Width 392 -Height 502 -Scale 1.5 -Covered $true | Should Be 'size'
        Get-RoomFailureReasonKey -Width 588 -Height 753 -Scale 1.5 -Covered $true | Should Be 'covered'
        Get-RoomFailureReasonKey -Width 588 -Height 753 -Scale 1.5 -Covered $false | Should Be ''
    }

    It 'Get-RoomFailureHint never throws, even for a window that does not exist, and answers a plain string' {
        $e = Get-ThrownError { [void](Get-RoomFailureHint -Hwnd 0) }
        $e | Should BeNullOrEmpty
        ((Get-RoomFailureHint -Hwnd 0) -is [string]) | Should Be $true
    }

    It 'the hint messages exist and say what to do' {
        Get-Msg -Key 'room.hint.size' -FormatArgs @(392, 502, 100, 588, 753) | Should Match '크기'
        Get-Msg -Key 'room.hint.covered' | Should Match '가려'
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
        $capture = { param($h) [void]$seen.Add($h); [pscustomobject]@{ Lines = $shotLines; Width = $shotW; Height = $shotH; Scale = 1.5 } }.GetNewClosure()
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
        $captureTwo = { param($h) [pscustomobject]@{ Lines = $two; Width = $shotW; Height = $shotH; Scale = 1.5 } }.GetNewClosure()
        $captureOne = { param($h) [pscustomobject]@{ Lines = $one; Width = $shotW; Height = $shotH; Scale = 1.5 } }.GetNewClosure()
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.30 -Capture $captureOne | Should Be $true
        Test-SearchResultSingle -Hwnd 1 -ExpectedName '테스트방' -ClickRelY 0.30 -Capture $captureTwo | Should Be $false
    }

    It 'is false when the capture says the window was covered, even if the lines look right' {
        $shotLines = @($searchBox, $row1Name, $row1Prev1)
        $shotW = $W
        $shotH = $H
        $capture = { param($h) [pscustomobject]@{ Lines = $shotLines; Width = $shotW; Height = $shotH; Scale = 1.5; Covered = $true } }.GetNewClosure()
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
