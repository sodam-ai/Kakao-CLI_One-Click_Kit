<a id="top"></a>
# KakaoTalk Kit (Kakao-CLI One-Click Kit)

[한국어](README.md) · [English](README.en.md)

> **Current status: under development (6 of 13 steps done).**
>
> The only command you can really use right now is **`kakao version`**. Sending messages, reading chats, searching, saving and the numbered menu are **not built yet.** This document keeps "works now (✅)" and "planned (⏳)" apart from the first line to the last.
>
> This is an **unofficial tool**. It has no relationship with the company that makes KakaoTalk (Kakao Corp.). You are responsible for how you use it. Please read [Chapter 17, Legal, copyright and license](#legal) before using it.

Document date: 2026-10-29 · Basis: steps 1-6 done + two verification rounds + repository cleanup (M0) + minimal version check (M7-0) + gatekeeper Hangul-key exception · License: Apache License 2.0 · Written so that people who are new to computers can follow it.

- ✅ = works right now. ⏳ = does not work yet (planned).
- In this document `kakao` is shorthand. You actually type `.\kakao.cmd`. The reason is in [Chapter 6](#run).
- Unfamiliar words are explained in [Chapter 19, Glossary](#glossary).

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

Development is split into 13 steps, and steps 1-6 are finished. In the table, "parts done" means **the parts (functions) for that feature are built and pass the automated tests, but they are not yet connected to a command that a user can call.**

| Step | Content | Status |
|---|---|---|
| 1 | Starting frame: no Korean text corruption, no administrator rights, `시작.bat` temporary screen, `kakao version` | ✅ Done |
| 2 | Settings, allowed room list, consent to use | ✅ Parts done |
| 3 | Records (log) and error report | ✅ Parts done |
| 4 | Key input layer and safety device (the "gatekeeper") | ✅ Parts done (testing real input into KakaoTalk is ⏳) |
| 5 | Saving and restoring the clipboard | ✅ Parts done |
| 6 | Reading export files (parser) | ✅ Parts done |
| 7 | Opening a room | ⏳ Parts done (tested with fake parts); the real-screen test and the connection to a command are not done yet. In the preliminary research, pasting into the search, opening a room, checking the opened window's title and closing it each passed once with the kit's code |
| 8 | Sending a message | ⏳ Planned |
| 9 | Export, read, search | ⏳ Planned |
| 10 | Status check, KakaoTalk version check, login guidance, lock for unverified versions | ⏳ Planned |
| 11 | Finished command router, numbered menu, `help` | ⏳ Planned |
| 12 | First-run consent, update, uninstall | ⏳ Planned |
| 13 | End-to-end acceptance test, final user guide | ⏳ Planned |

### Verification environment (the conditions that were actually checked)

| Item | Value |
|---|---|
| Operating system | Windows 11 Home, build 10.0.26300 |
| PowerShell | Windows PowerShell 5.1 (5.1.26100.9711) |
| KakaoTalk PC | 26.9.0.5337 (the only version confirmed in the research before development). KakaoTalk on this PC later updated itself to **26.9.1.5339**, where only clicking, pasting, opening a room and closing its window have been tested, and sending has not (it is not on the tested-version list) |
| Display language | English (en-US). Even so, every message of the kit is in Korean. |
| Monitors | 4 (including negative coordinates on a secondary monitor). Display scaling differs per monitor; the monitor holding KakaoTalk is at 150% |
| Rights | No administrator rights (normal user) |
| Default terminal | Windows Terminal |

### What has not been verified yet (an honest list)

- Testing, with the kit's own code, that keys really reach KakaoTalk: this is done in step 7. So far the only input the kit's code has sent is **a click, a paste (Ctrl+V), a double-click (opening a room) and a window-close request in the step 7 preliminary research** (no message was sent, and the safety guard did not stop; see chapter 14). Other keys such as Enter and Ctrl+S, and sending messages and exporting, have never been tested with the kit's code. (In the research stage before development, sending, opening a room and exporting were confirmed with temporary experiments.)
- Actually sending Korean text, multi-line text, long messages and emoji
- Searching, opening and exporting in ordinary rooms (1:1 and group chats) (the test room is an open chat room, so its window title and search results may differ from ordinary rooms)
- Behaviour when KakaoTalk is closed or shows the login screen
- How to tell rooms apart when several rooms have the same name
- False alarms of human-hand detection (did the person touch the keyboard or mouse), whether the pressed-key check is too strict, and behaviour with monitors of different display scaling mixed together: the Hangul/English key is read as held down on this PC even with hands off, so it was left out of the pressed-key check (every other key is still checked). Whether that key is the only one with this problem on other keyboards and input methods has not been checked
- How system messages ("○○ joined") appear in the export file: for now they may be read as continuation lines of the previous message.
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
- Typing only `.\kakao.cmd` with no command prints `명령이 없습니다. 도움말은 "kakao help" 로 볼 수 있습니다.` ("There is no command. See help with kakao help.") (exit code 1).
- Typing an unknown command prints `알 수 없는 명령입니다: <what you typed>  (도움말: kakao help)` ("Unknown command: ... (help: kakao help)") (exit code 1).
- Known mismatch: the message above points to `kakao help`, but `help` does not exist yet (⏳ step 11). The message is also planned to be changed to `.\kakao.cmd help`.

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
| `kakao status` | ⏳ Planned | Checks KakaoTalk installation, version, running and login state, number of allowed rooms and recent errors. | 10 |
| `kakao rooms` | ⏳ Planned | Manages allowed rooms: `rooms list`, `rooms add <name>`, `rooms remove <name>` (only a person can change them) | 11 |
| `kakao open <room>` | ⏳ Planned | Opens a room from the allowed list through search and checks the window title. | 7 |
| `kakao send <room> "<message>"` | ⏳ Planned | Sends a message to an allowed room. The default is preview and confirmation. | 8 |
| `kakao export <room>` | ⏳ Planned | Saves the whole chat to a file with the official export. | 9 |
| `kakao read <room>` | ⏳ Planned | Exports, then reads the file and shows it. | 9 |
| `kakao search "<keyword>"` | ⏳ Planned | Searches in chat files that were saved earlier (does not operate KakaoTalk). | 9 |
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

### How reading a chat works (⏳ built in step 9, the parser is ✅)

1. Open the room and press `Ctrl+S`. KakaoTalk's "Save as" window appears.
2. Always paste a new file name and press `Enter` to save (this prevents the overwrite question that appears when the same name exists).
3. Read the saved file. The file looks like this: line 1 `<room name> 님과 카카오톡 대화`, line 2 `저장한 날짜 : YYYY-MM-DD HH:MM:SS`, the date divider `--------------- 2026년 10월 21일 수요일 ---------------`, and messages `[nickname] [오전 2:59] text`.
4. Keeping: per room it keeps 1 latest copy and 3 earlier snapshots, and snapshots older than 30 days are deleted (⏳).

### What the gatekeeper blocks

- No key other than the 5 allowed keys (`Ctrl+S`, `Ctrl+V`, `Ctrl+A`, `Ctrl+C`, `Enter`) is ever sent.
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
  7. open the room (search only) .... ⏳ step 7
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
  2. open the room ............................ ⏳ step 7
  3. Ctrl+S -> check the save window .......... ⏳ step 9
  4. paste a new file name -> Enter ........... ⏳ step 9
  5. wait until the file exists (max 10 s) .... ⏳ step 9
  6. read the file (parser) ................... part ✅ (ConvertFrom-KakaoExport)
  7. tidy the stored copies (latest + 3) ...... ⏳
  8. print to screen (JSON with --json) ....... ⏳
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
   Config      Log      Guard+Win32          Clip        Parse      (⏳ Room, Send,
   settings    records  gatekeeper,          clipboard   reading     Export, Search,
   + allowed            input                            exports     Status, Install, Menu)
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
| `Win32.ps1` | Loads Windows features (finding windows, sending key input) through C# code. It is compiled the first time it is loaded and takes about 0.2-0.3 seconds. | ✅ Parts |
| `Guard.ps1` | Handles the check right before input (the gatekeeper), the allowed-key table, human-hand detection and the lock against running twice. | ✅ Parts |
| `Clip.ps1` | Saves, replaces and restores only the clipboard text, and checks each step. | ✅ Parts |
| `Parse.ps1` | Turns an export text file into the room name, saved time and message list. | ✅ Parts |
| `Ocr.ps1` | Decides, with on-screen text reading (OCR), whether the search result is only the room name. It reads the screen in memory only, writes nothing to disk and sends no input. | ✅ Parts (real-screen test is ⏳) |
| `Room.ps1` | Opens only an allowed room, and only through the search; checks before opening that the result is exactly one row; counts it as success only when the opened window's title equals the room name letter for letter. It does not open when it cannot check. | ✅ Parts (connection to a command is ⏳ step 7) |
| `Send.ps1` | Sending messages | ⏳ step 8 |
| `Export.ps1`, `Search.ps1` | Export, read, search | ⏳ step 9 |
| `Status.ps1` | Reads the installed KakaoTalk version (cross-checking the registry against the running process) and decides whether it is a version that was actually tested. Read-only. The login check and the full status check are added in step 10. | ✅ Parts (minimal) |
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
| 5 allowed keys, no Esc | The same allowed table exists on both sides of the code (PowerShell, C#), and a test checks that there is no Esc code. | ✅ |
| Human-hand detection | Waits until idle before starting, and stops if human input is detected during the work. | ✅ (checking false alarms is ⏳) |
| No running twice at once | A named lock (`Local\KakaoKit.InputLock`) | ✅ |
| Clipboard protection | Only text is saved and restored, a job stops if there is an image or file, and it is checked after putting text in and after restoring. | ✅ |
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
| Exported chat files | KakaoTalk's official feature | `%LOCALAPPDATA%\KakaoKit\exports\` (⏳) | No | They contain other people's chats. 1 latest copy and 3 snapshots per room, deleted after 30 days. |
| Password | Not handled | Not stored | Not applicable | The user logs in directly in the KakaoTalk app. |

The kit does not send chat content over the internet. However, **if you hand a chat you have read to an AI service, that content leaves the computer.** To guard against this, the "allow AI to read" switch for each room is off by default, and it is planned to tell you this and ask for consent when you turn it on (⏳).

### 12.3 Known security limits (written down, not hidden)

1. **How `kakao.cmd` interprets arguments**: because Windows cmd interprets the command line first, if you call it by pasting untrusted text such as a message straight into the command-line arguments, `&` or `%name%` can run as commands. This is how cmd is built, and escaping cannot fully stop it. So the message text is planned to be accepted only through `--file` or standard input, and automated callers are planned to call `powershell -NoProfile -ExecutionPolicy Bypass -File src\kakao.ps1` directly (⏳ steps 8 and 11). The current version uses what you type only to compare command names and never runs it, so it is not affected (tested with 20 kinds of special characters).
2. **The settings file is a plain text file.** A person or a program running under the same user account could edit it and change the allowed list. The "only a person may change" rule is kept only at the command level. Options such as a read-only settings file will be examined in step 12.
3. **The `KAKAO_KIT_HOME` environment variable** can change the data folder (originally for testing). It also applies in real use, so using a folder other than the default is planned to be shown on every command (⏳ step 11).
4. **Real behaviour of the key input method**: whether the newly built input method (SendInput) really works in KakaoTalk, and how false alarms of human-hand detection turn out, has not yet been checked for real (⏳ steps 7 and 8).
5. **Timing of restoring the clipboard right after pasting**: if it is restored before KakaoTalk has finished pasting, the original clipboard text could be sent instead, so a waiting time before restoring is planned and will be checked for real (⏳ step 8).
6. **Programs that briefly lock the clipboard**: the Windows clipboard history or a capture tool can hold the clipboard right after a change. The kit checks the result of reading and writing, retries, and stops the work if it still fails.
7. **A malicious program already running under the same account** cannot be stopped by this kit. This is a general limit.

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
└─ .remember, .sodam-re             folders made by other development tools (unrelated to the kit, not uploaded to Git)
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
| `exports\` | Exported chat files | ⏳ step 9 |
| `manifest.json` | List of what the kit created (used when uninstalling) | ⏳ step 12 |

<a id="changelog"></a>
## 14. Update summary (click to expand)

Click a title to expand it. Work was done from 2026-10-27 to 2026-10-30. The test counts are the number of automated tests that passed at that point.

<details>
<summary><strong>Room-opening parts (M7 main work)</strong> — tests 184 → 230</summary>

- I built `Room.ps1`, which opens a room in KakaoTalk, and `Ocr.ps1`, which checks the search result with on-screen text reading (OCR). They are not yet connected to a command that a user can call (⏳).
- The rules come down to one: **if it cannot check, it does not open.** A room that is not on the allowed list gets no input at all; without confirming that the search result is only the room name it does not double-click; and if the new window's title is not the room name letter for letter after opening, it closes that window and stops. A window that was already open is reused but never closed, and only a window the kit opened is closed. The result check looks at only the top line in the room-name column, so another room's preview text that equals the room name cannot pass; it also rejects another room whose name has digits glued right after it (for example a room named with an extra digit), and it does not open when the window is covered or when the window size or click height differs from the measured values.
- On a PC without the Korean text reader it does not open by default. Only a person can allow "open without checking", and then a warning is recorded.
- I wrote 38 tests first and confirmed all of them failed before implementing, and after pushing I added 8 more tests for the 4 gaps an automated security review pointed out and confirmed they failed before fixing them (22 for opening a room, 24 for text reading). All use fake parts and never touch real KakaoTalk.
- Limits: the click positions and the result area come from screens of KakaoTalk 26.9.1.5339 with a 588x753 window (150% scaling) on the open-chat tab. Reading two real screens (one result, several results) with the text reader showed that the icon in front of the room name is read as the digit 0 and the left-menu icons are read as characters, so "exactly one result" was not judged correctly (an error on the safe side: the room is not opened). I changed the check to use the positions of the word boxes and added 19 tests (tests 230 → 249). The same KakaoTalk window shows a different pixel size depending on the monitor's scale setting (588x753 at 150%, 392x502 at 100%), so the check now converts its measured pixel values by the scale of the monitor the window is on. This scale conversion has been confirmed on real screens at 150% and 100%; other scales such as 125% and 200% have been checked only with test data. After the fix I re-read the real one-result screen once and it was judged "exactly one result" (the several-results screen was not captured again after the fix and was checked only with test data). The real room-opening and closing test passed once at 100% (one double-click on the first result row, the new window's title confirmed to equal the room name letter for letter, then closing only the window the kit opened, 7.4 s; the search-icon click and the paste steps were skipped because the screen was prepared in advance). It has not been run at 150% or through the whole flow that starts with the search-icon click.

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
- Confirmed that 20 kinds of command-line special characters (`& | ^ ! ; $()`, Korean text, emoji, 6000 characters, etc.) are not executed as commands.

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

- 7: opening a room / 8: sending a message / 9: export, read, search / 10: status, version, login guidance / 11: command router, menu, help / 12: first run, update, uninstall / 13: acceptance test, final guide
- From step 7, tests that operate the real KakaoTalk begin, and before that the user must not touch the keyboard or mouse.

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

### When the safety device stopped the work (messages that appear once the feature is connected)

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

### When you report a problem

For now, the message shown on screen and `%LOCALAPPDATA%\KakaoKit\logs\kakao.log` (if it exists) are your clues. The part that builds an error report exists, but it is not connected to a command yet (⏳ step 11). The report contains no chat content but may contain room names, so check it before sending it to anyone.

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

| What you want to do | Is it possible? |
|---|---|
| Testing and using it on my own PC | Possible (use is at one's own responsibility) |
| Copying the folder and handing it to someone | Possible (hand over a copy of `LICENSE` and the copyright notices with it) |
| Publishing it on the internet (GitHub, etc.) | Possible under the license. But whether this repository is made public is the owner's decision, and before that personal identifying information such as the test room name and the risk under Kakao's terms must be checked again. |
| Modifying the code and using it | Possible (mark the changed files with a notice that they were changed) |
| Using it commercially | Possible under the license. The separate checks in 17.6 (terms, personal information, advertising rules, trademarks) must be kept. |
| Quoting part of the document | Possible (keep the license conditions) |

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
| `Bootstrap.Tests.ps1` | 20 | Rules against Korean text corruption (BOM, line ends), no administrator request and no writing to Program Files or HKLM, Korean messages and the data folder location, the rule that fixes the error setting, `시작.bat` working with special characters in the folder name, `.gitignore` entries, behaviour of `version` and of an unknown command |
| `Config.Tests.ps1` | 30 | Allowed list, permissions, only a person may change, consent, strange hand-edited settings |
| `Log.Tests.ps1` | 11 | Records without message text, tidying the record file, error report |
| `Guard.Tests.ps1` | 43 | The gatekeeper: window check, allowed keys, pressed-key check (only the Hangul key is exempt), human-hand detection, lock against running twice, click safety, no dangerous key code such as Esc in the source, reading real Windows features (no input is sent) |
| `Clip.Tests.ps1` | 9 | Saving, replacing and restoring the clipboard, stopping on an image or file |
| `Parse.Tests.ps1` | 20 | Reading export files, strange dates and times, line-end differences |
| `Status.Tests.ps1` | 23 | Reading the installed KakaoTalk version (registry cross-checked with the process; no version when unreadable), letter-for-letter check against the tested versions, read-only, the switch for real-operation tests |
| `Ocr.Tests.ps1` | 43 | Deciding whether the search result is only the room name (second row, search-box text, ad, longer names, digits glued to the name, another room's preview text, the name column, the click height, the window size, space differences), the real screen layout (the icon read as 0, left-menu text, a line with the front of the name missing, several rows), checking that the window is not covered, the fake-capture connection, the text-reading engine (including word boxes), no writing to disk and no input |
| `Room.Tests.ps1` | 22 | Opening a room: the allowed list first, reusing an already-open window, the check before opening (no double-click when it cannot check), the title check after opening, closing only a window the kit opened, no key other than Ctrl+V in the source |
| `Readme.Tests.ps1` | 28 | The guide converter, whether the guide equals reality (test counts, command status, version, on-screen messages, links), the LICENSE text and owner |
| **Total** | **249** | |

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

- Repository: a private GitHub repository. Making it public is decided by the owner, and before that personal identifying information (the test room name, local paths) and the risk under Kakao's terms must be checked again.
- Branches: nothing is pushed straight to the default branch `main`; work goes from a working branch through a pull request (PR).
- What is not uploaded: session records, checkpoints (`CHECKPOINT.md`), development-tool folders (`.remember`, `.sodam-re`) and secret values (`.env`, key files) are excluded by `.gitignore`.
- Line-ending rules: `.gitattributes` fixes `.bat` and `.cmd` to CRLF and the other text files to LF. This is so that the tests give the same result whatever the git settings of the receiving PC are.
- Release: none has been made yet. Whether to make one, with an official version number, is decided after steps 7-13 are done.

### Development rules (enforced by the automated tests)

- `.ps1` is UTF-8 with BOM, and `.bat` and `.cmd` are without BOM + CRLF. After writing a file, repair it with `tools\Write-Bom.ps1 -All`.
- The first statement of every function that contains `throw` is `$ErrorActionPreference = 'Stop'` (so that the caller's error setting cannot cause the safety device to be ignored).
- The allowed keys are only `Ctrl+S`, `Ctrl+V`, `Ctrl+A`, `Ctrl+C` and `Enter`, and there must be no `Esc` code.
- Tests that operate the real KakaoTalk run only when the environment variable `KAKAO_E2E=1` is set, and the test room is only a room where I am alone (from step 7).
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

[Back to top](#top)
