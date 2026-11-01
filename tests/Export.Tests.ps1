# 내보내기 보관·읽기·검색(카카오톡을 건드리지 않는 부분). 모두 임시 폴더(KAKAO_KIT_HOME)와 합성 자료로만 시험한다.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config', 'Parse', 'Export', 'Search')
. (Join-Path $here '_Load.ps1')

$sample = Join-Path $here 'fixtures\export-sample.txt'   # 방 "테스트방", 메시지 4개(2026-10-21 00:05 ~ 2026-10-22 23:59)

function New-TestRoom([string]$Name, [bool]$CanRead = $true, [bool]$AiRead = $false) {
    return [pscustomobject]@{ name = $Name; type = 'open'; verified = $true; canRead = $CanRead; canSend = $false; selfOnly = $true; aiRead = $AiRead; aiSend = $false }
}

function Set-TestRooms([object[]]$Rooms) {
    Save-KitConfig -Config ([pscustomobject]@{ version = 1; consentAcceptedAt = $null; lastRoom = $null; rooms = @($Rooms) })
}

# 합성 내보내기 파일(UTF-8, BOM 없음, CRLF)을 임시 위치에 만들고 경로를 돌려준다.
function New-TestExport([string]$Room, [string[]]$Body) {
    $text = $Room + " 님과 카카오톡 대화`r`n저장한 날짜 : 2026-10-27 04:10:00`r`n`r`n" + ($Body -join "`r`n") + "`r`n"
    $p = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-export-test-' + [guid]::NewGuid().ToString('N') + '.txt')
    [System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $p
}

function Remove-TestFile([string]$Path) { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }

function Get-SnapshotNames([string]$Room) {
    $dir = Get-ExportRoomDir -Room $Room
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -like 'snapshot-*.txt' } | Sort-Object Name | ForEach-Object { $_.Name })
}

$base = New-Object DateTime 2026, 11, 2, 12, 0, 0

Describe 'Export: 방별 보관 폴더 이름' {
    It 'gives the same folder for the same room, directly under the exports folder' {
        Use-TempHome {
            $a = Get-ExportRoomDir -Room '테스트방'
            $b = Get-ExportRoomDir -Room '테스트방'
            $a | Should Be $b
            (Split-Path -Parent $a) | Should Be (Get-KitPaths).ExportsDir
        }
    }

    It 'gives different folders to rooms whose names look alike after cleaning (a/b and a?b)' {
        Use-TempHome {
            (Get-ExportRoomDir -Room 'a/b') | Should Not Be (Get-ExportRoomDir -Room 'a?b')
        }
    }

    It 'never leaves the exports folder and never uses characters a folder name cannot have, even for hostile names' {
        Use-TempHome {
            $exports = (Get-KitPaths).ExportsDir
            foreach ($name in '..', '..\x', 'C:\x', 'a/../../b', 'CON', 'room.', '😀방') {
                $dir = Get-ExportRoomDir -Room $name
                (Split-Path -Parent $dir) | Should Be $exports
                $leaf = Split-Path -Leaf $dir
                ($leaf.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) | Should Be $false
                $leaf.EndsWith('.') | Should Be $false
                $leaf -ne 'CON' | Should Be $true
            }
        }
    }

    It 'rejects a room name that the allow list would reject (leading space, empty, control character)' {
        Use-TempHome {
            (Get-ThrownError { Get-ExportRoomDir -Room ' 방' }) | Should Not BeNullOrEmpty
            (Get-ThrownError { Get-ExportRoomDir -Room '' }) | Should Not BeNullOrEmpty
            (Get-ThrownError { Get-ExportRoomDir -Room ("방" + [char]0x200B) }) | Should Not BeNullOrEmpty
        }
    }
}

