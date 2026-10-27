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

# 본문이 던진 예외 객체를 돌려준다(던지지 않으면 $null).
function Get-ThrownError([scriptblock]$Body) {
    try { & $Body } catch { return $_.Exception }
    return $null
}
