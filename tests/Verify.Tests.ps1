$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Verify')
. (Join-Path $here '_Load.ps1')

# 보낸 글 확인(VerifySent)의 "판정" 부분만 시험한다. 내보낸 파일에서 읽은 메시지 목록에서 방금 보낸 글을 찾는 순수 함수이며,
# 카카오톡·클립보드·키·파일을 건드리지 않는다. 내보내기를 실제로 하는 부분(Ctrl+S, 저장 창)은 사람 확인 라운드 뒤에 따로 만든다.
function New-Msg([string]$Text, $Stamp, [string]$Sender = '나') {
    return [pscustomobject]@{ Timestamp = $Stamp; Sender = $Sender; Text = $Text }
}
$t0 = [datetime]'2026-11-15 13:05:30'

Describe 'Verify: 내보낸 메시지에서 방금 보낸 글 찾기' {
    It 'confirms when the exact text appears at or after the send minute' {
        $r = Find-SentMessageInExport -Messages @((New-Msg '안녕' ([datetime]'2026-11-15 13:05:00'))) -Text '안녕' -Since $t0 -SelfOnly $true
        $r.State | Should Be 'confirmed'
        $r.Matches | Should Be 1
        $r = Find-SentMessageInExport -Messages @((New-Msg '안녕' ([datetime]'2026-11-15 13:07:00'))) -Text '안녕' -Since $t0 -SelfOnly $true
        $r.State | Should Be 'confirmed'
    }

    It 'does not count the same text from before the send minute (an old message is not proof)' {
        $r = Find-SentMessageInExport -Messages @((New-Msg '안녕' ([datetime]'2026-11-15 13:04:00'))) -Text '안녕' -Since $t0 -SelfOnly $true
        $r.State | Should Be 'unknown'
        $r.Matches | Should Be 0
    }

    It 'ignores line-ending differences and trailing spaces but nothing else (multi-line text)' {
        $r = Find-SentMessageInExport -Messages @((New-Msg "첫째 줄`n둘째 줄" ([datetime]'2026-11-15 13:06:00'))) -Text "첫째 줄  `r`n둘째 줄 " -Since $t0 -SelfOnly $true
        $r.State | Should Be 'confirmed'
        foreach ($other in '첫째 줄 둘째 줄', "둘째 줄`n첫째 줄", '첫째 줄', "첫째 줄`n둘째 줄`n셋째 줄") {
            (Find-SentMessageInExport -Messages @((New-Msg "첫째 줄`n둘째 줄" ([datetime]'2026-11-15 13:06:00'))) -Text $other -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        }
    }

    It 'needs the exact text: a longer or shorter message, another case or another symbol is not a match' {
        $m = @((New-Msg 'Hello World' ([datetime]'2026-11-15 13:06:00')))
        foreach ($other in 'Hello', 'Hello World!', 'hello world', 'Hello  World', 'ello World') {
            (Find-SentMessageInExport -Messages $m -Text $other -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        }
        (Find-SentMessageInExport -Messages $m -Text 'Hello World' -Since $t0 -SelfOnly $true).State | Should Be 'confirmed'
    }

    It 'matches emoji exactly' {
        $e = [char]::ConvertFromUtf32(0x1F600) + [char]::ConvertFromUtf32(0x1F44D)
        (Find-SentMessageInExport -Messages @((New-Msg ('이모지 ' + $e) ([datetime]'2026-11-15 13:06:00'))) -Text ('이모지 ' + $e) -Since $t0 -SelfOnly $true).State | Should Be 'confirmed'
        (Find-SentMessageInExport -Messages @((New-Msg ('이모지 ' + $e) ([datetime]'2026-11-15 13:06:00'))) -Text ('이모지 ' + [char]::ConvertFromUtf32(0x1F600)) -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
    }

    It 'never confirms for a room that is not self-only (the sender cannot be told apart)' {
        $m = @((New-Msg '안녕' ([datetime]'2026-11-15 13:06:00') '다른사람'))
        (Find-SentMessageInExport -Messages $m -Text '안녕' -Since $t0 -SelfOnly $false).State | Should Be 'unknown'
        (Find-SentMessageInExport -Messages $m -Text '안녕' -Since $t0 -SelfOnly 'true').State | Should Be 'unknown'
        (Find-SentMessageInExport -Messages $m -Text '안녕' -Since $t0 -SelfOnly 1).State | Should Be 'unknown'
    }

    It 'reports how many matches there are (two means the same text may have gone out twice)' {
        $m = @((New-Msg '안녕' ([datetime]'2026-11-15 13:06:00')), (New-Msg '다른 글' ([datetime]'2026-11-15 13:06:10')), (New-Msg '안녕' ([datetime]'2026-11-15 13:06:40')))
        $r = Find-SentMessageInExport -Messages $m -Text '안녕' -Since $t0 -SelfOnly $true
        $r.State | Should Be 'confirmed'
        $r.Matches | Should Be 2
    }

    It 'skips messages with an unknown time and never throws on empty or odd input' {
        (Find-SentMessageInExport -Messages @((New-Msg '안녕' $null)) -Text '안녕' -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        (Find-SentMessageInExport -Messages @() -Text '안녕' -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        (Find-SentMessageInExport -Messages $null -Text '안녕' -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        (Find-SentMessageInExport -Messages @($null, 5, 'x', (New-Msg '안녕' ([datetime]'2026-11-15 13:06:00'))) -Text '안녕' -Since $t0 -SelfOnly $true).State | Should Be 'confirmed'
        foreach ($bad in $null, '', '   ') {
            (Find-SentMessageInExport -Messages @((New-Msg '안녕' ([datetime]'2026-11-15 13:06:00'))) -Text $bad -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
        }
        (Find-SentMessageInExport -Messages @([pscustomobject]@{ Timestamp = 'not a date'; Sender = 'a'; Text = '안녕' }) -Text '안녕' -Since $t0 -SelfOnly $true).State | Should Be 'unknown'
    }

    It 'is a pure judgement: no keys, clicks, clipboard, windows, files or logging in the source' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitRoot 'src\lib\Verify.ps1'))
        $code = (($text -split "`r?`n") | Where-Object { $_.TrimStart() -notmatch '^#' }) -join "`n"
        foreach ($bad in 'Send-KeyCombo', 'Invoke-RelClick', 'SendKeys', 'SendInput', 'Set-Clipboard', 'Get-Clipboard', 'Use-TextClipboard', 'Add-Type', 'Write-Host', 'Write-KitLog', 'Out-File', 'Set-Content', 'WriteAllText', 'ReadAllText', 'Remove-Item') {
            $code.IndexOf($bad, [System.StringComparison]::OrdinalIgnoreCase) | Should Be -1
        }
    }
}