Describe 'Export: Update-ExportStore (보관 3개, 30일)' {
    It 'stores a snapshot and latest.txt that are byte-for-byte the source, and leaves the source in place' {
        Use-TempHome {
            $r = Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base
            (Split-Path -Leaf $r.Snapshot) | Should Be 'snapshot-20261102-120000.txt'
            (Split-Path -Leaf $r.Latest) | Should Be 'latest.txt'
            $src = [System.IO.File]::ReadAllBytes($sample)
            ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($r.Snapshot))) | Should Be ([System.Convert]::ToBase64String($src))
            ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($r.Latest))) | Should Be ([System.Convert]::ToBase64String($src))
            (Test-Path -LiteralPath $sample) | Should Be $true
        }
    }

    It 'keeps only the newest 3 snapshots and latest.txt is the newest one' {
        Use-TempHome {
            $stamps = @()
            for ($i = 1; $i -le 4; $i++) {
                $when = $base.AddMinutes($i)
                $stamps += $when.ToString('yyyyMMdd-HHmmss')
                $p = New-TestExport '테스트방' @('--------------- 2026년 10월 21일 수요일 ---------------', "[나] [오전 1:0$i] 글 $i")
                try { Update-ExportStore -Room '테스트방' -SourcePath $p -Now $when | Out-Null } finally { Remove-TestFile $p }
            }
            $names = @(Get-SnapshotNames '테스트방')
            $names.Count | Should Be 3
            $names[0] | Should Be ('snapshot-' + $stamps[1] + '.txt')
            $names[2] | Should Be ('snapshot-' + $stamps[3] + '.txt')
            $latest = Join-Path (Get-ExportRoomDir -Room '테스트방') 'latest.txt'
            ([System.IO.File]::ReadAllText($latest)).Contains('글 4') | Should Be $true
        }
    }

    It 'deletes a snapshot older than 30 days even when fewer than 3 exist, and keeps one that is 29 days old' {
        Use-TempHome {
            $dir = Get-ExportRoomDir -Room '테스트방'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            foreach ($old in $base.AddDays(-31), $base.AddDays(-29)) {
                [System.IO.File]::WriteAllText((Join-Path $dir ('snapshot-' + $old.ToString('yyyyMMdd-HHmmss') + '.txt')), 'old')
            }
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $names = @(Get-SnapshotNames '테스트방')
            $names.Count | Should Be 2
            ($names -contains ('snapshot-' + $base.AddDays(-31).ToString('yyyyMMdd-HHmmss') + '.txt')) | Should Be $false
            ($names -contains ('snapshot-' + $base.AddDays(-29).ToString('yyyyMMdd-HHmmss') + '.txt')) | Should Be $true
        }
    }

    It 'never deletes files that are not kit snapshots (notes, backups, malformed names)' {
        Use-TempHome {
            $dir = Get-ExportRoomDir -Room '테스트방'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            foreach ($n in 'notes.txt', 'snapshot-bad.txt', 'snapshot-20200101-000000.txt.bak') { [System.IO.File]::WriteAllText((Join-Path $dir $n), 'keep me') }
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            foreach ($n in 'notes.txt', 'snapshot-bad.txt', 'snapshot-20200101-000000.txt.bak') { (Test-Path -LiteralPath (Join-Path $dir $n)) | Should Be $true }
        }
    }

    It 'storing twice in the same second replaces the snapshot without an error' {
        Use-TempHome {
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            @(Get-SnapshotNames '테스트방').Count | Should Be 1
        }
    }

    It 'refuses an export whose header names another room, and writes nothing' {
        Use-TempHome {
            $p = New-TestExport '다른방' @('--------------- 2026년 10월 21일 수요일 ---------------', '[나] [오전 1:00] 안녕')
            try {
                $e = Get-ThrownError { Update-ExportStore -Room '테스트방' -SourcePath $p -Now $base }
                $e.Message | Should Be (Get-Msg -Key 'export.roomMismatch' -FormatArgs @('테스트방'))
                $e.ExitCode | Should Be 3
                (Test-Path -LiteralPath (Get-ExportRoomDir -Room '테스트방')) | Should Be $false
            }
            finally { Remove-TestFile $p }
        }
    }

    It 'refuses a file that is not a KakaoTalk export and a file that does not exist, and writes nothing' {
        Use-TempHome {
            $junk = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-junk-' + [guid]::NewGuid().ToString('N') + '.txt')
            [System.IO.File]::WriteAllText($junk, "그냥 글입니다`r`n둘째 줄")
            try {
                $e1 = Get-ThrownError { Update-ExportStore -Room '테스트방' -SourcePath $junk -Now $base }
                $e1.Message | Should Be (Get-Msg -Key 'parse.notExport' -FormatArgs @($junk))
                $e2 = Get-ThrownError { Update-ExportStore -Room '테스트방' -SourcePath ($junk + '.missing') -Now $base }
                $e2.Message | Should Be (Get-Msg -Key 'parse.fileNotFound' -FormatArgs @($junk + '.missing'))
                (Test-Path -LiteralPath (Get-ExportRoomDir -Room '테스트방')) | Should Be $false
            }
            finally { Remove-TestFile $junk }
        }
    }

    It 'turns a storage failure into a Korean kit error instead of a raw system error' {
        Use-TempHome {
            New-Item -ItemType Directory -Path (Get-KitPaths).DataDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Get-KitPaths).ExportsDir, 'a file where the folder should be')
            $e = Get-ThrownError { Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base }
            ($e -is [KakaoKitException]) | Should Be $true
            $e.Message | Should Be (Get-Msg -Key 'export.storeFailed')
            $e.ExitCode | Should Be 3
        }
    }
}

