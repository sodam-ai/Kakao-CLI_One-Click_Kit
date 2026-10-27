# README 마크다운(원본)에서 같은 내용의 HTML 을 만든다. md 가 원본이고 html 은 이 도구가 만들기 때문에 두 문서의 내용이 어긋나지 않는다.
#   만들기:           powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Readme.ps1
#   최신인지 확인만:   powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Readme.ps1 -Check   (다르면 종료 코드 1)
# 지원하는 마크다운(README 가 쓰는 것만): 제목 # ~ ####, 문단, 글머리(-)·번호(1.) 목록과 중첩, 표, ``` 코드 블록, 인용(>), 구분선(---),
#   **굵게**, `코드`, [글자](주소), 그리고 <details>·<summary>·<a id> 줄(그대로 통과).
# 지원하지 않는 문법(그림, 이어 쓴 목록 줄, 5단계 제목 등)을 만나면 조용히 틀리게 만들지 않고 오류로 멈춘다.
# 바깥 주소·글꼴·스크립트를 쓰지 않는 한 파일짜리 HTML 을 만든다(인터넷 없이 열린다).
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

# 코드 조각·표의 \| 를 잠시 맡겨 두는 표식(사설 영역 문자라 문서에 나올 일이 없다).
$script:PhOpen = [string][char]0xE000
$script:PhClose = [string][char]0xE001
$script:PhPipe = [string][char]0xE002

