# Kakao Kit (Windows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비개발자도 `시작.bat` 더블클릭으로 카카오톡 PC의 보내기·읽기·내보내기·검색을 쓰고, AI는 `kakao` CLI로 같은 기능을 쓰는 Windows 키트를 만든다.

**Architecture:** `시작.bat`(메뉴, `choice`) / `kakao.cmd`(CLI) → `src/kakao.ps1` 라우터 → `src/lib/*.ps1` 모듈(Win32 입력 계층 + 가드 + 방 열기 + 내보내기 + 파서 + 설정). 카카오톡 조작은 키 화이트리스트(Ctrl+S/V/A/C, Enter)와 3중 가드를 통과해야만 한다. 읽기는 공식 내보내기(Ctrl+S) 파일 파싱.

**Tech Stack:** Windows PowerShell 5.1(내장), `.bat`/`choice.exe`, Win32 P/Invoke(`Add-Type`), `Windows.Media.Ocr`(선택), Pester 3.4.0(내장, 시험).

**Spec:** `docs/superpowers/specs/2026-10-27-kakao-kit-design.md` (13.6의 기본값 포함). 번호(§)는 이 문서의 장 번호.

**Repo note:** 프로젝트 폴더는 git 저장소가 아니므로 commit 단계는 없다. 각 작업이 끝나면 `tasks/todo.md`에 체크하고 `tools/Test-All.ps1` 통과를 기록한다.

## Global Constraints

- Windows 11 + Windows PowerShell 5.1만. winget/pwsh 없음. 관리자 권한 요청 금지(`RunAs`·`-Verb`·`Program Files` 쓰기·서비스·작업 스케줄러 금지), 레지스트리는 `HKCU`만 (§6.2)
- 사용자 출력은 전부 한글. 메뉴 항목은 `한글 (english)` 병기, 오류·안내·도움말은 한글만 (§6.2)
- **인코딩**: 모든 `.ps1`는 UTF-8 **BOM 포함**(PS 5.1이 BOM 없는 UTF-8을 cp949로 읽음), 모든 `.bat`/`.cmd`는 UTF-8 **BOM 없음** + CRLF + 첫 줄 이후 `chcp 65001`. 시험이 강제한다 (§8)
- 허용 입력 키는 `Ctrl+S`, `Ctrl+V`, `Ctrl+A`, `Ctrl+C`, `Enter`뿐. **Esc 금지**, ≡ 메뉴 마우스 클릭 금지 (§7.3)
- 입력 직전 가드: 대상 창이 KakaoTalk 프로세스 소유 + 창 제목 == 방 이름(정확히) + 포그라운드. 하나라도 틀리면 입력 0 (§7.2)
- 방 이름은 허용 목록과 정확히 일치. 근사 일치 없음 (§7.1)
- 전송: 한 번에 한 방·한 메시지, 최소 간격 **2초**, 최대 **1000자**(스펙에 값 없음 → 내 판단), 기본은 미리보기+확인, 비대화형은 `--yes` 필요 (§7.4)
- 클립보드는 텍스트만 저장·복원, 비텍스트면 중단 (§7.5)
- 로그에 메시지 본문 금지 (§7.8)
- 검증된 카카오톡 버전: `26.9.0.5337`. 그 외는 **읽기 전용**(`--allow-unverified`로만 보내기) (§13.3)
- 내보내기 보관: 방마다 `latest.txt` + 스냅샷 3개, 30일 초과 스냅샷 삭제 (§13.4)
- 허용 목록 변경·동의는 사람만, 방마다 `aiRead`/`aiSend` 기본 꺼짐, 친구 방(`type=normal`)은 읽기만 (§13.6)
- E2E 시험은 `KAKAO_E2E=1`일 때만, 방은 **"비밀방", "나와의 채팅"만** (§11). **2026-10-30 부터 시험 방은 "비밀방" 대신 "테스트방"**(사용자 결정, 설계서 §4)
- 사용자 데이터 위치 `%LOCALAPPDATA%\KakaoKit` (시험은 `KAKAO_KIT_HOME`으로 대체) (§8)
- 종료 코드: 0 성공 · 1 사용법/권한 · 2 가드 중단 · 3 환경 문제(카카오톡 꺼짐 등) · 4 미검증 버전 잠금

## Review Focus

