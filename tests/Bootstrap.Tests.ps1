$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
foreach ($f in 'Messages.ko.ps1', 'Paths.ps1') {
    $p = Join-Path $root ('src\lib\' + $f)
    if (Test-Path $p) { . $p }
}

function Get-RepoFiles([string[]]$Extensions) {
    Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
        Where-Object { $_.FullName -notmatch '\\(\.remember|\.git|\.superpowers)\\' }
}

function Invoke-Cli([string[]]$CliArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/c ""' + (Join-Path $root 'kakao.cmd') + '" ' + ($CliArgs -join ' ') + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    @{ ExitCode = $proc.ExitCode; Out = $out; Err = $err }
}

Describe 'Bootstrap: 인코딩 규칙' {
    It 'every .ps1 file starts with a UTF-8 BOM' {
        $bad = @()
        foreach ($f in (Get-RepoFiles @('.ps1'))) {
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { $bad += $f.Name }
        }
        ($bad -join ', ') | Should BeNullOrEmpty
    }

    It 'every .bat/.cmd file has no BOM and only CRLF line endings' {
        $bad = @()
        foreach ($f in (Get-RepoFiles @('.bat', '.cmd'))) {
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
            $lf = 0; $crlf = 0
            for ($i = 0; $i -lt $b.Length; $i++) {
                if ($b[$i] -eq 10) { $lf++; if ($i -gt 0 -and $b[$i - 1] -eq 13) { $crlf++ } }
            }
            if ($hasBom -or $lf -ne $crlf) { $bad += $f.Name }
        }
        ($bad -join ', ') | Should BeNullOrEmpty
    }
}

Describe 'Bootstrap: 관리자 권한 없음' {
    It 'src never asks for elevation or installs services/tasks' {
        $patterns = 'RunAs', '-Verb', 'Register-ScheduledTask', 'New-Service', 'schtasks'
        $hits = @()
        foreach ($f in (Get-ChildItem -Path (Join-Path $root 'src') -Recurse -File -Include *.ps1, *.cmd, *.bat)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            foreach ($pat in $patterns) {
                if ($text.IndexOf($pat, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += ($f.Name + ':' + $pat) }
            }
        }
        ($hits -join ', ') | Should BeNullOrEmpty
    }

    It 'no line writes to Program Files or HKLM' {
        $write = 'Set-Content|Add-Content|Out-File|New-Item|Copy-Item|Move-Item|Remove-Item|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty'
        $hits = @()
        foreach ($f in (Get-ChildItem -Path (Join-Path $root 'src') -Recurse -File -Include *.ps1)) {
            foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
                if ($line -match 'Program Files|HKLM' -and $line -match $write) { $hits += ($f.Name + ': ' + $line.Trim()) }
            }
        }
        ($hits -join ' | ') | Should BeNullOrEmpty
    }

    It 'Test-KitElevated is false in this session' {
        Test-KitElevated | Should Be $false
    }
}

Describe 'Bootstrap: 한글 문구와 경로' {
    It 'Get-Msg formats a Korean message' {
        Get-Msg -Key 'version.banner' -FormatArgs @('1.0.0') | Should Be '카카오톡 키트 1.0.0'
    }

    It 'Get-Msg throws for an unknown key' {
        { Get-Msg -Key 'no.such.key' } | Should Throw 'Unknown message key'
    }

    It 'Get-KitPaths honors KAKAO_KIT_HOME' {
        $old = $env:KAKAO_KIT_HOME
        try {
            $env:KAKAO_KIT_HOME = 'C:\KitTestHome'
            $p = Get-KitPaths
            $p.DataDir | Should Be 'C:\KitTestHome'
            $p.ConfigFile | Should Be 'C:\KitTestHome\config.json'
            $p.ExportsDir | Should Be 'C:\KitTestHome\exports'
            $p.LogsDir | Should Be 'C:\KitTestHome\logs'
            $p.ManifestFile | Should Be 'C:\KitTestHome\manifest.json'
            $p.LockName | Should Not BeNullOrEmpty
        }
        finally { $env:KAKAO_KIT_HOME = $old }
    }

    It 'Get-KitPaths is a pure calculation: a data folder on a drive that does not exist gives paths and no error' {
        $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
        $free = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T') | Where-Object { $used -notcontains $_ } | Select-Object -First 1
        if (-not $free) { return }   # 이 PC 에 비어 있는 드라이브 문자가 없으면 확인할 수 없다(통과로 센다)
        $old = $env:KAKAO_KIT_HOME
        $oldEap = $ErrorActionPreference
        try {
            $env:KAKAO_KIT_HOME = $free + ':\no such folder'
            $ErrorActionPreference = 'Stop'   # 제품(kakao.ps1)과 같은 설정: 여기서 던지면 사용자에게 영어 시스템 오류가 보인다
            $p = Get-KitPaths
            $p.ConfigFile | Should Be ($free + ':\no such folder\config.json')
            $p.LogsDir | Should Be ($free + ':\no such folder\logs')
            $p.ExportsDir | Should Be ($free + ':\no such folder\exports')
        }
        finally { $ErrorActionPreference = $oldEap; $env:KAKAO_KIT_HOME = $old }
    }

    It 'Get-KitPaths defaults to LOCALAPPDATA\KakaoKit' {
        $old = $env:KAKAO_KIT_HOME
        try {
            $env:KAKAO_KIT_HOME = $null
            (Get-KitPaths).DataDir | Should Be (Join-Path $env:LOCALAPPDATA 'KakaoKit')
        }
        finally { $env:KAKAO_KIT_HOME = $old }
    }
}

Describe 'Bootstrap: 안전 규칙 (throw 하는 함수는 항상 중단한다)' {
    # 호출하는 쪽이 -ErrorAction SilentlyContinue 를 쓰면 throw 가 무시되어 안전 정지가 뚫린다(실제로 확인됨).
    # 함수 첫 줄의 $ErrorActionPreference = 'Stop' 이 이를 막는다. 앞으로 만드는 함수도 빼먹지 못하게 소스를 구문 분석해 강제한다.
    It 'every function in src that contains throw starts with $ErrorActionPreference = Stop' {
        $bad = @()
        foreach ($f in (Get-ChildItem -Path (Join-Path $root 'src') -Recurse -File -Include *.ps1)) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            if (@($errors).Count -gt 0) { $bad += ($f.Name + ':parse-error'); continue }
            $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $functions) {
                $throws = $fn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true)
                if (@($throws).Count -eq 0) { continue }
                $first = @($fn.Body.EndBlock.Statements) | Select-Object -First 1
                $ok = ($first -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
                    ($first.Left.ToString() -eq '$ErrorActionPreference') -and
                    ($first.Right.ToString().Trim("'", '"') -eq 'Stop')
                if (-not $ok) { $bad += ($f.Name + ':' + $fn.Name) }
            }
        }
        ($bad -join ', ') | Should BeNullOrEmpty
    }
}