function ConvertTo-HtmlText {
    param([AllowEmptyString()][string]$Text)
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

# 한 줄 안의 서식: `코드`, [글자](주소), **굵게**. 코드 조각은 먼저 빼 두고(안의 ** · [] 를 해석하지 않게) 마지막에 되돌린다.
function ConvertFrom-InlineMarkdown {
    param([AllowEmptyString()][string]$Text)
    $ErrorActionPreference = 'Stop'
    if ($Text.Contains('![')) { throw ('그림은 지원하지 않습니다: ' + $Text) }
    $codes = New-Object 'System.Collections.Generic.List[string]'
    $open = $script:PhOpen
    $close = $script:PhClose
    $work = [regex]::Replace($Text, '`([^`]+)`', [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $codes.Add($m.Groups[1].Value)
            return ($open + [string]($codes.Count - 1) + $close)
        })
    $work = ConvertTo-HtmlText $work
    # 같은 폴더의 README 끼리 링크한 것은 html 쪽에서는 .html 로 이어지게 한다.
    $work = [regex]::Replace($work, '\[([^\]]+)\]\(([^)\s]+)\)', [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $href = [regex]::Replace($m.Groups[2].Value, '^(README(?:\.en)?)\.md(#.*)?$', '$1.html$2')
            return ('<a href="' + $href + '">' + $m.Groups[1].Value + '</a>')
        })
    $work = [regex]::Replace($work, '\*\*(.+?)\*\*', '<strong>$1</strong>')
    $work = [regex]::Replace($work, ([regex]::Escape($open) + '(\d+)' + [regex]::Escape($close)), [System.Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $raw = $codes[[int]$m.Groups[1].Value]
            return ('<code>' + (ConvertTo-HtmlText $raw) + '</code>')
        })
    return $work.Replace($script:PhPipe, '|')
}

function Split-TableRow {
    param([string]$Line)
    $t = $Line.Trim().Replace('\|', $script:PhPipe)
    if ($t.StartsWith('|')) { $t = $t.Substring(1) }
    if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    return @($t.Split('|') | ForEach-Object { $_.Trim() })
}

# 줄 배열 -> HTML 줄 배열. 인용(>) 안쪽은 이 함수를 다시 불러 같은 규칙으로 처리한다.
function ConvertFrom-KitMarkdownLines {
    param([string[]]$Lines)
    $ErrorActionPreference = 'Stop'
    $out = New-Object 'System.Collections.Generic.List[string]'
    $para = New-Object 'System.Collections.Generic.List[string]'
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $flush = {
        if ($para.Count -gt 0) {
            $out.Add('<p>' + (ConvertFrom-InlineMarkdown ($para -join ' ')) + '</p>')
            $para.Clear()
        }
    }
    $closeLists = {
        while ($stack.Count -gt 0) {
            $f = $stack.Pop()
            $out.Add('</li></' + $f.Type + '>')
        }
    }

    $i = 0
    while ($i -lt $Lines.Count) {
        $line = $Lines[$i]

        if ($line -match '^```(.*)$') {
            $lang = $Matches[1].Trim()
            & $flush
            & $closeLists
            $code = New-Object 'System.Collections.Generic.List[string]'
            $i++
            while ($i -lt $Lines.Count -and $Lines[$i] -notmatch '^```\s*$') { $code.Add($Lines[$i]); $i++ }
            if ($i -ge $Lines.Count) { throw '코드 블록(```)이 닫히지 않았습니다.' }
            $cls = ''
            if ($lang) { $cls = ' class="language-' + (ConvertTo-HtmlText $lang) + '"' }
            $out.Add('<pre><code' + $cls + '>' + (ConvertTo-HtmlText ($code -join "`n")) + '</code></pre>')
            $i++
            continue
        }

        if ($line.Trim() -eq '') { & $flush; $i++; continue }

        if ($line -match '^\s*(<details>|</details>|<summary>|<a id=)') {
            & $flush
            & $closeLists
            $out.Add($line.Trim())
            $i++
            continue
        }

        if ($line -match '^#{5,}') { throw ('5단계 이상 제목은 지원하지 않습니다: ' + $line) }
        if ($line -match '^(#{1,4}) (.+?)\s*$') {
            $level = $Matches[1].Length
            $headingText = $Matches[2]
            & $flush
            & $closeLists
            $out.Add('<h' + $level + '>' + (ConvertFrom-InlineMarkdown $headingText) + '</h' + $level + '>')
            $i++
            continue
        }

        if ($line -match '^-{3,}\s*$') {
            if ($para.Count -gt 0) { throw ('문단 바로 아래의 --- 는 제목으로 해석될 수 있어 지원하지 않습니다. 앞에 빈 줄을 넣으세요: ' + $para[$para.Count - 1]) }
            & $closeLists
            $out.Add('<hr>')
            $i++
            continue
        }

        if ($line -match '^>') {
            & $flush
            & $closeLists
            $quoted = New-Object 'System.Collections.Generic.List[string]'
            while ($i -lt $Lines.Count -and $Lines[$i] -match '^>') { $quoted.Add(($Lines[$i] -replace '^> ?', '')); $i++ }
            $out.Add('<blockquote>')
            foreach ($x in @(ConvertFrom-KitMarkdownLines -Lines $quoted.ToArray())) { $out.Add($x) }
            $out.Add('</blockquote>')
            continue
        }

        if ($line -match '^\|') {
            if (($i + 1) -ge $Lines.Count -or $Lines[$i + 1] -notmatch '^\|[\s:|-]+\|\s*$') { throw ('표의 머리글 아래에 구분 줄(|---|---|)이 없습니다: ' + $line) }
            & $flush
            & $closeLists
            $header = @(Split-TableRow $line)
            $i += 2
            $rows = New-Object 'System.Collections.Generic.List[object]'
            while ($i -lt $Lines.Count -and $Lines[$i] -match '^\|') {
                $cells = @(Split-TableRow $Lines[$i])
                if ($cells.Count -ne $header.Count) { throw ('표의 칸 수가 머리글(' + $header.Count + '칸)과 다릅니다: ' + $Lines[$i]) }
                $rows.Add($cells)
                $i++
            }
            $out.Add('<div class="table-wrap"><table>')
            $out.Add('<thead><tr>' + ((@($header) | ForEach-Object { '<th>' + (ConvertFrom-InlineMarkdown $_) + '</th>' }) -join '') + '</tr></thead>')
            $out.Add('<tbody>')
            foreach ($r in $rows) {
                $out.Add('<tr>' + ((@($r) | ForEach-Object { '<td>' + (ConvertFrom-InlineMarkdown $_) + '</td>' }) -join '') + '</tr>')
            }
            $out.Add('</tbody></table></div>')
            continue
        }

        if ($line -match '^(\s*)(-|\d+\.) (.+)$') {
            $indent = $Matches[1].Length
            $listType = 'ol'
            if ($Matches[2] -eq '-') { $listType = 'ul' }
            $itemText = $Matches[3]
            & $flush
            while ($stack.Count -gt 0 -and $stack.Peek().Indent -gt $indent) {
                $f = $stack.Pop()
                $out.Add('</li></' + $f.Type + '>')
            }
            if ($stack.Count -gt 0 -and $stack.Peek().Indent -eq $indent) {
                if ($stack.Peek().Type -eq $listType) { $out.Add('</li>') }
                else {
                    $f = $stack.Pop()
                    $out.Add('</li></' + $f.Type + '>')
                }
            }
            if ($stack.Count -eq 0 -or $stack.Peek().Indent -lt $indent) {
                $out.Add('<' + $listType + '>')
                $stack.Push([pscustomobject]@{ Indent = $indent; Type = $listType })
            }
            $out.Add('<li>' + (ConvertFrom-InlineMarkdown $itemText))
            $i++
            continue
        }

        if ($line -match '^\s{2,}\S') { throw ('들여쓴 줄은 지원하지 않습니다(목록 항목은 한 줄로 쓰세요): ' + $line) }

        & $closeLists
        $para.Add($line.Trim())
        $i++
    }
    & $flush
    & $closeLists
    return $out.ToArray()
}

function ConvertFrom-KitMarkdown {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Markdown)
    $ErrorActionPreference = 'Stop'
    $normalized = $Markdown.Replace("`r`n", "`n").Replace("`r", "`n")
    return ((ConvertFrom-KitMarkdownLines -Lines @($normalized -split "`n")) -join "`n")
}

