$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Win32', 'Guard', 'Config', 'Log', 'Clip', 'Parse', 'Exporter')
. (Join-Path $here '_Load.ps1')

# 내보내기 부품(Exporter)을 가짜 제공자로 시험한다. 실제 카카오톡·키·클립보드·파일은 건드리지 않는다.
# 부품이 하는 일: 열려 있는 방 창에서 Ctrl+S → 저장 창 확인 → 파일 이름 칸에 임시 경로 붙여넣기 → 칸 값 확인 → Enter → 파일 읽기 → 임시 파일 지우기.
# 핵심 규칙: 확인되지 않은 것에는 다음 키를 보내지 않는다(fail-closed). 제목이 없는 창은 어떤 경우에도 닫지 않는다(2026-11-15 D2 에서 놓친 점).
$roomTitle = '테스트방'
$dlgTitle = '다른 이름으로 저장'
$tmpPath = 'C:\Temp\KakaoKit\verify\v12345678.txt'

function New-ExWin([long]$Hwnd, [string]$Title, [string]$Class = 'EVA_Window_Dblclk') { [pscustomobject]@{ Hwnd = $Hwnd; Title = $Title; Class = $Class; ProcessName = 'KakaoTalk' } }

# 상태를 가진 가짜 제공자. Phase: 0 = 방 창만, 1 = Ctrl+S 후(저장 창), 2 = Enter 후(저장 창 사라짐).
function New-FakeExporter {
    $s = @{
        Calls = (New-Object System.Collections.ArrayList)
        Phase = 0
        Main = (New-ExWin 1 '카카오톡')
        RoomWindows = @((New-ExWin 2 '테스트방'))
        DialogAppears = $true
        DialogWindow = (New-ExWin 9 '다른 이름으로 저장' '#32770')
        ExtraOnCtrlS = @()
        ExtraAfterSave = @()
        DialogGoesAway = $true
        Focus = $true
        BoxValue = $null
        FileAppears = $true
        Path = 'C:\Temp\KakaoKit\verify\v12345678.txt'
        Parsed = $null
        ReadThrows = $false
        Pasted = $null
    }
    $s.Parsed = [pscustomobject]@{ Room = '테스트방'; SavedAt = [datetime]'2026-11-15 13:06:00'; Messages = @([pscustomobject]@{ Timestamp = [datetime]'2026-11-15 13:05:00'; Sender = '나'; Text = '안녕' }) }
    $s.Provider = @{
        Windows = { [void]$s.Calls.Add('Windows')
            $list = @($s.Main) + @($s.RoomWindows)
            if ($s.Phase -eq 1) { if ($s.DialogAppears) { $list += $s.DialogWindow }; $list += @($s.ExtraOnCtrlS) }
            if ($s.Phase -eq 2) { if (-not $s.DialogGoesAway) { $list += $s.DialogWindow }; $list += @($s.ExtraAfterSave) }
            $list }.GetNewClosure()
        MakePath = { [void]$s.Calls.Add('MakePath'); $s.Path }.GetNewClosure()
        WaitIdle = { [void]$s.Calls.Add('WaitIdle') }.GetNewClosure()
        PressCtrlS = { param($hwnd, $title) [void]$s.Calls.Add(('CtrlS:{0}:{1}' -f $hwnd, $title)); $s.Phase = 1 }.GetNewClosure()
        FileNameFocus = { param($dlg) [void]$s.Calls.Add('Focus'); $s.Focus }.GetNewClosure()
        PasteText = { param($dlg, $text, $title) [void]$s.Calls.Add(('Paste:{0}:{1}' -f $dlg, $title)); $s.Pasted = $text }.GetNewClosure()
        FileNameValue = { param($dlg) [void]$s.Calls.Add('Value'); if ($null -ne $s.BoxValue) { $s.BoxValue } else { $s.Pasted } }.GetNewClosure()
        PressEnter = { param($dlg, $title) [void]$s.Calls.Add(('Enter:{0}:{1}' -f $dlg, $title)); $s.Phase = 2 }.GetNewClosure()
        FileReady = { param($p) [void]$s.Calls.Add('FileReady'); $s.FileAppears }.GetNewClosure()
        ReadExport = { param($p) [void]$s.Calls.Add('Read'); if ($s.ReadThrows) { throw 'bad export' }; $s.Parsed }.GetNewClosure()
        DeleteFile = { param($p) [void]$s.Calls.Add('Delete') }.GetNewClosure()
        CloseWindow = { param($hwnd, $title) [void]$s.Calls.Add(('Close:{0}:{1}' -f $hwnd, $title)) }.GetNewClosure()
        Sleep = { param($ms) }.GetNewClosure()
    }
    return $s
}
function Get-ExCalls($s, [string]$Like) { return @($s.Calls | Where-Object { $_ -like $Like }) }
# 키로 나가는 호출만(Ctrl+S, 붙여넣기, Enter).
function Get-KeyCalls($s) { return @($s.Calls | Where-Object { $_ -like 'CtrlS:*' -or $_ -like 'Paste:*' -or $_ -like 'Enter:*' }) }

