# 텍스트 클립보드 보존. 붙여넣기 자동화가 사용자의 기존 복사 내용을 지우지 않게 "저장 -> 사용 -> 복원"을 한 덩어리로 묶는다.
# 윈도우 클립보드 기록(Win+V)이나 캡처 도구가 변경 직후 클립보드를 잠깐 붙잡거나 빈 값으로 읽히게 하는 일이 실제로 있어서,
# 모든 읽기·쓰기는 "읽혔는지 확인하고, 안 읽히면 재시도하고, 끝내 안 되면 중단"한다. (빈 값을 그대로 믿고 복원하면 사용자의 복사 내용이 지워진다)
Add-Type -AssemblyName System.Windows.Forms

function New-ClipboardError {
    param([Parameter(Mandatory)][string]$Key)
    return New-Object KakaoClipboardException -ArgumentList @(Get-Msg -Key $Key)
}

# 클립보드는 STA 스레드에서만 안정적으로 쓸 수 있다.
function Assert-ClipboardSta {
    $ErrorActionPreference = 'Stop'
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw (New-ClipboardError -Key 'clip.notSta')
    }
}

# 다른 프로그램이 클립보드를 잠깐 잡고 있으면 실패하므로 몇 번 다시 시도한다. 키트가 일부러 던진 거부는 재시도하지 않는다.
function Invoke-ClipboardRetry {
    param([Parameter(Mandatory)][scriptblock]$Body)
    $ErrorActionPreference = 'Stop'
    for ($i = 1; $i -le 5; $i++) {
        try { return (& $Body) }
        catch {
            if ($_.Exception -is [KakaoKitException]) { throw }
            if ($i -eq 5) { throw (New-ClipboardError -Key 'clip.busy') }
            Start-Sleep -Milliseconds 100
        }
    }
}

# 클립보드에 기대한 글이 읽힐 때까지(최대 TimeoutMs) 기다린다. 읽기가 일시적으로 비어 보이는 경우를 견딘다.
function Wait-ClipboardText {
    param([string]$Expected, [int]$TimeoutMs = 2000)
    $cb = [System.Windows.Forms.Clipboard]
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        try { if ([string]::Equals($cb::GetText(), $Expected, [System.StringComparison]::Ordinal)) { return $true } } catch { }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

# 지금 클립보드를 텍스트로 저장한다. 이미지·파일처럼 텍스트로 되돌릴 수 없는 내용이면 바꾸기 전에 거부한다.
# 글자가 있다고 나오는데 내용이 비어 읽히면(일시적 현상) 다시 읽고, 끝내 못 읽으면 중단한다: 비어 있다고 착각해 복원하면 원래 내용이 지워진다.
function Get-ClipboardSnapshot {
    $ErrorActionPreference = 'Stop'
    Assert-ClipboardSta
    $cb = [System.Windows.Forms.Clipboard]
    $emptySeen = 0
    $emptyTextSeen = 0
    for ($i = 1; $i -le 40; $i++) {
        try {
            if ($cb::ContainsImage() -or $cb::ContainsFileDropList() -or $cb::ContainsAudio()) { throw (New-ClipboardError -Key 'clip.nonText') }
            if ($cb::ContainsText()) {
                $emptySeen = 0
                $text = $cb::GetText()
                if ($text.Length -gt 0) { return @{ HasText = $true; Text = $text } }
                # 일시적 빈 값은 곧 글이 읽히지만, 계속 비어 있으면 진짜 빈 글(보존할 내용 없음)이다.
                $emptyTextSeen++
                if ($emptyTextSeen -ge 20) { return @{ HasText = $false; Text = $null } }
            }
            else {
                $data = $cb::GetDataObject()
                if ($null -ne $data -and @($data.GetFormats()).Count -gt 0) { throw (New-ClipboardError -Key 'clip.nonText') }
                $emptySeen++
                if ($emptySeen -ge 2) { return @{ HasText = $false; Text = $null } }
            }
        }
        catch {
            if ($_.Exception -is [KakaoKitException]) { throw }
        }
        Start-Sleep -Milliseconds 80
    }
    throw (New-ClipboardError -Key 'clip.busy')
}

# 글을 클립보드에 넣는다. 기본은 윈도우 클립보드 기록·클라우드 동기화에서 빼 달라는 표시를 붙인다(대화 내용이 기록에 남지 않게).
function Set-KitClipboardText {
    param([Parameter(Mandatory)][string]$Text, [switch]$KeepInHistory)
    $data = New-Object System.Windows.Forms.DataObject
    $data.SetText($Text, [System.Windows.Forms.TextDataFormat]::UnicodeText)
    if (-not $KeepInHistory) {
        foreach ($format in 'CanIncludeInClipboardHistory', 'CanUploadToCloudClipboard', 'ExcludeClipboardContentFromMonitorProcessing') {
            $data.SetData($format, (New-Object System.IO.MemoryStream (, [byte[]](0, 0, 0, 0))))
        }
    }
    [void](Invoke-ClipboardRetry { [System.Windows.Forms.Clipboard]::SetDataObject($data, $true, 10, 100) })
}

function Restore-ClipboardSnapshot {
    param([Parameter(Mandatory)][hashtable]$Snapshot)
    $ErrorActionPreference = 'Stop'
    if ($Snapshot.HasText) {
        Set-KitClipboardText -Text ([string]$Snapshot.Text) -KeepInHistory
        if (-not (Wait-ClipboardText -Expected ([string]$Snapshot.Text) -TimeoutMs 2000)) { throw (New-ClipboardError -Key 'clip.restoreFailed') }
    }
    else { [void](Invoke-ClipboardRetry { [System.Windows.Forms.Clipboard]::Clear() }) }
}

function Use-TextClipboard {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $ErrorActionPreference = 'Stop'
    $snapshot = Get-ClipboardSnapshot
    try {
        Set-KitClipboardText -Text $Text
        # 넣은 글이 정말 읽히는지 확인한다. 아니면 Ctrl+V가 엉뚱한 글을 붙여넣게 된다.
        if (-not (Wait-ClipboardText -Expected $Text)) { throw (New-ClipboardError -Key 'clip.setFailed') }
        return (& $Action)
    }
    finally {
        try { Restore-ClipboardSnapshot -Snapshot $snapshot }
        catch {
            if (Get-Command Add-KitWarning -ErrorAction SilentlyContinue) { Add-KitWarning -Warning (Get-Msg -Key 'clip.restoreFailed') }
        }
    }
}
