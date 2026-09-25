<#
.SYNOPSIS
    RHEL 版（openapi2jmx.sh）と Windows 版（OpenApi2Jmx.ps1）が同一の JMX を出力するかを総当たりで検証します。

.DESCRIPTION
    入力ファイル × オプション × 乱数シード の全組み合わせで各実装を実行し、出力の SHA-256 を比較します。
    bash は Git for Windows の bash.exe または WSL を想定しています。

.EXAMPLE
    .\Compare-Generators.ps1 -Inputs ..\openapi\orders-api.openapi.json,.\fixtures\feature-coverage.openapi.json
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [string[]]$Inputs = @(),
    [string]$BashExe = 'C:\Program Files\Git\bin\bash.exe',
    [string]$PythonForBash = 'python',
    [string]$Pwsh7 = '',
    [string]$WorkDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'openapi2jmx-compare'),
    [string[]]$Seeds = @('0', '12345', '999999999999')
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# powershell.exe -File 経由では配列引数がカンマ区切りの 1 文字列で渡るため分割する
$Inputs = @($Inputs | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
$Seeds = @($Seeds | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
$root = Split-Path -Parent $PSScriptRoot
$sh = Join-Path $root 'linux/openapi2jmx.sh'
$ps = Join-Path $root 'windows/OpenApi2Jmx.ps1'
if ($Inputs.Count -eq 0) {
    $Inputs = @((Join-Path $root 'openapi/orders-api.openapi.json'), (Join-Path $PSScriptRoot 'fixtures/feature-coverage.openapi.json'))
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$optionSets = @(
    @{ Name = 'default'; Sh = @(); Ps = @() },
    @{ Name = 'required-only'; Sh = @('--required-only'); Ps = @('-RequiredOnly') },
    @{ Name = 'use-examples'; Sh = @('--use-examples'); Ps = @('-UseExamples') },
    @{ Name = 'custom'; Sh = @('--any-method', 'POST', '--base-path', '/prod', '--host', 'api.example.com', '--port', '0443', '--protocol', 'HTTPS', '--api-key', 'k,e\y$1'); Ps = @('-AnyMethod', 'post', '-BasePath', '/prod', '-TargetHost', 'api.example.com', '-Port', '0443', '-Protocol', 'HTTPS', '-ApiKey', 'k,e\y$1') }
)

function Invoke-Quiet([string]$Exe, [string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $quoted = foreach ($a in $ArgList) { if ($a -match '[\s"]' -or $a.Length -eq 0) { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
    $psi.Arguments = [string]::Join(' ', $quoted)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['OPENAPI2JMX_PYTHON'] = $PythonForBash
    # Git for Windows の bash は /prod のような引数を Windows パスへ自動変換するため無効化する（RHEL では不要）
    $psi.EnvironmentVariables['MSYS_NO_PATHCONV'] = '1'
    $psi.EnvironmentVariables['MSYS2_ARG_CONV_EXCL'] = '*'
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Out = $out; Err = $err }
}

$total = 0
$ng = 0
foreach ($in in $Inputs) {
    $inFull = (Resolve-Path -LiteralPath $in).ProviderPath
    $base = [System.IO.Path]::GetFileNameWithoutExtension($inFull)
    foreach ($o in $optionSets) {
        foreach ($seed in $Seeds) {
            $total++
            $tag = '{0}_{1}_{2}' -f $base, $o.Name, $seed
            $outSh = Join-Path $WorkDir ($tag + '_sh.jmx')
            $outP5 = Join-Path $WorkDir ($tag + '_ps51.jmx')
            $outP7 = Join-Path $WorkDir ($tag + '_ps7.jmx')
            $r1 = Invoke-Quiet $BashExe (@($sh.Replace('\', '/'), '-i', $inFull.Replace('\', '/'), '-o', $outSh.Replace('\', '/'), '--seed', $seed, '--force') + $o.Sh)
            $r2 = Invoke-Quiet 'powershell.exe' (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps, '-InputFile', $inFull, '-OutputFile', $outP5, '-Seed', $seed, '-Force') + $o.Ps)
            $hashes = @()
            $codes = @($r1.Code, $r2.Code)
            if ($r1.Code -eq 0) { $hashes += (Get-FileHash -LiteralPath $outSh -Algorithm SHA256).Hash }
            if ($r2.Code -eq 0) { $hashes += (Get-FileHash -LiteralPath $outP5 -Algorithm SHA256).Hash }
            if ($Pwsh7.Length -gt 0) {
                $r3 = Invoke-Quiet $Pwsh7 (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps, '-InputFile', $inFull, '-OutputFile', $outP7, '-Seed', $seed, '-Force') + $o.Ps)
                $codes += $r3.Code
                if ($r3.Code -eq 0) { $hashes += (Get-FileHash -LiteralPath $outP7 -Algorithm SHA256).Hash }
            }
            $allOk = (@($codes | Where-Object { $_ -ne 0 }).Count -eq 0) -and (@($hashes | Select-Object -Unique).Count -eq 1)
            if ($allOk) {
                Write-Host ('[OK] {0}  {1}' -f $tag, $hashes[0].Substring(0, 16))
            } else {
                $ng++
                Write-Host ('[NG] {0}  exit={1} hashes={2}' -f $tag, ($codes -join ','), (($hashes | ForEach-Object { $_.Substring(0, 12) }) -join ','))
                if ($r1.Code -ne 0) { Write-Host ('     sh  : ' + $r1.Err.Trim()) }
                if ($r2.Code -ne 0) { Write-Host ('     ps51: ' + $r2.Err.Trim()) }
            }
        }
    }
}
Write-Host ('---- 組み合わせ {0} 件中 不一致 {1} 件' -f $total, $ng)
if ($ng -gt 0) { exit 1 }
exit 0