Describe 'Export: Read-KakaoRoom' {
    It 'says in Korean that nothing is stored yet when there is no export' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            $e = Get-ThrownError { Read-KakaoRoom -Room '테스트방' }
            $e.Message | Should Be (Get-Msg -Key 'export.noExport' -FormatArgs @('테스트방'))
            $e.ExitCode | Should Be 3
        }
    }

    It 'returns all messages of the stored export in order' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $m = @(Read-KakaoRoom -Room '테스트방')
            $m.Count | Should Be 4
            $m[0].Text | Should Be '자정 지나서 보낸 글'
            $m[3].Timestamp | Should Be (New-Object DateTime 2026, 10, 22, 23, 59, 0)
        }
    }

    It '-Last returns only the newest N messages, still in order' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $m = @(Read-KakaoRoom -Room '테스트방' -Last 2)
            $m.Count | Should Be 2
            $m[1].Timestamp | Should Be (New-Object DateTime 2026, 10, 22, 23, 59, 0)
            @(Read-KakaoRoom -Room '테스트방' -Last 99).Count | Should Be 4
        }
    }

    It '-Since keeps only messages inside the time window counted back from now' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $now = New-Object DateTime 2026, 10, 23, 12, 0, 0
            @(Read-KakaoRoom -Room '테스트방' -Since ([timespan]::FromDays(1)) -Now $now).Count | Should Be 1
            @(Read-KakaoRoom -Room '테스트방' -Since ([timespan]::FromDays(3)) -Now $now).Count | Should Be 4
        }
    }

    It '-Since leaves out a message that has no known time (it cannot be shown to be recent), while no -Since keeps it' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            $p = New-TestExport '테스트방' @('[나] [오전 1:00] 날짜 줄보다 앞선 글', '--------------- 2026년 10월 21일 수요일 ---------------', '[나] [오전 2:00] 날짜 있는 글')
            try { Update-ExportStore -Room '테스트방' -SourcePath $p -Now $base | Out-Null } finally { Remove-TestFile $p }
            $now = New-Object DateTime 2026, 10, 21, 12, 0, 0
            @(Read-KakaoRoom -Room '테스트방').Count | Should Be 2
            $m = @(Read-KakaoRoom -Room '테스트방' -Since ([timespan]::FromDays(1)) -Now $now)
            $m.Count | Should Be 1
            $m[0].Text | Should Be '날짜 있는 글'
        }
    }

    It 'rejects a count or a window that is not positive, with a Korean message' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            (Get-ThrownError { Read-KakaoRoom -Room '테스트방' -Last 0 }).Message | Should Be (Get-Msg -Key 'export.optionInvalid')
            (Get-ThrownError { Read-KakaoRoom -Room '테스트방' -Last -3 }).Message | Should Be (Get-Msg -Key 'export.optionInvalid')
            (Get-ThrownError { Read-KakaoRoom -Room '테스트방' -Since ([timespan]::Zero) }).Message | Should Be (Get-Msg -Key 'export.optionInvalid')
        }
    }

    It 'reads only latest.txt, so a newer export replaces the older view' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $p = New-TestExport '테스트방' @('--------------- 2026년 11월 1일 일요일 ---------------', '[나] [오전 1:00] 새 내보내기')
            try { Update-ExportStore -Room '테스트방' -SourcePath $p -Now $base.AddMinutes(5) | Out-Null } finally { Remove-TestFile $p }
            $m = @(Read-KakaoRoom -Room '테스트방')
            $m.Count | Should Be 1
            $m[0].Text | Should Be '새 내보내기'
        }
    }

    It 'refuses a room that is not on the allow list, or whose reading is switched off, before touching any file' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방'; New-TestRoom '막힌방' -CanRead $false)
            $p = New-TestExport '막힌방' @('[나] [오전 1:00] x')
            try { Update-ExportStore -Room '막힌방' -SourcePath $p -Now $base | Out-Null } finally { Remove-TestFile $p }
            $e1 = Get-ThrownError { Read-KakaoRoom -Room '미등록방' }
            $e1.Message | Should Be (Get-Msg -Key 'export.notAllowed' -FormatArgs @('미등록방'))
            $e2 = Get-ThrownError { Read-KakaoRoom -Room '막힌방' }
            $e2.Message | Should Be (Get-Msg -Key 'export.notAllowed' -FormatArgs @('막힌방'))
            $e2.ExitCode | Should Be 1
        }
    }

    It 'lets an AI caller read only rooms whose AI reading is on; a human is not held to that switch; an unknown caller is refused' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방'; New-TestRoom 'AI방' -AiRead $true)
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $p = New-TestExport 'AI방' @('--------------- 2026년 10월 21일 수요일 ---------------', '[나] [오전 1:00] 열린 글')
            try { Update-ExportStore -Room 'AI방' -SourcePath $p -Now $base | Out-Null } finally { Remove-TestFile $p }
            (Get-ThrownError { Read-KakaoRoom -Room '테스트방' -Caller ai }).Message | Should Be (Get-Msg -Key 'export.notAllowed' -FormatArgs @('테스트방'))
            @(Read-KakaoRoom -Room 'AI방' -Caller ai).Count | Should Be 1
            @(Read-KakaoRoom -Room '테스트방' -Caller human).Count | Should Be 4
            (Get-ThrownError { Read-KakaoRoom -Room 'AI방' -Caller robot }) | Should Not BeNullOrEmpty
        }
    }
}

