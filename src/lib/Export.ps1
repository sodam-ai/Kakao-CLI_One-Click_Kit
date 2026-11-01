# 내보내기 파일의 보관과 읽기. 이 파일의 함수는 카카오톡이나 클립보드를 건드리지 않는다(저장 대화상자를 여는 일은 따로 만든다).
#   exports\<방 폴더>\snapshot-yyyyMMdd-HHmmss.txt   방마다 최근 3개만, 30일이 지난 것은 지운다
#   exports\<방 폴더>\latest.txt                     가장 새 스냅샷의 복사본. 읽기·검색은 이것만 본다
# 내보낸 파일에는 다른 사람의 대화가 들어 있다: 이 키트의 데이터 폴더 밖으로 내보내지 않고, 로그에 본문을 쓰지 않는다.
# 필요한 부품: Config(Assert-RoomNameValid, Test-SameRoomName, Test-RoomAllowed), Parse(ConvertFrom-KakaoExport), Errors, Messages.ko, Paths.

$script:ExportKeepCount = 3
$script:ExportKeepDays = 30
$script:ReSnapshotName = New-Object System.Text.RegularExpressions.Regex('^snapshot-(?<t>\d{8}-\d{6})\.txt$')

# 방 이름으로 보관 폴더 이름을 만든다(폴더는 만들지 않는 순수 계산).
# 방 이름에는 폴더 이름에 못 쓰는 글자가 있을 수 있으므로 글자·숫자·밑줄·붙임표만 남기고 나머지는 밑줄로 바꾼 뒤 30자로 자르고,
# 원래 이름의 해시를 붙여 비슷하게 생긴 이름("a/b" 와 "a?b")이 같은 폴더를 쓰지 못하게 한다. 해시가 항상 끝에 붙으므로
# ".." 나 "CON" 같은 이름도 그 자체로는 폴더 이름이 되지 않고, 결과는 언제나 exports 폴더 바로 아래의 한 칸이다.
function Get-ExportRoomDir {
    param([string]$Room)
    $ErrorActionPreference = 'Stop'
    Assert-RoomNameValid -Name $Room
    $clean = [System.Text.RegularExpressions.Regex]::Replace($Room, '[^\p{L}\p{N}_-]', '_')
    if ($clean.Length -gt 30) { $clean = $clean.Substring(0, 30) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Room)) }
    finally { $sha.Dispose() }
    $hex = -join (@($hash[0..5]) | ForEach-Object { $_.ToString('x2') })
    return [System.IO.Path]::Combine((Get-KitPaths).ExportsDir, ($clean + '-' + $hex))
}

# 같은 폴더 안에서 임시 이름으로 복사한 뒤 이름을 바꿔 넣는다(중간에 멈춰도 반쯤 쓴 파일이 이름을 차지하지 않는다).
function Copy-ExportFileAtomic {
    param([string]$From, [string]$To)
    $ErrorActionPreference = 'Stop'
    $tmp = $To + '.tmp'
    try {
        [System.IO.File]::Copy($From, $tmp, $true)
        Move-Item -LiteralPath $tmp -Destination $To -Force
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw
    }
}