$script:ReadmeCss = @'
:root{color-scheme:light dark;--bg:#ffffff;--fg:#1f2328;--muted:#59636e;--line:#d1d9e0;--soft:#f6f8fa;--accent:#0b57d0;--note-bg:#fff8e1;--note-line:#d49b00;--code-bg:#eceff3}
@media (prefers-color-scheme: dark){:root{--bg:#0f1318;--fg:#e6edf3;--muted:#9aa7b4;--line:#2d333b;--soft:#161b22;--accent:#79b8ff;--note-bg:#2b2410;--note-line:#d29922;--code-bg:#1c2128}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.75 "Malgun Gothic","Apple SD Gothic Neo","Noto Sans KR",system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:56rem;margin:0 auto;padding:1.5rem 1rem 4rem}
h1,h2,h3,h4{line-height:1.35;margin:2rem 0 .75rem;scroll-margin-top:1rem}
h1{font-size:1.9rem;border-bottom:1px solid var(--line);padding-bottom:.4rem}
h2{font-size:1.45rem;border-bottom:1px solid var(--line);padding-bottom:.3rem}
h3{font-size:1.2rem}
h4{font-size:1.05rem}
p,ul,ol{margin:.7rem 0}
li{margin:.2rem 0}
a{color:var(--accent)}
code{background:var(--code-bg);padding:.1em .35em;border-radius:4px;font:.9em ui-monospace,SFMono-Regular,Consolas,"D2Coding",monospace;overflow-wrap:anywhere}
pre{background:var(--soft);border:1px solid var(--line);border-radius:6px;padding:.9rem 1rem;overflow:auto;line-height:1.5}
pre code{background:none;padding:0;overflow-wrap:normal}
.table-wrap{overflow-x:auto;margin:1rem 0}
table{border-collapse:collapse;width:100%;min-width:32rem}
th,td{border:1px solid var(--line);padding:.45rem .65rem;text-align:left;vertical-align:top}
th{background:var(--soft);white-space:nowrap}
blockquote{margin:1rem 0;padding:.4rem 1rem;border-left:4px solid var(--note-line);background:var(--note-bg);border-radius:0 6px 6px 0}
blockquote p{margin:.5rem 0}
details{border:1px solid var(--line);border-radius:6px;padding:.5rem .9rem;margin:.7rem 0;background:var(--soft)}
summary{cursor:pointer;font-weight:600}
hr{border:0;border-top:1px solid var(--line);margin:2rem 0}
@media print{body{font-size:11pt}main{max-width:none;padding:0}pre,table{page-break-inside:avoid}}
'@

function New-ReadmePage {
    param(
        [Parameter(Mandatory)][string]$Markdown,
        [Parameter(Mandatory)][string]$Lang
    )
    $ErrorActionPreference = 'Stop'
    $body = ConvertFrom-KitMarkdown -Markdown $Markdown
    $h1 = [regex]::Match($Markdown, '(?m)^# (.+?)\s*$')
    if (-not $h1.Success) { throw '맨 위에 제목 줄(# ...)이 없습니다.' }
    $title = ConvertTo-HtmlText ($h1.Groups[1].Value -replace '[*`]', '')
    $lines = @(
        '<!doctype html>',
        ('<html lang="' + $Lang + '">'),
        '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        ('<title>' + $title + '</title>'),
        '<style>',
        $script:ReadmeCss.Trim(),
        '</style>',
        '</head>',
        '<body>',
        '<main>',
        $body,
        '</main>',
        '</body>',
        '</html>'
    )
    return (($lines -join "`n") + "`n")
}

function Get-ReadmeTargets {
    param([Parameter(Mandatory)][string]$Root)
    return @(
        [pscustomobject]@{ Md = (Join-Path $Root 'README.md'); Html = (Join-Path $Root 'README.html'); Lang = 'ko' },
        [pscustomobject]@{ Md = (Join-Path $Root 'README.en.md'); Html = (Join-Path $Root 'README.en.html'); Lang = 'en' }
    )
}

# 만들기(기본) 또는 확인만(-Check). 최신이 아닌 html 의 개수를 돌려준다(만들기에서는 0).
function Invoke-ReadmeBuild {
    param([Parameter(Mandatory)][string]$Root, [switch]$Check)
    $ErrorActionPreference = 'Stop'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stale = 0
    foreach ($t in (Get-ReadmeTargets -Root $Root)) {
        if (-not (Test-Path -LiteralPath $t.Md)) { throw ('원본 마크다운이 없습니다: ' + $t.Md) }
        $html = New-ReadmePage -Markdown ([System.IO.File]::ReadAllText($t.Md, $utf8)) -Lang $t.Lang
        if ($Check) {
            $current = $null
            if (Test-Path -LiteralPath $t.Html) { $current = [System.IO.File]::ReadAllText($t.Html, $utf8) }
            if ($current -ceq $html) { Write-Host ('최신입니다: ' + $t.Html) }
            else { Write-Host ('최신이 아닙니다(다시 만들어야 합니다): ' + $t.Html); $stale++ }
        }
        else {
            [System.IO.File]::WriteAllText($t.Html, $html, $utf8)
            Write-Host ('만들었습니다: ' + $t.Html)
        }
    }
    return $stale
}

# 다른 스크립트(시험)가 점(.)으로 불러올 때는 실행하지 않는다.
if ($MyInvocation.InvocationName -ne '.') {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $staleCount = Invoke-ReadmeBuild -Root $Root -Check:$Check
    if ($staleCount -gt 0) { exit 1 }
    exit 0
}
