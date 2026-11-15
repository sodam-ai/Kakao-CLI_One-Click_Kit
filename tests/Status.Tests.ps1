$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config', 'Status')
. (Join-Path $here '_Load.ps1')

# 가짜 제공자: 레지스트리 버전 글자와 실행 중인 프로세스 목록을 시험이 정한다. 진짜 레지스트리·프로세스는 건드리지 않는다.
function New-FakeInstallProvider {
    param([string]$Registry, [object[]]$Processes = @(), [switch]$RegistryThrows, [switch]$ProcessesThrows)
    $provider = @{}
    $provider.RegistryVersion = { if ($RegistryThrows) { throw 'fake registry read error' }; $Registry }.GetNewClosure()
    $provider.Processes = { if ($ProcessesThrows) { throw 'fake process read error' }; $Processes }.GetNewClosure()
    return $provider
}
function New-FakeProcess([string]$Version, [string]$Path = 'C:\Fake\KakaoTalk.exe') {
    return @{ Version = $Version; ExePath = $Path }
}

Describe 'Status: 설치 정보는 레지스트리와 실행 중인 프로세스를 대조한다' {
    It 'trusts the registry version when KakaoTalk is not running' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337')
        $i.Installed | Should Be $true
        $i.Version | Should Be '26.9.0.5337'
        $i.Source | Should Be 'registry'
        $i.Running | Should Be $false
        $i.ExePath | Should BeNullOrEmpty
    }

    It 'takes the executable path from the running process when registry and process agree' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @(New-FakeProcess '26.9.0.5337' 'C:\Fake\KakaoTalk.exe'))
        $i.Installed | Should Be $true
        $i.Version | Should Be '26.9.0.5337'
        $i.Source | Should Be 'registry+process'
        $i.Running | Should Be $true
        $i.ExePath | Should Be 'C:\Fake\KakaoTalk.exe'
    }

    It 'does not trust the registry when the running process has another version' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @(New-FakeProcess '26.9.1.5339'))
        $i.Installed | Should Be $true
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'mismatch'
        $i.Running | Should Be $true
    }

    It 'is a mismatch when two running processes disagree about the version' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @((New-FakeProcess '26.9.0.5337'), (New-FakeProcess '26.9.1.5339')))
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'mismatch'
    }

    It 'uses the process version when the registry has none' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Processes @(New-FakeProcess '26.9.1.5339'))
        $i.Installed | Should Be $true
        $i.Version | Should Be '26.9.1.5339'
        $i.Source | Should Be 'process'
        $i.Running | Should Be $true
    }

    It 'treats an empty or blank registry value as not found' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '   ')
        $i.Installed | Should Be $false
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'none'
    }

    It 'reports not installed when there is neither a registry version nor a process' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider)
        $i.Installed | Should Be $false
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'none'
        $i.Running | Should Be $false
        $i.ExePath | Should BeNullOrEmpty
    }

    It 'gives no version and does not throw when the registry cannot be read' {
        { $script:i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -RegistryThrows) } | Should Not Throw
        $script:i.Version | Should BeNullOrEmpty
        $script:i.Source | Should Be 'error'
    }

    It 'gives no version and does not throw when the process list cannot be read' {
        { $script:i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -ProcessesThrows) } | Should Not Throw
        $script:i.Version | Should BeNullOrEmpty
        $script:i.Source | Should Be 'error'
    }

    It 'gives no version when a running process version cannot be read (nothing to cross-check)' {
        $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @(@{ Version = $null; ExePath = $null }))
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'error'
        $i.Running | Should Be $true
    }

    It 'still gives no version when the caller silences errors' {
        $old = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            $i = Get-KakaoInstallInfo -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -RegistryThrows)
        }
        finally { $ErrorActionPreference = $old }
        $i.Version | Should BeNullOrEmpty
        $i.Source | Should Be 'error'
    }

    It 'reads this PC in the documented shape (no version number is hardcoded here)' {
        $i = Get-KakaoInstallInfo
        (($i.PSObject.Properties.Name | Sort-Object) -join ',') | Should Be 'ExePath,Installed,Running,Source,Version'
        (@('registry', 'registry+process', 'process', 'mismatch', 'none', 'error') -contains $i.Source) | Should Be $true
        ($i.Installed -is [bool]) | Should Be $true
        ($i.Running -is [bool]) | Should Be $true
        if ($i.Version) { $i.Version | Should Match '^\d+(\.\d+){1,3}$' }
        if (-not $i.Running) { $i.ExePath | Should BeNullOrEmpty }
    }
}

