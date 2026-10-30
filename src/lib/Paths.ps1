# 키트 버전, 관리자 권한 여부, 데이터 폴더 위치.

function Get-KitVersion { '1.0.0' }

function Test-KitElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 폴더는 만들지 않는다(순수 계산). 시험은 KAKAO_KIT_HOME 으로 다른 위치를 쓴다.
# 경로 이음에는 Join-Path 가 아니라 [System.IO.Path]::Combine 을 쓴다: Join-Path 는 드라이브가 실제로 있는지 확인해서
# 없는 드라이브(예: Z:\...)이면 영어 시스템 오류로 멈추지만, 이 함수는 존재 여부를 따지지 않는 계산이어야 한다.
function Get-KitPaths {
    if ($env:KAKAO_KIT_HOME) { $data = $env:KAKAO_KIT_HOME }
    else { $data = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'KakaoKit') }
    return @{
        DataDir      = $data
        ConfigFile   = [System.IO.Path]::Combine($data, 'config.json')
        ExportsDir   = [System.IO.Path]::Combine($data, 'exports')
        LogsDir      = [System.IO.Path]::Combine($data, 'logs')
        ManifestFile = [System.IO.Path]::Combine($data, 'manifest.json')
        LockName     = 'Local\KakaoKit.InputLock'
    }
}
