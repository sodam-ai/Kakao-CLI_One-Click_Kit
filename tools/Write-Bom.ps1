# Fix file encodings after the Write tool (which cannot add a BOM).
#   .ps1      -> UTF-8 WITH BOM (Windows PowerShell 5.1 reads BOM-less UTF-8 as cp949)
#   .bat/.cmd -> UTF-8 WITHOUT BOM, CRLF line endings
# Idempotent. Keep this file ASCII-only so it parses before its own BOM is applied.
param(
    [string[]]$Path = @(),
    [switch]$All
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($All) {
    $Path = @(Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.bat', '.cmd' } |
        Where-Object { $_.FullName -notmatch '\\(\.remember|\.git|\.superpowers)\\' } |
        ForEach-Object { $_.FullName })
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$changed = 0
foreach ($p in $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $skip = 0
    if ($hasBom) { $skip = 3 }
    $body = New-Object byte[] ($bytes.Length - $skip)
    [System.Array]::Copy($bytes, $skip, $body, 0, $body.Length)
    if ([System.IO.Path]::GetExtension($p).ToLowerInvariant() -eq '.ps1') {
        $out = New-Object byte[] ($body.Length + 3)
        $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
        [System.Array]::Copy($body, 0, $out, 3, $body.Length)
    }
    else {
        $text = $utf8.GetString($body) -replace "`r?`n", "`r`n"
        $out = $utf8.GetBytes($text)
    }
    $same = ($out.Length -eq $bytes.Length)
    if ($same) {
        for ($i = 0; $i -lt $out.Length; $i++) { if ($out[$i] -ne $bytes[$i]) { $same = $false; break } }
    }
    if (-not $same) {
        [System.IO.File]::WriteAllBytes($p, $out)
        $changed++
        Write-Host ('fixed: ' + $p)
    }
}
Write-Host ('files checked: {0}, fixed: {1}' -f $Path.Count, $changed)
