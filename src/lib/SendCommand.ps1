# kakao send 명령 계층: 인자 해석, 글 파일 읽기, 호출자(사람/AI) 판정, 실행 잠금, 결과 표시.
# 실제 보내기는 Send.ps1 이 한다. 여기서는 입력을 만들지 않고, 실제 제공자가 잠겨 있는 동안(Ready = $false)에는 어떤 호출도 입력 0 으로 멈춘다.
# 규칙: 호출자는 --human 이 있고 키보드 입력이 막혀 있지 않을 때만 사람이다. 그 밖에는 모두 AI 로 본다(기본이 더 엄격한 쪽).

$script:SendFileMaxBytes = 8192

# 인자를 해석한다. 모르는 옵션, 같은 옵션 두 번, 값 없음, 값이 --로 시작, --text/--file 둘 다 또는 둘 다 없음, 방 없음은 모두 사용법 오류(종료 코드 1).
function ConvertFrom-SendArgv {
    param([string[]]$Argv = @())
    $ErrorActionPreference = 'Stop'
    $valueOptions = @('--room', '--text', '--file', '--attempt-id')
    $flagOptions = @('--dry-run', '--yes', '--human')
    $o = @{ Room = $null; Text = $null; File = $null; AttemptId = $null; DryRun = $false; Yes = $false; Human = $false }
    $seen = @()
    $i = 0
    while ($i -lt $Argv.Count) {
        $a = [string]$Argv[$i]
        # 옵션 이름은 대소문자를 구분한다(-ccontains / -cin)
        if ($seen -ccontains $a) { throw (New-KitError -Key 'send.argInvalid' -ExitCode 1) }
        if ($a -cin $flagOptions) {
            $seen += $a
            switch ($a) { '--dry-run' { $o.DryRun = $true } '--yes' { $o.Yes = $true } '--human' { $o.Human = $true } }
            $i += 1
            continue
        }
        if ($a -cin $valueOptions) {
            if ($i + 1 -ge $Argv.Count) { throw (New-KitError -Key 'send.argInvalid' -ExitCode 1) }
            $v = [string]$Argv[$i + 1]
            # 값이 --로 시작하면 옵션 이름을 빠뜨린 것으로 본다. 그런 글을 보내려면 --file 을 쓴다.
            if ($v.StartsWith('--', [System.StringComparison]::Ordinal)) { throw (New-KitError -Key 'send.argInvalid' -ExitCode 1) }
            $seen += $a
            switch ($a) { '--room' { $o.Room = $v } '--text' { $o.Text = $v } '--file' { $o.File = $v } '--attempt-id' { $o.AttemptId = $v } }
            $i += 2
            continue
        }
        throw (New-KitError -Key 'send.argInvalid' -ExitCode 1)
    }
    if ([string]::IsNullOrEmpty($o.Room)) { throw (New-KitError -Key 'send.argInvalid' -ExitCode 1) }
    $hasText = $seen -ccontains '--text'
    $hasFile = $seen -ccontains '--file'
    if (($hasText -and $hasFile) -or (-not $hasText -and -not $hasFile)) { throw (New-KitError -Key 'send.argInvalid' -ExitCode 1) }
    return $o
}

# 글 파일을 읽는다: 8KB 이하, 엄격한 UTF-8(BOM 은 있어도 없어도 됨). 끝의 줄바꿈 한 번만 뗀다. 실패 이유는 하나의 안내로 묶는다.
function Read-SendTextFile {
    param([string]$Path)
    $ErrorActionPreference = 'Stop'
    try {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'not a file' }
        if ((New-Object System.IO.FileInfo -ArgumentList $full).Length -gt $script:SendFileMaxBytes) { throw 'too big' }
        $bytes = [System.IO.File]::ReadAllBytes($full)
        if ($bytes.Length -gt $script:SendFileMaxBytes) { throw 'too big' }
        $skip = 0
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $skip = 3 }
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strict.GetString($bytes, $skip, $bytes.Length - $skip)
        return [regex]::Replace($text, '(\r\n|\n|\r)\z', '')
    }
    catch { throw (New-KitError -Key 'send.fileInvalid' -ExitCode 1) }
}

function Write-SendWarnings {
    foreach ($w in @(Get-KitWarnings)) { Write-Host $w }
    Clear-KitWarnings
}

# kakao send 를 실행하고 종료 코드를 돌려준다. -Provider 는 시험이 가짜를 넣는 자리이고, 없으면 실제(잠긴) 제공자를 쓴다.
function Invoke-SendCommand {
    param(
        [string[]]$Argv = @(),
        [AllowNull()][hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    Clear-KitWarnings
    $locked = $false
    try {
        $o = ConvertFrom-SendArgv -Argv $Argv
        $text = if ($null -ne $o.File) { Read-SendTextFile -Path $o.File } else { [string]$o.Text }
        $caller = 'ai'
        if ($o.Human) {
            Assert-HumanPath -Human
            $caller = 'human'
        }
        # 작업 전체를 감싸는 실행 잠금: 한 번에 하나만. 못 잡으면 입력 0 으로 멈춘다.
        Enter-KitLock
        $locked = $true
        # 실제 실행이면 보낸 글 확인용 내보내기 제공자를 연결한다(실행 잠금은 위에서 잡았다. 내보내기 부품은 잠금을 잡지 않는다). 시험 제공자가 있으면 그쪽이 확인을 정한다.
        if ($null -eq $Provider) { $script:SendExporter = Get-DefaultSendExporter }
        $params = @{ Room = $o.Room; Text = $text; Caller = $caller; DryRun = [bool]$o.DryRun; Yes = [bool]$o.Yes }
        if ($null -ne $o.AttemptId) { $params.AttemptId = $o.AttemptId }
        if ($null -ne $Provider) { $params.Provider = $Provider }
        $res = Send-KakaoMessage @params
        Write-SendWarnings
        switch ($res.Status) {
            'preview' { Write-Host (Get-Msg -Key 'send.preview' -FormatArgs @($res.Room)); return 0 }
            'confirmed' { Write-Host (Get-Msg -Key 'send.confirmed' -FormatArgs @($res.Room)); return 0 }
            default { Write-Host $res.Message; return 2 }
        }
    }
    catch [KakaoKitException] {
        Write-SendWarnings
        Write-Host $_.Exception.Message
        return [int]$_.Exception.ExitCode
    }
    catch {
        # 알 수 없는 오류: 원문(본문이 섞였을 수 있음)을 화면에 내지 않는다.
        Write-SendWarnings
        Write-Host (Get-Msg -Key 'error.unexpected')
        return 3
    }
    finally {
        if ($locked) { Exit-KitLock }
    }
}
