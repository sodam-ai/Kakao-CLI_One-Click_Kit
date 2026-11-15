# 카카오톡 공식 "대화 내보내기" 텍스트 파일을 읽는 순수 함수. 카카오톡이나 클립보드를 건드리지 않는다.
#   1행  <방 이름> 님과 카카오톡 대화      (단체방은 " 님과" 없이 "<방 이름> 카카오톡 대화")
#   2행  저장한 날짜 : YYYY-MM-DD HH:MM:SS
#        --------------- 2026년 10월 21일 수요일 ---------------
#        [닉네임] [오전 2:59] 내용        (다음 줄들은 같은 메시지의 이어지는 줄)
# 가정: 닉네임에는 "]" 가 들어 있지 않다. 이어지는 줄이 우연히 "[이름] [오전 1:00] ..." 꼴이면 새 메시지로 읽는다(구분할 방법이 없다).

$script:ReExportHeader = New-Object System.Text.RegularExpressions.Regex('^(?<room>.+?)(?: 님과)? 카카오톡 대화\s*$')
$script:ReExportSaved = New-Object System.Text.RegularExpressions.Regex('^저장한 날짜 : (?<d>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*$')
$script:ReExportDate = New-Object System.Text.RegularExpressions.Regex('^-{3,}\s*(?<y>\d{4})년\s*(?<mo>\d{1,2})월\s*(?<d>\d{1,2})일.*?-{3,}\s*$')
# 시각은 12시간제(0~12시, 00~59분)만 인정한다. [오후 99:99] 같은 값은 메시지 머리글이 아니라 일반 글로 본다.
# 글이 빈 메시지("[나] [오전 1:01]")도 머리글이다(뒤의 공백+글은 선택).
$script:ReExportMessage = New-Object System.Text.RegularExpressions.Regex('^\[(?<n>[^\]]+)\] \[(?<ap>오전|오후) (?<h>1[0-2]|0?\d):(?<m>[0-5]\d)\](?: (?<t>.*))?$')

function ConvertFrom-KakaoExport {
    param([Parameter(Mandatory)][string]$Path)
    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (New-KitError -Key 'parse.fileNotFound' -FormatArgs @($Path) -ExitCode 3) }

    # BOM이 있으면 읽으면서 걷어낸다(공식 파일은 BOM 없음). 줄 끝은 CRLF·LF·CR 모두 받는다.
    try { $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false))) }
    catch { throw (New-KitError -Key 'parse.fileNotFound' -FormatArgs @($Path) -ExitCode 3) }
    $lines = $text -split '\r\n|\n|\r'

    $head = $script:ReExportHeader.Match($lines[0])
    if (-not $head.Success) { throw (New-KitError -Key 'parse.notExport' -FormatArgs @($Path) -ExitCode 3) }

    $savedAt = $null
    $messages = New-Object 'System.Collections.Generic.List[object]'
    $currentDate = $null
    $open = $false      # 마무리하지 않은 메시지가 있는가
    $sender = $null
    $stamp = $null
    $first = $null      # 메시지 첫 줄(머리글 뒤의 글)
    $cont = $null       # 이어지는 줄들(없으면 null: 대부분의 메시지)
    $reDate = $script:ReExportDate
    $reMsg = $script:ReExportMessage

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($i -le 4 -and $null -eq $savedAt) {
            $s = $script:ReExportSaved.Match($line)
            if ($s.Success) {
                # 저장 날짜가 이상해도(2026-13-45 같은) 읽기를 멈추지 않는다. 그 값만 비워 둔다.
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParseExact($s.Groups['d'].Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { $savedAt = $parsed }
                continue
            }
        }
        $c0 = if ($line.Length -gt 0) { $line[0] } else { [char]0 }
        $isDate = $false
        $m = $null
        if ($c0 -eq '-') {
            $d = $reDate.Match($line)
            # 13월 45일 같은 불가능한 날짜는 날짜 줄로 보지 않는다(일반 글로 흘러가 앞 메시지의 이어지는 줄이 된다).
            if ($d.Success) {
                $dy = [int]$d.Groups['y'].Value; $dmo = [int]$d.Groups['mo'].Value; $dd = [int]$d.Groups['d'].Value
                $isDate = ($dy -ge 1 -and $dmo -ge 1 -and $dmo -le 12 -and $dd -ge 1 -and $dd -le [datetime]::DaysInMonth($dy, $dmo))
            }
        }
        elseif ($c0 -eq '[') {
            $m = $reMsg.Match($line)
            if (-not $m.Success) { $m = $null }
        }
        if ($isDate -or $null -ne $m) {
            # 지금까지 모은 메시지를 마무리해 목록에 넣는다. 끝의 빈 줄(날짜 구분선 앞 여백)은 버린다.
            if ($open) {
                if ($null -eq $cont) { $text1 = $first.TrimEnd("`n") }
                else { $text1 = ($first + "`n" + ($cont -join "`n")).TrimEnd("`n") }
                $messages.Add([pscustomobject]@{ Timestamp = $stamp; Sender = $sender; Text = $text1 })
                $open = $false
            }
            if ($isDate) {
                $currentDate = New-Object DateTime $dy, $dmo, $dd
            }
            else {
                $g = $m.Groups
                $hour = ([int]$g['h'].Value) % 12
                if ($g['ap'].Value -eq '오후') { $hour += 12 }
                $sender = $g['n'].Value
                $stamp = $null
                if ($null -ne $currentDate) { $stamp = $currentDate.AddHours($hour).AddMinutes([int]$g['m'].Value) }
                $first = $g['t'].Value
                $cont = $null
                $open = $true
            }
            continue
        }
        # 새 메시지가 아닌 줄은 앞 메시지의 이어지는 줄이다. (머리글 아래 빈 줄처럼 앞 메시지가 아직 없으면 버린다)
        if ($open) {
            if ($null -eq $cont) { $cont = New-Object 'System.Collections.Generic.List[string]' }
            $cont.Add($line)
        }
    }
    if ($open) {
        if ($null -eq $cont) { $text1 = $first.TrimEnd("`n") }
        else { $text1 = ($first + "`n" + ($cont -join "`n")).TrimEnd("`n") }
        $messages.Add([pscustomobject]@{ Timestamp = $stamp; Sender = $sender; Text = $text1 })
    }
    return [pscustomobject]@{
        Room     = $head.Groups['room'].Value
        SavedAt  = $savedAt
        Messages = $messages.ToArray()
    }
}
