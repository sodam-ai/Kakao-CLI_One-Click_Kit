# 카카오톡 키트 CLI 라우터. kakao.cmd / 시작.bat 이 호출한다.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

foreach ($name in 'Messages.ko.ps1', 'Paths.ps1') {
    . (Join-Path $PSScriptRoot ('lib\' + $name))
}

function Invoke-KakaoCommand {
    param([string[]]$Argv = @())

    if ($Argv.Count -eq 0) {
        Write-Host (Get-Msg -Key 'error.noCommand')
        return 1
    }
    switch ($Argv[0]) {
        'version' {
            Write-Host (Get-Msg -Key 'version.banner' -FormatArgs @(Get-KitVersion))
            return 0
        }
        default {
            Write-Host (Get-Msg -Key 'error.unknownCommand' -FormatArgs @($Argv[0]))
            return 1
        }
    }
}

# 다른 스크립트가 점(.)으로 불러올 때(시험)는 실행하지 않는다.
if ($MyInvocation.InvocationName -ne '.') {
    exit ([int](Invoke-KakaoCommand -Argv $args))
}
