# 키트 버전, 관리자 권한 여부, 데이터 폴더 위치.

function Get-KitVersion { '1.0.0' }

function Test-KitElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 폴더는 만들지 않는다(순수 계산). 시험은 KAKAO_KIT_HOME 으로 다른 위치를 쓴다.
function Get-KitPaths {
    if ($env:KAKAO_KIT_HOME) { $data = $env:KAKAO_KIT_HOME }
    else { $data = Join-Path $env:LOCALAPPDATA 'KakaoKit' }
    return @{
        DataDir      = $data
        ConfigFile   = Join-Path $data 'config.json'
        ExportsDir   = Join-Path $data 'exports'
        LogsDir      = Join-Path $data 'logs'
        ManifestFile = Join-Path $data 'manifest.json'
        LockName     = 'Local\KakaoKit.InputLock'
    }
}