Describe 'Exporter: 정상 흐름' {
    It '방 창에서 Ctrl+S, 저장 창에 경로 붙여넣기, Enter 순서로 하고 읽은 메시지 목록을 돌려준다' {
        $f = New-FakeExporter
        $r = @(Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        $r.Count | Should Be 1
        $r[0].Text | Should Be '안녕'
        (Get-KeyCalls $f) -join '|' | Should Be ('CtrlS:2:{0}|Paste:9:{1}|Enter:9:{1}' -f $roomTitle, $dlgTitle)
    }
    It '붙여넣은 경로는 제공자가 만든 임시 경로 그대로이고, 칸 값을 읽어 확인한 뒤에만 Enter 를 보낸다' {
        $f = New-FakeExporter
        [void](Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        $f.Pasted | Should Be $f.Path
        $order = @($f.Calls | Where-Object { $_ -like 'Paste:*' -or $_ -like 'Value' -or $_ -like 'Enter:*' })
        ($order -join '|') | Should Be ('Paste:9:{0}|Value|Enter:9:{0}' -f $dlgTitle)
    }
    It '읽은 뒤 임시 파일을 지운다(대화 내용을 남기지 않는다)' {
        $f = New-FakeExporter
        [void](Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        (Get-ExCalls $f 'Delete').Count | Should Be 1
    }
    It '저장 창이 스스로 닫혔으면 닫기 요청을 보내지 않는다' {
        $f = New-FakeExporter
        [void](Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        (Get-ExCalls $f 'Close:*').Count | Should Be 0
    }
}

Describe 'Exporter: 시작 전 확인(하나라도 어긋나면 키 0)' {
    It '방 창이 없으면 멈추고 키를 보내지 않는다' {
        $f = New-FakeExporter; $f.RoomWindows = @()
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-KeyCalls $f).Count | Should Be 0
    }
    It '같은 제목의 방 창이 둘이면 멈추고 키를 보내지 않는다' {
        $f = New-FakeExporter; $f.RoomWindows = @((New-ExWin 2 '테스트방'), (New-ExWin 3 '테스트방'))
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-KeyCalls $f).Count | Should Be 0
    }
    It '방 이름이 비어 있으면 멈추고 아무것도 읽지 않는다' {
        $f = New-FakeExporter
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room '' -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        $f.Calls.Count | Should Be 0
    }
    It '임시 경로가 영문·숫자·기호(ASCII)가 아니면 멈추고 키를 보내지 않는다(한글 경로는 확인하지 못했다)' {
        $f = New-FakeExporter; $f.Path = 'C:\Users\홍길동\v1.txt'
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-KeyCalls $f).Count | Should Be 0
    }
    It '임시 경로가 비어 있거나 문자열이 아니면 멈추고 키를 보내지 않는다' {
        foreach ($bad in @('', $null, 5)) {
            $f = New-FakeExporter; $f.Path = $bad
            $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            (Get-KeyCalls $f).Count | Should Be 0
        }
    }
}

Describe 'Exporter: 저장 창 확인(확인되지 않으면 붙여넣지 않는다)' {
    It '저장 창이 시간 안에 뜨지 않으면 멈추고, 붙여넣기·Enter·닫기를 하지 않는다' {
        $f = New-FakeExporter; $f.DialogAppears = $false
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Paste:*').Count | Should Be 0
        (Get-ExCalls $f 'Enter:*').Count | Should Be 0
        (Get-ExCalls $f 'Close:*').Count | Should Be 0
    }
    It '새 창의 제목이나 종류가 저장 창이 아니면 붙여넣지 않고 어떤 창도 닫지 않는다' {
        foreach ($w in @((New-ExWin 9 '다른 창' '#32770'), (New-ExWin 9 '다른 이름으로 저장' 'EVA_Window_Dblclk'))) {
            $f = New-FakeExporter; $f.DialogWindow = $w
            $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
            $e.ExitCode | Should Be 2
            (Get-ExCalls $f 'Paste:*').Count | Should Be 0
            (Get-ExCalls $f 'Close:*').Count | Should Be 0
        }
    }
    It '저장 창 말고 다른 새 창이 같이 뜨면 붙여넣지 않고, 저장 창만 자기 제목으로 닫고 멈춘다' {
        $f = New-FakeExporter; $f.ExtraOnCtrlS = @((New-ExWin 10 '' 'EVA_Window_Dblclk'))
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Paste:*').Count | Should Be 0
        (Get-ExCalls $f 'Close:*') -join '|' | Should Be ('Close:9:{0}' -f $dlgTitle)
    }
    It '파일 이름 칸에 키보드 포커스가 확인되지 않으면 붙여넣지 않고 저장 창을 자기 제목으로 닫고 멈춘다' {
        $f = New-FakeExporter; $f.Focus = $false
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Paste:*').Count | Should Be 0
        (Get-ExCalls $f 'Close:*') -join '|' | Should Be ('Close:9:{0}' -f $dlgTitle)
    }
    It '붙여넣은 뒤 칸의 값이 우리 경로와 다르면 Enter 를 보내지 않고 저장 창을 닫고 멈춘다' {
        $f = New-FakeExporter; $f.BoxValue = 'C:\Temp\other.txt'
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Enter:*').Count | Should Be 0
        (Get-ExCalls $f 'Close:*') -join '|' | Should Be ('Close:9:{0}' -f $dlgTitle)
    }
}

Describe 'Exporter: 저장 뒤 확인과 정리' {
    It '파일이 시간 안에 생기지 않으면 멈춘다. 남은 저장 창은 자기 제목으로 닫는다' {
        $f = New-FakeExporter; $f.FileAppears = $false; $f.DialogGoesAway = $false
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Read').Count | Should Be 0
        (Get-ExCalls $f 'Close:*') -join '|' | Should Be ('Close:9:{0}' -f $dlgTitle)
        (Get-ExCalls $f 'Delete').Count | Should Be 1
    }
    It '파일을 읽지 못해도(형식 오류) 멈추고 임시 파일은 지운다' {
        $f = New-FakeExporter; $f.ReadThrows = $true
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Delete').Count | Should Be 1
    }
    It '내보낸 파일의 방 이름이 요청한 방과 다르면 메시지를 주지 않고 멈춘다' {
        $f = New-FakeExporter; $f.Parsed = [pscustomobject]@{ Room = '다른방'; SavedAt = $null; Messages = @([pscustomobject]@{ Timestamp = [datetime]'2026-11-15 13:05:00'; Sender = '나'; Text = '안녕' }) }
        $e = Get-ThrownError { Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider }
        $e.ExitCode | Should Be 2
        (Get-ExCalls $f 'Delete').Count | Should Be 1
    }
    It '저장 뒤 제목 없는 새 창이 생겨도 닫지 않고 경고만 남기며 결과는 그대로 돌려준다(D2 에서 놓친 점)' {
        $f = New-FakeExporter; $f.ExtraAfterSave = @((New-ExWin 10 '' 'EVA_Window_Dblclk'))
        Clear-KitWarnings
        $r = @(Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        $r.Count | Should Be 1
        (Get-ExCalls $f 'Close:*').Count | Should Be 0
        (Get-KitWarnings).Count | Should Be 1
    }
    It '저장 뒤 제목 있는 낯선 새 창도 닫지 않고 경고만 남긴다' {
        $f = New-FakeExporter; $f.ExtraAfterSave = @((New-ExWin 10 '알림' 'EVA_Window_Dblclk'))
        Clear-KitWarnings
        [void](Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        (Get-ExCalls $f 'Close:*').Count | Should Be 0
        (Get-KitWarnings).Count | Should Be 1
    }
    It '저장 창이 Enter 뒤에도 남아 있으면 자기 제목으로 닫는다(결과는 파일이 읽히면 그대로)' {
        $f = New-FakeExporter; $f.DialogGoesAway = $false
        $r = @(Export-KakaoRoomMessages -Room $roomTitle -Provider $f.Provider)
        $r.Count | Should Be 1
        (Get-ExCalls $f 'Close:*') -join '|' | Should Be ('Close:9:{0}' -f $dlgTitle)
    }
}

Describe 'Exporter: 안전 규칙을 소스에서 강제한다' {
    $src = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'Exporter.ps1'))
    It '키는 Ctrl+S, Ctrl+V(붙여넣기), Enter 만 쓴다(Ctrl+A·Esc·Delete·Backspace·클릭 없음)' {
        foreach ($bad in @('Ctrl+A', "'Esc'", "'Delete'", "'Del'", 'Backspace', 'Invoke-RelClick', 'Click', 'SendKeys')) {
            ($src -match [regex]::Escape($bad)) | Should Be $false
        }
        ($src -match "'Ctrl\+S'") | Should Be $true
        ($src -match "'Enter'") | Should Be $true
    }
    It '창 닫기는 저장 창을 자기 제목으로 닫는 한 곳뿐이고, 제목 없는 창을 닫는 길은 없다' {
        ([regex]::Matches($src, 'CloseWindow')).Count | Should BeLessThan 4
        ($src -match 'Remove-Item') | Should Be $false
    }
    It '기본 제공자가 필요한 부품을 모두 갖추고, 보내기용 내보내기 훅은 스크립트 블록이다' {
        $p = Get-DefaultExporterProvider
        foreach ($k in 'Windows', 'MakePath', 'WaitIdle', 'PressCtrlS', 'FileNameFocus', 'PasteText', 'FileNameValue', 'PressEnter', 'FileReady', 'ReadExport', 'DeleteFile', 'CloseWindow', 'Sleep') {
            ($p.ContainsKey($k) -and $p[$k] -is [scriptblock]) | Should Be $true
        }
        (Get-DefaultSendExporter) -is [scriptblock] | Should Be $true
    }
}
