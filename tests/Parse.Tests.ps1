$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Parse')
. (Join-Path $here '_Load.ps1')

$sample = Join-Path $here 'fixtures\export-sample.txt'

# 내용을 임시 파일(UTF-8, BOM 없음)로 저장하고 경로를 돌려준다.
function New-TempExport([string]$Text, [switch]$Bom) {
    $p = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-export-' + [guid]::NewGuid().ToString('N') + '.txt')
    [System.IO.File]::WriteAllText($p, $Text, (New-Object System.Text.UTF8Encoding([bool]$Bom)))
    return $p
}

Describe 'Parse: 머리글' {
    It 'reads the room name and the saved time' {
        $r = ConvertFrom-KakaoExport -Path $sample
        $r.Room | Should Be '테스트방'
        $r.SavedAt | Should Be (New-Object DateTime 2026, 10, 27, 4, 10, 0)
    }

    It 'also accepts a group-chat header without "님과"' {
        $p = New-TempExport ("단체방 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n")
        try { (ConvertFrom-KakaoExport -Path $p).Room | Should Be '단체방' }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'returns zero messages for a header-only export' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n")
        try { @((ConvertFrom-KakaoExport -Path $p).Messages).Count | Should Be 0 }
        finally { Remove-Item -LiteralPath $p -Force }
    }
}

Describe 'Parse: 메시지' {
    It 'splits the sample into 4 messages with sender, time and text' {
        $m = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $m.Count | Should Be 4
        $m[0].Sender | Should Be '나'
        $m[0].Text | Should Be '자정 지나서 보낸 글'
        $m[3].Sender | Should Be '나'
        $m[3].Timestamp | Should Be (New-Object DateTime 2026, 10, 22, 23, 59, 0)
    }

    It '오전 12:05 is 00:05 and 오후 12:05 is 12:05' {
        $m = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $m[0].Timestamp | Should Be (New-Object DateTime 2026, 10, 21, 0, 5, 0)
        $m[1].Timestamp | Should Be (New-Object DateTime 2026, 10, 21, 2, 59, 0)
        $m[2].Timestamp | Should Be (New-Object DateTime 2026, 10, 21, 12, 5, 0)
    }

    It 'does not mistake a body that starts with [ for a new message' {
        $m = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $m[1].Sender | Should Be '나'
        $m[1].Text | Should Be '[kakao-kit test] send check'
    }

    It 'joins continuation lines with a line feed and trims the trailing blank line' {
        $m = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $m[2].Sender | Should Be '상대 친구'
        $m[2].Text | Should Be ("정오 직후`n여러 줄 메시지의 둘째 줄`n[이 줄은 대괄호로 시작하지만 헤더가 아님] 셋째 줄")
    }

    It 'keeps emoji, quotes and shell characters exactly' {
        $m = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $emoji = [char]::ConvertFromUtf32(0x1F600)
        $m[3].Text | Should Be ('이모지 ' + $emoji + ' 와 "따옴표" & % ^ ! | 기호')
    }

    It 'gives a null Timestamp to a message that appears before any date line' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n[나] [오전 2:59] 날짜 줄 없음`r`n")
        try {
            $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
            $m.Count | Should Be 1
            $m[0].Timestamp | Should BeNullOrEmpty
            $m[0].Text | Should Be '날짜 줄 없음'
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }
}

