$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('InputProbe')
. (Join-Path $here '_Load.ps1')

# 방 창의 입력란을 "읽기만" 해서 비었는지 판정하는 부품(UI 자동화). 2026-11-15 읽기 전용 조사: 입력란은 RICHEDIT50W 컨트롤이고,
# 비어 있을 때는 안내 문구 "메시지 입력" 이 그대로 글로 읽힌다(값은 끝에 줄바꿈 하나가 더 붙음). 아래 시험은 판정 규칙과 "읽기만 한다"는 약속을 지킨다.
Describe 'InputProbe: 입력란 글 판정 (ConvertTo-InputState)' {
    It 'an empty box reads as empty: nothing at all, or only the placeholder, with at most ONE trailing line break' {
        foreach ($t in '', '메시지 입력', "메시지 입력`r", "메시지 입력`n", "메시지 입력`r`n", "`r", "`n", "`r`n") {
            ConvertTo-InputState -Text $t | Should Be 'empty'
        }
    }

    It 'anything else is a draft: text, whitespace, several line breaks, the placeholder with extra text, a different letter case' {
        foreach ($t in '초안시험', ' ', "`t", "`r`n`r`n", "`n`n", "`r`r", '메시지 입력 ', ' 메시지 입력', '메시지 입력!', '메시지  입력', "a`nb", '[kit-send-test 1]', "메시지 입력`r`n`r`n") {
            ConvertTo-InputState -Text $t | Should Be 'draft'
        }
    }

    It 'a value that could not be read is unknown, never empty' {
        ConvertTo-InputState -Text $null | Should Be 'unknown'
        ConvertTo-InputState -Text 5 | Should Be 'unknown'
        ConvertTo-InputState -Text $true | Should Be 'unknown'
        ConvertTo-InputState -Text @('a', 'b') | Should Be 'unknown'
    }
}

Describe 'InputProbe: 두 가지 읽기 결과를 합치는 규칙 (Merge-InputStates)' {
    It 'is empty only when both readings say empty' {
        Merge-InputStates -A 'empty' -B 'empty' | Should Be 'empty'
    }

    It 'is a draft when either reading says draft, whatever the other says' {
        foreach ($other in 'empty', 'draft', 'unknown') {
            Merge-InputStates -A 'draft' -B $other | Should Be 'draft'
            Merge-InputStates -A $other -B 'draft' | Should Be 'draft'
        }
    }

    It 'is unknown when it is not certain (one reading is missing or odd)' {
        Merge-InputStates -A 'empty' -B 'unknown' | Should Be 'unknown'
        Merge-InputStates -A 'unknown' -B 'empty' | Should Be 'unknown'
        Merge-InputStates -A 'unknown' -B 'unknown' | Should Be 'unknown'
        Merge-InputStates -A 'empty' -B 'weird' | Should Be 'unknown'
        Merge-InputStates -A $null -B 'empty' | Should Be 'unknown'
    }
}

Describe 'InputProbe: 실제 읽기는 실패해도 던지지 않고 unknown 이다' {
    It 'returns unknown for a window that does not exist, and for an invalid handle' {
        foreach ($h in 0, 1, 123456789) {
            Get-KakaoInputState -Hwnd $h | Should Be 'unknown'
        }
    }
}

Describe 'InputProbe: 읽기만 한다는 약속 (소스 검사)' {
    # 이 파일에 쓰기·클릭·키·포커스를 바꾸는 호출이 들어오면 시험이 깨진다. 주석 줄은 검사하지 않는다.
    It 'the source never writes a value, clicks, sends keys, moves focus or presses a control' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\InputProbe.ps1'))
        $code = (($text -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        $forbidden = 'SetValue', 'Invoke', 'SetFocus', 'SendKeys', 'SendInput', 'keybd_event', 'mouse_event', 'PostMessage', 'SendMessage',
        'SetForegroundWindow', 'Click', 'Expand', 'Collapse', 'Toggle', 'Select', 'Scroll', 'Set-Clipboard', 'ClipboardText'
        $hits = @($forbidden | Where-Object { $code.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        ($hits -join ', ') | Should BeNullOrEmpty
    }

    It 'only reads properties and the value/text patterns, and only of the one input control' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\InputProbe.ps1'))
        $text.Contains('RICHEDIT50W') | Should Be $true
        $text.Contains('ValuePattern') | Should Be $true
        $text.Contains('TextPattern') | Should Be $true
    }

    It 'never writes the text it reads to the screen, a log or a file' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\InputProbe.ps1'))
        $code = (($text -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        foreach ($bad in 'Write-Host', 'Write-Output', 'Write-Verbose', 'Write-Debug', 'Write-KitLog', 'Out-File', 'Add-Content', 'Set-Content', 'WriteAllText', 'AppendAllText') {
            $code.IndexOf($bad, [System.StringComparison]::OrdinalIgnoreCase) | Should Be -1
        }
    }
}