1. 메시지·방 이름에 `"` `%` `&` `^` `!` `|`, 이모지, 여러 줄이 `.bat`→PowerShell 인자 전달에서 변형되거나 **명령으로 실행됨**. 기대: 그대로 전송되거나 명확히 거절, 명령 실행은 절대 없음 → Task 8 (`--file`/stdin 경로 제공)
2. 카카오톡이 꺼져 있음·로그인 화면·화면 잠금. 기대: 입력 0, 한글 안내, 종료 코드 3 → Task 7·10
3. 저장 대화상자: 폴더 없음, 한글·공백 경로, 같은 이름 파일 존재("덮어쓰시겠습니까?" 추가 창). 기대: 항상 새 파일명 사용, 예상 밖 창이면 그 창만 닫고 중단 → Task 9
4. 작업 중 사용자가 마우스·키보드를 만지거나 다른 창이 포커스를 가져감. 기대: 즉시 중단, 클립보드 복원, 부분 입력 없음 → Task 4·5
5. 화면 배율 150%, 창 크기 변경, 다른 모니터 위치. 기대: 클릭 지점이 창 크기에 비례해 계산돼 맞거나, 못 찾으면 입력 0으로 중단 → Task 7

---

## 파일 구조

```
시작.bat                    메뉴 런처 (choice, 숫자 1회)
kakao.cmd                   CLI 진입점 → powershell -NoProfile -ExecutionPolicy Bypass -File src\kakao.ps1 %*
src/kakao.ps1               라우터: Invoke-KakaoCommand
src/lib/Messages.ko.ps1     한글 문구 사전 (Get-Msg)
src/lib/Paths.ps1  Log.ps1  Config.ps1  Win32.ps1  Guard.ps1  Clip.ps1
src/lib/Ocr.ps1  Room.ps1  Send.ps1  Export.ps1  Parse.ps1  Search.ps1
src/lib/Status.ps1  Install.ps1  Menu.ps1
config/verified-versions.json   {"verified":["26.9.0.5337"]}
tests/*.Tests.ps1  tests/fixtures/export-sample.txt (합성 데이터)
tools/Test-All.ps1  tools/Accept-E2E.ps1
docs/README.ko.md  docs/spike-notes.md
tasks/todo.md
```

## Task 1: 부트스트랩 — 한글·BOM·관리자 권한 없음

**Files:**
- Create: `시작.bat`(임시 골격), `kakao.cmd`, `src/kakao.ps1`, `src/lib/Messages.ko.ps1`, `src/lib/Paths.ps1`, `tools/Test-All.ps1`
- Test: `tests/Bootstrap.Tests.ps1`

**Interfaces:**
- Produces: `Get-Msg -Key <string> [-FormatArgs <object[]>] : string` · `Test-KitElevated : bool` · `Get-KitPaths : hashtable{DataDir,ConfigFile,ExportsDir,LogsDir,ManifestFile,LockName}` · `Invoke-KakaoCommand -Argv <string[]> : int`

- [ ] **Step 1: 시험 작성** `Bootstrap.Tests.ps1`: ① 저장소의 모든 `*.ps1`은 첫 3바이트가 `EF BB BF`, 모든 `*.bat/*.cmd`는 BOM 없음이고 줄 끝이 CRLF ② `src` 전체에 `RunAs`, `-Verb`, `Program Files`, `Register-ScheduledTask`, `New-Service` 문자열이 없음 ③ `Test-KitElevated` 가 `$false` ④ `cmd /c kakao.cmd version` 출력(UTF-8로 읽음)에 `카카오톡 키트`와 `1.0.0`이 있고 종료 코드 0 ⑤ 알 수 없는 명령은 종료 코드 1 + 한글 안내
- [ ] **Step 2: 실패 확인** `powershell -File tools/Test-All.ps1` → FAIL(파일 없음)
- [ ] **Step 3: 구현** 위 시그니처 그대로. `.bat`·`.cmd`는 BOM 없이 쓰고, `.ps1`는 BOM을 붙여 저장하는 `tools/Write-Bom.ps1` 헬퍼로 쓴다(Write 도구는 BOM을 못 붙임). `kakao.cmd`는 `chcp 65001 >nul` 후 `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\kakao.ps1" %*`
- [ ] **Step 4: 한글 깨짐 스파이크** 이 PC(화면 언어 en-US)에서 `시작.bat`을 더블클릭과 동일한 방식(`cmd /c start`)으로 열어 한글 출력이 정상인지 확인하고 결과를 `docs/spike-notes.md`에 기록
- [ ] **Step 5: 통과 확인** `tools/Test-All.ps1` → PASS

