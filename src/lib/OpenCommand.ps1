# kakao open 명령 계층: 인자 해석, 호출자(사람/AI) 판정, 실행 잠금, 결과 표시.
# 허용 목록에 있는 방을 열어 창 제목이 방 이름과 정확히 같은지 확인하고, 키트가 연 창이면 닫는다(글을 쓰거나 보내지 않는다).
# 입력은 Room.ps1 의 Open-KakaoRoom 이 만든다(허용 키 안에서만). 여기서는 새 입력을 만들지 않는다.
# 규칙: 호출자는 --human 이 있고 키보드 입력이 막혀 있지 않을 때만 사람이다. 그 밖에는 모두 AI 로 본다(AI 는 방의 AI 읽기 허용이 켜져 있어야 한다).

# 인자를 해석한다. 모르는 옵션, 같은 옵션 두 번, 값 없음, 값이 --로 시작, 방 없음·빈 이름, 옵션 아닌 글자는 모두 사용법 오류(종료 코드 1).
function ConvertFrom-OpenArgv {
    param([string[]]$Argv = @())
    $ErrorActionPreference = 'Stop'
    $o = @{ Room = $null; Human = $false }
    $seen = @()
    $i = 0
    while ($i -lt $Argv.Count) {
        $a = [string]$Argv[$i]
        # 옵션 이름은 대소문자를 구분한다(-ccontains / -ceq)
        if ($seen -ccontains $a) { throw (New-KitError -Key 'open.argInvalid' -ExitCode 1) }
        if ($a -ceq '--human') {
            $seen += $a
            $o.Human = $true
            $i += 1
            continue
        }
        if ($a -ceq '--room') {
            if ($i + 1 -ge $Argv.Count) { throw (New-KitError -Key 'open.argInvalid' -ExitCode 1) }
            $v = [string]$Argv[$i + 1]
            if ($v.StartsWith('--', [System.StringComparison]::Ordinal)) { throw (New-KitError -Key 'open.argInvalid' -ExitCode 1) }
            $seen += $a
            $o.Room = $v
            $i += 2
            continue
        }
        throw (New-KitError -Key 'open.argInvalid' -ExitCode 1)
    }
    if ([string]::IsNullOrEmpty($o.Room)) { throw (New-KitError -Key 'open.argInvalid' -ExitCode 1) }
    return $o
}

function Write-OpenWarnings {
    foreach ($w in @(Get-KitWarnings)) { Write-Host $w }
    Clear-KitWarnings
}

# kakao open 을 실행하고 종료 코드를 돌려준다. -Provider 는 시험이 가짜 방 열기 제공자를 넣는 자리이고, 없으면 실제 제공자를 쓴다.
function Invoke-OpenCommand {
    param(
        [string[]]$Argv = @(),
        [AllowNull()][hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    Clear-KitWarnings
    $locked = $false
    try {
        $o = ConvertFrom-OpenArgv -Argv $Argv
        $caller = 'ai'
        if ($o.Human) {
            Assert-HumanPath -Human
            $caller = 'human'
        }
        # 작업 전체를 감싸는 실행 잠금: 한 번에 하나만. 못 잡으면 입력 0 으로 멈춘다.
        Enter-KitLock
        $locked = $true
        $params = @{ Name = $o.Room; Caller = $caller; Action = 'read' }
        if ($null -ne $Provider) { $params.Provider = $Provider }

        # 일반 방을 열면 상대에게 읽음 표시가 뜰 수 있다(설계서 7장 9번). 허용된 방일 때만 미리 알린다(허용되지 않으면 아래 열기가 거절한다).
        $room = Find-Room -Config (Get-KitConfig) -Name $o.Room
        if ($room -and ([string]$room.type -ceq 'normal') -and (Test-RoomAllowed -Name $o.Room -Action 'read' -Caller $caller)) {
            Write-Host (Get-Msg -Key 'open.readMarkWarning' -FormatArgs @($o.Room))
        }

        $opened = Open-KakaoRoom @params
        $closeParams = @{ Opened = $opened }
        if ($null -ne $Provider) { $closeParams.Provider = $Provider }
        Write-OpenWarnings
        if ($opened.OpenedByKit) {
            # 키트가 연 창만 닫는다(닫기 요청 하나). 원래 열려 있던 창은 건드리지 않는다.
            [void](Close-KitOpenedWindow @closeParams)
            Write-Host (Get-Msg -Key 'open.done' -FormatArgs @($opened.Title))
        }
        else {
            Write-Host (Get-Msg -Key 'open.alreadyOpen' -FormatArgs @($opened.Title))
        }
        return 0
    }
    catch [KakaoKitException] {
        Write-OpenWarnings
        Write-Host $_.Exception.Message
        return [int]$_.Exception.ExitCode
    }
    catch {
        # 알 수 없는 오류: 원문을 화면에 내지 않는다.
        Write-OpenWarnings
        Write-Host (Get-Msg -Key 'error.unexpected')
        return 3
    }
    finally {
        if ($locked) { Exit-KitLock }
    }
}
