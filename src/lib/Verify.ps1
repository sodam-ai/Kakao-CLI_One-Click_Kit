# 보낸 글 확인(VerifySent)의 "판정" 부분. 카카오톡 공식 내보내기에서 읽은 메시지 목록에서 방금 보낸 글을 찾는 순수 함수다.
# 카카오톡·클립보드·키·파일을 건드리지 않고 아무것도 기록하지 않는다(시험이 소스를 검사해 강제한다).
# 내보내기를 실제로 하는 부분(Ctrl+S, 저장 창)은 사람 확인 라운드(docs/human-rounds-verify.md)를 거친 뒤에 따로 만든다. 아직 Send 에 연결하지 않았다.
#
# 판정은 보수적이다: 확실히 찾았을 때만 'confirmed', 그 밖에는 모두 'unknown'(= 입력은 나갔지만 확인 못 함. 자동 재시도 없음).
#  - 내보낸 시각은 "분" 단위라서, 보낸 시각을 분으로 내림한 시각 이후의 메시지만 센다(예전에 같은 글이 있었다는 것은 증거가 아니다).
#  - 보낸 사람 구분이 없는 방(selfOnly 가 아님)에서는 남이 같은 글을 쓴 것과 구별할 수 없으므로 항상 'unknown' 이다.
#  - 글은 줄바꿈 방식(CRLF/LF)과 줄 끝 공백만 무시하고, 그 밖에는 글자 그대로(대소문자·기호·이모지) 같아야 한다.
#  - 한계: 같은 분 안에 같은 글이 이미 있었다면 거짓으로 확인될 수 있다. 그래서 일치 개수(Matches)를 함께 돌려준다(2 이상이면 중복 전송 의심).

function ConvertTo-ComparableMessageText {
    param($Text)
    if ($Text -isnot [string]) { return $null }
    $t = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($t -split "`n" | ForEach-Object { $_.TrimEnd() })
    return ($lines -join "`n").TrimEnd()
}

# 반환: State = 'confirmed' | 'unknown', Matches = 보낸 분 이후에 같은 글이 몇 개 있는가. 어떤 입력에서도 던지지 않는다.
function Find-SentMessageInExport {
    param($Messages, $Text, $Since, $SelfOnly)
    $unknown = [pscustomobject]@{ State = 'unknown'; Matches = 0 }
    try {
        if ($SelfOnly -isnot [bool] -or $SelfOnly -ne $true) { return $unknown }
        $want = ConvertTo-ComparableMessageText -Text $Text
        if ([string]::IsNullOrWhiteSpace($want)) { return $unknown }
        if ($Since -isnot [datetime]) { return $unknown }
        $floor = [datetime]::new($Since.Year, $Since.Month, $Since.Day, $Since.Hour, $Since.Minute, 0)
        $count = 0
        foreach ($m in @($Messages)) {
            if ($null -eq $m -or $m -is [string] -or $m -is [ValueType]) { continue }
            $stamp = $m.Timestamp
            if ($stamp -isnot [datetime] -or $stamp -lt $floor) { continue }
            $got = ConvertTo-ComparableMessageText -Text $m.Text
            if ($null -ne $got -and [string]::Equals($got, $want, [System.StringComparison]::Ordinal)) { $count++ }
        }
        if ($count -ge 1) { return [pscustomobject]@{ State = 'confirmed'; Matches = $count } }
        return $unknown
    }
    catch { return $unknown }
}

# 내보내기 제공자(-Export)에게 방과 보낸 분을 주고 메시지 목록을 받아 판정한다. 진짜 불리언 하나만 돌려준다.
# 일치가 정확히 1개일 때만 $true 다. 0개는 못 찾은 것이고, 2개 이상은 같은 분에 같은 글이 이미 있었거나 두 번 나갔을 수 있어
# "확인됨"으로 말하지 않는다(어느 쪽이든 자동 재시도는 없다). 제공자가 없거나 던지거나 아무것도 못 주면 $false(= 불명)이다.
function Confirm-SentMessage {
    param($Room, $Text, $Since, $SelfOnly, $Export)
    try {
        if ($Export -isnot [scriptblock]) { return $false }
        $messages = @(& $Export $Room $Since)
        $r = Find-SentMessageInExport -Messages $messages -Text $Text -Since $Since -SelfOnly $SelfOnly
        return ($r.State -ceq 'confirmed' -and $r.Matches -eq 1)
    }
    catch { return $false }
}