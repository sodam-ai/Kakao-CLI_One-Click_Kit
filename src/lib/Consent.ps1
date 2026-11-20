# 사용 동의: 동의 게이트(어떤 명령이 동의를 먼저 요구하는가)와 kakao consent 명령.
# 설계서 13.6: 동의 전에는 카카오톡을 건드리거나 대화를 읽는 명령이 실행을 거부한다. 동의는 사람만, 키보드로 직접 한다.
# 이 파일은 카카오톡을 조작하지 않는다(키·클릭·창 닫기 없음). 설정 파일의 동의 날짜만 읽거나 쓴다.

# 동의를 먼저 요구하는 명령인가. 명령 이름은 대소문자 구분 없이 본다(라우터가 대소문자를 구분하지 않으므로 더 엄격한 쪽).
# 요구하지 않는 것: 인자 없음, version, help, status, consent(동의를 받는 명령 자신), rooms list, 알 수 없는 명령.
function Test-ConsentRequiredFor {
    param([string[]]$Argv = @())
    if ($Argv.Count -eq 0) { return $false }
    $cmd = [string]$Argv[0]
    if ($cmd -in 'open', 'send', 'read', 'search') { return $true }
    if ($cmd -eq 'rooms' -and $Argv.Count -ge 2 -and ([string]$Argv[1]) -in 'add', 'remove', 'set') { return $true }
    return $false
}

# 동의가 있으면 아무것도 내지 않고 끝난다. 없으면 한글 안내를 보이고 종료 코드(정수)를 돌려준다.
# 설정 파일이 깨졌거나 손으로 고친 값이면 동의로 치지 않는다(막는 쪽으로 닫힘).
function Invoke-ConsentGate {
    $ErrorActionPreference = 'Stop'
    try {
        Assert-KitReady
        return
    }
    catch [KakaoKitException] {
        Write-Host $_.Exception.Message
        Write-KitLog -Level 'warn' -Command 'consent' -Result ('stopped exit=' + $_.Exception.ExitCode)
        return [int]$_.Exception.ExitCode
    }
    catch {
        Write-Host (Get-Msg -Key 'error.unexpectedInfo')
        return 3
    }
}

function Get-ConsentDateText {
    $value = (Get-KitConfig).consentAcceptedAt
    if ($value -is [datetime]) { return $value.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) }
    return ([string]$value).Replace('T', ' ')
}

# kakao consent: 옵션 없이 쓰면 동의 상태만 보여 준다. --human 이면 사람이 안내를 읽고 정해진 문장을 직접 입력할 때만 동의를 기록한다.
# -Provider 는 시험이 입력 대신 답을 넣는 자리이고, 없으면 키보드에서 읽는다.
function Invoke-ConsentCommand {
    param(
        [string[]]$Argv = @(),
        [AllowNull()][hashtable]$Provider
    )
    $ErrorActionPreference = 'Stop'
    try {
        if ($Argv.Count -eq 0) {
            if (Test-KitConsent) { Write-Host (Get-Msg -Key 'consent.statusYes' -FormatArgs @(Get-ConsentDateText)) }
            else { Write-Host (Get-Msg -Key 'consent.statusNo') }
            return 0
        }
        if ($Argv.Count -ne 1 -or -not ([string]$Argv[0] -ceq '--human')) {
            Write-Host (Get-Msg -Key 'consent.argInvalid')
            return 1
        }
        Assert-HumanPath -Human
        if (Test-KitConsent) {
            Write-Host (Get-Msg -Key 'consent.alreadyYes' -FormatArgs @(Get-ConsentDateText))
            return 0
        }
        foreach ($key in 'consent.notice1', 'consent.notice2', 'consent.notice3', 'consent.notice4', 'consent.notice5') {
            Write-Host (Get-Msg -Key $key)
        }
        Write-Host (Get-Msg -Key 'consent.prompt')
        $answer = if ($null -ne $Provider -and $Provider.ContainsKey('ReadAnswer')) { & $Provider.ReadAnswer } else { Read-Host }
        if ($answer -is [string] -and $answer.Trim() -ceq '동의합니다') {
            Set-KitConsent -Human
            Write-Host (Get-Msg -Key 'consent.accepted')
            Write-KitLog -Level 'info' -Command 'consent' -Result 'accepted'
            return 0
        }
        Write-Host (Get-Msg -Key 'consent.declined')
        return 1
    }
    catch [KakaoKitException] {
        Write-Host $_.Exception.Message
        return [int]$_.Exception.ExitCode
    }
    catch {
        Write-Host (Get-Msg -Key 'error.unexpectedInfo')
        return 3
    }
}