Describe 'Parse: 파일 형식 차이' {
    It 'gives the same result for LF, CRLF and a UTF-8 BOM' {
        $raw = [System.IO.File]::ReadAllText($sample, [System.Text.Encoding]::UTF8)
        $base = @((ConvertFrom-KakaoExport -Path $sample).Messages)
        $crlf = New-TempExport (($raw -replace "`r?`n", "`r`n"))
        $bom = New-TempExport $raw -Bom
        try {
            foreach ($p in $crlf, $bom) {
                $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
                $m.Count | Should Be $base.Count
                for ($i = 0; $i -lt $base.Count; $i++) {
                    $m[$i].Text | Should Be $base[$i].Text
                    $m[$i].Sender | Should Be $base[$i].Sender
                    $m[$i].Timestamp | Should Be $base[$i].Timestamp
                }
                (ConvertFrom-KakaoExport -Path $p).Room | Should Be '테스트방'
            }
        }
        finally { Remove-Item -LiteralPath $crlf, $bom -Force }
    }

    It 'parsing one file never leaks a message into the next parse' {
        $first = New-TempExport ("방A 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] 첫 파일 마지막 글`r`n")
        $second = New-TempExport ("방B 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n")
        try {
            @((ConvertFrom-KakaoExport -Path $first).Messages).Count | Should Be 1
            @((ConvertFrom-KakaoExport -Path $second).Messages).Count | Should Be 0
        }
        finally { Remove-Item -LiteralPath $first, $second -Force }
    }

    It 'does not crash on an impossible saved date: SavedAt is null, messages still parse' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-13-45 99:99:99`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] a`r`n")
        try {
            $r = ConvertFrom-KakaoExport -Path $p
            $r.Room | Should Be '테스트방'
            $r.SavedAt | Should BeNullOrEmpty
            @($r.Messages).Count | Should Be 1
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'treats an impossible date line (13월 45일) as plain text, not as a crash' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] a`r`n--------------- 2026년 13월 45일 수요일 ---------------`r`n[나] [오전 1:01] b`r`n")
        try {
            $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
            $m.Count | Should Be 2
            $m[0].Text | Should Match '13월 45일'
            $m[1].Timestamp | Should Be (New-Object DateTime 2026, 10, 21, 1, 1, 0)
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'does not turn an impossible time into a wrong timestamp ([오후 99:99], [오전 13:00] are plain text)' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] a`r`n[나] [오후 99:99] b`r`n[나] [오전 13:00] c`r`n")
        try {
            $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
            $m.Count | Should Be 1
            $m[0].Text | Should Match '99:99'
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'keeps a message whose text is empty instead of merging it into the previous one' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n[나] [오전 1:00] a`r`n[나] [오전 1:01]`r`n[나] [오전 1:02] c`r`n")
        try {
            $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
            $m.Count | Should Be 3
            $m[1].Text | Should Be ''
            $m[0].Text | Should Be 'a'
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'reads files that use CR-only line endings' {
        $p = New-TempExport ("테스트방 님과 카카오톡 대화`r저장한 날짜 : 2026-10-27 04:10:00`r`r--------------- 2026년 10월 21일 수요일 ---------------`r[나] [오전 1:00] a`r[나] [오전 1:01] b`r")
        try { @((ConvertFrom-KakaoExport -Path $p).Messages).Count | Should Be 2 }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'throws the Korean "file not found" error (exit 3) when given a folder' {
        $e = Get-ThrownError { ConvertFrom-KakaoExport -Path ([System.IO.Path]::GetTempPath()) }
        $e.ExitCode | Should Be 3
        $e.Message | Should Match '내보내기 파일'
    }

    It 'throws a Korean error (exit 3) for a missing file' {
        $e = Get-ThrownError { ConvertFrom-KakaoExport -Path 'C:\no\such\export.txt' }
        $e.ExitCode | Should Be 3
        $e.Message | Should Match '내보내기 파일'
    }

    It 'throws a Korean error (exit 3) for a file that is not a KakaoTalk export' {
        $p = New-TempExport "그냥 메모입니다`r`n둘째 줄`r`n"
        try {
            $e = Get-ThrownError { ConvertFrom-KakaoExport -Path $p }
            $e.ExitCode | Should Be 3
            $e.Message | Should Match '카카오톡 내보내기 파일이 아닙니다'
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }

    It 'parses a few thousand messages quickly' {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("테스트방 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n--------------- 2026년 10월 21일 수요일 ---------------`r`n")
        for ($i = 1; $i -le 3000; $i++) { [void]$sb.Append("[나] [오후 1:05] 메시지 $i`r`n둘째 줄 $i`r`n") }
        $p = New-TempExport $sb.ToString()
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $m = @((ConvertFrom-KakaoExport -Path $p).Messages)
            $sw.Stop()
            $m.Count | Should Be 3000
            $m[2999].Text | Should Be "메시지 3000`n둘째 줄 3000"
            $sw.Elapsed.TotalSeconds | Should BeLessThan 10
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }
}

Describe 'Parse: 고정 결과(속도 개선 전후 동일성)' {
    It '날짜·이어지는 줄·잘못된 머리글이 뒤섞인 파일을 기존 파서와 똑같이 읽는다' {
        $rnd = New-Object System.Random 7
        $pieces = @('[나] [오전 1:05] 안녕', '[A] [오후 12:00] x', '[B] [오후 99:99] bad', '[C] [오전 1:01]', '[길동] [오후 11:59] 끝 [내용]',
            '--------------- 2026년 10월 21일 수요일 ---------------', '--------------- 2026년 13월 45일 수요일 ---------------', '--- 그냥 줄 ---', '',
            '이어지는 줄', '[깨진 머리글', '  [x] [오전 1:00] 앞공백', '--------------- 2024년 2월 29일 목요일 ---------------', '[X] [오전 0:30] 자정')
        $ls = @('테스트방 님과 카카오톡 대화', '저장한 날짜 : 2026-10-27 04:10:00', '')
        for ($j = 0; $j -lt 400; $j++) { $ls += $pieces[$rnd.Next(0, $pieces.Count)] }
        $p = New-TempExport ($ls -join "`r`n")
        try {
            $r = ConvertFrom-KakaoExport -Path $p
            $sb = New-Object System.Text.StringBuilder
            foreach ($m in $r.Messages) {
                $ts = 'NULL'
                if ($null -ne $m.Timestamp) { $ts = $m.Timestamp.ToString('yyyyMMddHHmm') }
                [void]$sb.Append($ts + '|' + $m.Sender + '|' + ($m.Text -replace "`n", '\n') + "`n")
            }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $digest = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))).Replace('-', '').ToLower()
            @($r.Messages).Count | Should Be 140
            $digest | Should Be '792e5a7ee922213887a5d6c05ddbc2a7d3ad5bc5aaaa94a8918075647f1590ad'
        }
        finally { Remove-Item -LiteralPath $p -Force }
    }
}