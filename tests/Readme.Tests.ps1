# README 변환기(tools\Build-Readme.ps1)와 README 4종(한글/영문 x md/html)을 검사한다.
# 이 시험은 문서가 거짓말을 하지 못하게 한다: 시험 개수·명령 상태·버전·링크·한글/영문 구조가 실제와 같아야 통과한다.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$libs = @('Config')
. (Join-Path $here '_Load.ps1')
. (Join-Path $kitRoot 'tools\Build-Readme.ps1')

function Join-Lines([string[]]$Lines) { return ($Lines -join "`n") }
function Get-Flat([string]$Html) { return ($Html -replace "`r?`n", '') }
function Read-Utf8([string]$Path) { return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false))) }
# 코드 블록(``` ... ```) 안은 표·목록·제목 세기에서 뺀다.
function Remove-CodeBlocks([string]$Text) { return [regex]::Replace($Text, '(?ms)^```.*?^```[ \t]*$', '') }

$docs = @{
    ko = @{ Md = (Join-Path $kitRoot 'README.md'); Html = (Join-Path $kitRoot 'README.html'); Lang = 'ko' }
    en = @{ Md = (Join-Path $kitRoot 'README.en.md'); Html = (Join-Path $kitRoot 'README.en.html'); Lang = 'en' }
}

