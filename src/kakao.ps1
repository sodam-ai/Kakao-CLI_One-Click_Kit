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
        'help' {
            # 문구만 보여 준다(카카오톡·설정 파일·기록을 건드리지 않는다). 뒤에 글자가 있으면 사용법 오류다.
            if ($Argv.Count -gt 1) {
                Write-Host (Get-Msg -Key 'help.extraArgs')
                return 1
            }
            foreach ($key in 'help.title', 'help.version', 'help.status', 'help.rooms', 'help.read', 'help.search', 'help.send', 'help.help', 'help.soon') {
                Write-Host (Get-Msg -Key $key)
            }
            return 0
        }
        'send' {
            # 보내기에 필요한 부품은 이 명령일 때만 불러온다(version 등 다른 명령은 카카오톡 관련 부품을 건드리지 않는다).
            foreach ($name in 'Errors', 'Win32', 'Guard', 'Config', 'Log', 'Clip', 'Status', 'Room', 'InputProbe', 'Foreground', 'Send', 'SendCommand') {
                . (Join-Path $PSScriptRoot ('lib\' + $name + '.ps1'))
            }
            return (Invoke-SendCommand -Argv @($Argv | Select-Object -Skip 1))
        }
        { $_ -cin 'rooms', 'read', 'search', 'status' } {
            # 읽기·관리 명령: 카카오톡을 조작하지 않는다(키·클릭 없음). 이 명령일 때만 필요한 부품을 불러온다.
            foreach ($name in 'Errors', 'Config', 'Log', 'Parse', 'Export', 'Search', 'Status', 'Send', 'InfoCommands') {
                . (Join-Path $PSScriptRoot ('lib\' + $name + '.ps1'))
            }
            $rest = @($Argv | Select-Object -Skip 1)
            switch -CaseSensitive ($Argv[0]) {
                'rooms' { return (Invoke-RoomsCommand -Argv $rest) }
                'read' { return (Invoke-ReadCommand -Argv $rest) }
                'search' { return (Invoke-SearchCommand -Argv $rest) }
                'status' { return (Invoke-StatusCommand -Argv $rest) }
            }
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