## Task 2: 설정·허용 목록·동의

**Files:**
- Create: `src/lib/Config.ps1`, `config/verified-versions.json`
- Test: `tests/Config.Tests.ps1`

**Interfaces:**
- Consumes: `Get-KitPaths`
- Produces: `Get-KitConfig : PSCustomObject{version, consentAcceptedAt, lastRoom, rooms[]}` (room = `{name,type('open'|'self'|'normal'),verified,canRead,canSend,selfOnly,aiRead,aiSend}`) · `Save-KitConfig -Config` · `Add-AllowedRoom -Name <string> -Type <string> -SelfOnly <bool> -Human` · `Remove-AllowedRoom -Name -Human` · `Set-RoomPermission -Name -Permission aiRead|aiSend|canSend -Value <bool> -Human` · `Test-RoomAllowed -Name <string> -Action read|send -Caller human|ai [-AllowUnverifiedRoom] : bool` · `Set-KitConsent -Human` · `Test-KitConsent : bool` · `Assert-KitReady` (동의 없으면 한글 메시지 + 종료 코드 1)

- [ ] **Step 1: 시험 작성**(임시 `KAKAO_KIT_HOME`): 정확히 일치만 허용(`"비밀방 "`, `"비밀"` 은 `$false`) · `-Human` 없이 `Add-AllowedRoom`/`Set-RoomPermission` 호출은 throw · `[Console]::IsInputRedirected` 가 참이면 사람 경로도 거부 · `type=normal` 방의 `send`는 `-AllowUnverifiedRoom` 없이 `$false` · `-Caller ai` 는 `aiRead`/`aiSend`가 켜진 방만 `$true`(기본 둘 다 꺼짐) · 동의 전 `Assert-KitReady` throw
- [ ] **Step 2: 실패 확인** → FAIL
- [ ] **Step 3: 구현** `rooms.json` 대신 `config.json` 한 파일(UTF-8, BOM 없음, `ConvertTo-Json -Depth 5`). 스키마 `version=1`
- [ ] **Step 4: 통과 확인**

## Task 3: 로그와 오류 보고서

**Files:**
- Create: `src/lib/Log.ps1`
- Test: `tests/Log.Tests.ps1`

**Interfaces:**
- Produces: `Write-KitLog -Level info|warn|error -Command <string> -Room <string> -Result <string>` (본문 매개변수 **없음**) · `New-KitErrorReport : string` (환경 정보 + 최근 로그 50줄, 클립보드 텍스트로 복사)

- [ ] **Step 1: 시험 작성**: 함수 매개변수 이름에 `Text|Body|Message`가 없음 · 한 줄 형식 `yyyy-MM-dd HH:mm:ss | level | command | room | result` · 1MB 초과 시 `.1`~`.3`으로 회전 · 보고서에 카카오톡 버전·키트 버전·OS가 있고 로그에 쓴 적 없는 문자열(예: 시험용 본문 `ZZZ-BODY`)은 없음
- [ ] **Step 2~4**: 실패 확인 → 구현 → 통과 확인

## Task 4: Win32 입력 계층과 가드

**Files:**
- Create: `src/lib/Win32.ps1`, `src/lib/Guard.ps1`
- Test: `tests/Guard.Tests.ps1`

**Interfaces:**
- Produces: `Get-KakaoWindows : object[]{Hwnd,Class,Title,ProcessName,Rect}` (EnumWindows 기반, UIA 아님 — 모달 저장 창 포함) · `Send-KeyCombo -Hwnd <long> -Keys 'Ctrl+S'|'Ctrl+V'|'Ctrl+A'|'Ctrl+C'|'Enter'` (**화이트리스트 밖이면 throw**, 보내기 전에 `Assert-InputTarget` 호출을 강제하는 `-Guard` 인자 포함) · `Invoke-RelClick -Hwnd <long> -RelX <double> -RelY <double> [-Double]` (0~1 비례 좌표, 클릭 지점의 최상위 창이 `Hwnd`인지 확인) · `Close-KakaoWindow -Hwnd <long>` (`WM_CLOSE`만) · `Assert-InputTarget -Hwnd <long> -ExpectedTitle <string> [-Provider <hashtable>]` (실패 시 `[KakaoGuardException]`, 한글 메시지, 종료 코드 2) · `Wait-UserIdle -Seconds <int>` · `Enter-KitLock` / `Exit-KitLock` (명명된 mutex, 두 번째는 종료 코드 2)