function Get-DocShape([string]$Path) {
    $text = Read-Utf8 $Path
    $plain = Remove-CodeBlocks $text
    return [pscustomobject]@{
        Anchors   = @([regex]::Matches($text, '(?m)^<a id="([^"]+)"></a>[ \t]*$') | ForEach-Object { $_.Groups[1].Value })
        Levels    = (@([regex]::Matches($plain, '(?m)^(#{1,4}) ') | ForEach-Object { $_.Groups[1].Value.Length }) -join ',')
        Tables    = [regex]::Matches($plain, '(?m)^\|[\s:|-]+\|[ \t]*$').Count
        TableRows = [regex]::Matches($plain, '(?m)^\|').Count
        Fences    = [regex]::Matches($text, '(?m)^```').Count
        Details   = [regex]::Matches($text, '<details>').Count
        ListItems = [regex]::Matches($plain, '(?m)^\s*(?:-|\d+\.) ').Count
        Links     = @([regex]::Matches($plain, '\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
    }
}

Describe 'Readme 변환기: 문법' {
    It 'converts headings, paragraphs, bold and code spans' {
        $html = ConvertFrom-KitMarkdown (Join-Lines @('# 제목', '', '본문 **굵게** 와 `code` 입니다', '둘째 줄'))
        $html.Contains('<h1>제목</h1>') | Should Be $true
        $html.Contains('<p>본문 <strong>굵게</strong> 와 <code>code</code> 입니다 둘째 줄</p>') | Should Be $true
    }

    It 'escapes html in text and in code spans' {
        $html = ConvertFrom-KitMarkdown 'a < b & c > d `<script>x</script>`'
        $html.Contains('a &lt; b &amp; c &gt; d') | Should Be $true
        $html.Contains('<code>&lt;script&gt;x&lt;/script&gt;</code>') | Should Be $true
        $html.Contains('<script>') | Should Be $false
    }

    It 'bold may wrap a code span and a link text may contain one' {
        $html = ConvertFrom-KitMarkdown '**`kakao version`** 와 [`x`](#a)'
        $html.Contains('<strong><code>kakao version</code></strong>') | Should Be $true
        $html.Contains('<a href="#a"><code>x</code></a>') | Should Be $true
    }

    It 'keeps a fenced code block as it is (escaped, nothing formatted)' {
        $html = ConvertFrom-KitMarkdown (Join-Lines @('```text', '**not bold** <b> & `x`', '| not | a table |', '```'))
        $html.Contains('<pre><code class="language-text">**not bold** &lt;b&gt; &amp; `x`' + "`n" + '| not | a table |</code></pre>') | Should Be $true
    }

    It 'converts a table with header, body, inline markup and an escaped pipe' {
        $html = Get-Flat (ConvertFrom-KitMarkdown (Join-Lines @('| 이름 | 값 |', '|---|---|', '| `a\|b` | **1** |', '| 둘 | 2 |')))
        $html.Contains('<thead><tr><th>이름</th><th>값</th></tr></thead>') | Should Be $true
        $html.Contains('<tr><td><code>a|b</code></td><td><strong>1</strong></td></tr>') | Should Be $true
        $html.Contains('<tr><td>둘</td><td>2</td></tr>') | Should Be $true
        $html.Contains('class="table-wrap"') | Should Be $true
    }

    It 'stops with an error when a table row has the wrong number of cells' {
        $e = Get-ThrownError { ConvertFrom-KitMarkdown (Join-Lines @('| a | b |', '|---|---|', '| 1 |')) }
        $e | Should Not BeNullOrEmpty
    }

    It 'converts nested bullet lists and a following numbered list' {
        $html = Get-Flat (ConvertFrom-KitMarkdown (Join-Lines @('- 하나', '- 둘', '  - 안쪽', '- 셋', '', '1. 첫째', '2. 둘째')))
        $html.Contains('<ul><li>하나</li><li>둘<ul><li>안쪽</li></ul></li><li>셋</li></ul>') | Should Be $true
        $html.Contains('<ol><li>첫째</li><li>둘째</li></ol>') | Should Be $true
    }

    It 'passes details, summary and anchor lines through and still formats what is inside' {
        $html = Get-Flat (ConvertFrom-KitMarkdown (Join-Lines @('<a id="intro"></a>', '## 소개', '', '<details>', '<summary><strong>제목</strong></summary>', '', '- 항목 `x`', '', '</details>')))
        $html.Contains('<a id="intro"></a><h2>소개</h2>') | Should Be $true
        $html.Contains('<details><summary><strong>제목</strong></summary>') | Should Be $true
        $html.Contains('<li>항목 <code>x</code></li>') | Should Be $true
        $html.Contains('</details>') | Should Be $true
    }

    It 'turns a blockquote into a formatted block with paragraphs and a list' {
        $html = Get-Flat (ConvertFrom-KitMarkdown (Join-Lines @('> **주의**', '>', '> 둘째 문단', '> - 항목')))
        $html.Contains('<blockquote><p><strong>주의</strong></p><p>둘째 문단</p><ul><li>항목</li></ul></blockquote>') | Should Be $true
    }

    It 'rewrites links to the sibling README so the html pair links to each other; other links stay' {
        $html = ConvertFrom-KitMarkdown '[영문](README.en.md) [앵커](README.md#top) [문서](docs/spike-notes.md) [쪽](#a)'
        $html.Contains('href="README.en.html"') | Should Be $true
        $html.Contains('href="README.html#top"') | Should Be $true
        $html.Contains('href="docs/spike-notes.md"') | Should Be $true
        $html.Contains('href="#a"') | Should Be $true
    }

    It 'stops with an error instead of silently mis-rendering unsupported syntax' {
        (Get-ThrownError { ConvertFrom-KitMarkdown '![그림](a.png)' }) | Should Not BeNullOrEmpty
        (Get-ThrownError { ConvertFrom-KitMarkdown (Join-Lines @('```', '닫히지 않음')) }) | Should Not BeNullOrEmpty
        (Get-ThrownError { ConvertFrom-KitMarkdown (Join-Lines @('- 항목', '  이어 쓴 줄')) }) | Should Not BeNullOrEmpty
        (Get-ThrownError { ConvertFrom-KitMarkdown (Join-Lines @('문단', '---')) }) | Should Not BeNullOrEmpty
        (Get-ThrownError { ConvertFrom-KitMarkdown '##### 너무 깊은 제목' }) | Should Not BeNullOrEmpty
    }

    It 'builds a self-contained page: doctype, language, title, utf-8, no external files' {
        $page = New-ReadmePage -Markdown (Join-Lines @('# 제목 **굵게**', '', '본문')) -Lang 'en'
        $page.StartsWith('<!doctype html>') | Should Be $true
        $page.Contains('<html lang="en">') | Should Be $true
        $page.Contains('<meta charset="utf-8">') | Should Be $true
        $page.Contains('<title>제목 굵게</title>') | Should Be $true
        $page.Contains('prefers-color-scheme: dark') | Should Be $true
        ($page -match '<script|<link|<img|src=|https?://') | Should Be $false
    }
}

Describe 'README: 파일과 최신 상태' {
    It 'all four files exist at the project root' {
        foreach ($d in $docs.Values) {
            Test-Path -LiteralPath $d.Md | Should Be $true
            Test-Path -LiteralPath $d.Html | Should Be $true
        }
    }

    It 'README.html is exactly what Build-Readme makes from README.md (not stale)' {
        (Read-Utf8 $docs.ko.Html) | Should BeExactly (New-ReadmePage -Markdown (Read-Utf8 $docs.ko.Md) -Lang 'ko')
    }

    It 'README.en.html is exactly what Build-Readme makes from README.en.md (not stale)' {
        (Read-Utf8 $docs.en.Html) | Should BeExactly (New-ReadmePage -Markdown (Read-Utf8 $docs.en.Md) -Lang 'en')
    }
}

Describe 'README: 한글과 영문의 구조가 같다' {
    It 'has the same anchors and heading levels in the same order' {
        $ko = Get-DocShape $docs.ko.Md
        $en = Get-DocShape $docs.en.Md
        ($ko.Anchors -join ',') | Should Be ($en.Anchors -join ',')
        $ko.Levels | Should Be $en.Levels
        $ko.Anchors.Count -ge 19 | Should Be $true
    }

    It 'has the same number of tables, table rows, code blocks, toggles, list items and links' {
        $ko = Get-DocShape $docs.ko.Md
        $en = Get-DocShape $docs.en.Md
        $ko.Tables | Should Be $en.Tables
        $ko.TableRows | Should Be $en.TableRows
        $ko.Fences | Should Be $en.Fences
        $ko.Details | Should Be $en.Details
        $ko.ListItems | Should Be $en.ListItems
        ($ko.Links -join ' ') | Should Be ($en.Links -join ' ')
    }

    It 'links the two languages to each other' {
        (Read-Utf8 $docs.ko.Md).Contains('](README.en.md)') | Should Be $true
        (Read-Utf8 $docs.en.Md).Contains('](README.md)') | Should Be $true
    }
}

Describe 'README: 링크' {
    It 'every in-page link (#name) points to an existing anchor' {
        foreach ($d in $docs.Values) {
            $shape = Get-DocShape $d.Md
            foreach ($t in $shape.Links) {
                if ($t.StartsWith('#')) { ($shape.Anchors -contains $t.Substring(1)) | Should Be $true }
            }
        }
    }

    It 'every link to another file points to a file that exists' {
        foreach ($d in $docs.Values) {
            foreach ($t in (Get-DocShape $d.Md).Links) {
                if (-not $t.StartsWith('#')) {
                    $rel = ($t -split '#')[0]
                    Test-Path -LiteralPath (Join-Path $kitRoot $rel) | Should Be $true
                }
            }
        }
    }
}

Describe 'README: 내용이 실제와 같다' {
    It 'shows the real kit version and the verified KakaoTalk version' {
        $version = Get-KitVersion
        $verified = @(Get-VerifiedKakaoVersions)
        $verified.Count | Should Be 1
        foreach ($d in $docs.Values) {
            $text = Read-Utf8 $d.Md
            $text.Contains($version) | Should Be $true
            $text.Contains($verified[0]) | Should Be $true
        }
    }

    It 'marks as available (✅) exactly the commands the router really handles' {
        $router = Read-Utf8 (Join-Path $kitRoot 'src\kakao.ps1')
        $real = @([regex]::Matches($router, "(?m)^\s+'(\w+)'\s*\{") | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $real.Count -ge 1 | Should Be $true
        foreach ($d in $docs.Values) {
            $plain = Remove-CodeBlocks (Read-Utf8 $d.Md)
            $claimed = @([regex]::Matches($plain, '(?m)^\|\s*`kakao (\w+)[^`]*`\s*\|\s*✅') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
            ($claimed -join ',') | Should Be ($real -join ',')
        }
    }

    # 문서가 코드 문구(``...``)로 인용한 한글 화면 문구는 문구 사전의 문장과 글자 그대로 같아야 한다. 일부만 잘라 인용하면 안 된다.
    # 자리 표시자 <...> 는 사전의 {0} 과 같은 것으로 본다.
    It 'every Korean on-screen message quoted in the guide is word for word in the message dictionary' {
        $known = @($script:KitMessages.Values)
        foreach ($d in $docs.Values) {
            $plain = Remove-CodeBlocks (Read-Utf8 $d.Md)
            $checked = 0
            foreach ($m in [regex]::Matches($plain, '`([^`]+)`')) {
                $s = $m.Groups[1].Value
                if ($s -match '[가-힣]' -and $s.Length -gt 12 -and $s -match '[.)…]$') {
                    $norm = [regex]::Replace($s, '<[^>]+>', '{0}')
                    if (-not ($known -ccontains $norm)) { throw ('문구 사전에 없는 인용: ' + $s) }
                    $checked++
                }
            }
            $checked -ge 15 | Should Be $true
        }
    }

    # 키트가 사용자에게 보여 줄 수 있는 화면 문구는 두 설명서에 모두 있어야 한다(오류 보고서 줄은 제외). 새 문구를 만들고 설명서에 빼먹는 것을 막는다.
    # 자리 표시자({0}) 앞부분이 글자 그대로 들어 있으면 된다. "(방:" 처럼 끝에 걸친 열린 괄호는 뺀다.
    It 'every message the kit can show is described in the guide (report lines excepted)' {
        foreach ($d in $docs.Values) {
            $text = Read-Utf8 $d.Md
            foreach ($key in $script:KitMessages.Keys) {
                if ($key.StartsWith('report.')) { continue }
                $full = [string]$script:KitMessages[$key]
                $head = (($full -split '\{')[0]).Trim() -replace '\s*\([^)]*$', ''
                if ($head.Length -lt 6) { $head = $full.Trim() }
                if (-not $text.Contains($head)) { throw ('설명서에 없는 화면 문구 (' + $key + '): ' + $head) }
            }
        }
    }

    It 'lists the real number of tests per test file and in total' {
        $actual = @{}
        foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $kitRoot 'tests') -Filter '*.Tests.ps1' -File)) {
            $actual[($f.Name -replace '\.Tests\.ps1$', '')] = [regex]::Matches((Read-Utf8 $f.FullName), "(?m)^\s+It '").Count
        }
        $total = 0
        foreach ($v in $actual.Values) { $total += $v }
        foreach ($d in $docs.Values) {
            $plain = Remove-CodeBlocks (Read-Utf8 $d.Md)
            $claimed = @{}
            foreach ($m in [regex]::Matches($plain, '(?m)^\|\s*`(\w+)\.Tests\.ps1`\s*\|\s*(\d+)\s*\|')) { $claimed[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
            $claimed.Count | Should Be $actual.Count
            foreach ($k in $actual.Keys) { $claimed[$k] | Should Be $actual[$k] }
            $sum = [regex]::Match($plain, '(?m)^\|\s*\*\*(?:합계|Total)\*\*\s*\|\s*\*\*(\d+)\*\*')
            $sum.Success | Should Be $true
            [int]$sum.Groups[1].Value | Should Be $total
        }
    }
}

Describe 'README: 라이선스' {
    # LICENSE 는 Apache License 2.0(최신판) 전문이어야 하고, 권리자 SoDam AI Studio 가 채워져 있어야 하며, 두 README 가 같은 라이선스를 말해야 한다.
    It 'LICENSE is the full Apache License 2.0 text owned by SoDam AI Studio, and both guides name the same license' {
        $lic = Read-Utf8 (Join-Path $kitRoot 'LICENSE')
        $lic.Length -gt 10000 | Should Be $true
        $lic.Contains('Apache License') | Should Be $true
        $lic.Contains('Version 2.0, January 2004') | Should Be $true
        $lic.Contains('TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION') | Should Be $true
        $lic.Contains('END OF TERMS AND CONDITIONS') | Should Be $true
        $lic.Contains('Copyright 2026 SoDam AI Studio') | Should Be $true
        ($lic -match '\[yyyy\]|\[name of copyright owner\]') | Should Be $false
        foreach ($d in $docs.Values) {
            $t = Read-Utf8 $d.Md
            $t.Contains('Apache License 2.0') | Should Be $true
            $t.Contains('SoDam AI Studio') | Should Be $true
            $t.Contains('](LICENSE)') | Should Be $true
        }
    }
}

Describe 'README: 안전' {
    It 'the html files load nothing from outside (no script, link, image, src or web address)' {
        foreach ($d in $docs.Values) {
            (Read-Utf8 $d.Html) -match '<script|<link|<img|src=|https?://' | Should Be $false
        }
    }

    It 'contains no e-mail address, phone number or personal user folder' {
        foreach ($d in $docs.Values) {
            foreach ($path in $d.Md, $d.Html) {
                $text = Read-Utf8 $path
                ($text -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') | Should Be $false
                ($text -match '01[016-9][- ]?\d{3,4}[- ]?\d{4}') | Should Be $false
                ($text -match '(?i)C:\\Users\\') | Should Be $false
            }
        }
    }

    It 'has no unfinished-work markers' {
        foreach ($d in $docs.Values) {
            # 대문자 표식만 본다: 실제 파일 이름 tasks/todo.md 의 소문자 todo 는 미완성 표식이 아니다.
            (Read-Utf8 $d.Md) -cmatch '\bTBD\b|\bTODO\b|\bFIXME\b|추후 결정|미정입니다' | Should Be $false
        }
    }
}
