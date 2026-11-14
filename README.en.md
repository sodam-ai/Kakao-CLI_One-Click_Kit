<a id="top"></a>
# KakaoTalk Kit (Kakao-CLI One-Click Kit)

[한국어](README.md) · [English](README.en.md)

> **Current status: under development (6 of 13 steps done, step 7 in progress).**
>
> The only command you can really use right now is **`kakao version`** (`status`, `rooms`, `read`, `search` and `send` have only their command lines connected; their state is in the table below. In particular `read` and `search` need kept export files, but `export`, which makes them, does not exist yet, so they have nothing to use, and `send` is locked). Saving a chat and the numbered menu **cannot be used as commands yet.** The part that opens a chat room (step 7) is built and tested (with fake data only) but is not connected to a command yet. The part that saves a chat from the KakaoTalk screen (`Ctrl+S`) is not built yet. This document keeps "works now (✅)" and "planned (⏳)" apart from the first line to the last.
>
> This is an **unofficial tool**. It has no relationship with the company that makes KakaoTalk (Kakao Corp.). You are responsible for how you use it. Please read [Chapter 17, Legal, copyright and license](#legal) before using it.

Document date: 2026-11-02 · Basis: steps 1-6 done + step 7 chat-room opening and on-screen text reading parts + the parts of step 9 that do not touch KakaoTalk (keeping, reading, searching) + mid-way verification · 290 automated tests · License: Apache License 2.0 · Written so that people who are new to computers can follow it.

- ✅ = works right now. ⏳ = does not work yet (planned).
- In this document `kakao` is shorthand. You actually type `.\kakao.cmd`. The reason is in [Chapter 6](#run).
- Unfamiliar words are explained in [Chapter 19, Glossary](#glossary).

**At a glance**

| What you may wonder | Answer |
|---|---|
| Commands you can use now | Only `kakao version`. (`kakao status`, `rooms`, `read` and `search` have only a command line connected that does not operate KakaoTalk, and `read` and `search` have data only after `export` is built. `kakao send` has sending locked and sends nothing.) |
| Sending messages, reading chats | Not yet. Reading is built first, sending after it (Chapter 2). |
| Setup and preparation | Copy the folder and you are done. No installer, no sign-up, no administrator rights and no internet are needed (Chapters 3-4). |
| Who uses it | As the owner decided, it is used **for personal use only**. It is tested only with your own account, on your own computer, in a room where you are alone, and it is not published, distributed or sold (Chapter 17). |
| The biggest risk | Kakao's operating policy may forbid automating the screen, so the chance that your account use is restricted cannot be ruled out (Chapter 17). |
| License | Apache License 2.0 (copyright holder SoDam AI Studio). The repository is private. |

<a id="toc"></a>
## Table of contents

- [1. What is this project?](#about)
- [2. Current status: what works and what does not yet](#status)
- [3. Prerequisites and required programs](#prereq)
- [4. Download and installation](#download)
- [5. Quick start (5 minutes)](#quickstart)
- [6. How to run](#run)
- [7. How to use](#usage)
- [8. Command reference](#commands)
- [9. How it works (principles)](#how)
- [10. Workflows](#workflow)
- [11. Architecture](#architecture)
- [12. Security and data flow](#security)
- [13. Where files and documents are](#files)
- [14. Update summary (click to expand)](#changelog)
- [15. Troubleshooting](#troubleshooting)
- [16. Frequently asked questions (FAQ)](#faq)
- [17. Legal, copyright, license and commercial use](#legal)
- [18. For developers: tests and building this document](#dev)
- [19. Glossary](#glossary)

<a id="about"></a>
## 1. What is this project?

**In one line:** a set of tools that lets you operate the Windows KakaoTalk PC app with a single command line, or by double-clicking `시작.bat`.

### Why is it needed?

KakaoTalk has no official command feature (API) that programs can use. So this kit works **only by pressing, on your behalf,** the keys a person would press on the keyboard (paste `Ctrl+V`, send `Enter`, save a chat `Ctrl+S`). It is being built with two kinds of users in mind.

1. People who do not code: a Korean menu screen where you press numbers (⏳ planned)
2. AI assistants (for example Claude Code): a command line in the form `kakao <command> --json` (⏳ planned)

### What it aims to do (goals)

- Send messages only to rooms that I have allowed
- Read chats: uses KakaoTalk's official "Export chat" feature
- Search keywords in chats that were saved earlier
- Check the environment, install, update and uninstall
- When something goes wrong, leave an explanation in Korean that non-developers can understand, plus a record (log)
- Uninstalling never touches the KakaoTalk app or your chat data

### What it does not do (non-goals)

- Decrypting KakaoTalk's chat storage (DB) or analysing or modifying the app: this may conflict with the terms of service, so it is decided that this kit will not use that approach.
- Real-time monitoring, auto-reply bots, sending to many rooms at once
- Reading or sending non-text messages such as photos and files
- Messengers other than KakaoTalk, macOS (Mac), smartphones

### What was used as a reference

There is an open-source tool for macOS only (named kakaocli), but it works only on a Mac and could not be used on Windows. So the same goal was **built from scratch for Windows, and no code from that tool was used.**

### The 4 promises set by the user

| Promise | Status now |
|---|---|
| The administrator permission (UAC) window never appears | ✅ There is no code that asks for administrator rights. There is also no registry, service or scheduled-task registration, and no writing to Program Files (automated tests check this). |
| English menus are written in Korean or in Korean plus English | ✅ Every message is built from one Korean message dictionary. Windows' English `pause` text was also replaced with Korean. The menu screen itself is ⏳ planned. |
| Keep the number of steps to enter a menu to a minimum | ⏳ Designed: one number press runs it, and sending takes 4 inputs or fewer. The menu does not exist yet. |
| The menu is simple but detailed | ⏳ Designed. The menu does not exist yet. |

<a id="status"></a>
## 2. Current status: what works and what does not yet

Development is split into 13 steps; steps 1-6 are finished, the parts of step 7 are built, and so are the parts of step 9 that do not touch KakaoTalk (keeping, reading, searching). In the table, "parts done" means **the parts (functions) for that feature are built and pass the automated tests, but they are not yet connected to a command that a user can call.**

| Step | Content | Status |
|---|---|---|
| 1 | Starting frame: no Korean text corruption, no administrator rights, `시작.bat` temporary screen, `kakao version` | ✅ Done |
| 2 | Settings, allowed room list, consent to use | ✅ Parts done |
| 3 | Records (log) and error report | ✅ Parts done |
| 4 | Key input layer and safety device (the "gatekeeper") | ✅ Parts done (testing real input into KakaoTalk is ⏳) |
| 5 | Saving and restoring the clipboard | ✅ Parts done |
| 6 | Reading export files (parser) | ✅ Parts done |
| 7 | Opening a room | ⏳ Parts done; the connection to a command is not done yet. Checked in real KakaoTalk: judging with on-screen text reading whether the search result is exactly one room name (checked on a real screen and then fixed), and opening and closing a room (on a 100% monitor: double-click the first result → check the new window's title → close only the window the kit opened; passed once). S5 passed once on 2026-11-12 (KakaoTalk 26.9.2.5342, window 588x753 at scale 1.5 on the 150% monitor, open-chat screen, a test room where I am alone): `Ctrl+F` → paste the room name → check for exactly 1 result → double-click the first row → check the new window title → close only the window the kit opened, finished in 8.6 seconds, and the window list after closing matched the start. It was one run only; other tabs, the 100% monitor and ordinary rooms (1:1 and group chats) were not tested. The defect where the window's scaling was misread as 100% on a 150% monitor is fixed, and reading the scaling as 1.5 was confirmed by a read-only check. Opening a room on the 150% monitor passed once in the S5 run on 2026-11-12 (item 10 of 12.3) |
| 8 | Sending a message | ⏳ Planned (built after step 9; a separate approval from the user is taken before starting) |
| 9 | Export, read, search | ⏳ Some parts done (built before step 8). The parts for keeping export files (the 3 newest per room, 30 days), reading and searching passed their tests with fake files. Saving with `Ctrl+S` in KakaoTalk and the connection to a command are not done yet |
| 10 | Status check, KakaoTalk version check, login guidance, lock for unverified versions | ⏳ Planned |
| 11 | Finished command router, numbered menu, `help` | ⏳ Planned |
| 12 | First-run consent, update, uninstall | ⏳ Planned |
| 13 | End-to-end acceptance test, final user guide | ⏳ Planned |

**Change of work order (approved by the user on 2026-10-30):** The plan had reading (step 9) after sending (step 8), but **reading is built first and sending afterwards.** There are three reasons. ① Without reading, you cannot confirm that a sent message really went through, so only "unknown" would ever come out of the three results (confirmed, failed, unknown) that design document 13.7 defines. ② The reading parser is already built and can be tested with synthetic fake chat files. ③ The only key sent to real KakaoTalk so far is `Ctrl+V`, so if the first `Enter` is pressed in a file-save window instead of in a message that goes to someone else, a mistake does less harm.

### Verification environment (the conditions that were actually checked)

| Item | Value |
|---|---|
| Operating system | Windows 11 Home, build 10.0.26300 |
| PowerShell | Windows PowerShell 5.1 (5.1.26100.9711) |
| KakaoTalk PC | 26.9.0.5337 (the only version confirmed in the research before development). KakaoTalk on this PC later updated itself to **26.9.1.5339**, where only clicking, pasting, opening a room and closing its window have been tested, and sending has not (it is not on the tested-version list) |
| Display language | English (en-US). Even so, every message of the kit is in Korean. |
| Monitors | 4 (including negative coordinates on a secondary monitor). Three are at 100% display scaling and the one below is at 150%. The same KakaoTalk window looks like 392x502 at 100% and 588x753 at 150%. The room-opening test was done only on the 100% main monitor. On the 150% monitor, a read-only check on 2026-11-02 found the window's scaling misread as 100%; after the fix to read the monitor's scaling, a read-only check on 2026-11-11 read it as 1.5 and the size matched the reference (588x753) (item 10 of 12.3) |
| Rights | No administrator rights (normal user) |
| Default terminal | Windows Terminal |

### What has not been verified yet (an honest list)

- Testing, with the kit's own code, that keys really reach KakaoTalk: this is done in step 7. So far the only input the kit's code has sent is **a click, a paste (Ctrl+V), a double-click (opening a room) and a window-close request in the step 7 preliminary research and the room-opening test** (no message was sent. In the tests that passed, the safety guard did not stop; when a person touched the machine or the window size or monitor scaling differed from the reference, it really did stop before any input. See chapter 14). Other keys such as Enter and Ctrl+S, and sending messages and exporting, have never been tested with the kit's code. (In the research stage before development, sending, opening a room and exporting were confirmed with temporary experiments.)
- Select all in the search box (`Ctrl+A`) is **not used**: a tooltip on screen showed that in the KakaoTalk main window `Ctrl+A` opens the "add friend" window (2026-11-12). The whole room-opening flow starting with `Ctrl+F` passed once on 2026-11-12 (150% monitor, see above). Other tabs, the 100% monitor and ordinary rooms are not done yet.
- With a display scaling of 125% or 200%: checked only with fake test data (the monitors of this PC are only at 100% and 150%). Opening a room on the 150% monitor passed once in the S5 run of 2026-11-12 (item 10 of 12.3).
- Actually sending Korean text, multi-line text, long messages and emoji
- Searching, opening and exporting in ordinary rooms (1:1 and group chats) (the test room is an open chat room, so its window title and search results may differ from ordinary rooms)
- Behaviour when KakaoTalk is closed or shows the login screen
- How to tell rooms apart when several rooms have the same name
- False alarms of human-hand detection (did the person touch the keyboard or mouse; stopping although nobody touched anything) and whether the pressed-key check is too strict: the Hangul/English key is read as held down on this PC even with hands off, so it was left out of the pressed-key check (every other key is still checked). Whether that key is the only one with this problem on other keyboards and input methods has not been checked
- How system messages ("○○ joined") appear in the export file: for now they may be read as continuation lines of the previous message.
- The parts for keeping, reading and searching exports were tested only with synthetic fake chat files. They have never kept a real KakaoTalk export, and it is not known whether the first line of the file for 1:1 chats and "chat with myself" equals the room name (if it differs, the kit stops without keeping anything, for safety).
- Static analysis tool (PSScriptAnalyzer): it is not installed, so it could not be run.
- Reaction of antivirus software and SmartScreen
- The automation-related clauses of Kakao's operating policy (the original text could not be checked, and a reply in the Kakao Developers forum said that automatic screen operation is prohibited: see 17.2)

<a id="prereq"></a>
## 3. Prerequisites and required programs

### Prerequisites (checklist)

- A Windows 11 computer
- One kit folder: already extracted if it came as a compressed file (.zip)
- (To use sending and reading in the future) the KakaoTalk PC app installed and logged in
- (When testing) a room where only I am present, for example "Chat with myself". Testing is only ever done in a room where you are alone.
- (Optional) A web browser: needed to view `README.html`. `README.md` can also be read in Notepad.

### Required programs (nothing extra to install)

| Program | Needed? | Description |
|---|---|---|
| Windows 11 | Needed | Verified on this PC (10.0.26300). Other versions such as Windows 10 were not checked. |
| Windows PowerShell 5.1 | Needed, no installation | Built into Windows. To check: open PowerShell from the Start menu and type `$PSVersionTable.PSVersion`; you will see 5.1.x. |
| PowerShell 7 (`pwsh`) | Not needed | Not used even if present. The kit uses only the built-in `powershell.exe`. |
| KakaoTalk PC | Not needed for now | `version` works without KakaoTalk. Later, sending and similar features will be allowed only on 26.9.0.5337, and other versions are planned to be read-only (⏳). |
| Windows Korean on-screen text reading (OCR) | Needed for opening a room (⏳ after it is connected to a command), not needed for now | The Korean engine of the on-screen text reading feature built into Windows. It is used to check that the search result is exactly one room name, and without it the kit does not open the room. This PC has it (`ko` is among the installed text-reading languages). How to install it on a PC that lacks it has not been checked (adding Korean in the Windows language settings is the usual way, but it was not tried on this PC). |
| Access to the GitHub repository (web browser or `gh`) | Only when downloading | Needed to download from the private repository (Chapter 4). Not needed if you received the folder by USB or as a compressed file. |
| Administrator rights | Not needed | The UAC (administrator permission) window does not appear. |
| Internet | Not needed | The kit's code has no part that connects to the internet (checked by code search). The KakaoTalk app itself does use the internet. |
| Pester 3.4.0 | Developers only | The automated test tool. The copy built into Windows is used; it is not included in or redistributed with the kit. |
| Disk space | Under 1 MB | The kit's files are all text files (not counting folders made by other development tools) and together are less than 1 MB. |

<a id="download"></a>
## 4. Download and installation

### How to download

**The source is in a private GitHub repository named `Kakao-CLI_One-Click_Kit`.** It is not a public repository yet, so only people who have access can get it, and there is no public address that anyone can download from. If you have access, get it in one of two ways.

- Way A: on the GitHub repository page click the green `Code` button and then `Download ZIP` to get a compressed file (English interface).
- Way B: if the GitHub CLI (`gh`) is installed, run `gh repo clone <owner>/Kakao-CLI_One-Click_Kit`. `<owner>` is the name of the GitHub account that created the repository.

If you received the folder directly by USB or as a compressed file, install it with the steps right below.

### How to install (copy the folder)

1. If it is a compressed file (.zip), **extract it completely first.** Right-click the file and choose "Extract All". If you run it from inside the compressed file, only some files are unpacked temporarily and it fails.
2. Put the extracted folder wherever you like. Example: `D:\KakaoKit`. A short name with only English letters and digits is recommended. Do not name a folder in the `%NAME%` form such as `%PATH%` (a known limitation in Chapter 15).
3. When you can see `시작.bat`, `kakao.cmd` and the `src` folder inside the folder, you are ready.
4. There is no installer, no sign-up and no login.

### How to update

There is no update command for now (`update` is ⏳ planned). If you receive a new folder, just use it in place of the old folder. If you got the repository with `gh repo clone`, you can also bring it up to date by running `git pull` inside that folder. After the feature that saves settings and records is connected, those will live separately in `%LOCALAPPDATA%\KakaoKit` in your user folder, so they are kept even if you replace the program folder (⏳).

### How to uninstall

**Just delete the folder.** The current version creates nothing outside its folder. It does not touch the registry, desktop shortcuts, the Start menu, PATH or Task Scheduler (checked by code search, and it was also confirmed that this PC has no `%LOCALAPPDATA%\KakaoKit` folder). Once the feature that saves settings is connected, that folder may appear, and the `uninstall` command will guide you (⏳). In every case the KakaoTalk app and your chats are left untouched.

<a id="quickstart"></a>
## 5. Quick start (5 minutes)

This is everything you can do right now. It checks that the kit is in place.

1. Open the kit folder in File Explorer.
2. Double-click `시작.bat`.
3. If the black window shows text like the following, it is **working**. (The blank lines before and after are omitted. The kit always prints in Korean.)

```text
  카카오톡 키트 (Kakao Kit)
  준비 중입니다. (임시 화면)

카카오톡 키트 1.0.0

  아무 키나 누르면 닫힙니다.
```

4. Press any key and the window closes. (The last line means "Press any key to close.")

The `1.0.0` on screen is just a number inside the code; it does not mean development is finished. If it does not look like the above, see [Chapter 15](#troubleshooting).

To do the same check with a command: click the address bar at the top of File Explorer, type `cmd` and press Enter; a black window opens in that folder. Type `.\kakao.cmd version` there and press Enter, and `카카오톡 키트 1.0.0` (KakaoTalk Kit 1.0.0) appears.

<a id="run"></a>
## 6. How to run

### Method 1. Double-click (the easiest)

Double-click `시작.bat`. A temporary screen appears for now. The numbered menu is ⏳ planned.

### Method 2. Command Prompt (cmd)

1. Open the kit folder in File Explorer.
2. Click the address bar at the top, type `cmd` and press Enter.
3. In the black window type `.\kakao.cmd version` and press Enter.

### Method 3. PowerShell or Windows Terminal

In the same folder type `.\kakao.cmd version`. In PowerShell the leading `.\` is required.

### Why `.\kakao.cmd` and not `kakao`?

Windows has a security setting (the environment variable `NoDefaultCurrentDirectoryInExePath`) that stops it from finding programs in the current folder by name alone. On this PC its value is 1, so typing only `kakao version` gave a "not recognized" error. PowerShell always requires `.\` regardless of the setting. So it is safe to use **`.\kakao.cmd`, which works in every environment.**

### Running from another folder

Using the full path works from any folder. Example: `D:\KakaoKit\kakao.cmd version`. If the path contains spaces, wrap it in quotation marks.

### Environment variables (settings)

An environment variable is a named setting stored in Windows. **The only one the kit reads itself is `KAKAO_KIT_HOME`**, and all of them are optional. There is no feature that takes secret values such as passwords or tokens from environment variables or files.

| Name | Who sets it | Meaning | Default |
|---|---|---|---|
| `KAKAO_KIT_HOME` | User (optional) | Moves the kit's data folder (settings, records, exports) to this folder. Originally meant for automated tests. | None → `%LOCALAPPDATA%\KakaoKit` |
| `KAKAO_E2E` | Developer (optional) | A name reserved for running tests that operate the real KakaoTalk when set to `1`. The test helper `Test-E2EEnabled` (`tests\_Load.ps1`) reads this variable and turns on only when the text is exactly `1`. No test uses that helper yet; it is planned to be used from step 7 (⏳). | None → not run |
| `NoDefaultCurrentDirectoryInExePath` | Windows security setting | When `1`, programs in the current folder are not found by name alone. The kit does not change it and you do not need to. | Differs per PC (1 on this PC) |
| `LOCALAPPDATA` | Windows | The base location of the user data folder. | Decided by Windows |

To change `KAKAO_KIT_HOME`, type `set KAKAO_KIT_HOME=D:\KitData` in cmd or `$env:KAKAO_KIT_HOME = 'D:\KitData'` in PowerShell, then run the kit in the same window. It applies only to that window and disappears when you close it.

### What happens inside when you run it

1. `kakao.cmd` switches that window's character table to UTF-8 (65001). This is so Korean text does not get corrupted, and it applies only to that window.
2. It runs `powershell -NoProfile -ExecutionPolicy Bypass -File src\kakao.ps1 <what you typed>`. `-NoProfile` means personal settings files are not read, and `-ExecutionPolicy Bypass` means scripts are allowed **for this run only.** The computer's security settings are not changed.
3. The router (`src\kakao.ps1`) looks at the first word, runs the command, prints Korean messages and returns an exit code.

### Exit codes (result numbers)

| Number | Meaning | Does it appear now? |
|---|---|---|
| 0 | Success | ✅ |
| 1 | Usage error or no permission (no command, unknown command, an action only a person may do, etc.) | ✅ |
| 2 | The safety device stopped the action (wrong window, a person touched the keyboard or mouse, etc.) | ⏳ once the feature is connected |
| 3 | Environment problem (KakaoTalk is closed, clipboard unavailable, damaged settings file, etc.) | ⏳ once the feature is connected |
| 4 | Sending is locked because the KakaoTalk version is not verified | ⏳ once the feature is connected |

How to check: in cmd type `echo %errorlevel%`, in PowerShell type `$LASTEXITCODE`.

<a id="usage"></a>
## 7. How to use

### What you can do now

- Check the version: typing `.\kakao.cmd version` prints `카카오톡 키트 1.0.0` (exit code 0).
- See the temporary guide screen: double-click `시작.bat`.
- Typing only `.\kakao.cmd` with no command prints `명령이 없습니다. 지금 쓸 수 있는 명령: version (버전 보기), status (점검), rooms (허용 방 관리), read (대화 읽기), search (대화 찾기), send (보내기, 지금은 잠겨 있음)` ("There is no command. Commands you can use now: version (show the version), status (check), rooms (manage allowed rooms), read (read a chat), search (search a chat), send (send; locked for now).") (exit code 1).
- Typing an unknown command prints `알 수 없는 명령입니다: <what you typed>  (지금 쓸 수 있는 명령: version, status, rooms, read, search, send)` ("Unknown command: ... (commands you can use now: version, status, rooms, read, search, send)") (exit code 1).
- `.\kakao.cmd status` only reads and shows the kit version, the KakaoTalk version and whether it is running, the sending mode and the number of allowed rooms (exit code 0). The login state, monitor scaling and recent errors are ⏳ step 10.
- `.\kakao.cmd rooms list` shows the allowed rooms and their permissions. `rooms add`, `remove` and `set`, which add, remove and change permissions, are done **by a person only** (add `--human` and type it yourself at the keyboard). The header line is `방 이름 | 종류 | 사람 읽기 | AI 읽기 | 사람 보내기 | AI 보내기` (room name | kind | person read | AI read | person send | AI send), followed by one line per room.
- `.\kakao.cmd read <room> [--since 7d|12h] [--last N]` and `.\kakao.cmd search <word> [--room <room>]` only read and search export files that are already kept. When an AI calls them (no `--human`), only rooms with `aiRead` turned on work. The message text and the searched word are not left in the records (only the room name and a count), and terminal control characters are removed before printing. **Because `export` does not exist yet, when no kept file exists they stop with `저장된 내보내기 파일이 아직 없습니다. 먼저 대화를 내보내 주세요. (방: <room name>)` (exit code 3).**
- Only the command line of `.\kakao.cmd send ...` is connected. Real sending is locked for safety, so any input (even `--dry-run`) prints `보내기는 아직 연결되지 않았습니다. 입력란 위치를 측정하기 전이라 안전을 위해 잠가 두었습니다. 아무것도 보내지 않았습니다.` and stops with exit code 3, and nothing is typed into KakaoTalk. Wrong options print the usage (exit code 1).
- The message used to point to `kakao help`, which did not exist; this was fixed on 2026-10-31. The `help` command itself does not exist yet (⏳ step 11).

### How it will look (⏳ planned, based on the design document)

- Menu: open `시작.bat` and press one number to run (no Enter needed).
- Sending from the menu: `1` → choose a room (the last used room is the default) → type the message → `Y`. Within 4 inputs.
- Sending from the command line: the design document gives the form `kakao send <room> "<message>" [--dry-run] [--yes]`, and for text with many special characters there is a separate way to pass it through `--file <path>` or standard input (`-`).
- When an AI uses it: `kakao <command> --json` returns the result as JSON.

### Rules for staying safe (promises that apply once the features open)

1. Testing is done only in a room where I am alone.
2. Do not touch the keyboard or mouse while it works. If you do, the safety device stops the job.
3. Rooms with friends have sending locked by default, and a person must unlock it by hand.
4. If you have copied an image or a file to the clipboard, the job stops (because it could not be restored).
5. Only one room and one message at a time. Sending interval is at least 2 seconds, and length is at most 1000 characters.
6. Opening an ordinary room may show a "read" mark to the other person. You are told once when a room is added to the allowed list.
7. Changing the allowed list and giving consent must be done by a person, and cannot be done by automated execution.

<a id="commands"></a>
## 8. Command reference

`kakao` in the table is shorthand for `.\kakao.cmd`. **Only commands marked ✅ work right now.**

| Command | Status | What it does | Step |
|---|---|---|---|
| `kakao version` | ✅ Available | Shows the kit version. Output: `카카오톡 키트 1.0.0` | 1 |
| `kakao help` | ⏳ Planned | Shows Korean help with examples. | 11 |
| `kakao status` | ✅ Available (minimal) | Only reads and shows the kit version, the KakaoTalk version and whether it is running, the sending mode (full / read-only), the number of allowed rooms and of rooms with AI permission, and whether sending is locked. The login state, monitor scaling and recent errors are added in step 10. | 10 |
| `kakao rooms (list \| add \| remove \| set)` | ✅ Available | Manages allowed rooms: `rooms list`, `rooms add <room> --type open\|self\|normal [--self-only] --human`, `rooms remove <room> --human`, `rooms set <room> <aiRead\|aiSend\|canSend\|noDraft> <on\|off> --human`. `list` is for anyone; the rest are for a person only (`--human` plus keyboard input). The design's "register only when the search shows exactly one exact-name match" needs KakaoTalk to be operated and does not exist yet (⏳); for now `add` registers by name only, and AI read and send are both off at first. | 11 |
| `kakao open <room>` | ⏳ Planned | Opens a room from the allowed list through search and checks the window title. The part is built and tested; only the connection to a command is left. | 7 |
| `kakao send --room <room> (--text <text> \| --file <file>) [--dry-run] [--yes] [--attempt-id <number>] [--human]` | ✅ Command connected (sending is locked) | The command line (argument parsing, reading a text file, person/AI distinction, run lock, showing the result) is connected. Real sending is locked until the position of the input box is measured, so every call stops with exit code 3 and sends nothing. `--human` works only for a person at the keyboard; without it the caller is treated as an AI (an AI must give `--attempt-id`). | 8 |
| `kakao export <room>` | ⏳ Planned | Saves the whole chat to a file with the official export. Built before step 8. | 9 |
| `kakao read <room> [--since 7d\|12h] [--last N] [--human]` | ✅ Command connected (data after `export`) | Reads messages from the kept export file and shows them (does not operate KakaoTalk). `--json` is ⏳ step 11. `export`, which makes the kept file, does not exist yet, so for now it stops saying "no saved export file yet" (exit code 3). | 9 |
| `kakao search <word> [--room <room>] [--human]` | ✅ Command connected (data after `export`) | Looks for a word, letter for letter, in the kept export files (200 characters or fewer, does not operate KakaoTalk). The word is not left in the records. | 9 |
| `kakao update` | ⏳ Planned | Installs over the old one from a new folder (settings and records kept). | 12 |
| `kakao uninstall` | ⏳ Planned | Removes only what the kit created. Asks whether to delete exported chats (default: keep). | 12 |
| `kakao menu` | ⏳ Planned | Opens the numbered menu. | 11 |

### Options (all ⏳ planned)

| Option | Meaning | Step |
|---|---|---|
| `--json` | Prints the result as JSON that computers read easily (for AI). | 11 |
| `--dry-run` | Only previews sending; no real input is made. | 8 |
| `--yes` | Goes ahead without asking for confirmation. Required for automated runs. | 8 |
| `--file <path>` or `-` | Takes the message text from a file or standard input (a path that is safe for special characters). | 8 |
| `--allow-unverified` | Lets a person send by hand on a KakaoTalk version that is not verified. | 8, 10 |
| `--since 7d`, `--last N` | Sets the range to read (last 7 days, last N messages). | 9 |
| `--out <folder>` | Sets the folder where exports are saved. | 9 |
| `--room <room>` | Limits the search to one room. | 9 |

<a id="how"></a>
## 9. How it works (principles)

### The big picture (an analogy)

KakaoTalk is a house without an official front door (API). So this kit places a **robot hand that presses keyboard shortcuts** in place of the user. The robot hand moves only when a strict **gatekeeper (guard)** allows it, and if the gatekeeper is even slightly doubtful, it presses nothing and stops.

### Three approaches and the choice

| Approach | Description | Used? |
|---|---|---|
| A. Screen automation | Sends keyboard and mouse input on your behalf. | ✅ Used for sending and opening rooms |
| B. Official chat export | Saves the chat as a text file with KakaoTalk's own feature (`Ctrl+S`), then reads that file. | ✅ The main way of reading |
| C. Decrypting storage / analysing the app | Unpacks and reads KakaoTalk's internal data. | ❌ Not used (conflicts with the terms) |

### How sending a message works (⏳ built in step 8, the parts below are ✅)

1. Check the allowed list: only a room whose name matches character for character passes.
2. Open the room: not by clicking on the list by eye, but only through search. If the search result is not exactly 1 item, it stops.
3. Gatekeeper check: whether the window belongs to KakaoTalk, whether the window title is exactly the room name, whether it is in front, whether a person touched the keyboard or mouse, and whether any key is held down (the Hangul/English key is not counted).
4. Save the clipboard: safely keeps the text you currently have copied (only when it is text).
5. Put the text to send on the clipboard and confirm it really went in.
6. Paste with `Ctrl+V` and send with `Enter`.
7. Put the clipboard back as it was and confirm it was restored.
8. Leave only time, command, room name and result in the record (log). The message text is not kept.

Why paste instead of typing: Korean text, emoji and long text then do not lose or change characters.

### How reading a chat works (⏳ built in step 9, the parser, keeping, reading and searching parts are ✅)

1. Open the room and press `Ctrl+S`. KakaoTalk's "Save as" window appears.
2. Always paste a new file name and press `Enter` to save (this prevents the overwrite question that appears when the same name exists).
3. Read the saved file. The file looks like this: line 1 `<room name> 님과 카카오톡 대화`, line 2 `저장한 날짜 : YYYY-MM-DD HH:MM:SS`, the date divider `--------------- 2026년 10월 21일 수요일 ---------------`, and messages `[nickname] [오전 2:59] text`.
4. Keeping: per room it keeps 1 latest copy (`latest.txt`) and the 3 newest snapshots, and snapshots older than 30 days are deleted (✅ parts, tested with fake files). If the room name on the first line of the file differs from the registered room, nothing is saved and the kit stops. Reading and searching look only at the latest copy, and an AI can read only rooms where AI reading is switched on. Exporting through the save window and the connection to a command are ⏳.

### How opening a room works (⏳ connected to a command in step 7, the parts below are ✅)

1. It first checks that the room is on the allowed list. If it is not, it stops without even reading the window list.
2. If exactly one room window with the same title is already open, it uses that window (it does not close it, because the kit did not open it); if there are two or more, it cannot tell which is which and stops.
3. It checks that there is exactly one KakaoTalk main window and that Korean on-screen text reading (OCR) is available. If either is not true, it does not open the room.
4. It waits until your hands are off the keyboard and mouse, then searches in this order: open the search (`Ctrl+F`) → paste the room name (`Ctrl+V`). It never clicks a list by eye.
5. It reads the search-result area with on-screen text reading and checks that it shows exactly one room name. If it cannot confirm that, it does not double-click. It also checks that the KakaoTalk window has the reference size and that the result area is not covered by another window.
6. It double-clicks the first result row once and waits up to 8 seconds for a new window. It counts as success only when the new window's title is word for word the room name.
7. If the title differs, it closes that window and stops. It closes only the window the kit opened, and sends a single close request only to a window that belongs to KakaoTalk and whose title matches exactly.

On-screen text reading looks at the screen in memory only (nothing is saved to disk). The size of the KakaoTalk window and the position of its text depend on the display scaling of the monitor the window sits on (the same window is 588x753 at 150% and 392x502 at 100%), so the pixel values used for the decision are meant to be recalculated for that scaling. If they do not match the reference, it stops on the side of not opening. However, even when the KakaoTalk main window is on a 150% monitor, the window's own scaling value comes out as 100% (read-only check, 2026-11-02), so there was a defect where it judged "different from the reference" and stopped on that monitor; it was fixed on 2026-11-11 by reading the scaling of the monitor the window sits on (item 10 of 12.3). On the 100% monitor, opening and closing a room really passed. Opening a room can show a "read" mark to the other person and cannot be undone, so not opening unless it is sure is this part's basic rule.

### What the gatekeeper blocks

- No key other than the 5 allowed keys (`Ctrl+S`, `Ctrl+V`, `Ctrl+C`, `Ctrl+F`, `Enter`) is ever sent.
- `Esc` is never sent. In KakaoTalk `Esc` closes the chat window (a mistake that really happened).
- The ≡ menu at the top right of the window is never clicked. Inside it, "Delete all chat content" and "Leave chat room" sit right next to each other.
- "Check" and "input" are bundled into one action, so there is no gap between checking and typing in which the window could change.
- If any key is held down right before input, nothing is sent: a Ctrl combination sent while a person holds a key would turn into a wrong shortcut. **Only the Hangul/English key is exempt.** On some keyboards and input methods that key is read as held down even with hands off (confirmed on this PC), and blocking it would mean nothing could ever be sent. No other key has an exception.

<a id="workflow"></a>
## 10. Workflows

### A. When `시작.bat` is run (✅ works now)

```text
Double-click 시작.bat
  -> switch the window character table to UTF-8 (chcp 65001)
  -> print the temporary guide text
  -> call kakao.cmd version
       -> powershell -NoProfile -ExecutionPolicy Bypass -File src\kakao.ps1 version
            -> the router (Invoke-KakaoCommand) recognises 'version'
            -> prints "카카오톡 키트 1.0.0", exit code 0
  -> print "Press any key to close" (in Korean) and wait
```

### B. Sending a message (⏳ design)

```text
kakao send <room> <message>
  1. check consent to use ........... part ✅ (Assert-KitReady)
  2. check the allowed list ......... part ✅ (Test-RoomAllowed)
  3. check length (1000) / gap (2s) . ⏳
  4. check KakaoTalk version ........ ⏳ (exit code 4 if unverified)
  5. preview + confirm (skip with --yes) ⏳
  6. before starting, wait hands off . part ✅ (Wait-UserIdle)
  7. open the room (search only) .... part ✅ (Open-KakaoRoom), command link ⏳
  8. gatekeeper check ............... part ✅ (Assert-InputTarget)
  9. check the input box is empty ... ⏳ (stop if text is already written)
 10. save clipboard -> put text ..... part ✅ (Use-TextClipboard)
 11. Ctrl+V -> Enter ................ part ✅ (Send-KeyCombo)
 12. restore the clipboard .......... part ✅
 13. write the record (no text) ..... part ✅ (Write-KitLog)
 14. close only the window it opened  part ✅ (Close-KakaoWindow)
```

### C. Reading a chat (⏳ design)

```text
kakao read <room>
  1. check allowed list + AI read permission .. part ✅
  2. open the room ............................ part ✅ (Open-KakaoRoom), command link ⏳
  3. Ctrl+S -> check the save window .......... ⏳ step 9
  4. paste a new file name -> Enter ........... ⏳ step 9
  5. wait until the file exists (max 10 s) .... ⏳ step 9
  6. read the file (parser) ................... part ✅ (ConvertFrom-KakaoExport)
  7. tidy the stored copies (latest + 3) ...... part ✅ (Update-ExportStore), command link ⏳
  8. read from the stored copy ................ part ✅ (Read-KakaoRoom), command link ⏳
  9. print to screen (JSON with --json) ....... ⏳
```

### D. The order in which the gatekeeper allows input (parts ✅, tested with fake parts)

```text
Start of work
  -> wait until the keyboard and mouse are idle (Wait-UserIdle)
  -> make sure no other kit job runs at the same time (named lock)
  -> check the target window: owned by KakaoTalk? exact same title? in front?
  -> is the key in the allowed-key table? is no other key held down? (Hangul/English key excluded)
  -> has no person's input happened since the last input?
  -> run [check + input] together as one action
  If anything is wrong: 0 inputs, a Korean error message, exit code 2
```

### E. Opening a room (parts ✅, tested in real KakaoTalk only in part)

```text
Open-KakaoRoom <room name>
  1. check the allowed list ............ if it fails, do nothing at all
  2. is a window with the same title already open? .. one: reuse it (do not close it); two or more: stop
  3. exactly 1 main window + text reading (OCR) available? .. if not, stop
     is it the open-chat tab? ........ if not, stop without any click (on another tab the same spot is a different button)
  4. wait hands off -> open the search (`Ctrl+F`) -> Ctrl+V
  5. is the search result exactly 1 row? .. if not, stop without a double-click (and explain why)
  6. double-click the first result row once
  7. is the new window's title word for word the room name? (waits up to 8 s)
       same: success / different: close that window and stop / time is up: stop
  8. at the end, close only the window the kit opened (never one that was already open)
```

<a id="architecture"></a>
## 11. Architecture

### Layer diagram

```text
 Person --- 시작.bat (numbered menu, ⏳) --+
 AI ------- kakao.cmd (command line) ------+
                                           v
                         src\kakao.ps1  (router: decides which command)
                                           |
      +----------+----------+--------------+---+-----------+
      v          v          v                  v           v
   Config      Log      Guard+Win32          Clip        Parse      Status, Ocr, Room, Export, Search
   settings    records  gatekeeper,          clipboard   reading     version check, text reading, opening rooms,
   + allowed            input                            exports     keep / read / search  (⏳ not yet: Send, Install, Menu)
      \________ Messages.ko (all Korean messages) · Paths · Errors ________/
                                           |
                  KakaoTalk PC app (windows, keyboard)  /  exported text files
```

### Parts (modules) table

| File (under `src\lib\`) | What it does | Status |
|---|---|---|
| `Messages.ko.ps1` | Builds every Korean message shown to the user in one place. | ✅ |
| `Paths.ps1` | Works out the kit version, whether it runs as administrator, and the data folder location (`%LOCALAPPDATA%\KakaoKit`). It does not create the folder. | ✅ |
| `Errors.ps1` | Defines the kit's own error types and exit codes (1-4). | ✅ |
| `Config.ps1` | Handles the settings file, allowed room list, per-room permissions and consent to use. | ✅ Parts |
| `Log.ps1` | Makes one-line records without message text, tidies the record file, and builds the error report text. | ✅ Parts |
| `Win32.ps1` | Loads Windows features (finding windows, sending key input, reading the display scaling of the monitor a window is on) through C# code. It is compiled the first time it is loaded and takes about 0.2-0.3 seconds. | ✅ Parts |
| `Guard.ps1` | Handles the check right before input (the gatekeeper), the allowed-key table, human-hand detection and the lock against running twice. | ✅ Parts |
| `Clip.ps1` | Saves, replaces and restores only the clipboard text, and checks each step. | ✅ Parts |
| `Parse.ps1` | Turns an export text file into the room name, saved time and message list. | ✅ Parts |
| `Ocr.ps1` | Decides, with on-screen text reading (OCR), whether the search result is only the room name. It reads the screen in memory only, writes nothing to disk and sends no input. | ✅ Parts (checked on a real screen and fixed, see chapter 14) |
| `Room.ps1` | Opens only an allowed room, and only through the search; checks before opening that the result is exactly one row; counts it as success only when the opened window's title equals the room name letter for letter. It does not open when it cannot check. | ✅ Parts (one real open-and-close test passed; connection to a command is ⏳ step 7) |
| `Send.ps1` | Sending messages | ⏳ step 8 |
| `Export.ps1` | Keeps exported files per room (the 3 newest, snapshots older than 30 days deleted, the latest copy as `latest.txt`) and reads messages from the kept latest copy. It does not operate KakaoTalk. Exporting through the save window is ⏳. | ✅ Parts (partly, step 9) |
| `Search.ps1` | Looks for a word in the kept latest copy, letter for letter (not as a pattern). It does not operate KakaoTalk. | ✅ Parts (step 9) |
| `Status.ps1` | Reads the installed KakaoTalk version (cross-checking the registry against the running process) and decides whether it is a version that was actually tested. Read-only. The login check and the full status check are added in step 10. The check that locks sending for an untested version (exit code 4) is here too. | ✅ Parts (minimal) |
| `Send.ps1` | The safety frame for sending messages: checking the text (not empty, 1000 characters, no hidden control characters), stating the caller (person or AI), the lock for untested versions, the allowed list and AI permission, checking that the run lock is held, the 2-second interval and attempt numbers (required for an AI, recorded in the data folder so they hold across processes), sending only to a window the kit opened, sorting the result into confirmed or unknown (unknown is never resent), and keeping the message body out of the records. **It is not connected to any command yet**, and real sending is locked on purpose because the position of the input box has not been measured (calling it stops with no input). | ✅ Parts (sending locked) |
| `SendCommand.ps1` | The command layer of `kakao send`: parsing the arguments (an unknown option, a repeated option, a missing value, `--text` and `--file` together, or a value starting with `--` is a usage error), reading a text file (8 KB or less, UTF-8, only one trailing line break removed), deciding the caller (a person only with `--human` and when keyboard input is not redirected; anything else is an AI), taking and releasing the run lock, and showing the result (the message body is kept off the screen and out of the records). It creates no input. | ✅ Parts (connected, sending locked) |
| `Foreground.ps1` | Waits, with no input, until KakaoTalk is the front window (design 13.8). It goes on when the window has been in front for 2 seconds in a row and stops if that does not happen within 120 seconds (exit code 2). It only reads the front window; it sends no keys, no clicks and does not change the focus. **It is not yet placed in the sending or room-opening flow.** | ✅ Parts (not connected) |
| `InfoCommands.ps1` | The command layer of `kakao status`, `rooms`, `read` and `search`: parsing the arguments (letter case counts; an unknown option, a repeated option, a missing value or a value starting with `--` is a usage error), deciding the caller (a person only with `--human` and when keyboard input is not redirected), changing the allowed list by a person only, checking the `aiRead` permission for reading, removing control characters before printing, keeping only the room name and a count in the records (no text, no word), and unknown errors without their raw text. It does not operate KakaoTalk. | ✅ Parts (connected) |
| `Menu.ps1` | Numbered menu | ⏳ step 11 |
| `Install.ps1` | First run, update, uninstall | ⏳ step 12 |

### Why it was built this way

- **`.bat` + the PowerShell 5.1 built into Windows**: nothing extra to install, and it works as it is on a PC without administrator rights. Install is copying a folder, uninstall is deleting a folder. (Python and Node.js approaches were also considered, but not chosen because of separate installation and compatibility problems.)
- **C# code snippets**: the Windows feature for sending key input precisely is hard to use from PowerShell syntax alone, so it is made as a C# snippet that is compiled while running. Only the .NET that comes with Windows is used.
- **One Korean message dictionary**: it stops English text from leaking out and makes it easy for tests to check the messages.
- **Testing with fake parts (Provider)**: the gatekeeper is fitted with fake parts instead of real Windows features, so that "no input was delivered even once" can be proven with a number.

<a id="security"></a>
## 12. Security and data flow

### 12.1 The promises that are kept

| Promise | How | Status |
|---|---|---|
| Only allowed rooms | The room name must match character for character (case, spaces and invisible characters are all distinguished). Two rooms with the same name are refused. | ✅ Tested |
| Gatekeeper right before input | Owned by KakaoTalk, exact title match, window in front, no human hands, no key held down (only the Hangul/English key is exempt). If any one is wrong, 0 inputs. | ✅ Tested with fake parts (real KakaoTalk is ⏳) |
| 5 allowed keys, no Esc or Ctrl+A | The same allowed table exists on both sides of the code (PowerShell, C#), and a test checks that there is no Esc code. | ✅ |
| Human-hand detection | Waits until idle before starting, and stops if human input is detected during the work. | ✅ (checking false alarms is ⏳) |
| No running twice at once | A named lock (`Local\KakaoKit.InputLock`) | ✅ |
| Clipboard protection | Only text is saved and restored, a job stops if there is an image or file, and it is checked after putting text in and after restoring. | ✅ |
| Does not open unless sure | Opening a room checks the allowed list, that the search result is exactly one row, and that the window title matches; if any one fails, it does not open. If the opened window is a different one, it closes that window and stops. | ✅ Tested with fake parts (one real open-and-close test passed) |
| On-screen text reading is read-only | It reads the window in memory only, writes nothing to disk and sends no input. The text it reads is used only for the decision and is never logged or printed (because a capture can show other rooms' names). | ✅ Tested |
| No message text in the log | The log function has no parameter at all that takes message text, and each column is cut to 120 characters. | ✅ |
| Does not handle passwords | They are neither stored nor typed. The user logs in directly in KakaoTalk. | ✅ |
| Does not use administrator rights | There is no code that asks for them, and a test checks this. | ✅ |
| Items only a person may change | Changing the allowed list and giving consent need both the `-Human` switch and direct keyboard input. | ✅ Parts (commands ⏳) |
| AI permission split | Each room has an AI-read and an AI-send switch, off by default. Sending to friend rooms is always locked for AI. | ✅ Parts |
| Strict check of permission values | A permission in the settings file counts as on only if it is a real `true`. The text "true", the number 1 and arrays all count as off. | ✅ |
| Unverified KakaoTalk versions are read-only | Sending is locked on anything other than 26.9.0.5337. | ⏳ step 10 |
| Notice about the read mark | When an ordinary room is added to the allowed list, you are told once and asked to consent. | ⏳ |

### 12.2 Data flow

| Data | Where it comes from | Where it is stored | Does it leave? | Note |
|---|---|---|---|---|
| Allowed room list, permissions, consent time | Set by a person | `%LOCALAPPDATA%\KakaoKit\config.json` | No | A plain text file that contains room names. Parts ✅, screens ⏳ |
| Work record (log) | The kit writes one line each: time, command, room name, result | `%LOCALAPPDATA%\KakaoKit\logs\kakao.log` | No | No message text. When it exceeds 1 MB it shifts to `.1`-`.3` and the oldest is deleted. |
| Error report | Kit, KakaoTalk, Windows and PowerShell versions and the last 50 record lines | Text shown on screen (saving is ⏳) | No | It has no chat content, but may contain room names. For a 1:1 room that may be the other person's name, so check before sending it to anyone. |
| Message text to send | Typed by the user | Memory, the clipboard briefly, and KakaoTalk | To KakaoTalk (the intended send) | A mark asking to exclude it from clipboard history and cloud sync is attached. Whether every program obeys it was not checked. |
| Original clipboard content | Text the user had copied | In memory only | No | It is restored after the work. It is not written to disk (checked by code search). |
| Screen capture (to check before opening a room) | The kit reads the KakaoTalk window | In memory only (not saved) | No | A capture can show other rooms' names and previews, so the text it reads is not logged. Captures taken during development for a person to look at were approved one by one, deleted right after checking, and never uploaded to the repository (`.gitignore` excludes picture files). |
| Exported chat files | KakaoTalk's official feature | `%LOCALAPPDATA%\KakaoKit\exports\<room folder>\` (keeping part ✅, not created at present; saving from KakaoTalk ⏳) | No | They contain other people's chats. 1 latest copy (`latest.txt`) and 3 snapshots per room, deleted after 30 days. |
| Password | Not handled | Not stored | Not applicable | The user logs in directly in the KakaoTalk app. |

The kit does not send chat content over the internet. However, **if you hand a chat you have read to an AI service, that content leaves the computer.** To guard against this, the "allow AI to read" switch for each room is off by default, and it is planned to tell you this and ask for consent when you turn it on (⏳).

### 12.3 Known security limits (written down, not hidden)

1. **How `kakao.cmd` interprets arguments**: because Windows cmd interprets the command line first, if you call it by pasting untrusted text such as a message straight into the command-line arguments, `&` or `%name%` can run as commands. This is how cmd is built, and escaping cannot fully stop it. So the message text is planned to be accepted only through `--file` or standard input, and automated callers are planned to call `powershell -NoProfile -ExecutionPolicy Bypass -File src\kakao.ps1` directly (⏳ steps 8 and 11). What was checked directly on 2026-10-31: when `&` or `|` reaches `kakao.cmd` without quotes, what follows it **really runs as a command.** A quoted one, and calling `src\kakao.ps1` directly (special characters in it do not run), are safe, and both are pinned by tests. Right now there is only `version`, and it uses what you type only to compare command names, so the risk when you type it yourself is low, but you must not pass untrusted text such as a message through `kakao.cmd`.
2. **The settings file is a plain text file.** A person or a program running under the same user account could edit it and change the allowed list. The "only a person may change" rule is kept only at the command level. Options such as a read-only settings file will be examined in step 12.
3. **The `KAKAO_KIT_HOME` environment variable** can change the data folder (originally for testing). It also applies in real use, so using a folder other than the default is planned to be shown on every command (⏳ step 11).
4. **Real behaviour of the key input method**: with the newly built input method (SendInput), clicking, pasting (`Ctrl+V`), double-clicking and closing a window passed in real KakaoTalk. `Enter`, `Ctrl+S`, other keyboards and input methods, and false alarms of human-hand detection (stopping although nobody touched anything) have not been checked yet (⏳ steps 7-9).
5. **Timing of restoring the clipboard right after pasting**: if it is restored before KakaoTalk has finished pasting, the original clipboard text could be sent instead, so a waiting time before restoring is planned and will be checked for real (⏳ step 8).
6. **Programs that briefly lock the clipboard**: the Windows clipboard history or a capture tool can hold the clipboard right after a change. The kit checks the result of reading and writing, retries, and stops the work if it still fails.
7. **A malicious program already running under the same account** cannot be stopped by this kit. This is a general limit.
8. **A decision that leans on on-screen text reading**: the room-opening decision "the search result is exactly 1 row" leans on values measured with KakaoTalk 26.9.1.5339, the open-chat tab and the reference window size, and is affected by the accuracy of the Korean text-reading engine. It was built to stop on the side of not opening when the values differ or the text cannot be read, and the wrong room has never been opened on a real screen, but not every screen was checked. It must be checked again for ordinary rooms (1:1 and group chats) and for a screen where KakaoTalk has changed again.
9. **Opening a room cannot be undone**: opening a room can show a "read" mark to the other person. So it opens only after checking the allowed room, exactly one search result and the matching window title, but even when the checks were right, there is no way to undo a read mark that has already appeared.
10. **Opening a room stopped on a 150% monitor (defect fixed on 2026-11-11; opening a room on the 150% monitor passed once in the S5 run on 2026-11-12)**: in a read-only check on 2026-11-02 (no key or mouse input, no screen capture), when the KakaoTalk main window was on the 150% monitor its size was 588x753, but the window scaling Windows reported for it was 100% (another, smaller window of the same program was read as 150%). So the kit, before the fix, concluded "the size differs from the reference (392x502)" and did not open the room. This errs on the side of not opening, so it is safe, but the message shown says "monitor scaling 100%", which is misleading. This problem does not occur on the 100% monitor, where opening and closing a room really passed. Cause (confirmed by a measurement on 2026-11-10): the KakaoTalk main window and room windows are "system-aware" in Windows' scaling awareness, so the window's own scaling value comes out as 100% (96) even on the 150% monitor, while on screen they are stretched to the monitor's scaling (392x502 × 1.5 = 588x753). A notification window on the same monitor is "per-monitor aware" and was read correctly as 150% (144). The fix (2026-11-11): read the scaling of the monitor the window sits on instead of the window's own value (6 tests added, Ocr 47 → 53). Hardening (2026-11-11, pointed out by Codex's verification): the monitor's value is trusted only when the calling thread is per-monitor DPI aware; otherwise (the DPI setting failed) the window's own value is used, which is the same behavior as before the fix. It is not guaranteed that this always refuses safely (the case where screen coordinates are virtualized was not checked); only a fresh process's main thread really becoming per-monitor aware was confirmed by a test. What was confirmed: in a read-only check (no input, no screen capture) the main window (588x753) had a window scaling of 96, a monitor scaling of 144 and a new scale of 1.5, and its size matched the reference (before the fix it was 1.0 and did not match). What was not confirmed: really opening a room on the 150% monitor (it needs input, so it can only be done after the user's approval).

<a id="files"></a>
## 13. Where files and documents are

### Folder structure

```text
(kit folder)
├─ README.md / README.html          Korean guide
├─ README.en.md / README.en.html    English guide (this document)
├─ LICENSE                          full text of the Apache License 2.0 (owner: SoDam AI Studio)
├─ .gitignore, .gitattributes       files Git does not upload, and line-ending rules
├─ 시작.bat                          start file for double-clicking (a temporary screen for now)
├─ kakao.cmd                        command-line entry point
├─ src
│  ├─ kakao.ps1                     command router
│  └─ lib                           parts (table in Chapter 11)
├─ config
│  └─ verified-versions.json        list of KakaoTalk versions that were tested
├─ tests                            automated tests (fixtures hold a fake chat file)
├─ tools
│  ├─ Test-All.ps1                  test runner
│  ├─ Write-Bom.ps1                 file encoding fixer
│  └─ Build-Readme.ps1              tool that makes the html of the README
├─ docs                             design document, plan, research notes
├─ tasks                            task checklist and progress record
├─ CHECKPOINT.md                    notes for picking development up again (only on the development PC, not uploaded to Git)
└─ .remember, .sodam-re, .omc etc.  folders made by other development tools (unrelated to the kit, not uploaded to Git)
```

### Where the documents are

| Document | Location | Content |
|---|---|---|
| Guide (Korean) | [README.md](README.md) | The Korean guide. Its html version is README.html in the same folder. |
| Guide (English, this document) | [README.en.md](README.en.md) | The English guide. The html with the same content is README.en.html. |
| License | [LICENSE](LICENSE) | Full text of the Apache License 2.0 (owner: SoDam AI Studio) |
| Design document | [docs/superpowers/specs/2026-10-27-kakao-kit-design.md](docs/superpowers/specs/2026-10-27-kakao-kit-design.md) | What is built and why, safety rules, decisions made (written in Korean) |
| Implementation plan | [docs/superpowers/plans/2026-10-27-kakao-kit-plan.md](docs/superpowers/plans/2026-10-27-kakao-kit-plan.md) | The 13-step work plan and test criteria (written in Korean) |
| Research notes | [docs/spike-notes.md](docs/spike-notes.md) | Facts checked directly on this PC (Korean text corruption, window structure, etc.) |
| Task checklist | [tasks/todo.md](tasks/todo.md) | Check items for each step |
| Progress record | [tasks/progress.md](tasks/progress.md) | The result of each step and the record of judgments and decisions |

### Where user data is

The settings and records the kit creates are stored separately in your **user folder**, not in the program folder. Type `%LOCALAPPDATA%\KakaoKit` into the File Explorer address bar to open it.

| Location (under `%LOCALAPPDATA%\KakaoKit`) | Content | Status |
|---|---|---|
| `config.json` | Allowed room list, permissions, consent time | Parts ✅ (not created for now) |
| `logs\kakao.log` (and `.1`-`.3`) | Work record (no message text) | Parts ✅ (not created for now) |
| `exports\` | Exported chat files (one folder per room) | keeping part ✅ (not created at present); saving from KakaoTalk ⏳ step 9 |
| `manifest.json` | List of what the kit created (used when uninstalling) | ⏳ step 12 |

<a id="changelog"></a>
## 14. Update summary (click to expand)

Click a title to expand it. Work was done from 2026-10-27 to 2026-10-31. The test counts are the number of automated tests that passed at that point.

<details>
<summary><strong>Part of step 9: the parts for keeping, reading and searching exports</strong> — tests 262 → 290</summary>

- Only the part that does not touch KakaoTalk was built first: keeping exported files per room (the 3 newest, snapshots older than 30 days deleted, the latest copy as `latest.txt`), reading messages from the kept latest copy (`-Last`, `-Since`), and searching for a word (letter for letter, upper/lower case ignored).
- Safety points: if the room name on the first line of the file differs from the registered room, nothing is saved (this stops another room's chat from being kept under this room's name and leaking through the AI reading permission). The keeping folder name is made by cleaning the room name and adding a hash, so a name like `..` cannot leave the keeping folder. Files that are not snapshots made by the kit are never deleted. Reading and searching follow the allowed list and each room's AI reading setting.
- 28 tests were written first and seen to fail before the implementation; then 8 deliberate breakages of the code (switching off the room-name check, changing the number kept, switching off the 30-day cleanup, pattern search, switching off the read permission, dropping the hash from the folder name, ignoring the AI setting, deleting other files) were all caught by the tests.
- Limits: tested only with synthetic fake chat files. Exporting a real file through KakaoTalk's `Ctrl+S` save window, the connection to a command, and checking a real export file are not done yet.

</details>

<details>
<summary><strong>Full check of this guide</strong> — tests 261 → 262</summary>

- I re-checked the guide against what has been built so far: the status, date and "at a glance" table at the top, steps 7-9 and the change of work order in chapter 2, the Korean on-screen text reading (OCR) requirement in chapter 3, the command table in chapter 8, how opening a room works and its flow in chapters 9-10, the parts table in chapter 11, the on-screen reading data flow and limits in chapter 12, the full list of on-screen messages in chapter 15, the FAQ in chapter 16, the split between what the license allows and the owner's policy in chapter 17, the development rules in chapter 18 and the glossary in chapter 19.
- During the check I found 29 on-screen messages that were missing from the guide (room-opening, gatekeeper, clipboard, settings and file-reading messages that chapter 15 did not have). All are now in chapter 15, and I added one test so that new messages cannot be left out of the guide in the future (I wrote the test first, confirmed it failed, and then fixed the documents).
- Limit: the only things the tests check mechanically are the test counts, command status, version, on-screen messages, links and the Korean/English structure. The rest of the text was matched against the code and the records by an AI, and has not yet had a final review by a person.

</details>

<details>
<summary><strong>Mid-way verification</strong> — tests 257 → 261</summary>

- In the middle of development I checked normal flows, exceptions, wrong input, boundary values and failures (no input was sent to KakaoTalk). Automated tests passed 257 of 257 three times in a row, a syntax check, the encoding rules, a search for 8 kinds of sensitive-data patterns (0 hits in the 43 tracked files), code searches for forbidden input, network, privilege-raising and run-text-as-code constructs, real runs of `kakao.cmd` and `시작.bat` (normal, no argument, unknown command, upper case, extra argument, empty argument, Korean, 7000 characters, spaces and Korean in the path, another folder), and about 50 boundary values of settings, parser and log.
- Four things found and fixed: ① A message that pointed to the non-existent `kakao help` now points to `version`. ② Working out the data folder on a drive that does not exist ended with an English system error; this is fixed. ③ I reproduced directly that when `&` or `|` reaches `kakao.cmd` without quotes, what follows it really runs as a command, so I corrected the explanations in chapters 12 and 14 and pinned both paths (`kakao.cmd` and calling `src\kakao.ps1` directly) with tests. ④ Where the guide's quotes of on-screen messages differed from the message dictionary, an existing test caught it and it was fixed.
- 4 tests were added. Not done (not run): real input into KakaoTalk, and static analysis (PSScriptAnalyzer is not installed).

</details>

<details>
<summary><strong>Room-opening parts (M7 main work)</strong> — tests 184 → 230</summary>

- I built `Room.ps1`, which opens a room in KakaoTalk, and `Ocr.ps1`, which checks the search result with on-screen text reading (OCR). They are not yet connected to a command that a user can call (⏳).
- The rules come down to one: **if it cannot check, it does not open.** A room that is not on the allowed list gets no input at all; without confirming that the search result is only the room name it does not double-click; and if the new window's title is not the room name letter for letter after opening, it closes that window and stops. A window that was already open is reused but never closed, and only a window the kit opened is closed. The result check looks at only the top line in the room-name column, so another room's preview text that equals the room name cannot pass; it also rejects another room whose name has digits glued right after it (for example a room named with an extra digit), and it does not open when the window is covered or when the window size or click height differs from the measured values.
- On a PC without the Korean text reader it does not open by default. Only a person can allow "open without checking", and then a warning is recorded.
- I wrote 38 tests first and confirmed all of them failed before implementing, and after pushing I added 8 more tests for the 4 gaps an automated security review pointed out and confirmed they failed before fixing them (22 for opening a room, 24 for text reading). All use fake parts and never touch real KakaoTalk.
- Limits: the click positions and the result area come from screens of KakaoTalk 26.9.1.5339 with a 588x753 window (150% scaling) on the open-chat tab. Reading two real screens (one result, several results) with the text reader showed that the icon in front of the room name is read as the digit 0 and the left-menu icons are read as characters, so "exactly one result" was not judged correctly (an error on the safe side: the room is not opened). I changed the check to use the positions of the word boxes and added 19 tests (tests 230 → 249). The same KakaoTalk window shows a different pixel size depending on the monitor's scale setting (588x753 at 150%, 392x502 at 100%), so the check now converts its measured pixel values by the scale of the monitor the window is on. This scale conversion has been confirmed on real screens at 150% and 100%; other scales such as 125% and 200% have been checked only with test data (corrected 2026-11-02: what was confirmed at 150% was only that the window looks like 588x753; a defect was found later in which the value read for the window scaling on that monitor comes out as 100%, so room opening was refused on a 150% monitor for a while; it was fixed on 2026-11-11 by reading the monitor's scaling, item 10 of 12.3). After the fix I re-read the real one-result screen once and it was judged "exactly one result" (the several-results screen was not captured again after the fix and was checked only with test data). The real room-opening and closing test passed once at 100% (one double-click on the first result row, the new window's title confirmed to equal the room name letter for letter, then closing only the window the kit opened, 7.4 s; the search-icon click and the paste steps were skipped because the screen was prepared in advance). It has not been run at 150% or through the whole flow that starts with the search-icon click.
- (Correction, 2026-11-12) The **select all (Ctrl+A)** that was added to overwrite leftover text in the search box has been removed: in the KakaoTalk main window `Ctrl+A` opens the "add friend" window. If text is left, the result is not exactly 1 row and the kit stops without the double-click. When opening a room stops, it also tells you why (the window size or monitor scale differs from the reference, or the window is covered). I wrote 8 tests first, confirmed they failed, and then implemented (tests 249 → 257).

</details>

<details>
<summary><strong>Change of work order: reading first, sending after</strong> — test count unchanged</summary>

- I swapped the order of step 8 (sending) and step 9 (reading) in the plan. The user approved it on 2026-10-30, and the reasons are in chapter 2 (without reading, the result of sending cannot be confirmed; the parser already exists and can be tested with synthetic data; the first `Enter` can be tried in a file-save window).
- Only documents changed; the code did not change.

</details>

<details>
<summary><strong>Gatekeeper: Hangul-key exception</strong> — tests 180 → 184</summary>

- When the real-KakaoTalk spike (step 7) started, the gatekeeper stopped before the first click, because the pressed-key check read the Hangul/English key as held down all the time. I confirmed it by only reading key state without sending any key: it was held in 20 of 20 reads, even 30 seconds after the last input. The kit could not send a single input.
- The pressed-key check now leaves out that one key. It is a mode-switch key, so a paste or click sent while it is held cannot turn into a wrong shortcut. Every other key (Ctrl, Shift, Alt, Esc, Delete, the Windows key, letters and so on) is still blocked. This judgment rested on the nature of the key. On 2026-10-30, on this PC, one real KakaoTalk click and one paste passed without a guard stop and with no abnormal behavior visible in the captures (confirmed once). Other keyboards and input methods, and other kinds of input, have not been checked.
- Four tests were added (only the Hangul key held passes; Hangul plus Ctrl held is refused because of Ctrl; every other key in the scanned range is refused one by one; the exception list has exactly one entry).
- After the fix I read the key state again on this PC and saw it change to no key held (0).
- I brought the guide in line with the development state: the step 7 marker and the verification environment in chapter 2 (KakaoTalk 26.9.1.5339 is a version that has not been tested yet; 4 monitors and their scaling), the "not verified yet" list, three descriptions of the gatekeeper (the Hangul/English key exception), the "another key is held down" remedy in chapter 15, the FAQ in chapter 16, and the note in 17.2 that the terms of the updated version have not been checked again.

</details>

<details>
<summary><strong>Minimal version check (M7-0)</strong> — tests 157 → 180</summary>

- KakaoTalk updated itself from `26.9.0.5337` to `26.9.1.5339`. Prompted by that, I added `Status.ps1` (minimal), which reads the installed KakaoTalk version and decides whether it is a version that was actually tested. It does not open or operate KakaoTalk; it only reads the registry value and the file version of the running process.
- If the two values differ, if running processes differ from each other, or if a value cannot be read, the version is returned empty and treated as not tested (when unsure, the safe side).
- The list of tested versions (`config\verified-versions.json`) is unchanged. `26.9.1.5339` on this PC is not on it, so the verdict is not a tested version. It will be added only after a real send test on KakaoTalk passes.
- Added the test helper `Test-E2EEnabled`, which reads the switch that turns on tests that operate the real KakaoTalk. It turns on only when the text is exactly `1`. No test uses it yet.
- Added 23 tests (12 with a fake registry and fake processes, 8 for the version verdict, 2 for read-only, 1 for the switch).

</details>

<details>
<summary><strong>Repository cleanup (M0)</strong> — tests 149 → 157</summary>

- Fixed `시작.bat` ending with neither a version line nor an error message when the folder name contains `^` or `%` (for example `A^B`, `A%20B`). It now enters that folder, calls `kakao.cmd` by a relative path without special characters, and shows a Korean message when it fails. A negative exit code (for example -196608) is also treated as a failure.
- Known limitation: a folder name that wraps the name of an existing environment variable in `%`, such as `%PATH%`, is rewritten by Windows before `시작.bat` is opened, so it cannot be fixed. Behaviour when double-clicking in File Explorer was not confirmed.
- One `Guard` test that failed in a folder path containing Korean text was a problem on the test side (the test helper wrote its temporary file without a BOM); the product code was fine. Fixed.
- Added `.omc/`, `.codex/` and screen captures (`captures/`, `*.png`, `*.jpg`) to `.gitignore`, because a capture can show the names of other chat rooms.
- Added 8 tests (6 for `시작.bat` by folder name, 1 for the Korean message on failure, 1 for `.gitignore`).

</details>

<details>
<summary><strong>GitHub private repository and license added</strong> — tests 148 → 149</summary>

- Added `LICENSE` (the full Apache License 2.0 text, owner SoDam AI Studio) at the root. The text was taken from GitHub's license API and compared with the original on the Apache Software Foundation's site; the only change is one copyright line.
- Added `.gitignore` (excludes session records, checkpoints and secret values) and `.gitattributes` (fixes line endings). This is so that the tests give the same result even when the repository is received on another PC.
- Rewrote Chapter 17 (license and commercial use) from "no license" to the Apache License 2.0, and completed Chapter 4 (how to get it), Chapter 6 (environment variables), Chapter 13 (file locations) and Chapter 18 (build and deployment).
- Added 1 LICENSE test (the full text, the latest version 2.0, the owner, and agreement between the two guides).
- The repository is created as a private GitHub repository, and is run so that nothing is pushed straight to `main`; work goes through a working branch and a pull request.

</details>

<details>
<summary><strong>This guide added</strong> — tests 121 → 148</summary>

- Four guide files (md and html, Korean and English) were added to the top-level project folder.
- `tools\Build-Readme.ps1` was added. It builds the html automatically from the md source so that the two documents cannot drift apart.
- 27 guide tests were added. They check that the test counts, command status, version, quoted on-screen messages, links and the structure of the Korean and English versions match reality.

</details>

<details>
<summary><strong>Verification round 2: handling the independent reviewer's findings</strong> — tests 118 → 121</summary>

- The room-name comparison was not exact. The PowerShell 5.1 comparison ignores invisible characters (such as zero-width characters), so a room with a different name could be mistaken for an allowed room. It now compares character for character.
- The check for consent was loose. `false`, `0` or `"no"` in the settings file counted as consent. It now accepts only the date text that the kit itself writes.
- If two rooms with the same name appeared through hand editing, you could not even delete them. Deleting (a change that reduces permissions) is now allowed.
- Not fixed, but written down as "known limits": how `kakao.cmd` interprets arguments, nicknames that contain `]`, a message line that looks like a date divider, the parsing speed for 100,000 messages, and `%` in the folder name.

</details>

<details>
<summary><strong>Verification round 1: tests with wrong input</strong> — tests 105 → 118</summary>

- Fixed permission values in a hand-edited settings file (the text "true", the number 1, an array) being accepted as "allowed". Only a real `true` is allowed now.
- Fixed a settings file that was damaged into `[]` or a single word not being recognised as damaged.
- When saving the settings failed, an English system error appeared; it was replaced with a Korean message.
- Room names with invisible characters or 101 or more characters are refused.
- Export parser: fixed English errors or wrong times from strange dates and times, messages without text being merged into the previous message, an English error when given a folder path, and files whose line ends are only CR not being readable.
- Confirmed that 20 kinds of command-line special characters (`& | ^ ! ; $()`, Korean text, emoji, 6000 characters, etc.) are not executed as commands. (Corrected on 2026-10-31: this holds only when they are quoted or when `src\kakao.ps1` is called directly. A `&` or `|` that reaches `kakao.cmd` without quotes does run. See "Known limits" in chapter 12.)

</details>

<details>
<summary><strong>Step 6: reading export files (parser)</strong></summary>

- Made a function that turns KakaoTalk's official export file into the room name, saved time and a message list (sender, time, text).
- It handles 12 o'clock AM/PM, messages whose text starts with `[`, multi-line messages, and differences in BOM and line ends (CRLF/LF/CR).
- Fixed the last message of one file leaking into the next file.

</details>

<details>
<summary><strong>Step 5: clipboard preservation</strong></summary>

- It saves the text you copied, puts the text to send, restores the original, and checks each step. It stops if an image or a file is on the clipboard.
- Bug fix: when the Windows clipboard history or a capture tool briefly held the clipboard, an "empty text" was trusted as the original and restored, which could overwrite the user's clipboard with empty text. Reading is now retried and checked.
- A mark asking to exclude the pasted text from clipboard history and cloud sync is attached.

</details>

<details>
<summary><strong>Step 4: key input layer and gatekeeper</strong></summary>

- Built key-input sending in C# and bundled checking and input into a single action.
- Fixed the 8 problems pointed out by the security review. Typical ones: `throw` being ignored depending on the caller's error setting so that the gatekeeper opened (every function now fixes the error setting on its first line, enforced by an automated test), a click going to the current cursor position instead of the checked coordinates, and a gap between checking and input.
- Added human-hand detection, a held-key check, a lock against running twice, and display scaling (DPI) support.

</details>

<details>
<summary><strong>Step 3: records (log) and error report</strong></summary>

- Added a record function that cannot hold message text, tidying of the file at 1 MB, and building of the error report text.

</details>

<details>
<summary><strong>Step 2: settings, allowed list, consent</strong></summary>

- Made the allowed room list, per-room permissions and consent to use. Changing the allowed list and giving consent can be done only by a person.

</details>

<details>
<summary><strong>Step 1: starting frame</strong></summary>

- Made the Korean message dictionary, the folder structure, `시작.bat`, `kakao.cmd` and `kakao version`.
- Enforced the rules against Korean text corruption (`.ps1` with BOM, `.bat` and `.cmd` without BOM + CRLF) and the no-administrator rule with automated tests.

</details>

<details>
<summary><strong>What comes next (steps 7-13)</strong></summary>

- 7: opening a room (left: connecting it to a command and testing other tabs, the 100% monitor and ordinary rooms; the whole `Ctrl+F` flow passed once on 150% on 2026-11-12) / 9: export, read, search (first) / 8: sending a message (after step 9, after a separate approval) / 10: status, version, login guidance / 11: command router, menu, help / 12: first run, update, uninstall / 13: acceptance test, final guide
- Tests that operate the real KakaoTalk are run only after the user explicitly says to start, for no more than 60 seconds at a time, with one sub-step per round. The user must keep their hands off the keyboard and mouse meanwhile. Each screen capture is approved one by one and deleted right after checking.

</details>

<a id="troubleshooting"></a>
## 15. Troubleshooting

### By symptom

| Symptom | Cause | Fix |
|---|---|---|
| When you open `시작.bat` the black window flashes and disappears | You ran it from inside the compressed file, or the folder name is in the `%NAME%` form such as `%PATH%`. | Extract everything, move it to a place with a short English-and-digits folder name, and run it again. When it cannot run, the window shows a message saying it could not run. |
| `'kakao.cmd' is not recognized as an internal or external command` (on Korean Windows, a Korean message with the same meaning) | A Windows setting stops it from finding programs in the current folder by name alone. | Put `.\` in front, as in `.\kakao.cmd version`, or run it with the full path. |
| `kakao version` does not work in PowerShell | PowerShell does not run programs in the current folder without `.\`. | Type `.\kakao.cmd version`. |
| Korean text shows as `???` or strange characters | A problem with the window's character table, or a `.ps1` file was saved without BOM. | Run it with `시작.bat`. If you need to edit a file, save `.ps1` as "UTF-8 with BOM" or repair it with `tools\Write-Bom.ps1 -All`. |
| An execution policy error such as "running scripts is disabled on this system" | A management policy on a company or school computer is blocking it (this case was not checked). | The kit allows scripts for this run only with `-ExecutionPolicy Bypass`, but a higher-level policy may win. Ask the computer administrator. Do not change the policy on your own. |
| Antivirus or SmartScreen shows a warning | Programs that imitate key input can be treated as suspicious (this case was not checked). | Do not add an exception before you have confirmed where it came from. Every file is a text file, so you can open it and read the content yourself. If it is a compressed file from GitHub, before extracting it right-click it and, if "Unblock" is shown in Properties, tick it (this was not checked on this PC). |
| `알 수 없는 명령입니다: help` (Unknown command: help) | `help` has not been built yet. | Look at the table in Chapter 8 for the commands you can use. |
| `send`, `read` and others are all "unknown command" | They are not built yet. | Check the status (✅/⏳) in the table in Chapter 8. |
| `설정 파일을 읽을 수 없습니다. 파일이 손상되었을 수 있습니다: <파일 경로>` (The settings file cannot be read. The file may be damaged: path) | `config.json` is damaged, or its syntax broke while editing by hand. | Rename the file to `config.json.bak` to keep it. The kit starts with defaults, and the allowed list and consent are reset. |
| `설정 파일을 저장하지 못했습니다. 폴더 권한이나 디스크 공간을 확인해 주세요: <파일 경로>` (The settings file could not be saved. Check folder permissions or disk space: path) | No permission on the folder, or not enough disk space. | Check the permissions and free disk space of the `%LOCALAPPDATA%\KakaoKit` folder. |
| `시험해 본 적 없는 카카오톡 버전이라 보내기가 잠겨 있습니다. 읽기만 할 수 있습니다. 아무것도 보내지 않았습니다.` (This KakaoTalk version has never been tested, so sending is locked. Reading only. Nothing was sent.) | The installed KakaoTalk version is not on the "tested versions" list in `config\verified-versions.json`. This lock check (exit code 4) is built as a part but not yet connected to sending, so this message cannot appear yet. | A person decides the list (an AI does not change it). Add a version only after its real tests are finished. |
| `보낼 글이 올바르지 않습니다. 비어 있거나, 1000자를 넘거나, 줄바꿈·탭 말고 눈에 보이지 않는 조작 문자나 깨진 글자가 들어 있으면 안 됩니다. 아무것도 보내지 않았습니다.` (The text to send is not valid. It must not be empty, longer than 1000 characters, or contain invisible control characters or broken characters other than line breaks and tabs. Nothing was sent.) | The text is empty (blank counts too), longer than 1000 characters, or has a hidden control character or a broken character (an unpaired UTF-16 half). The sending part refused it before any input (sending is not connected to a command yet, so this cannot appear yet). | Fix the text and try again. |
| `호출한 쪽(사람 또는 AI)을 정확히 밝혀야 합니다. 아무것도 보내지 않았습니다.` (The caller (a person or an AI) must be stated exactly. Nothing was sent.) | When calling send, it was not stated exactly whether the caller is a person or an AI (there is no default, so a call that forgets it cannot gain a person's rights). | State `human` for a person or `ai` for an AI exactly. |
| `시도 번호는 영문·숫자·밑줄·붙임표로 64자 이내여야 하고, AI 가 부를 때는 반드시 있어야 합니다. 아무것도 보내지 않았습니다.` (The attempt number must be letters, digits, underscores or hyphens, up to 64 characters, and it is required when an AI calls. Nothing was sent.) | The attempt number has other characters (a trailing line break counts), or is too long. Or an AI asked for a real send without a number (without one, running the same command again cannot be stopped from sending twice). | Use only letters, digits, `_` and `-`, up to 64 characters. An AI must always give a number. |
| `동시에 두 번 실행되지 않게 하는 실행 잠금을 잡지 않아서 보내지 않았습니다. 명령으로 실행하면 자동으로 잡힙니다. 아무것도 보내지 않았습니다.` (The run lock that prevents two runs at once was not held, so nothing was sent. Running it as a command takes it automatically. Nothing was sent.) | A real send must run one at a time (if the interval and attempt record are written over each other, a duplicate send cannot be stopped). This part does not take the lock itself; it only checks that it is held. | Running it through a command (`시작.bat` or `kakao`) takes it automatically. The command is connected and real sending is locked, so this cannot appear yet. |
| `보내기는 아직 연결되지 않았습니다. 입력란 위치를 측정하기 전이라 안전을 위해 잠가 두었습니다. 아무것도 보내지 않았습니다.` (Sending is not connected yet. It is locked for safety until the position of the input box is measured. Nothing was sent.) | Real sending is locked on purpose until the position of the input box is measured. | This is normal. It opens only after the position is measured and the user approves. |
| `보내기 전에 확인이 필요합니다. 미리보기만 하려면 --dry-run, 보내려면 확인(--yes)이 필요합니다. 아무것도 보내지 않았습니다.` (Confirmation is needed before sending. Use --dry-run to only preview, or confirm with --yes to send. Nothing was sent.) | The confirmation for sending is missing. | Add `--dry-run` to preview, or `--yes` to really send. |
| `직전 보내기 뒤 2초가 지나지 않았습니다. 잠시 뒤에 다시 하세요. 아무것도 보내지 않았습니다.` (Two seconds have not passed since the last send. Try again shortly. Nothing was sent.) | The 2-second interval rule that prevents rapid repeated sending. It also stops if the clock was set backwards. | Wait a moment and try again. |
| `보내기 간격·시도 기록을 읽거나 쓸 수 없어 보내지 않았습니다. 폴더 권한을 확인하거나 이 파일을 지우고 다시 하세요: <파일 경로>` (The send interval and attempt record could not be read or written, so nothing was sent. Check the folder permissions or delete this file and try again: path) | The interval and attempt record file is damaged or cannot be written. Without it a duplicate send cannot be prevented, so the kit stops. | Check the folder permissions. If the file is damaged, delete just that one file (the record of attempt numbers is reset). |
| `같은 시도 번호로는 다시 보낼 수 없습니다(중복 전송 방지). 방에서 보내졌는지 직접 확인한 뒤, 새로 보내려면 새 시도 번호로 하세요. 아무것도 보내지 않았습니다.` (The same attempt number cannot be sent again (to prevent a duplicate). Check in the room whether it was sent, and to send anew use a new attempt number. Nothing was sent.) | The attempt number was already used. | Check in the room first, and if you must send again use a new number. |
| `이미 열려 있는 방이라 보내지 않았습니다. 그 방 창을 닫고 다시 하세요(키트가 연 창에만 보냅니다). 아무것도 보내지 않았습니다.` (That room was already open, so nothing was sent. Close that room window and try again (the kit sends only to a window it opened). Nothing was sent.) | The room window is already open. There is no way to check whether an unfinished message sits in its input box, so the kit sends only to a window it opened itself. | Close the room window and try again. |
| `이 방은 "초안을 남기지 않는 방"으로 표시되어 있지 않아 AI 는 보낼 수 없습니다. 카카오톡은 방 창을 닫았다 열어도 쓰다 만 글을 남기므로, 그 위에 덧붙어 잘못 전송될 수 있습니다. 사람이 이 방에 초안을 쓰지 않기로 하고 표시해야 합니다(kakao rooms set 방이름 noDraft on --human). 아무것도 보내지 않았습니다.` (This room is not marked as a "room where no unfinished message is left", so an AI cannot send to it. KakaoTalk keeps an unfinished message even after the room window is closed and reopened, so new text could be appended to it and sent by mistake. A person must decide not to leave drafts in this room and mark it (kakao rooms set RoomName noDraft on --human). Nothing was sent.) | An AI tried to send but a person has not marked that room as draft-free. A test confirmed that an unfinished message stays after closing and reopening the room window (2026-11-14), and an AI cannot ask a person "is it empty?", so it sends only to rooms a person decided on beforehand. | After deciding not to leave unfinished messages in that room, mark it with `kakao rooms set RoomName noDraft on --human`. |
| `입력란이 비어 있다는 확인을 받지 못해 보내지 않았습니다. 방 창의 입력란을 직접 비운 뒤 다시 하세요. 아무것도 보내지 않았습니다.` (No confirmation that the input box is empty, so nothing was sent. Empty the input box in the room window yourself and try again. Nothing was sent.) | When a person sends, they did not answer y to "is it empty?", or the answer could not be collected. | Empty the input box in the room window yourself and try again. |
| `입력란이 비어 있습니까? (방: <방 이름>) 쓰다 만 글이 있으면 그 뒤에 덧붙어 전송됩니다. 비어 있으면 y, 아니면 아무 키나 누르고 Enter:` (Is the input box empty? (Room: <room name>) If an unfinished message is there, new text is appended and sent after it. Press y if it is empty, or any other key then Enter if not.) | The question the kit asks a person who is sending, after opening the room and before touching the input box (not an error). The kit uses no delete keys, so it cannot tell by itself whether the box is empty. | Look at the input box in the room window; press y then Enter only if it is empty. If text is left, press another key to stop and empty it yourself. |
| `입력은 보냈지만 보내졌는지 확인하지 못했습니다. 방에서 직접 확인해 주세요(글이 보내졌거나 입력란에 남아 있을 수 있습니다). 확인하기 전에는 다시 보내지 마세요(중복 전송될 수 있습니다).` (The input was sent, but it could not be confirmed that the message went through. Please check in the room (it may have been sent or may remain in the input box). Do not send again before checking (it could be sent twice).) | The result is "unknown". The key input went out, but the feature that reads the room to confirm it (the export read) is not connected yet, or the check failed. | Open the room and check yourself. Do not send the same text again before checking. The kit never resends on its own. |
| `보낸 뒤 키트가 연 방 창을 닫지 못했습니다. 창이 남아 있으면 직접 닫아 주세요.` (After sending, the kit could not close the room window it had opened. If the window remains, please close it yourself.) | Sending finished, but the request to close the kit-opened window failed. The result of sending is not affected. | If the window remains, close it yourself. |
| `사용법: kakao send --room 방이름 (--text 글 또는 --file 파일) [--dry-run] [--yes] [--attempt-id 번호] [--human]  (--text 와 --file 은 하나만, 같은 옵션은 한 번만, 값은 --로 시작하면 안 됩니다) 아무것도 보내지 않았습니다.` (Usage: kakao send --room room-name (--text text or --file file) [--dry-run] [--yes] [--attempt-id number] [--human]  (Only one of --text and --file, each option only once, and a value must not start with --.) Nothing was sent.) | The options of the send command are wrong (an unknown option, a repeated option, a missing value, no room name, both or neither of text and file, or a value starting with `--`). | Type it again as in the usage. Send text that starts with `--` through `--file`. |
| `글 파일을 읽지 못했습니다. 파일이 없거나, 8KB 를 넘거나, UTF-8 글이 아닙니다. 아무것도 보내지 않았습니다.` (The text file could not be read. The file is missing, over 8 KB, or not UTF-8 text. Nothing was sent.) | The file given to `--file` cannot be read. | Check the path, the size (8 KB or less) and the encoding (UTF-8). |
| `미리보기: 검사를 모두 통과했습니다. 아무것도 보내지 않았습니다. (방: <room name>)` (Preview: every check passed. Nothing was sent. (Room: ...)) | The result of `--dry-run`. All checks before sending passed, and nothing was sent. | To send, remove `--dry-run` and add `--yes` (after sending is opened). |
| `보냈고 방에서 확인했습니다. (방: <room name>)` (Sent and confirmed in the room. (Room: ...)) | The sent text was seen to appear in the room. | This is normal. |
| `예상하지 못한 오류로 멈췄습니다. 방에서 보내졌는지 직접 확인해 주세요. 확인하기 전에는 다시 보내지 마세요.` (Stopped by an unexpected error. Please check in the room whether it was sent. Do not send again before checking.) | An unexpected error. The raw error text is not shown because it could contain the message body. | Check in the room yourself; if it keeps happening, look at the error report (the records). |
| `카카오톡 창이 맨 앞에 있지 않습니다. 카카오톡 창을 한 번 클릭해 주세요. 최대 <seconds>초 기다립니다. 그동안 키트는 아무것도 입력하지 않습니다.` (The KakaoTalk window is not in front. Please click the KakaoTalk window once. It waits up to ... seconds. Meanwhile the kit types nothing.) | The kit cannot bring KakaoTalk to the front by itself, so before any input it waits for a person to click the window once (it goes on when the window has been in front for 2 seconds in a row, and stops with no input if that does not happen within 120 seconds). This waiting part is built and tested but not yet placed in the sending or room-opening flow. | Click the KakaoTalk window once and take your hands off. After 120 seconds it stops with `대상 창이 맨 앞에 있지 않습니다. 입력하지 않았습니다.`. |
| `명령 사용법이 올바르지 않습니다. 사용법: <usage>` (The command usage is not correct. Usage: ...) | The options of `rooms`, `read`, `search` or `status` are wrong (an unknown option, a repeated option, a missing value, a value starting with `--`, the wrong number of arguments, or a wrong letter case). The usage of that command follows. | Type it again as in the usage shown. |
| `예상하지 못한 오류로 멈췄습니다. 기록(로그)의 마지막 줄을 확인해 주세요.` (Stopped by an unexpected error. Please check the last line of the records (log).) | `rooms`, `read`, `search` or `status` stopped by an unexpected error. The raw error text is not shown because it could contain chat content. | Check the last line of the records. If it continues, send the error report. |
| `허용된 방이 없습니다. 사람이 방을 허용 목록에 넣어야 합니다(rooms add).` (There are no allowed rooms. A person must put a room on the allowed list (rooms add).) | The allowed list is empty. | A person adds a room with `rooms add <room> --type open --human`. |
| `방 이름 \| 종류 \| 사람 읽기 \| AI 읽기 \| 사람 보내기 \| AI 보내기` (Room name \| kind \| person read \| AI read \| person send \| AI send) | The header line of the `rooms list` table. Under it, each line shows the room name, the kind, and each permission as `예` (yes) or `아니오` (no). A value that is not a real true counts as `아니오`. | Normal output; nothing to do. |
| `허용 목록에 넣었습니다: <room name>` (Put on the allowed list: ...) | `rooms add` succeeded. | Read the note that follows. |
| `키트는 카카오톡 검색으로 이 방이 맞는지 확인하지 않았습니다. 같은 이름의 방이 하나뿐인지 직접 확인하세요. 처음에는 AI 읽기·보내기가 모두 꺼져 있습니다.` (The kit did not check through the KakaoTalk search that this is the right room. Check yourself that there is only one room with this name. AI read and send are both off at first.) | `rooms add` registers by name only (the KakaoTalk search check is ⏳), so a different room with the same name could be opened. AI permissions are all off at first. | Check in KakaoTalk that there is only one room with that name. To let an AI read it, use `rooms set <room> aiRead on --human`. |
| `허용 목록에서 뺐습니다: <room name>` (Removed from the allowed list: ...) | `rooms remove` succeeded. | This is normal. |
| `권한을 바꿨습니다. (방: <room name>)` (Permission changed. (Room: ...)) | `rooms set` succeeded. | This is normal. Check with `rooms list`. |
| `조건에 맞는 메시지가 없습니다.` (No messages match the condition.) | No message in the kept file matches the period or count of `read`. A message whose time is unknown is left out when `--since` is used. | Widen the period. |
| `찾은 메시지가 없습니다.` (No messages were found.) | `search` found nothing. When called as an AI, rooms with `aiRead` off are not searched, so their text counts as absent. | Change the word, or a person turns the permission on with `rooms set <room> aiRead on --human`. |
| `카카오톡이 설치되어 있지 않거나 설치 정보를 읽지 못했습니다.` (KakaoTalk is not installed, or its installation information could not be read.) | `status` could not find the KakaoTalk installation information. The sending mode is then read-only. | Check that KakaoTalk is installed. |
| `카카오톡 실행 중: <예 or 아니오>` (KakaoTalk running: yes or no) | `status` shows whether a KakaoTalk process is running. | Normal output. |
| `보내기 모드: 전체 (시험해 본 카카오톡 버전)` (Sending mode: full (a KakaoTalk version that was tested)) | The installed KakaoTalk version is in the tested list. | This is normal. |
| `보내기 모드: 읽기 전용 (시험해 본 적 없는 버전이라 보내기가 잠겨 있습니다)` (Sending mode: read-only (this version was never tested, so sending is locked)) | The version was never tested (or could not be confirmed), so sending is locked. Reading works. | This is normal. Putting a version on the verified list is decided by a person after testing. |
| `허용된 방: <count>개` (Allowed rooms: ...) | `status` shows the number of rooms on the allowed list. | Normal output. |
| `AI 가 읽을 수 있는 방: <count>개` (Rooms an AI can read: ...) | `status` shows the number of rooms with AI read turned on. | Normal output. |
| `AI 가 보낼 수 있는 방: <count>개` (Rooms an AI can send to: ...) | `status` shows the number of rooms with AI send turned on (the mode and the sending lock apply separately). | Normal output. |
| `실제 보내기는 아직 잠겨 있습니다(입력란 위치를 측정하기 전).` (Real sending is still locked (before the position of the input box is measured).) | `status` tells you the sending lock has not been released. | This is normal. It opens only after the position is measured and the user approves. |

### When the safety device stopped the work (messages that appear once the feature is connected)

**Read this first.** The Korean "입력하지 않았습니다" (no input was made) at the end of the messages below means that **the one input where it stopped** (a click or a key) was not made. In a job made of several inputs, such as opening a room, the inputs before it (for example the first click) may already have gone out. In the S5 run on 2026-11-12 this was misread and an earlier click that had gone out was missed. So read which inputs went out from the job's steps (opening a room: `Ctrl+F` → `Ctrl+V` → … → double-click), not from the message alone.

These messages are already in the code, but the matching commands are not connected yet, so you cannot see them on screen now. The kit always prints them in Korean; the meaning is given here.

| Message on screen | Meaning | What to do |
|---|---|---|
| `키보드나 마우스를 쓰는 중이라 시작하지 못했습니다. 잠시 손을 떼고 다시 해 주세요.` | A person's input was detected before starting. | Take your hands off the keyboard and mouse and run it again. |
| `키보드나 마우스를 쓰신 것이 감지되어 작업을 중단했습니다. 작업 중에는 손대지 말아 주세요.` | A person's input was detected during the work. | Do not touch anything until the work is finished, and run it again. |
| `대상 창의 제목이 예상과 다릅니다. 입력하지 않았습니다. (예상: <방 이름>)` | The window that is open is not the allowed room. No key was sent. | Check the room name and the allowed list. |
| `대상 창이 맨 앞에 있지 않습니다. 입력하지 않았습니다.` | Another window came to the front. | Close or minimise the other window and run it again. |
| `대상 창이 카카오톡이 아닙니다. 입력하지 않았습니다.` | The window it was going to type into does not belong to KakaoTalk. | Open KakaoTalk again and run it. |
| `다른 키트 작업이 이미 실행 중입니다. 끝난 뒤 다시 해 주세요.` | The kit is already doing another job. | Wait for it to finish and run it again. |
| `다른 키가 눌려 있어 입력하지 않았습니다. 키보드에서 손을 떼 주세요.` | A key was being held down (the Hangul/English key is not counted). Either a key was being pressed, or the keyboard or input method keeps reporting a released key as held. | Release all keys and run it again. If it keeps appearing with your hands off, replug the keyboard into another USB port or try another keyboard, and if it is still the same, tell the developer which key appears to be held. |
| `클릭할 위치가 창 밖입니다. 입력하지 않았습니다.` or `클릭할 자리가 다른 창에 가려져 있습니다. 입력하지 않았습니다.` | The place to click is not safe. It did not click. | Keep the KakaoTalk window in front and uncovered, then run it again. |
| `클립보드에 이미지나 파일이 들어 있어 작업하지 않았습니다. 클립보드를 비우거나 글자를 복사한 뒤 다시 해 주세요.` | Something that is not text is copied, so it cannot be restored. | Empty the clipboard or copy some text, then run it again. |
| `클립보드를 다른 프로그램이 쓰고 있어 작업하지 못했습니다. 잠시 뒤 다시 해 주세요.` | Another program is holding the clipboard. | Run it again a little later. |
| `클립보드를 원래대로 되돌리지 못했습니다. 복사해 두었던 내용이 바뀌었을 수 있습니다.` | Restoring failed, so what you had copied may have changed. | Copy the text you need again. |
| `이 작업은 사람이 직접 해야 합니다. 자동 실행으로는 할 수 없습니다.` | Changing the allowed list or giving consent was tried by automated execution. | Open `시작.bat` and do it yourself. |
| `먼저 사용 동의가 필요합니다. 시작.bat 을 열어 안내에 따라 동의해 주세요.` | No command runs before consent is given. | Open `시작.bat` and give consent by following the guidance. |

### When opening a room stopped (messages that appear once the feature is connected)

Every message below means the kit stopped. If it stopped after the double-click, the room may already have been opened. The feature is not connected to a command yet, so you cannot see these on screen now. The kit always prints them in Korean; the meaning is given here.

| Message on screen | Meaning | What to do |
|---|---|---|
| `허용 목록에 없는 방이라 열지 않았습니다: <방 이름>` | The room is not an allowed one, so no input was made. | Check the room name and the allowed list. Only a person can change the allowed list. |
| `카카오톡 메인 창을 하나만 찾지 못했습니다. 카카오톡이 실행 중인지, 로그인되어 있는지 확인해 주세요. 방을 열지 않았습니다.` | There is no KakaoTalk main window, or there are two or more. | Start KakaoTalk and log in, make sure only one main window is visible, and run it again. |
| `같은 제목의 창이 둘 이상 있어 어느 창인지 알 수 없습니다. 아무것도 하지 않았습니다. (방: <방 이름>)` | Several windows have the same name, so it cannot tell which one is meant (it checks both before and after opening). | Close the duplicate windows so only one is left, and run it again. |
| `화면 글자 읽기(OCR)를 쓸 수 없어 검색 결과가 정확히 1건인지 확인하지 못했습니다. 방을 열지 않았습니다.` | Korean text reading is not available, so the search result could not be checked. | Check that Windows has Korean text reading (Chapter 3). A person can allow "open without checking", but that is not recommended because another room might be opened. |
| `카카오톡이 오픈채팅 탭이 아니어서 방을 열지 않았습니다. 아무것도 클릭하지 않았습니다. 오픈채팅 탭으로 바꾼 뒤 다시 시도하세요.` | The top line did not show both the title "채팅" (chats) and the branch label "오픈채팅" (open chat), which is the case on the friends tab and others. The kit stops before the first input so that it does not start opening a room on another screen (it is not confirmed that `Ctrl+F` opens the same search box on other tabs). No click or key was sent. | Switch KakaoTalk to the open-chat tab and run again. If it still appears on the open-chat tab, the window is covered or the text sits somewhere other than the reference. |
| `검색 결과가 정확히 1건인지 확인하지 못해 방을 열지 않았습니다. (방: <방 이름>)<설명>` | The search result is not exactly one room name, or the screen differs from the reference, so it could not be checked. It did not double-click. The `<설명>` after it tells the cause, in one of the two ways below. If there is no explanation, other rows are mixed into the result or the screen layout (tab and so on) differs from the reference. | Act on the explanation and run it again. |
| “카카오톡 창 크기가 기준과 다릅니다(지금 가로x세로, 모니터 배율 N%, 기준 가로x세로). 창 크기를 바꾸지 말고 원래 크기로 두거나, 창을 쓰던 모니터로 옮겨 주세요.” (the explanation after the message above) | The KakaoTalk window size was changed, or the window was moved to a monitor with different display scaling. The defect where this message appeared on a 150% monitor even though the size was not changed (the scaling was misread as 100%) was fixed on 2026-11-11 (item 10 of 12.3). If this message appears now, the window size really differs from the reference. | Do not touch the window size: keep the original size, or move the window back to the monitor it was used on. It has passed on the 100% monitor, so try it there (whether the size matches the reference right after moving from the 150% monitor to the 100% monitor was not checked). |
| “카카오톡 창의 검색 결과 부분이 다른 창에 가려져 있습니다. 가리는 창을 치워 주세요.” (the explanation after the message above) | Another window covers the search-result area. | Move the covering window away and run it again. |
| `방 창이 시간 안에 열리지 않았습니다. 아무 창도 닫지 않았습니다. (방: <방 이름>)` | The room window did not appear within 8 seconds after the double-click. | Check by yourself whether the room window appeared late. The room may already have been opened. |
| `열린 창의 제목이 방 이름과 달라 그 창을 닫고 멈췄습니다. 더 입력하지 않았습니다.` | The window opened by the double-click was not the allowed room, so only that window was closed and it stopped. | Check that no other room has a similar name and that the search result is right. That room was already opened, so a read mark is likely to have appeared. |
| `검색 결과를 확인하지 않고 방을 열었습니다(사람이 허용). 다른 방이 열렸을 수 있습니다.` | A warning that a person allowed "open without checking", so the result was not checked. | Check by yourself that the room that opened is the right one. |

### Other messages (messages that appear once the feature is connected)

These messages are also already in the code, but the matching commands are not connected yet, so you cannot see them on screen now. Where a row says "program error", it is not your fault: an internal check of the kit stopped it, so please tell the developer.

| Message on screen | Meaning | What to do |
|---|---|---|
| `대상 창 제목이 정해지지 않아 입력하지 않았습니다.` | There was no window title to check before input (program error). No input was made. | Tell the developer. |
| `작업을 시작하기 전 확인(키보드·마우스에서 손 떼기)이 먼저 필요합니다. 입력하지 않았습니다.` | It tried to send input without the hands-off check (program error). No input was made. | Tell the developer. |
| `허용되지 않은 키라서 보내지 않았습니다: <키 이름>` | It tried to send a key that is not among the 5 allowed keys (program error). It was not sent. | Tell the developer. |
| `허용되지 않은 키 조합이라 보내지 않았습니다.` | The input layer (C#) checked once more and blocked it (program error). | Tell the developer. |
| `마우스 위치가 바뀌어 클릭하지 않았습니다.` | The mouse moved after the check and before the click. It did not click. | Take your hand off the mouse and run it again. |
| `입력을 보내지 못했습니다.` | Windows did not accept the key or mouse input. | Put the KakaoTalk window in front and run it once more. If the same message keeps appearing, tell the developer. |
| `카카오톡 창이 아니라서 닫지 않았습니다.` | The window it was going to close does not belong to KakaoTalk, so no close request was sent. | Nothing happened. Close that window yourself if you need to. |
| `이 실행 방식에서는 클립보드를 쓸 수 없습니다. 시작.bat 이나 kakao.cmd 로 실행해 주세요.` | The clipboard can be used only in the intended way of running. | Run it with `시작.bat` or `.\kakao.cmd`. |
| `클립보드에 글을 넣지 못했습니다. 입력하지 않았습니다.` | The text to send was put on the clipboard, but it could not be confirmed that it arrived. | Run it again a little later. Check whether another program is holding the clipboard. |
| `이 작업은 키보드로 직접 입력하는 창에서만 할 수 있습니다. 시작.bat 으로 여세요.` | A job only a person may do was tried while the input comes from a file or another program. | Open `시작.bat` and type it yourself on the keyboard. |
| `방 이름이 올바르지 않습니다. 비어 있거나, 앞뒤에 공백이 있거나, 줄바꿈이나 보이지 않는 글자가 들어 있거나, 100자를 넘으면 안 됩니다.` | The room name breaks the rules (empty, spaces at the ends, a line break or invisible character, or over 100 characters). | Fix the room name so that it follows the rules. |
| `이미 등록된 방입니다: <방 이름>` | A room with the same name is already on the allowed list. | It is already registered, so just use it. |
| `등록되지 않은 방입니다: <방 이름>` | It tried to change the permissions of, or remove, a room that is not on the allowed list. | Check the room name. |
| `방 종류가 올바르지 않습니다: <값>  (open, self, normal 중 하나)` | A value that is not allowed was given as the room kind. | Change it to one of `open`, `self` or `normal`. |
| `권한 이름이 올바르지 않습니다: <값>  (aiRead, aiSend, canSend, noDraft 중 하나)` | The permission name is wrong. | Change it to one of `aiRead`, `aiSend`, `canSend` or `noDraft`. |
| `내보내기 파일을 찾을 수 없습니다: <파일 경로>` | The export file to read is not at that path. | Check the path and the file name. |
| `카카오톡 내보내기 파일이 아닙니다: <파일 경로>` | The first line of the file is not in the KakaoTalk export format. | Specify a text file saved with KakaoTalk's chat export. |
| `허용 목록에 없거나 읽기가 허용되지 않은 방이라 읽지 않았습니다: <방 이름>` | The room to read or search is not on the allowed list, reading is switched off, or an AI called and AI reading is switched off for that room. Nothing was read. | Check the room name. A person has to change the allowed list and permissions. |
| `저장된 내보내기 파일이 아직 없습니다. 먼저 대화를 내보내 주세요. (방: <방 이름>)` | There is no exported file in that room's store. | Export the chat and keep it first. |
| `내보내기 파일의 방 이름이 등록된 방과 달라 저장하지 않았습니다. (방: <방 이름>)` | The room name on the first line of the file is not letter for letter the registered room name. Nothing was saved, so that another room's chat is not kept under this room's name. | Check that it is the export file of the right room. If it keeps appearing for the same room, tell the developer. |
| `내보내기 파일을 보관하지 못했습니다. 폴더 권한이나 디스크 공간을 확인해 주세요.` | The keeping folder could not be created or the file could not be copied. | Check the permissions and free disk space of the `%LOCALAPPDATA%\KakaoKit` folder. |
| `읽을 개수와 기간은 0보다 커야 합니다.` | A value of 0 or less was given for the number or the period to read. | Change it to a value of 1 or more. |
| `검색할 낱말을 입력해 주세요.` | The word to search for is empty or only blanks. | Write the word to look for. |
| `화면 글자를 읽지 못했습니다.` | On-screen text reading did not finish within 15 seconds, or it failed. | Check that the KakaoTalk window is visible and run it again. |
| `기록(로그)을 파일에 쓰지 못했습니다. 동작은 계속합니다.` | The record file could not be written, but the work went on (a warning). | Check the permissions and free disk space of the `%LOCALAPPDATA%\KakaoKit` folder. |

### When you report a problem

For now, the message shown on screen and `%LOCALAPPDATA%\KakaoKit\logs\kakao.log` (if it exists) are your clues. The part that builds an error report exists, but it is not connected to a command yet (⏳ step 11). The report contains no chat content but may contain room names, so check it before sending it to anyone. The report holds, under the title `카카오톡 키트 오류 보고서 (대화 내용은 들어 있지 않습니다)`, the kit, KakaoTalk, Windows and PowerShell versions, whether it runs as administrator, and the last 50 record lines.

<a id="faq"></a>
## 16. Frequently asked questions (FAQ)

**Q1. Is this an official program made by Kakao?**

No. It is an unofficial tool that has no relationship with Kakao. See [Chapter 17](#legal) for details.

**Q2. Will my KakaoTalk account be suspended if I use it?**

Unknown. It was not possible to check whether Kakao's separate operating policy has clauses about automation, and an account restriction is possible. That is why no bulk or repeated sending is built, the sending interval is kept at 2 seconds or more, and testing is done only in a room where I am alone. This lowers the risk but does not remove it.

**Q3. Do I need administrator rights or a UAC window?**

No. At no step does it ask for administrator rights.

**Q4. Do I need the internet?**

The kit does not use the internet. README.html also does not fetch fonts or scripts from the internet, so it opens without an internet connection.

**Q5. Does it store my KakaoTalk password?**

No. It neither stores nor types your password. Log in directly in the KakaoTalk app.

**Q6. Is my chat content sent anywhere?**

The kit does not send chat content outside. However, if you hand a chat you have read to an AI service or the like, that content leaves the computer. That responsibility is the user's.

**Q7. Can I send a message right now?**

No. Sending is planned for step 8, and only `version` works now.

**Q8. Does it work on a Mac or a smartphone?**

No. It is for Windows PCs only.

**Q9. Is it fine that my Windows display is in English?**

Yes. The development PC has an English display, and the kit's messages are always in Korean. Korean Windows and other Windows versions were not checked.

**Q10. What happens when KakaoTalk is updated?**

Only 26.9.0.5337 was verified (KakaoTalk on this PC later updated itself to 26.9.1.5339, where only clicking, pasting, opening a room and closing its window have been tested). In the future, other versions are planned to be allowed to read only, with sending locked (⏳ step 10). The kit does not interfere with KakaoTalk's own updates.

**Q11. May I send messages to friends automatically?**

It is blocked by default. A room with friends is an "unverified type", so only reading works and sending is locked; a person must unlock it by hand, and an AI cannot unlock it. Testing is also done only in a room where I am alone.

**Q12. Why is the `Esc` key not used?**

In KakaoTalk `Esc` closes the chat window. It was a mistake that really happened during development, so it is blocked from ever being sent.

**Q13. Why paste instead of typing the text?**

So that Korean text, emoji and long text do not lose or change characters. In exchange it briefly uses the text you had copied, and puts it back when finished. If an image or a file is copied, it cannot be put back, so the work stops.

**Q14. `시작.bat` closes immediately.**

See the first row in [Chapter 15](#troubleshooting).

**Q15. May I move the folder somewhere else?**

Yes. Move the whole folder. `시작.bat` works even if the folder name contains `^` or `%` (fixed on 2026-10-28). However, a folder name that wraps the name of an existing environment variable in `%`, such as `%PATH%`, is rewritten by Windows first and does not run.

**Q16. May I edit the settings file by hand?**

It is not recommended. It would be a way to change the allowed list by something other than a person, so the kit treats every strange value as "refuse".

**Q17. Is it open source? May I use it at work?**

The license is the open-source Apache License 2.0 (owner: SoDam AI Studio). However, the repository is private for now. The license lets you use it at work too, but Kakao's terms, personal information, advertising rules and trademarks must be checked separately. Please read [Chapter 17](#legal).

**Q18. Can I read this document without the internet?**

Yes. `README.html` is a document that works as a single file; just open it in a browser.

**Q19. Why is reading a chat built before sending a message?**

Because without reading you cannot confirm that a sent message really went through (design document 13.7 reports the result of a send as confirmed, failed or unknown, and says not to resend automatically when it is unknown). Also, if the first `Enter` key is pressed in a file-save window instead of in a message that goes to someone else, a mistake does less harm. The order was changed with the user's approval on 2026-10-30 (Chapter 2).

**Q20. Has opening a room been tested in real KakaoTalk?**

Only in part. On a 100% screen, in a test room where I am alone, "double-click the first result → check the new window's title → close only the window the kit opened" passed (7.4 seconds). The whole flow starting with `Ctrl+F` passed once on the 150% monitor on 2026-11-12; ordinary rooms (1:1 and group chats) have not been tested yet. Opening a room on the 150% monitor was confirmed in that run (item 10 of 12.3). It is also not connected to a command yet, so you cannot call it yourself.

**Q21. Does on-screen text reading (OCR) save my screen or send it out?**

The kit does not. It reads the KakaoTalk window in memory only and writes nothing to disk, and the text it reads is used only to decide the search result and is never logged or printed. The kit's code has no part that connects to the internet (how the text-reading feature inside Windows works internally was not checked). Because other rooms' names can appear on screen, captures taken during development for a person to look at are approved one by one and deleted right after checking.

**Q22. Is it fine if I have several monitors or different display scaling?**

On a 100% monitor, yes. On a 150% monitor, it has not really been tried yet. Opening a room is built to be judged according to the scaling of the monitor the KakaoTalk window sits on, and if the window size differs from the reference it does not open and stops. The defect where the window's scaling was misread as 100% on a 150% monitor, which made it stop there, was fixed (item 10 of 12.3); only reading the scaling correctly has been confirmed. A room was really opened only at 100%. Other scalings such as 125% and 200% were checked only with fake test data. If you move the window to a monitor with different scaling, or change its size, during the work, the safety device stops.

**Q23. Does the owner of this project use it commercially or give it to other people?**

No. On 2026-10-30 the owner decided to use it **for personal use only**. It is not published, officially distributed, given to others or used commercially, and doing any of that needs a lawyer's check first. The Apache License 2.0 allows such uses legally, but the risk from Kakao's operating policy stays. See [Chapter 17](#legal) for details.

<a id="legal"></a>
## 17. Legal, copyright, license and commercial use

> **Please read this first.** This chapter is a summary of general information for **reference only** and does not guarantee legal effect. Responsibility for use rests with **the user.** For anything that needs a firm answer (commercial use, distribution, publication, interpreting the terms, etc.), always check with a lawyer.

### 17.1 Relationship with Kakao and trademarks

- "KakaoTalk" and "Kakao" are service names or trademarks of Kakao Corp.
- This project was **not** made, sponsored, approved or endorsed by Kakao. There is no partnership either.
- The name is used only to tell which program this tool is meant to be used with. If the trademark holder asks, the name may have to be changed.
- The Apache License 2.0 does not grant trademark rights. Using the names "KakaoTalk" and "Kakao", or the name "SoDam AI Studio", as a product name or in advertising is not something this license permits (license section 6).

### 17.2 Kakao's terms of service and operating policy

- At the time of development (2026-10-27), it was confirmed that clause 2.2 of the terms of the KakaoTalk installed on this PC (`EULA_ko.txt` in the install folder) prohibits reverse engineering, decompiling and disassembling. So this kit decided not to use such methods. KakaoTalk later updated itself (26.9.1.5339), and **the terms of the updated version have not been checked again.**
- However, whether Kakao's separate "operating policy" has clauses about automated programs **could not be checked.** So it cannot be said for certain whether using this tool goes against the terms or the operating policy, and there is a possibility of restrictions on the KakaoTalk account (a warning, a temporary suspension, etc.). However, in the Kakao Developers forum on 2026-09-30, a reply to a question about commercializing an open-chat management app that reads the screen automatically and presses KakaoTalk buttons said that the operating policy prohibits "the kind of use you describe". It could not be confirmed whether the person who replied works for Kakao or whether the reply applies as is to this tool (personal use, on my own computer, in a room where I am alone), but treat it as a real possibility that it conflicts and do not rule out the risk.
- Terms and policies can change. Before using the tool, check the latest terms and operating policy yourself.
- This kit is meant for **personal use only** (user decision, 2026-10-30). Knowing the risk above, it is used only with my own account on my own computer, and it is not distributed to others, turned into a public repository or officially released. Before any publishing or distribution, a lawyer should be consulted first (for reference only, with no legal effect).
- The kit's risk-reducing measures (only allowed rooms, no bulk sending, a 2-second gap, human-hand detection) lower the risk but do not remove it.

### 17.3 Copyright and license

- This project is provided under the **Apache License 2.0** (Apache License, Version 2.0, January 2004, the latest version). The full text is in the [LICENSE](LICENSE) file at the top of the repository.
- Copyright holder (owner): **SoDam AI Studio** (`Copyright 2026 SoDam AI Studio`). No personal name or contact is written in this document.
- What the license permits: use, copying, modification, making derivative works, distribution and commercial use. These conditions must be kept: ① hand over a copy of `LICENSE` with it, ② do not remove the copyright, patent, trademark and attribution notices, ③ mark the files you changed with a prominent notice that you changed them (license section 4). This repository has no `NOTICE` file.
- Patents: a person who contributes to this project grants permission to use the patents contained in their contribution, and if someone files a patent lawsuit over this software, that person's patent license ends (license section 3).
- No warranty: the software is provided "AS IS" with no warranty of any kind, and liability for damage caused by using it is limited (license sections 7 and 8). This permission does not permit or waive Kakao's terms, trademarks or the personal-information laws.
- It covers: the code, the documents (including this guide), the design document and plan, and the test materials (fake chats that are synthetic, not real conversations) — all of it. Whether the repository is made public (it is private for now) is decided by the owner, separately from the license.

### 17.4 Parts made with the help of AI

A large part of this project's code and documents was written and reviewed with the help of AI (Claude). A person set the requirements and checked the results. Whether copyright arises in what an AI made, and if so who owns it, differs by country and situation, and some parts are still unsettled. So this document does not claim that "copyright certainly exists." The permission of the Apache License 2.0 is given within the scope of the rights that SoDam AI Studio actually holds. Before outside distribution or sale, expert confirmation is needed, and also check whether the terms of the AI service you used contain conditions for using its output.

### 17.5 Third-party components

| Component | Made by | Included in this project? | Terms |
|---|---|---|---|
| Windows PowerShell 5.1, .NET Framework, Windows features (sending key input, etc.) | Microsoft | No (part of Windows) | Windows license. Not redistributed. |
| Pester 3.4.0 (test tool) | The Pester project | No (the copy built into Windows is used) | Apache License 2.0 (confirmed from the wording of the installed LICENSE file). Used only when testing, not redistributed. |
| KakaoTalk PC | Kakao Corp. | No (installed separately by the user) | Kakao's terms of service |
| The open-source kakaocli for macOS | That project | No | Used only as a reference; no code was used. |
| External code, libraries, fonts, images, icons, tracking scripts | None | None | The document (HTML) also works as a single file without external files (checked by a test). |
| Test chat file | This project | Yes (`tests\fixtures`) | Same as 17.3 above. It is synthetic data, not a real conversation. |

### 17.6 Commercial use (strict standard)

**The Apache License 2.0 permits commercial use.** Uses like the following are also permitted by the license if you keep the conditions of 17.3 (keep the copy of the license and the copyright notices, mark your changes).

**However, the policy of this project's owner is narrower than the license.** On 2026-10-30 the owner decided to use it for personal use only, and does not publish it, officially distribute it, give it to others or use it commercially (doing any of that needs a lawyer's check first). What follows explains what the license permits legally; it does not mean that the owner will use it that way.

- Selling it, subscriptions, or including it in a paid service or product
- Using it to send advertising or promotional messages or customer-service messages in bulk
- Putting it into a company's or shop's business systems
- Including it in consulting deliverables or handed-over products, or installing it for a fee

But even when the license permits it, there are things you **must check separately.** The license neither permits nor waives them.

1. Kakao's terms of service and operating policy: automation for profit carries a higher risk of account sanctions.
2. Laws on personal-information protection: because it processes the personal information of the people you chat with, you must check the rules on purpose of collection, consent, retention period and provision to third parties.
3. Rules on sending advertising information for profit: the recipient's prior consent and so on may be required.
4. Trademarks and names: the Apache License 2.0 grants no trademark rights. To use the names "KakaoTalk" (Kakao) and "SoDam AI Studio" as a product name or in advertising, a separate permission may be needed.

Before using it commercially, check the four points above and getting a lawyer's review is recommended. Because this project is provided without warranty and with limited liability (17.3), the risk of using it in a business is borne by the user.

### 17.7 Personal information and chat content

- Chats contain other people's personal information and creative works. Exported chat files are private, so be careful when storing and sharing them.
- Saving a chat you took part in on your own PC and handing its content to a third party (for example an AI service or another person) can be judged differently in law. Check the other person's consent and the relevant laws.
- The kit does not send chat content outside, but responsibility for content that the user hands over personally rests with the user.

### 17.8 What is and is not allowed (summary)

| What you want to do | Possible under the license? | The owner's policy (decided 2026-10-30) |
|---|---|---|
| Testing and using it on my own PC | Possible (use is at one's own responsibility) | Used only with the owner's own account on the owner's own computer, and tested only in a room where the owner is alone. |
| Copying the folder and handing it to someone | Possible (hand over a copy of `LICENSE` and the copyright notices with it) | Not done. Doing it needs a lawyer's check first. |
| Publishing it on the internet (GitHub, etc.) | Possible. But before that, personal identifying information such as the test room name, the author information left in the history, and the risk under Kakao's terms must be checked again. | Not done. The repository stays private, and the owner decides on making it public only after confirming which repository and which direction. |
| Modifying the code and using it | Possible (mark the changed files with a notice that they were changed) | Possible if it is for one's own use. |
| Using it commercially | Possible. The separate checks in 17.6 (terms, personal information, advertising rules, trademarks) must be kept. | Not done. Doing it needs a lawyer's check first. |
| Quoting part of the document | Possible (keep the license conditions) | Possible. |

### 17.9 When changing the license or accepting contributions (a note for the owner)

To change the license, the `LICENSE` file, this Chapter 17 and the same chapter of the Korean guide must be changed together. The rights of people who already received it under this license remain. No outside code is mixed into this project, so there is no restriction coming from third parties. When accepting contributions from outside people, unless stated otherwise, a contribution is treated as submitted under the same Apache License 2.0 terms (license section 5).

> This chapter is for reference and does not guarantee legal effect. Responsibility for use rests with the user, and a lawyer's confirmation is recommended if you need a firm answer.

<a id="dev"></a>
## 18. For developers: tests and building this document

### Running the automated tests

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-All.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-All.ps1 -Name Config
```

The first line runs everything, the second runs only the `Config` tests. It uses Pester 3.4 syntax (`Should Be`). The last line prints `통과 N / 실패 N / 건너뜀 N` (passed N / failed N / skipped N).

### Test counts (an automated test checks that this table equals the real counts)

| Test file | Count | What it checks |
|---|---|---|
| `Bootstrap.Tests.ps1` | 24 | Rules against Korean text corruption (BOM, line ends), no administrator request and no writing to Program Files or HKLM, Korean messages and the data folder location, the rule that fixes the error setting, `시작.bat` working with special characters in the folder name, `.gitignore` entries, behaviour of `version` and of an unknown command, no pointer to a `help` command that does not exist, computing the data folder on a drive that does not exist, which paths run special characters in an argument and which do not |
| `Config.Tests.ps1` | 34 | Allowed list, permissions, only a person may change, consent, strange hand-edited settings, per-room `noDraft` (draft-free) mark |
| `Log.Tests.ps1` | 11 | Records without message text, tidying the record file, error report |
| `Guard.Tests.ps1` | 44 | The gatekeeper: window check, allowed keys, pressed-key check (only the Hangul key is exempt), human-hand detection, lock against running twice, click safety, no dangerous key code such as Esc in the source, reading real Windows features (no input is sent) |
| `Clip.Tests.ps1` | 9 | Saving, replacing and restoring the clipboard, stopping on an image or file |
| `Parse.Tests.ps1` | 21 | Reading export files, strange dates and times, line-end differences |
| `Status.Tests.ps1` | 31 | Reading the installed KakaoTalk version (registry cross-checked with the process; no version when unreadable), letter-for-letter check against the tested versions, the sending lock for untested versions (unknown values lock, only a person can lift it, exit code 4), read-only, the switch for real-operation tests |
| `Ocr.Tests.ps1` | 62 | The window-size check and the reason a stop is explained (read-only), deciding whether the search result is only the room name (second row, search-box text, ad, longer names, digits glued to the name, another room's preview text, the name column, the click height, the window size, space differences), the real screen layout (the icon read as 0, left-menu text, a line with the front of the name missing, several rows), checking that the window is not covered, the fake-capture connection, the text-reading engine (including word boxes), no writing to disk and no input, choosing the monitor's scaling over the window's own, trusting the monitor's scaling only when the thread is per-monitor aware, the main thread of a fresh process really becoming per-monitor aware (D-24), the tab check before the first click (false unless open-chat) |
| `Room.Tests.ps1` | 29 | Opening a room: the allowed list first, reusing an already-open window, pasting right after opening the search with Ctrl+F (no select-all), the tab check before the first click (no click or key unless it is the open-chat tab), the check before opening (no double-click when it cannot check) with the reason for a stop explained, the title check after opening, closing only a window the kit opened, no key other than Ctrl+F and Ctrl+V and no click on the search-icon spot in the source |
| `Readme.Tests.ps1` | 29 | The guide converter, whether the guide equals reality (test counts, command status, version, on-screen messages, links), that every on-screen message the kit can show is in the guide, the LICENSE text and owner |
| `Export.Tests.ps1` | 28 | Keeping, reading and searching exports: the per-room keeping folder name (cannot leave the folder), keeping the 3 newest and 30 days with protection of other files, refusing a file whose room name differs, the Korean message for a storage failure, `-Last` and `-Since`, the allowed list and AI reading permission, letter-for-letter search without duplicates |
| `Send.Tests.ps1` | 54 | The safety frame for sending (fake parts only, KakaoTalk is not touched): refusals before any input (empty text, 1000 characters, invisible characters and control characters, a room that is not allowed, AI permission, an untested version, no confirmation, an already open window, a bad attempt number, an unstated caller, a missing attempt number for an AI, no run lock), the 2-second interval and attempt numbers holding across processes, stopping on a damaged record or one with only a temporary file left, replacing the record in one step, recording before any input, the confirmed/unknown split with no retry, a stop before any key counting as a failure, the body passed through unchanged, waiting after the paste (also when Enter fails) before the clipboard is restored, no body in the records, no keys other than Ctrl+V and Enter and no clicks in the source, and the real provider being locked, confirmation that the input box is empty (an AI only to `noDraft`-marked rooms; a person gets a y/N question; any other answer means zero input) |
| `Command.Tests.ps1` | 17 | The `kakao send` command layer (fake parts only): argument checks (unknown option, repeated option, missing value, both/neither, a value starting with `--`, letter case), the text file (UTF-8, BOM, trailing line break, missing file, over 8 KB, broken UTF-8, empty file), telling the caller (an AI without `--human`, a person refused when input is redirected), the run lock (held while sending and released after a stop, no input when already held), showing the result (confirmed 0, unknown 2, preview 0, no body on the screen, an unknown error without its raw text), running `kakao.cmd send` in a new process, and the real provider being locked |
| `Foreground.Tests.ps1` | 9 | Waiting for the front window (fake clock and fake window): goes on after 2 seconds with no guidance when already in front, the guidance appears only once while waiting, the 2 seconds restart after a brief departure, stops with no input after 120 seconds (exit code 2), succeeds when stable exactly at 120 seconds and fails when later (boundary), a failing check stops with the original error, a missing window handle or required member is refused, the source has no keys, clicks or focus changes, and the real provider only reads |
| `InfoCommands.Tests.ps1` | 26 | The `rooms`, `read`, `search` and `status` command layer (temporary folder, synthetic data and fake install information only): `rooms list` (when empty; a value that is not a real true counts as no), changes to the allowed list refused without `--human` or with redirected input and changing nothing, `add` (AI permissions off, the note, a duplicate refused, errors in kind, name and argument count), `remove`, `set` (lower-case on/off only), sub-command errors, `read` (person and AI permission, `--since` with a fixed clock, 13 option errors, no export gives exit code 3, control characters removed, no text in the records), `search` (letter for letter, the AI permission range, word length and option errors, no word in the records), `status` (full and read-only mode, not installed, sending locked, arguments refused, no config file created), and running `kakao.cmd` in a new process |
| **Total** | **428** | |

### Building the guide html

The sources of the guide are `README.md` and `README.en.md`. The html is made with the tool below and must not be edited by hand.

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Readme.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Readme.ps1 -Check
```

The first line rebuilds the two html files, and the second only checks that they are up to date without building (exit code 1 if they differ).

### How to build

There is **no** build step that compiles or bundles. The script files are run as they are, and the C# snippets are compiled automatically while running. Only the html of the guide is made, with `tools\Build-Readme.ps1` above.

### Deployment and running the repository (GitHub)

- Repository: a private GitHub repository. Making it public is decided by the owner, and before that personal identifying information (the test room name, local paths), the author information in the commit history (the records GitHub makes when merging were found to carry the account's public e-mail address in their author field) and the risk under Kakao's terms must be checked again. The history has not been rewritten.
- Branches: nothing is pushed straight to the default branch `main`; work goes from a working branch through a pull request (PR).
- What is not uploaded: session records, checkpoints (`CHECKPOINT.md`), development-tool folders (`.remember`, `.sodam-re`) and secret values (`.env`, key files) are excluded by `.gitignore`.
- Line-ending rules: `.gitattributes` fixes `.bat` and `.cmd` to CRLF and the other text files to LF. This is so that the tests give the same result whatever the git settings of the receiving PC are.
- Release: none has been made yet. Whether to make one, with an official version number, is decided after steps 7-13 are done.

### Development rules (enforced by the automated tests)

- `.ps1` is UTF-8 with BOM, and `.bat` and `.cmd` are without BOM + CRLF. After writing a file, repair it with `tools\Write-Bom.ps1 -All`.
- The first statement of every function that contains `throw` is `$ErrorActionPreference = 'Stop'` (so that the caller's error setting cannot cause the safety device to be ignored).
- The allowed keys are only `Ctrl+S`, `Ctrl+V`, `Ctrl+C`, `Ctrl+F` and `Enter` (`Ctrl+A`, the add-friend shortcut in the KakaoTalk main window, is not allowed), and there must be no `Esc` code.
- The switch that turns on tests operating the real KakaoTalk is the environment variable `KAKAO_E2E=1`, but no automated test uses it yet. The real tests so far were each run separately when the user said to start, and the test room is only a room where I am alone (from step 7).
- Static analysis (PSScriptAnalyzer) is not installed, so it could not be run.

<a id="glossary"></a>
## 19. Glossary

| Term | Plain explanation |
|---|---|
| Terminal / Command Prompt (cmd) | The black window where you tell the computer what to do with text. |
| PowerShell | Another tool built into Windows for telling the computer what to do with text. This kit uses it inside. |
| Command line (CLI) | A way of using a program by typing text (commands) instead of using the mouse. |
| `.bat` / `.cmd` file | A file that, when double-clicked, runs set commands in order. |
| Exit code | The result number a program leaves when it ends. 0 means success. |
| UAC | The permission window that appears when a program asks for administrator rights. This kit does not bring it up. |
| Clipboard | The place where what you copied (`Ctrl+C`) stays for a moment. |
| Allowed list | The list of rooms that a person has allowed in advance for the kit to handle. |
| Gatekeeper (guard) | A safety device that, right before key input is sent, checks things like "is this the right window" and stops if something is wrong. |
| Export | Saving a chat as a text file with KakaoTalk's official feature. |
| Parser | The part that reads a text file and splits it into "who said what, and when". |
| Log (record) | A record that notes one line each for when something was done. This kit does not keep the chat text. |
| JSON | A tidy text format that computers pass to each other easily. AI uses it to read results. |
| Environment variable | A named setting stored in Windows. |
| BOM | An invisible mark at the very start of a text file. Windows PowerShell needs it to read Korean files correctly. |
| Snapshot | A copy that keeps the content exactly as it was at a moment. |
| False alarm | Wrongly judging that there is a problem when there is none. |
| Text reading (OCR) | A feature that lets the computer read the text in a picture shown on the screen and turn it into text. This kit uses it to check that a search result holds only one room name. |
| Display scaling | A Windows setting that decides by what percentage the text and windows on a monitor are shown larger. The same window has a different pixel size depending on the scaling. |
| Pull request (PR) | A request to upload changes and have them checked before they are merged into the main line. This project does not push to `main` directly and goes through a PR. |

[Back to top](#top)
