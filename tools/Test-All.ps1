# 전체(또는 일부) 시험 실행기. 사용: powershell -File tools\Test-All.ps1 [-Name Bootstrap]
# E2E(실제 카카오톡 조작) 시험은 환경변수 KAKAO_E2E=1 일 때만 실행된다.
param([string]$Name = '*')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module Pester -RequiredVersion 3.4.0
$files = @(Get-ChildItem -Path (Join-Path $root 'tests') -Filter ($Name + '.Tests.ps1') -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) {
    Write-Host '시험 파일이 없습니다.'
    exit 1
}
$result = Invoke-Pester -Path @($files | ForEach-Object { $_.FullName }) -PassThru
Write-Host ('통과 {0} / 실패 {1} / 건너뜀 {2}' -f $result.PassedCount, $result.FailedCount, $result.SkippedCount)
if ($result.FailedCount -gt 0) { exit 1 }
exit 0
