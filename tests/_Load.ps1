# 시험 파일이 점(.)으로 불러오는 공통 로더. 부르기 전에 $libs(추가로 불러올 src\lib 파일 이름, 확장자 제외)를 정해 둔다.
$kitRoot = Split-Path -Parent $PSScriptRoot
$kitLibDir = Join-Path $kitRoot 'src\lib'
foreach ($libName in (@('Messages.ko', 'Paths', 'Errors') + @($libs))) {
    $libPath = Join-Path $kitLibDir ($libName + '.ps1')
    if (Test-Path -LiteralPath $libPath) { . $libPath }
}

# 임시 데이터 폴더(KAKAO_KIT_HOME)에서 본문을 실행하고 반드시 정리한다.
function Use-TempHome([scriptblock]$Body) {
    $old = $env:KAKAO_KIT_HOME
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('kakaokit-test-' + [guid]::NewGuid().ToString('N'))
    $env:KAKAO_KIT_HOME = $dir
    try { & $Body }
    finally {
        $env:KAKAO_KIT_HOME = $old
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
}

# 임시 데이터 폴더(KAKAO_KIT_HOME)에 "사용 동의함" 상태의 설정 파일을 만든다(새 프로세스로 명령을 돌리는 시험이 동의 게이트를 지나가게 할 때 쓴다).
function Set-TestConsent {
    $p = Get-KitPaths
    if (-not (Test-Path -LiteralPath $p.DataDir)) { New-Item -ItemType Directory -Path $p.DataDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($p.ConfigFile, '{"version":1,"consentAcceptedAt":"2026-11-20T09:00:00","lastRoom":null,"rooms":[]}', (New-Object System.Text.UTF8Encoding($false)))
}

# 본문이 던진 예외 객체를 돌려준다(던지지 않으면 $null).
function Get-ThrownError([scriptblock]$Body) {
    try { & $Body } catch { return $_.Exception }
    return $null
}

# 실제 카카오톡을 조작하는 시험(E2E)은 환경 변수 KAKAO_E2E 가 정확히 글자 1 일 때만 실행한다.
# 0·true·yes·공백이 붙은 1 등 다른 값은 모두 꺼짐이다. E2E 시험을 만들 때는 Describe 전체를 이 함수의 if 안에 둔다
# (Pester 의 -Skip 은 "건너뜀"으로 세어져 기준선 "건너뜀 0"이 깨진다).
function Test-E2EEnabled {
    return [string]::Equals($env:KAKAO_E2E, '1', [System.StringComparison]::Ordinal)
}