Describe 'Search: Search-KakaoExports' {
    It 'finds a keyword ignoring upper/lower case and returns room, time, sender and text' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $hits = @(Search-KakaoExports -Keyword 'SEND CHECK')
            $hits.Count | Should Be 1
            $hits[0].Room | Should Be '테스트방'
            $hits[0].Sender | Should Be '나'
            $hits[0].Text | Should Be '[kakao-kit test] send check'
            $hits[0].Timestamp | Should Be (New-Object DateTime 2026, 10, 21, 2, 59, 0)
        }
    }

    It 'treats the keyword as plain text, not as a pattern' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            @(Search-KakaoExports -Keyword '.*').Count | Should Be 0
            @(Search-KakaoExports -Keyword '[kakao-kit test]').Count | Should Be 1
        }
    }

    It 'gives each message once even when several snapshots hold it (only latest.txt is searched)' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            for ($i = 1; $i -le 3; $i++) { Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base.AddMinutes($i) | Out-Null }
            @(Get-SnapshotNames '테스트방').Count | Should Be 3
            @(Search-KakaoExports -Keyword 'send check').Count | Should Be 1
        }
    }

    It 'searches all readable rooms, skips rooms without an export, and -Room narrows to one room' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방'; New-TestRoom 'AI방' -AiRead $true; New-TestRoom '빈방')
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $p = New-TestExport 'AI방' @('--------------- 2026년 10월 21일 수요일 ---------------', '[나] [오전 1:00] send check 두 번째 방')
            try { Update-ExportStore -Room 'AI방' -SourcePath $p -Now $base | Out-Null } finally { Remove-TestFile $p }
            @(Search-KakaoExports -Keyword 'send check').Count | Should Be 2
            $one = @(Search-KakaoExports -Keyword 'send check' -Room 'AI방')
            $one.Count | Should Be 1
            $one[0].Room | Should Be 'AI방'
        }
    }

    It 'gives an AI caller only rooms whose AI reading is on, and refuses an explicit room that is not allowed' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방'; New-TestRoom 'AI방' -AiRead $true)
            Update-ExportStore -Room '테스트방' -SourcePath $sample -Now $base | Out-Null
            $p = New-TestExport 'AI방' @('--------------- 2026년 10월 21일 수요일 ---------------', '[나] [오전 1:00] send check 열린 방')
            try { Update-ExportStore -Room 'AI방' -SourcePath $p -Now $base | Out-Null } finally { Remove-TestFile $p }
            $hits = @(Search-KakaoExports -Keyword 'send check' -Caller ai)
            $hits.Count | Should Be 1
            $hits[0].Room | Should Be 'AI방'
            (Get-ThrownError { Search-KakaoExports -Keyword 'send check' -Room '테스트방' -Caller ai }).Message | Should Be (Get-Msg -Key 'export.notAllowed' -FormatArgs @('테스트방'))
        }
    }

    It 'refuses an empty or blank keyword with a Korean message' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            (Get-ThrownError { Search-KakaoExports -Keyword '' }).Message | Should Be (Get-Msg -Key 'search.keywordEmpty')
            (Get-ThrownError { Search-KakaoExports -Keyword '   ' }).Message | Should Be (Get-Msg -Key 'search.keywordEmpty')
        }
    }

    It 'returns nothing (not an error) when no room has a stored export, but says so when the one room asked for has none' {
        Use-TempHome {
            Set-TestRooms @(New-TestRoom '테스트방')
            @(Search-KakaoExports -Keyword 'send check').Count | Should Be 0
            (Get-ThrownError { Search-KakaoExports -Keyword 'send check' -Room '테스트방' }).Message | Should Be (Get-Msg -Key 'export.noExport' -FormatArgs @('테스트방'))
        }
    }
}
