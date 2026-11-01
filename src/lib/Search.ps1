# 보관된 내보내기(latest.txt)에서 낱말을 찾는다. 카카오톡을 조작하지 않는다.
# 필요한 부품: Export(Get-ExportRoomDir), Config, Parse, Errors, Messages.ko.

# 낱말은 정규식이 아니라 글자 그대로(대소문자 구분 없이) 메시지 본문에서 찾는다. 보낸 사람 이름은 보지 않는다.
# -Room 이 없으면 부른 쪽(-Caller)이 읽을 수 있는 모든 방을 찾고, 내보내기가 없는 방은 건너뛴다.
# -Room 이 있으면 그 방이 읽기 허용이어야 하고(아니면 멈춤), 보관된 내보내기가 없으면 없다고 알린다.
# latest.txt 만 보므로 스냅샷마다 같은 메시지가 있어도 결과에 한 번만 나온다.
function Search-KakaoExports {
    param([string]$Keyword, [string]$Room, [string]$Caller = 'human')
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrWhiteSpace($Keyword)) { throw (New-KitError -Key 'search.keywordEmpty' -ExitCode 1) }
    $explicit = $PSBoundParameters.ContainsKey('Room')
    if ($explicit) {
        if (-not (Test-RoomAllowed -Name $Room -Action 'read' -Caller $Caller)) { throw (New-KitError -Key 'export.notAllowed' -FormatArgs @($Room) -ExitCode 1) }
        $targets = @($Room)
    }
    else {
        $targets = @(Get-ConfigRooms -Config (Get-KitConfig) | ForEach-Object { [string]$_.name } | Where-Object { Test-RoomAllowed -Name $_ -Action 'read' -Caller $Caller })
    }
    $found = New-Object 'System.Collections.Generic.List[object]'
    foreach ($name in $targets) {
        $latest = [System.IO.Path]::Combine((Get-ExportRoomDir -Room $name), 'latest.txt')
        if (-not (Test-Path -LiteralPath $latest -PathType Leaf)) {
            if ($explicit) { throw (New-KitError -Key 'export.noExport' -FormatArgs @($name) -ExitCode 3) }
            continue
        }
        foreach ($m in @((ConvertFrom-KakaoExport -Path $latest).Messages)) {
            if (([string]$m.Text).IndexOf($Keyword, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found.Add([pscustomobject]@{ Room = $name; Timestamp = $m.Timestamp; Sender = $m.Sender; Text = $m.Text })
            }
        }
    }
    return $found.ToArray()
}