- [ ] **Step 1: 시험 작성**(가짜 Provider로): 제목 불일치·소유 프로세스가 KakaoTalk 아님·포그라운드 아님 → 각각 throw 이고 **입력 함수 호출 횟수 0**(스파이) · 모두 정상 → throw 없음 · `Send-KeyCombo -Keys 'Esc'`/`'Alt+F4'`/`'Delete'` → throw · `src` 전체에서 키 코드 `0x1B`·`VK_ESCAPE` 사용 없음(grep 시험) · `Enter-KitLock` 두 번째 호출 throw · `Wait-UserIdle` 가 최근 입력을 감지하면 throw
- [ ] **Step 2: 실패 확인** → FAIL
- [ ] **Step 3: 구현** P/Invoke는 `Add-Type`으로 한 클래스(`KakaoWin32`)에 모은다. 모든 좌표는 DPI 인식(`SetProcessDPIAware`) 후 물리 픽셀. 포커스는 입력 직전마다 `SetForegroundWindow` 재호출 + 재확인(터미널이 포커스를 가져간 사례, spec §9)
- [ ] **Step 4: 통과 확인**

## Task 5: 텍스트 클립보드 보존

**Files:** Create `src/lib/Clip.ps1` · Test `tests/Clip.Tests.ps1`

**Interfaces:** Produces `Use-TextClipboard -Text <string> -Action <scriptblock>` (현재 텍스트 저장 → 설정 → 실행 → `finally`로 복원, 클립보드에 이미지·파일 목록이 있으면 **변경 전에** `KakaoClipboardException`)

- [ ] **Step 1: 시험 작성**: 정상 복원 · 액션이 throw 해도 복원 · 이미지가 있으면 throw 이고 클립보드 그대로 · 빈 클립보드면 비움으로 복원
- [ ] **Step 2~4**: 실패 확인 → 구현(`System.Windows.Forms.Clipboard`, STA 확인) → 통과 확인

## Task 6: 내보내기 파서 (순수 함수)

**Files:** Create `src/lib/Parse.ps1`, `tests/fixtures/export-sample.txt`(합성, 실제 대화 아님) · Test `tests/Parse.Tests.ps1`

**Interfaces:** Produces `ConvertFrom-KakaoExport -Path <string> : PSCustomObject{Room, SavedAt:[datetime], Messages:[{Timestamp:[datetime],Sender,Text}]}`