# 시작.bat 을 폴더 이름이 다른 복사본에서 실제로 실행해 본다. 입력은 닫아 둔다(마지막의 "아무 키나" 대기가 바로 끝나게).
function Invoke-StartBatInFolder([string]$FolderName, [switch]$WithoutSrc) {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-startbat-' + [guid]::NewGuid().ToString('N'))
    $dir = Join-Path $base $FolderName
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root '시작.bat') -Destination $dir
        Copy-Item -LiteralPath (Join-Path $root 'kakao.cmd') -Destination $dir
        if (-not $WithoutSrc) { Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $dir -Recurse }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/c ""' + (Join-Path $dir '시작.bat') + '""'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $done = $proc.WaitForExit(30000)
        if (-not $done) { $proc.Kill() }
        $out = $proc.StandardOutput.ReadToEnd()
        return @{ TimedOut = (-not $done); Out = $out }
    }
    finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Bootstrap: 시작.bat 은 폴더 이름에 특수 글자가 있어도 동작한다' {
    # plain 은 대조군(시험 도구 자체가 맞는지 보여 준다). ^ 와 % 는 call 이 한 번 더 해석해서 예전에는 버전 줄 없이 조용히 끝났다.
    # 존재하는 환경 변수 이름을 %...% 로 감싼 폴더(A%TEMP%B)는 시험하지 않는다: cmd /c 가 배치 파일을 열기 전에 이름을 바꿔 버려서 배치 파일 안에서는 고칠 수 없다(README 알려진 한계).
    # 반복문 대신 It 를 하나씩 쓴다: Readme.Tests 가 소스의 "It '" 줄 수로 시험 개수를 세므로 반복문으로 만든 시험은 개수에서 빠진다.
    function Assert-StartBatShowsBanner([string]$Folder) {
        $r = Invoke-StartBatInFolder $Folder
        $r.TimedOut | Should Be $false
        $r.Out | Should Match '카카오톡 키트 1\.0\.0'
    }

    It 'shows the version banner in a plain folder (control: proves the test itself works)' { Assert-StartBatShowsBanner 'plain' }
    It 'shows the version banner when the folder name contains ^' { Assert-StartBatShowsBanner 'A^B' }
    It 'shows the version banner when the folder name contains %20' { Assert-StartBatShowsBanner 'A%20B' }
    It 'shows the version banner when the folder name contains &' { Assert-StartBatShowsBanner 'A&B' }
    It 'shows the version banner when the folder name contains !' { Assert-StartBatShowsBanner 'A!B' }
    It 'shows the version banner when the folder name has Korean, spaces and parentheses' { Assert-StartBatShowsBanner '한글 (복사본) 1' }

    It 'says in Korean that it could not run, instead of ending silently' {
        $r = Invoke-StartBatInFolder 'nosrc' -WithoutSrc
        $r.TimedOut | Should Be $false
        $r.Out | Should Match '실행하지 못했습니다'
    }
}