Describe 'Status: 검증된 버전인지 판정한다 (모르면 검증 안 됨)' {
    It 'is true for a version that is on the list' {
        Test-KakaoVersionVerified -Version '26.9.0.5337' -VerifiedList @('26.9.0.5337') | Should Be $true
    }

    It 'is true when the version is one of several on the list' {
        Test-KakaoVersionVerified -Version '26.9.1.5339' -VerifiedList @('26.9.0.5337', '26.9.1.5339') | Should Be $true
    }

    It 'is false for a version that is not on the list' {
        Test-KakaoVersionVerified -Version '26.9.1.5339' -VerifiedList @('26.9.0.5337') | Should Be $false
    }

    It 'is false for a null or empty version (not installed, or could not be read)' {
        Test-KakaoVersionVerified -Version $null -VerifiedList @('26.9.0.5337') | Should Be $false
        Test-KakaoVersionVerified -Version '' -VerifiedList @('26.9.0.5337') | Should Be $false
        Test-KakaoVersionVerified -Version '   ' -VerifiedList @('26.9.0.5337') | Should Be $false
    }

    It 'compares letter for letter: spaces, zero-width characters and look-alike digits do not match' {
        $zeroWidth = [string][char]0x200B
        $fullWidth = (([char[]]'26.9.0.5337' | ForEach-Object { if ($_ -match '\d') { [char](0xFF10 + [int][string]$_) } else { $_ } }) -join '')
        Test-KakaoVersionVerified -Version ' 26.9.0.5337' -VerifiedList @('26.9.0.5337') | Should Be $false
        Test-KakaoVersionVerified -Version '26.9.0.5337 ' -VerifiedList @('26.9.0.5337') | Should Be $false
        Test-KakaoVersionVerified -Version ('26.9.0.5337' + $zeroWidth) -VerifiedList @('26.9.0.5337') | Should Be $false
        Test-KakaoVersionVerified -Version $fullWidth -VerifiedList @('26.9.0.5337') | Should Be $false
    }

    It 'is false when the list is empty' {
        Test-KakaoVersionVerified -Version '26.9.0.5337' -VerifiedList @() | Should Be $false
    }

    It 'is false (not an error) when the verified list cannot be read' {
        function Get-VerifiedKakaoVersions { throw 'fake: list unreadable' }
        Test-KakaoVersionVerified -Version '26.9.0.5337' | Should Be $false
    }

    It 'uses the real verified list by default' {
        (Test-KakaoVersionVerified -Version '26.9.0.5337') | Should Be (@(Get-VerifiedKakaoVersions) -contains '26.9.0.5337')
        Test-KakaoVersionVerified -Version '0.0.0.0' | Should Be $false
    }
}

