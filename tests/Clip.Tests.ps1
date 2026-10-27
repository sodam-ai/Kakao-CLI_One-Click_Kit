$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Clip')
. (Join-Path $here '_Load.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 시험은 사용자의 실제 클립보드를 잠깐 빌려 쓴다. 이미지·파일이 들어 있으면 잃지 않도록 시험을 건너뛴다.
$skipClip = ([System.Windows.Forms.Clipboard]::ContainsImage() -or [System.Windows.Forms.Clipboard]::ContainsFileDropList() -or [System.Windows.Forms.Clipboard]::ContainsAudio())

# 이 PC에서는 윈도우 클립보드 기록·캡처 도구가 변경 직후 클립보드를 잠깐 붙잡아 읽기가 일시적으로 빈 값이 된다.
# 그래서 시험의 읽기도 기대한 값이 나올 때까지 잠깐 기다린다. (끝내 안 나오면 그 값 그대로 돌려줘 시험이 실패한다)
function Get-ClipTextSettled([string]$Expected) {
    $last = ''
    for ($i = 0; $i -lt 40; $i++) {
        try { $last = [System.Windows.Forms.Clipboard]::GetText() } catch { $last = '' }
        if ($last -eq $Expected) { return $last }
        Start-Sleep -Milliseconds 50
    }
    return $last
}
function Test-ClipHasTextSettled([bool]$Expected) {
    $last = $null
    for ($i = 0; $i -lt 40; $i++) {
        try { $last = [System.Windows.Forms.Clipboard]::ContainsText() } catch { $last = $null }
        if ($last -eq $Expected) { return $last }
        Start-Sleep -Milliseconds 50
    }
    return $last
}
function Set-ClipText([string]$Text) {
    for ($i = 0; $i -lt 5; $i++) {
        try { [System.Windows.Forms.Clipboard]::SetDataObject($Text, $true, 10, 100); return } catch { Start-Sleep -Milliseconds 100 }
    }
    throw 'test helper could not set the clipboard'
}

# 본문을 실행하고, 끝나면 원래 텍스트(또는 빈 상태)로 되돌린다.
function Use-ClipboardSandbox([scriptblock]$Body) {
    $snapshot = Get-ClipboardSnapshot
    try { & $Body }
    finally {
        if ($snapshot.HasText) { Set-ClipText $snapshot.Text } else { Invoke-ClipboardRetry { [System.Windows.Forms.Clipboard]::Clear() } | Out-Null }
    }
}

Describe 'Clip: Use-TextClipboard' {
    It 'puts the text on the clipboard during the action, returns its output, and restores the old text' -Skip:$skipClip {
        Use-ClipboardSandbox {
            Set-ClipText 'ORIGINAL-TEXT'
            $during = Use-TextClipboard -Text 'PASTE-ME' -Action { Get-ClipTextSettled 'PASTE-ME' }
            $during | Should Be 'PASTE-ME'
            Get-ClipTextSettled 'ORIGINAL-TEXT' | Should Be 'ORIGINAL-TEXT'
        }
    }

    It 'restores the old text even if the action throws' -Skip:$skipClip {
        Use-ClipboardSandbox {
            Set-ClipText 'ORIGINAL-TEXT'
            { Use-TextClipboard -Text 'PASTE-ME' -Action { throw 'boom' } } | Should Throw 'boom'
            Get-ClipTextSettled 'ORIGINAL-TEXT' | Should Be 'ORIGINAL-TEXT'
        }
    }

    It 'restores an empty clipboard to empty' -Skip:$skipClip {
        Use-ClipboardSandbox {
            Invoke-ClipboardRetry { [System.Windows.Forms.Clipboard]::Clear() } | Out-Null
            Use-TextClipboard -Text 'PASTE-ME' -Action { }
            Test-ClipHasTextSettled $false | Should Be $false
        }
    }

    It 'keeps Korean, line breaks and emoji exactly, both ways' -Skip:$skipClip {
        Use-ClipboardSandbox {
            $emoji = [char]::ConvertFromUtf32(0x1F600)
            $original = "원본 글`r`n둘째 줄 " + $emoji
            $pasted = "붙여넣을 글 한글`r`n두 번째 줄 `"따옴표`" & % ^ ! | " + $emoji
            Set-ClipText $original
            $during = Use-TextClipboard -Text $pasted -Action { Get-ClipTextSettled $pasted }
            $during | Should Be $pasted
            Get-ClipTextSettled $original | Should Be $original
        }
    }

    It 'keeps the pasted text out of the Windows clipboard history and cloud sync while it is on the clipboard' -Skip:$skipClip {
        Use-ClipboardSandbox {
            Set-ClipText 'ORIGINAL-TEXT'
            $formats = Use-TextClipboard -Text 'PASTE-ME' -Action {
                [void](Get-ClipTextSettled 'PASTE-ME')
                @([System.Windows.Forms.Clipboard]::GetDataObject().GetFormats())
            }
            ($formats -contains 'CanIncludeInClipboardHistory') | Should Be $true
            ($formats -contains 'CanUploadToCloudClipboard') | Should Be $true
            ($formats -contains 'ExcludeClipboardContentFromMonitorProcessing') | Should Be $true
        }
    }

    It 'never leaves an empty string behind when the original text reads back as empty for a moment' -Skip:$skipClip {
        Use-ClipboardSandbox {
            Set-ClipText 'ORIGINAL-TEXT'
            # 바로 이어서 여러 번 반복해도(윈도우 클립보드 기록이 막 읽는 순간과 겹쳐도) 원래 글이 항상 돌아와야 한다.
            for ($i = 0; $i -lt 6; $i++) {
                Use-TextClipboard -Text ('PASTE-' + $i) -Action { }
                Get-ClipTextSettled 'ORIGINAL-TEXT' | Should Be 'ORIGINAL-TEXT'
            }
        }
    }

    It 'refuses an image on the clipboard before changing anything, and never runs the action' -Skip:$skipClip {
        Use-ClipboardSandbox {
            $bmp = New-Object System.Drawing.Bitmap 4, 4
            try {
                [System.Windows.Forms.Clipboard]::SetImage($bmp)
                $flag = @{ ran = $false }
                $e = Get-ThrownError { Use-TextClipboard -Text 'X' -Action { $flag.ran = $true } }
                $e.GetType().Name | Should Be 'KakaoClipboardException'
                $e.ExitCode | Should Be 3
                $e.Message | Should Match '이미지나 파일'
                $flag.ran | Should Be $false
                [System.Windows.Forms.Clipboard]::ContainsImage() | Should Be $true
            }
            finally { $bmp.Dispose() }
        }
    }

    It 'refuses a copied file list before changing anything' -Skip:$skipClip {
        Use-ClipboardSandbox {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-clip-' + [guid]::NewGuid().ToString('N') + '.txt')
            [System.IO.File]::WriteAllText($tmp, 'x')
            try {
                $files = New-Object System.Collections.Specialized.StringCollection
                [void]$files.Add($tmp)
                [System.Windows.Forms.Clipboard]::SetFileDropList($files)
                $e = Get-ThrownError { Use-TextClipboard -Text 'X' -Action { } }
                $e.GetType().Name | Should Be 'KakaoClipboardException'
                [System.Windows.Forms.Clipboard]::ContainsFileDropList() | Should Be $true
            }
            finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Clip: STA 확인' {
    It 'refuses to run on a non-STA thread instead of failing in a confusing way' {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.Open()
        try {
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({
                    param($lib)
                    foreach ($n in 'Messages.ko', 'Paths', 'Errors', 'Clip') { . (Join-Path $lib ($n + '.ps1')) }
                    try { Use-TextClipboard -Text 'x' -Action { }; 'no-throw' } catch { $_.Exception.GetType().Name }
                }).AddArgument($kitLibDir)
            $out = @($ps.Invoke())
            $out[0] | Should Be 'KakaoClipboardException'
        }
        finally { $rs.Dispose() }
    }
}