Describe 'Bootstrap: 저장소에 올리면 안 되는 것' {
    It '.gitignore excludes tool state folders and capture images' {
        $lines = @([System.IO.File]::ReadAllLines((Join-Path $root '.gitignore'), (New-Object System.Text.UTF8Encoding($false))) | ForEach-Object { $_.Trim() })
        $missing = @('.omc/', '.codex/', 'captures/', '*.png', '*.jpg') | Where-Object { $lines -cnotcontains $_ }
        ($missing -join ', ') | Should BeNullOrEmpty
    }
}

Describe 'Bootstrap: kakao.cmd' {
    It 'version prints the Korean banner and exits 0' {
        $r = Invoke-Cli @('version')
        $r.ExitCode | Should Be 0
        $r.Out | Should Match '카카오톡 키트'
        $r.Out | Should Match '1\.0\.0'
    }

    It 'unknown command exits 1 with a Korean hint' {
        $r = Invoke-Cli @('nosuchcommand')
        $r.ExitCode | Should Be 1
        $r.Out | Should Match '[가-힣]'
    }

    # 'help' 명령이 생기면(11단계) 이 시험과 두 문구를 함께 고친다. 지금은 없는 명령을 안내하면 안내가 제자리를 돈다.
    It 'does not point to a help command that does not exist: no-command, unknown and "help" all name only commands that work' {
        foreach ($r in (Invoke-Cli @()), (Invoke-Cli @('nosuchcommand')), (Invoke-Cli @('help'))) {
            $r.ExitCode | Should Be 1
            $r.Out | Should Not Match 'kakao help'
            $r.Out | Should Match 'version'
        }
    }
}

Describe 'Bootstrap: 인자의 특수 글자는 어디서 실행되는가 (알려진 한계 D-07 를 시험으로 고정)' {
    function Invoke-PsDirect([string]$ArgText, [string]$WorkDir) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'src\kakao.ps1') + '" ' + $ArgText
        $psi.WorkingDirectory = $WorkDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        $out = $proc.StandardOutput.ReadToEnd()
        [void]$proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        @{ ExitCode = $proc.ExitCode; Lines = @(($out -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
    }

    It 'src\kakao.ps1 called directly (the path automatic callers should use) treats shell characters as plain text: exit 1, nothing runs, no file is created' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-argtest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        try {
            foreach ($payload in 'a&echo PWNED', 'a|echo PWNED', '$(echo PWNED)', 'a>PWNED_FILE.txt', '%OS%', ('a' * 6000)) {
                $r = Invoke-PsDirect $payload $dir
                $r.ExitCode | Should Be 1
                @($r.Lines | Where-Object { $_ -ceq 'PWNED' }).Count | Should Be 0
                @($r.Lines | Where-Object { $_ -like '*Windows_NT*' }).Count | Should Be 0
            }
            @(Get-ChildItem -LiteralPath $dir -Force).Count | Should Be 0
        }
        finally { Remove-Item -LiteralPath $dir -Force -Recurse -ErrorAction SilentlyContinue }
    }

    It 'control: a bare & that reaches kakao.cmd unquoted DOES run what follows (known limit D-07), while a quoted one does not - so the PWNED check can see an execution' {
        # 이 대조군이 거짓이 되면(= kakao.cmd 쪽이 고쳐지면) 이 시험과 README 의 "알려진 한계" 문구를 함께 고친다.
        $bare = Invoke-Cli @('a^&echo PWNED')
        @($bare.Out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ceq 'PWNED' }).Count | Should Be 1
        $quoted = Invoke-Cli @('"a&echo PWNED"')
        @($quoted.Out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ceq 'PWNED' }).Count | Should Be 0
        $quoted.ExitCode | Should Be 1
    }
}