Describe 'Status: 검증 안 된 버전이면 보내기를 잠근다 (읽기 전용 모드, 종료 코드 4)' {
    It 'is full mode when the installed version is on the verified list' {
        $p = New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @(New-FakeProcess '26.9.0.5337')
        Get-KitMode -Provider $p -VerifiedList @('26.9.0.5337') | Should Be 'full'
    }

    It 'is readonly mode for a version that is not on the list (a newer version that was never tested)' {
        $p = New-FakeInstallProvider -Registry '26.9.2.5342' -Processes @(New-FakeProcess '26.9.2.5342')
        Get-KitMode -Provider $p -VerifiedList @('26.9.0.5337') | Should Be 'readonly'
    }

    It 'is readonly mode whenever the version cannot be trusted: not installed, read error, registry and process disagree, empty list' {
        $list = @('26.9.0.5337')
        Get-KitMode -Provider (New-FakeInstallProvider) -VerifiedList $list | Should Be 'readonly'
        Get-KitMode -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -RegistryThrows) -VerifiedList $list | Should Be 'readonly'
        Get-KitMode -Provider (New-FakeInstallProvider -Registry '26.9.0.5337' -Processes @(New-FakeProcess '26.9.2.5342')) -VerifiedList $list | Should Be 'readonly'
        Get-KitMode -Provider (New-FakeInstallProvider -Registry '26.9.0.5337') -VerifiedList @() | Should Be 'readonly'
    }

    It 'sending is allowed in full mode, for a person and for an AI caller (AI permission is a separate room switch)' {
        Test-SendAllowedByMode -Mode 'full' | Should Be $true
        Test-SendAllowedByMode -Mode 'full' -Caller 'ai' | Should Be $true
    }

    It 'sending is locked in readonly mode' {
        Test-SendAllowedByMode -Mode 'readonly' | Should Be $false
        Test-SendAllowedByMode -Mode 'readonly' -Caller 'ai' | Should Be $false
    }

    It 'only a person can lift the lock with the allow-unverified switch; an AI caller cannot' {
        Test-SendAllowedByMode -Mode 'readonly' -AllowUnverified | Should Be $true
        Test-SendAllowedByMode -Mode 'readonly' -AllowUnverified -Caller 'human' | Should Be $true
        Test-SendAllowedByMode -Mode 'readonly' -AllowUnverified -Caller 'ai' | Should Be $false
    }

    It 'locks (fail closed) for any mode value it does not know, even with the allow-unverified switch' {
        foreach ($bad in @($null, '', ' ', 'FULL', 'full ', ' full', 'Full', 'readOnly', 'write', 'true', '1')) {
            Test-SendAllowedByMode -Mode $bad | Should Be $false
            Test-SendAllowedByMode -Mode $bad -AllowUnverified | Should Be $false
        }
    }

    It 'Assert-SendAllowedByMode stops with exit code 4 and a Korean message when locked, and does nothing when allowed' {
        $e = Get-ThrownError { Assert-SendAllowedByMode -Mode 'readonly' }
        $e | Should Not BeNullOrEmpty
        $e.ExitCode | Should Be 4
        $e.Message | Should Match '보내기가 잠겨'
        $e.Message | Should Match '아무것도 보내지 않았습니다'
        (Get-ThrownError { Assert-SendAllowedByMode -Mode 'readonly' -AllowUnverified -Caller 'ai' }).ExitCode | Should Be 4
        (Get-ThrownError { Assert-SendAllowedByMode -Mode $null }).ExitCode | Should Be 4
        Get-ThrownError { Assert-SendAllowedByMode -Mode 'full' } | Should BeNullOrEmpty
        Get-ThrownError { Assert-SendAllowedByMode -Mode 'readonly' -AllowUnverified } | Should BeNullOrEmpty
    }
}

Describe 'Status: 읽기만 한다' {
    It 'Status.ps1 has no cmdlet that writes, creates or deletes anything' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'Status.ps1'))
        $write = 'Set-Content|Add-Content|Out-File|New-Item|Copy-Item|Move-Item|Remove-Item|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Start-Process|Stop-Process|Start-Service|Stop-Service'
        $text | Should Not Match $write
    }

    It 'Status.ps1 sends no keys or mouse input and uses no Win32 input calls' {
        $text = [System.IO.File]::ReadAllText((Join-Path $kitLibDir 'Status.ps1'))
        $text | Should Not Match 'SendCombo|ClickAt|KakaoWin32|SendInput|SendKeys|PostClose|Close-KakaoWindow'
    }
}

Describe 'Status: 실제 카카오톡을 조작하는 시험(E2E)은 스위치가 정확히 1 일 때만 켜진다' {
    It 'is on only for the exact text 1' {
        $old = $env:KAKAO_E2E
        try {
            $env:KAKAO_E2E = '1'
            Test-E2EEnabled | Should Be $true
            foreach ($off in @($null, '', '0', '01', ' 1', '1 ', 'true', 'TRUE', 'yes', 'on', ([string][char]0xFF11))) {
                $env:KAKAO_E2E = $off
                Test-E2EEnabled | Should Be $false
            }
        }
        finally { $env:KAKAO_E2E = $old }
    }
}