- [ ] **Step 1: 시험 작성**(spec §9의 형식): 머리글 `<방> 님과 카카오톡 대화` / `저장한 날짜 : YYYY-MM-DD HH:MM:SS` · 날짜 구분선 `--------------- 2026년 10월 21일 수요일 ---------------` · 메시지 `[닉네임] [오전 2:59] 내용` · **본문이 `[`로 시작하는 메시지**(`[kakao-kit test] send check`)를 새 메시지로 오인하지 않음 · 여러 줄 메시지는 `` `n ``으로 이어붙음 · `오전 12:05`=00:05, `오후 12:05`=12:05 · CRLF·BOM 없음 · 닉네임에 `]` 포함 불가 가정 명시
- [ ] **Step 2~4**: 실패 확인 → 구현(헤더 정규식은 `^\[(?<n>[^\]]+)\] \[(?<ap>오전|오후) (?<h>\d{1,2}):(?<m>\d{2})\] ` 로 고정) → 통과 확인

## Task 7: 방 열기 (E2E 포함)

**Files:** Create `src/lib/Ocr.ps1`, `src/lib/Room.ps1` · Test `tests/Room.Tests.ps1`

**Interfaces:**
- Consumes: Task 2 `Test-RoomAllowed`, Task 4 가드·입력 계층, Task 5 `Use-TextClipboard`
- Produces: `Test-OcrAvailable : bool` · `Get-SearchResultNames -Hwnd <long> : string[]` (검색 결과 영역 OCR) · `Open-KakaoRoom -Name <string> -Caller human|ai : PSCustomObject{Hwnd,OpenedByKit}` (검색으로만 열기 → 제목 정확 일치 확인) · `Close-KitOpenedWindow -Opened <PSCustomObject>`

- [ ] **Step 1: 스파이크(먼저)**: 이 PC에서 ① 돋보기·검색 결과 행의 **비례 좌표 앵커**(창 크기 변경·배율에서도 맞는지), ② "나와의 채팅"이 검색·열기·제목 확인에서 비밀방과 같은지, ③ 같은 이름 방 둘 이상일 때 OCR이 무엇을 보이는지를 확인해 `docs/spike-notes.md`에 기록
- [ ] **Step 2: 시험 작성**: 허용 안 된 방 → throw 이고 Win32 호출 0 · OCR 없음(`Test-OcrAvailable` 가짜 `$false`)이면 열기 전 확인을 건너뛰고 제목 확인만, `status`용 경고 플래그 설정 · 열린 뒤 제목이 다르면 `Close-KakaoWindow` 후 throw(입력 0) · E2E(`KAKAO_E2E=1`): "비밀방"과 "나와의 채팅" 각각 열림 → `Hwnd`의 제목 == 방 이름, 두 번째 호출은 새 창 없이 재사용(`OpenedByKit=$false`), 직접 연 창만 닫힘
- [ ] **Step 3: 구현** 순서: `Wait-UserIdle` → 메인 창 포커스+가드(제목 `카카오톡`) → 돋보기 클릭(비례 좌표) → `Use-TextClipboard`로 방 이름 붙여넣기 → OCR 확인 → 첫 결과 더블클릭 → `Get-KakaoWindows` 로 최대 8초 폴링해 제목이 정확히 일치하는 창을 찾음(창 생성 1~3초 지연, spec §9) → 검색어 지우기·탭 복원
- [ ] **Step 4: 통과 확인**

## Task 8: 보내기 (E2E 포함)

**Files:** Create `src/lib/Send.ps1` · Test `tests/Send.Tests.ps1`

**Interfaces:**
- Consumes: Task 2, 4, 5, 7
- Produces: `Test-InputBoxEmpty -Hwnd <long> : bool` (입력란 Ctrl+A→Ctrl+C 센티널 방식, 불확실하면 `$false`) · `Send-KakaoMessage -Room <string> -Text <string> [-DryRun] [-Yes] [-Caller human|ai] [-AllowUnverified] : PSCustomObject{Status('confirmed'|'failed'|'unknown'),Sent,Reason}`(설계서 13.7); CLI는 `--file <경로>`와 `-`(표준 입력)로 본문을 받을 수 있음(특수문자 안전 경로)

- [ ] **Step 1: 시험 작성**: `-DryRun`은 입력 함수 호출 0 · 빈 문자열·1001자 거부 · 허용 목록에 없거나 `canSend=false` 거부 · `-Caller ai`는 `aiSend` 없으면 거부 · 비대화형(`IsInputRedirected`)에서 `selfOnly=false` 방은 `-Yes` 없으면 거부 · 마지막 전송 후 2초 이내 재전송 거부 · 카카오톡 버전 미검증이면 `-AllowUnverified` 없이 종료 코드 4 · 본문 `"a&b|c^d%e!"`·이모지·`` `n `` 포함 문자열이 `Use-TextClipboard`에 **변형 없이** 전달됨(스파이) · `--file`로 읽은 UTF-8 본문도 동일 · **(13.7)** 결과는 확인됨/실패/불명 셋 중 하나이고, 입력을 보낸 뒤 확인하지 못하면 '불명'이며 이때 전송 입력 호출은 1회로 끝난다(자동 재시도 0) · 같은 시도 번호를 다시 쓰면 입력 0으로 거부 · 입력란에 초안이 있으면 입력 0
- [ ] **Step 2: 실패 확인** → FAIL
- [ ] **Step 3: 구현** 순서: 검증 → 미리보기/확인 → `Open-KakaoRoom` → 가드 → `Test-InputBoxEmpty` 아니면 중단("작성 중인 글이 있어서 보내지 않았습니다") → 입력란 클릭 → `Use-TextClipboard { Send-KeyCombo Ctrl+V; Send-KeyCombo Enter }` → 전송 시각 기록. 입력란 초안 확인이 스파이크에서 불가로 판명되면 "이미 열려 있으면 중단"으로 후퇴하고 `docs/spike-notes.md`에 기록(§13.2)
- [ ] **Step 4: E2E**(`KAKAO_E2E=1`): "비밀방"과 "나와의 채팅"에 `[kakao-kit e2e <guid8>]` 한 줄 전송, 한글·여러 줄 각 1회. 읽기 확인은 Task 9에서
- [ ] **Step 5: 통과 확인**

