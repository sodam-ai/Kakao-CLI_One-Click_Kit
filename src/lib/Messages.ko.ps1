# 한글 문구 사전. 사용자에게 보이는 문장은 여기서만 만든다. (메뉴 항목은 "한글 (english)" 병기, 오류·안내는 한글만)
$script:KitMessages = @{
    'version.banner'       = '카카오톡 키트 {0}'
    'error.noCommand'      = '명령이 없습니다. 도움말은 "kakao help" 로 볼 수 있습니다.'
    'error.unknownCommand' = '알 수 없는 명령입니다: {0}  (도움말: kakao help)'
    'error.humanOnly'      = '이 작업은 사람이 직접 해야 합니다. 자동 실행으로는 할 수 없습니다.'
    'error.humanNeedsConsole' = '이 작업은 키보드로 직접 입력하는 창에서만 할 수 있습니다. 시작.bat 으로 여세요.'
    'error.consentRequired' = '먼저 사용 동의가 필요합니다. 시작.bat 을 열어 안내에 따라 동의해 주세요.'
    'error.roomNameInvalid' = '방 이름이 올바르지 않습니다. 비어 있거나, 앞뒤에 공백이 있거나, 줄바꿈이나 보이지 않는 글자가 들어 있거나, 100자를 넘으면 안 됩니다.'
    'error.configSaveFailed' = '설정 파일을 저장하지 못했습니다. 폴더 권한이나 디스크 공간을 확인해 주세요: {0}'
    'error.roomTypeInvalid' = '방 종류가 올바르지 않습니다: {0}  (open, self, normal 중 하나)'
    'error.roomExists'     = '이미 등록된 방입니다: {0}'
    'error.roomNotFound'   = '등록되지 않은 방입니다: {0}'
    'error.permissionInvalid' = '권한 이름이 올바르지 않습니다: {0}  (aiRead, aiSend, canSend 중 하나)'
    'warn.logFailed'       = '기록(로그)을 파일에 쓰지 못했습니다. 동작은 계속합니다.'
    'report.title'         = '카카오톡 키트 오류 보고서 (대화 내용은 들어 있지 않습니다)'
    'report.kit'           = '키트 버전: {0}'
    'report.kakao'         = '카카오톡 버전: {0}'
    'report.os'            = 'Windows: {0}'
    'report.ps'            = 'PowerShell: {0}'
    'report.elevated'      = '관리자 권한으로 실행 중: {0}'
    'report.recentLog'     = '--- 최근 기록 (최대 50줄) ---'
    'report.unknown'       = '알 수 없음'
    'report.yes'           = '예'
    'report.no'            = '아니오'
    'guard.keyNotAllowed'  = '허용되지 않은 키라서 보내지 않았습니다: {0}'
    'guard.noExpectedTitle' = '대상 창 제목이 정해지지 않아 입력하지 않았습니다.'
    'guard.processMismatch' = '대상 창이 카카오톡이 아닙니다. 입력하지 않았습니다.'
    'guard.titleMismatch'  = '대상 창의 제목이 예상과 다릅니다. 입력하지 않았습니다. (예상: {0})'
    'guard.notForeground'  = '대상 창이 맨 앞에 있지 않습니다. 입력하지 않았습니다.'
    'guard.clickRange'     = '클릭할 위치가 창 밖입니다. 입력하지 않았습니다.'
    'guard.clickCovered'   = '클릭할 자리가 다른 창에 가려져 있습니다. 입력하지 않았습니다.'
    'guard.userInterference' = '키보드나 마우스를 쓰신 것이 감지되어 작업을 중단했습니다. 작업 중에는 손대지 말아 주세요.'
    'guard.userBusy'       = '키보드나 마우스를 쓰는 중이라 시작하지 못했습니다. 잠시 손을 떼고 다시 해 주세요.'
    'guard.locked'         = '다른 키트 작업이 이미 실행 중입니다. 끝난 뒤 다시 해 주세요.'
    'guard.noBaseline'     = '작업을 시작하기 전 확인(키보드·마우스에서 손 떼기)이 먼저 필요합니다. 입력하지 않았습니다.'
    'guard.keysHeld'       = '다른 키가 눌려 있어 입력하지 않았습니다. 키보드에서 손을 떼 주세요.'
    'guard.keyNotAllowedNative' = '허용되지 않은 키 조합이라 보내지 않았습니다.'
    'guard.cursorMoved'    = '마우스 위치가 바뀌어 클릭하지 않았습니다.'
    'guard.sendFailed'     = '입력을 보내지 못했습니다.'
    'guard.closeNotKakao'  ='카카오톡 창이 아니라서 닫지 않았습니다.'
    'room.notAllowed'      = '허용 목록에 없는 방이라 열지 않았습니다: {0}'
    'room.mainNotFound'    = '카카오톡 메인 창을 하나만 찾지 못했습니다. 카카오톡이 실행 중인지, 로그인되어 있는지 확인해 주세요. 방을 열지 않았습니다.'
    'room.ambiguousWindows' = '같은 제목의 창이 둘 이상 있어 어느 창인지 알 수 없습니다. 아무것도 하지 않았습니다. (방: {0})'
    'room.ocrUnavailable'  = '화면 글자 읽기(OCR)를 쓸 수 없어 검색 결과가 정확히 1건인지 확인하지 못했습니다. 방을 열지 않았습니다.'
    'room.resultNotSingle' = '검색 결과가 정확히 1건인지 확인하지 못해 방을 열지 않았습니다. (방: {0}){1}'
    'room.hint.size'       = ' 카카오톡 창 크기가 기준과 다릅니다(지금 {0}x{1}, 모니터 배율 {2}%, 기준 {3}x{4}). 창 크기를 바꾸지 말고 원래 크기로 두거나, 창을 쓰던 모니터로 옮겨 주세요.'
    'room.hint.covered'    = ' 카카오톡 창의 검색 결과 부분이 다른 창에 가려져 있습니다. 가리는 창을 치워 주세요.'
    'room.openTimeout'     = '방 창이 시간 안에 열리지 않았습니다. 아무 창도 닫지 않았습니다. (방: {0})'
    'room.openedWrongTitle' = '열린 창의 제목이 방 이름과 달라 그 창을 닫고 멈췄습니다. 더 입력하지 않았습니다.'
    'room.unverifiedWarning' = '검색 결과를 확인하지 않고 방을 열었습니다(사람이 허용). 다른 방이 열렸을 수 있습니다.'
    'ocr.failed'           = '화면 글자를 읽지 못했습니다.'
    'clip.notSta'          = '이 실행 방식에서는 클립보드를 쓸 수 없습니다. 시작.bat 이나 kakao.cmd 로 실행해 주세요.'
    'clip.nonText'         = '클립보드에 이미지나 파일이 들어 있어 작업하지 않았습니다. 클립보드를 비우거나 글자를 복사한 뒤 다시 해 주세요.'
    'clip.busy'            = '클립보드를 다른 프로그램이 쓰고 있어 작업하지 못했습니다. 잠시 뒤 다시 해 주세요.'
    'clip.setFailed'       = '클립보드에 글을 넣지 못했습니다. 입력하지 않았습니다.'
    'clip.restoreFailed'   = '클립보드를 원래대로 되돌리지 못했습니다. 복사해 두었던 내용이 바뀌었을 수 있습니다.'
    'parse.fileNotFound'   = '내보내기 파일을 찾을 수 없습니다: {0}'
    'parse.notExport'      = '카카오톡 내보내기 파일이 아닙니다: {0}'
    'error.configCorrupt'  = '설정 파일을 읽을 수 없습니다. 파일이 손상되었을 수 있습니다: {0}'
}

function Get-Msg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs = @()
    )
    $ErrorActionPreference = 'Stop'
    if (-not $script:KitMessages.ContainsKey($Key)) { throw ('Unknown message key: ' + $Key) }
    $text = $script:KitMessages[$Key]
    if ($FormatArgs.Count -eq 0) { return $text }
    return [string]::Format($text, $FormatArgs)
}