# snapshot-yyyyMMdd-HHmmss.txt 꼴의 파일만 본다(그 밖의 파일은 사용자가 둔 것일 수 있어 절대 지우지 않는다).
# 가장 새 것부터 3개만 남기고, 30일을 넘긴 것은 3개 안이어도 지운다. -Keep 으로 받은 방금 저장한 파일은 지우지 않는다.
function Remove-ExpiredExportSnapshots {
    param([string]$Dir, [string]$Keep, [datetime]$Now)
    $ErrorActionPreference = 'Stop'
    $items = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File)) {
        $m = $script:ReSnapshotName.Match($f.Name)
        if (-not $m.Success) { continue }
        $t = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($m.Groups['t'].Value, 'yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t)) { continue }
        $items += [pscustomobject]@{ Path = $f.FullName; Time = $t }
    }
    $sorted = @($items | Sort-Object -Property Time -Descending)
    $cutoff = $Now.AddDays(-$script:ExportKeepDays)
    $removed = 0
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ([string]::Equals($sorted[$i].Path, $Keep, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($i -ge $script:ExportKeepCount -or $sorted[$i].Time -lt $cutoff) {
            Remove-Item -LiteralPath $sorted[$i].Path -Force
            $removed++
        }
    }
    return $removed
}

# 내보낸 파일 하나를 그 방의 보관함에 넣는다. 원본 파일은 건드리지 않는다(임시 파일 정리는 부른 쪽이 한다).
# 파일이 카카오톡 내보내기가 아니거나 머리글의 방 이름이 -Room 과 글자 그대로 다르면 아무것도 쓰지 않고 멈춘다
# (다른 방의 대화가 이 방의 이름으로 보관되어 AI 읽기 권한을 통해 새는 것을 막는다).
function Update-ExportStore {
    param([string]$Room, [string]$SourcePath, [datetime]$Now = (Get-Date))
    $ErrorActionPreference = 'Stop'
    $dir = Get-ExportRoomDir -Room $Room
    $parsed = ConvertFrom-KakaoExport -Path $SourcePath
    if (-not (Test-SameRoomName $parsed.Room $Room)) { throw (New-KitError -Key 'export.roomMismatch' -FormatArgs @($Room) -ExitCode 3) }
    $stamp = $Now.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $snapshot = [System.IO.Path]::Combine($dir, 'snapshot-' + $stamp + '.txt')
    $latest = [System.IO.Path]::Combine($dir, 'latest.txt')
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-ExportFileAtomic -From $SourcePath -To $snapshot
        Copy-ExportFileAtomic -From $snapshot -To $latest
        $removed = Remove-ExpiredExportSnapshots -Dir $dir -Keep $snapshot -Now $Now
    }
    catch { throw (New-KitError -Key 'export.storeFailed' -ExitCode 3) }
    return [pscustomobject]@{ Snapshot = $snapshot; Latest = $latest; Removed = $removed }
}

# 보관된 가장 새 내보내기(latest.txt)에서 메시지를 읽는다. 카카오톡을 조작하지 않는다.
# 허용 목록·읽기 권한은 Test-RoomAllowed 와 같다(AI 는 방마다 aiRead 가 켜진 곳만).
# -Last N 은 가장 새 N개, -Since 는 지금(-Now)에서 그만큼 거슬러 올라간 시각 이후의 메시지. 둘을 같이 쓰면 기간 안에서 마지막 N개다.
# 시각을 알 수 없는 메시지(첫 날짜 줄보다 앞선 글)는 최근 것임을 보일 수 없으므로 -Since 를 쓰면 뺀다.
function Read-KakaoRoom {
    param([string]$Room, [int]$Last = 0, [timespan]$Since, [string]$Caller = 'human', [datetime]$Now = (Get-Date))
    $ErrorActionPreference = 'Stop'
    if (-not (Test-RoomAllowed -Name $Room -Action 'read' -Caller $Caller)) { throw (New-KitError -Key 'export.notAllowed' -FormatArgs @($Room) -ExitCode 1) }
    $useLast = $PSBoundParameters.ContainsKey('Last')
    $useSince = $PSBoundParameters.ContainsKey('Since')
    if (($useLast -and $Last -lt 1) -or ($useSince -and $Since -le [timespan]::Zero)) { throw (New-KitError -Key 'export.optionInvalid' -ExitCode 1) }
    $latest = [System.IO.Path]::Combine((Get-ExportRoomDir -Room $Room), 'latest.txt')
    if (-not (Test-Path -LiteralPath $latest -PathType Leaf)) { throw (New-KitError -Key 'export.noExport' -FormatArgs @($Room) -ExitCode 3) }
    $messages = @((ConvertFrom-KakaoExport -Path $latest).Messages)
    if ($useSince) {
        $cutoff = $Now - $Since
        $messages = @($messages | Where-Object { $null -ne $_.Timestamp -and $_.Timestamp -ge $cutoff })
    }
    if ($useLast -and $messages.Count -gt $Last) { $messages = @($messages | Select-Object -Last $Last) }
    return $messages
}