## Task 9: 내보내기·읽기·검색

**Files:** Create `src/lib/Export.ps1`, `src/lib/Search.ps1` · Test `tests/Export.Tests.ps1`

**Interfaces:**
- Consumes: Task 4, 5, 6, 7
- Produces: `Export-KakaoRoom -Room <string> [-Caller] : string`(저장된 `snapshot-<yyyyMMdd-HHmmss>.txt` 경로, `latest.txt` 갱신) · `Update-ExportStore -Room <string> -SourcePath <string>` (보관 3개·30일 정리) · `Read-KakaoRoom -Room <string> [-Last <int>] [-Since <timespan>] [-Caller] : object[]` · `Search-KakaoExports -Keyword <string> [-Room <string>] : object[]` (`latest.txt`만 대상, 카카오톡 조작 없음)

- [ ] **Step 1: 시험 작성**(합성 폴더): 스냅샷 4개 → 최신 3개만 남음 · 31일 지난 스냅샷 삭제 · `latest.txt` 는 항상 가장 새 것 · 같은 메시지가 스냅샷마다 있어도 `Search-KakaoExports` 결과 중복 없음 · 허용·`aiRead` 규칙은 Task 2와 동일하게 적용 · E2E: Task 8에서 보낸 토큰이 `Read-KakaoRoom -Last 5` 결과에 있음
- [ ] **Step 2: 실패 확인** → FAIL
- [ ] **Step 3: 구현** `Export-KakaoRoom`: 방 열기 → 가드 → `Ctrl+S` → `Get-KakaoWindows` 에서 클래스 `#32770`·제목 `다른 이름으로 저장`·KakaoTalk 소유 창을 최대 8초 폴링 → 그 창에 포커스+가드 → `Ctrl+A` → `Use-TextClipboard`로 **항상 새 파일명**(타임스탬프)의 임시 경로 붙여넣기 → `Enter` → 파일이 생기고 크기 > 0 일 때까지 최대 10초 대기. 예상 밖 창이 뜨거나 시간 초과면 **그 창에만 `Close-KakaoWindow`** 하고 종료 코드 3. 임시 경로는 키트 데이터 폴더(한글·공백 없는 경로)
- [ ] **Step 4: 통과 확인**

## Task 10: 상태·버전·로그인 안내·미검증 모드

**Files:** Create `src/lib/Status.ps1` · Test `tests/Status.Tests.ps1`

**Interfaces:** Produces `Get-KakaoInstallInfo : {Installed,Version,Path,Running,MainHwnd,LoginState('loggedIn'|'loginScreen'|'notRunning'|'unknown')}` · `Get-KitStatus : {Kit:{Version},Kakao:{...},Mode('full'|'readonly'),Rooms:int,OcrAvailable:bool,Warnings:string[]}` · `Start-KakaoTalk -WaitSeconds <int>` · `Test-SendAllowedByMode -Mode <string> [-AllowUnverified] : bool`

- [ ] **Step 1: 시험 작성**: 레지스트리 `DisplayVersion` 이 목록에 없으면 `Mode=readonly` · 목록에 있으면 `full` · `notRunning`이면 입력 0, 종료 코드 3, 한글 안내 · `--json` 스키마 키 고정
- [ ] **Step 2: 스파이크**: `loggedIn`/`loginScreen` 구분 단서(메인 창 크기·자식 컨트롤)를 이 PC에서 확인하고 `docs/spike-notes.md`에 기록. 로그인 화면에서는 비밀번호를 **입력하지 않고** 사용자가 직접 로그인하도록 안내만 한다(§6.3)
- [ ] **Step 3~4**: 구현 → 통과 확인

## Task 11: CLI 라우터와 메뉴

**Files:** Create `src/lib/Menu.ps1`, 완성본 `시작.bat`, `src/kakao.ps1` 확장 · Test `tests/Cli.Tests.ps1`, `tests/Menu.Tests.ps1`

**Interfaces:**
- Consumes: Task 2~10
- Produces: `Invoke-KakaoCommand -Argv <string[]> : int` (명령: `status rooms open send export read search version help update uninstall menu`, 전역 `--json`) · `Show-MainMenu : string` · `Show-MoreMenu : string`

- [ ] **Step 1: 시험 작성**: 모르는 명령 → 종료 코드 1 + 한글 도움말 · `--json` 출력이 유효한 JSON(UTF-8) · `rooms add`는 입력이 리다이렉트되면 종료 코드 1이고 설정 파일 불변 · 메인 메뉴 문자열이 spec §6.2 초안과 같고 모든 항목 줄이 `한글 … (english)` 형태 · 보내기 흐름의 입력 요구 횟수 ≤ 4 · `시작.bat`이 `choice /c 12345670 /n`으로 숫자 1회 입력, "더 보기"는 `/c 123450`
- [ ] **Step 2~4**: 실패 확인 → 구현 → 통과 확인. 방 선택은 마지막에 쓴 방이 기본(엔터), `[A]`/`[B]` 자주 쓰는 방은 글자 1회

## Task 12: 첫 실행·업데이트·제거

**Files:** Create `src/lib/Install.ps1` · Test `tests/Install.Tests.ps1`

**Interfaces:** Produces `Initialize-Kit : void`(데이터 폴더·매니페스트 생성, 동의 화면, 멱등) · `Invoke-KitUpdate -From <string>` (설정·허용 목록·내보내기·로그 보존) · `Invoke-KitUninstall [-KeepExports <bool>]` (지울 목록 표시 → 확인 → **매니페스트에 적힌 것만** 삭제, 내보내기는 "함께 지울까요? (기본: 남김)")

- [ ] **Step 1: 시험 작성**(임시 홈): 두 번 `Initialize-Kit`해도 같은 결과 · 제거 후 매니페스트 항목은 없고 **무관한 파일은 남음** · 기본값에서 내보내기 폴더 유지 · 제거가 `C:\Program Files\Kakao`·`%LOCALAPPDATA%\Kakao`·`%USERPROFILE%\Documents\카카오톡 받은 파일`을 절대 건드리지 않음(경로 접두사 검사) · 업데이트 후 `config.json` 동일
- [ ] **Step 2~4**: 실패 확인 → 구현 → 통과 확인

## Task 13: 인수 시험과 사용 설명서

**Files:** Create `tools/Accept-E2E.ps1`, `docs/README.ko.md`, `docs/acceptance-<날짜>.md`

- [ ] **Step 1**: `Accept-E2E.ps1` 가 spec §11의 순서를 "비밀방"과 "나와의 채팅"에서 실행: 설치(첫 실행) → `status` → `rooms add` → `send --dry-run` → 실제 전송 → `read`로 확인 → `export` → `search` → 허용 안 된 방·제목 불일치·창 없음·포커스 이탈 시 **입력 0 중단** → 동시 실행 거부 → 제거 후 흔적 없음·카카오톡 정상·대화 그대로 → 재설치
- [ ] **Step 2**: 관리자 권한 창 0회(프로세스 시작마다 `Test-KitElevated -eq $false`, UAC 대화상자 없음 확인)
- [ ] **Step 3**: `README.ko.md` 는 비개발자용: 시작 방법, 메뉴 설명, 오류별 대처, 제거 방법, 위험·면책(참고용·법적 효력 없음·사용자 책임·약관 확인 권장). 결과 증거를 `acceptance-<날짜>.md` 에 기록
- [ ] **Step 4**: `tools/Test-All.ps1` 전체 통과 + 미해결 항목은 `docs/acceptance-<날짜>.md`에 "알려진 한계"로 정직하게 기록

---

## Self-Review

- **스펙 반영**: §6.1 명령 → Task 7~11 · §6.2 메뉴 4요구 → Task 1·11 · §6.3 매핑 → Task 10·12 · §7 안전 규칙 1~9 → Task 2·4·5·7·8·12 · §13.1~13.6 → Task 7·8·9·10·2 · §11 완료 기준 → Task 13. 누락 없음.
- **이름 일관성**: `Open-KakaoRoom` 반환 `{Hwnd,OpenedByKit}` 를 Task 8·9가 사용. `Send-KeyCombo`는 Task 4에서 정의, Task 7~9가 사용. `Test-RoomAllowed` 호출 시그니처 Task 2와 일치.
- **스파이크 위치**: 미검증 항목은 소유 작업에 배치(한글 깨짐=1, 좌표 앵커·나와의 채팅·동명 방=7, 초안 확인·한글·여러 줄 전송=8, 로그인 상태 구분=10).
