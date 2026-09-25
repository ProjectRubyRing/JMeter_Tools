<#
.SYNOPSIS
    OpenApi2Jmx.ps1 で生成した JMX を Apache JMeter 5.6.3 の CLI（非 GUI）モードで実行し、
    結果を JTL（XML・詳細付き。JMeter GUI で閲覧可）とログファイルに出力します。

.DESCRIPTION
    jmeter.bat は異常終了時に pause で入力待ちになり自動実行が止まるため、本スクリプトは
    jmeter.bat と同じ JVM オプションで java.exe を直接起動します（HEAP / GC_ALGO / JVM_ARGS /
    JMETER_LANGUAGE 環境変数は jmeter.bat と同様に反映します）。

    出力（既定: JMX と同じフォルダの results\）
      <JMX名>_<実行ID>.jtl … テスト結果（XML）。GUI の「結果をツリーで表示」等の［参照］で開けます
      <JMX名>_<実行ID>.log … JMeter のログ。1 リクエスト 1 行の [API-RESULT] 行を含みます

    終了コード: 0=全リクエスト成功 / 1=失敗したリクエストあり / 2=JMeter の実行エラー / 3=前提条件エラー

.PARAMETER JmxFile
    実行する JMX ファイル。必須。

.PARAMETER ResultDir
    JTL とログの出力先（既定: JMX と同じフォルダの results）。

.PARAMETER JMeterHome
    JMeter のインストール先（既定: 環境変数 JMETER_HOME → PATH 上の jmeter.bat →
    C:\Tools\apache-jmeter-5.6.3 → C:\apache-jmeter-5.6.3 → C:\Program Files\apache-jmeter-5.6.3）。

.PARAMETER JMeterArgs
    JMeter へそのまま渡す追加引数（例: -JMeterArgs '-JconnectTimeout=5000'）。

.EXAMPLE
    .\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx

.EXAMPLE
    .\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx -TargetHost 10.0.0.10 -Port 8080 -ApiKey MyKey
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$JmxFile = '',
    [string]$ResultDir = '',
    [string]$JMeterHome = '',
    [string]$TargetHost = '',
    [string]$Port = '',
    [string]$Protocol = '',
    [string]$BasePath = '',
    [string]$ApiKey = '',
    [string]$AuthToken = '',
    [string]$Threads = '',
    [string]$RampUp = '',
    [string]$Loops = '',
    [string[]]$JMeterArgs = @(),
    [switch]$Help,
    [switch]$Version
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ToolVersion = '1.0.0'

function Stop-Run([string]$Message, [int]$Code) {
    [Console]::Error.WriteLine('[ERROR] ' + $Message)
    exit $Code
}

function Show-Usage {
    @"
使い方:
  .\Invoke-JmxScenario.ps1 -JmxFile <シナリオ.jmx> [オプション]

必須:
  -JmxFile FILE        実行する JMX ファイル

任意:
  -ResultDir DIR       JTL とログの出力先（既定: JMX と同じフォルダの results）
  -JMeterHome DIR      JMeter のインストール先（既定: 環境変数 JMETER_HOME ほかを自動検出）
  -TargetHost HOST     接続先ホスト           （-Jhost=）
  -Port PORT           接続先ポート           （-Jport=）
  -Protocol PROTO      http / https           （-Jprotocol=）
  -BasePath PATH       パスの先頭に付ける値   （-JbasePath=）
  -ApiKey KEY          X-API-KEY ヘッダの値   （-JapiKey=）
  -AuthToken TOKEN     Authorization ヘッダの値（-JauthToken=。JMX 側で要素を有効化した場合のみ使用）
  -Threads N           スレッド数             （-Jthreads=）
  -RampUp SEC          ランプアップ秒         （-JrampUp=）
  -Loops N             ループ回数             （-Jloops=）
  -JMeterArgs ARGS     JMeter へそのまま渡す追加引数（例: '-JconnectTimeout=5000'）
  -Help / -Version

例:
  .\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx
  .\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx -TargetHost 10.0.0.10 -Port 8080 -ApiKey MyKey

終了コード: 0=全リクエスト成功 / 1=失敗あり / 2=JMeter 実行エラー / 3=前提条件エラー
"@
}

function Resolve-UserPath([string]$p) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
}

# 外部コマンドを実行し、標準出力と標準エラーをまとめて取得する（java -version は標準エラーに出力するため）
function Invoke-Capture([string]$Exe, [string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = [string]::Join(' ', $ArgList)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Text = ($out + $err) }
}

function Find-JMeterHome {
    $cands = New-Object 'System.Collections.Generic.List[string]'
    if ($JMeterHome.Length -gt 0) {
        $cands.Add((Resolve-UserPath $JMeterHome))
    } else {
        if (-not [string]::IsNullOrEmpty($env:JMETER_HOME)) { $cands.Add($env:JMETER_HOME) }
        $cmd = Get-Command 'jmeter.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd) { $cands.Add((Split-Path -Parent (Split-Path -Parent $cmd.Source))) }
        $cands.Add('C:\Tools\apache-jmeter-5.6.3')
        $cands.Add('C:\apache-jmeter-5.6.3')
        $cands.Add((Join-Path $env:ProgramFiles 'apache-jmeter-5.6.3'))
    }
    foreach ($h in $cands) {
        if ((Test-Path -LiteralPath (Join-Path $h 'bin\ApacheJMeter.jar') -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $h).ProviderPath
        }
    }
    return $null
}

function Find-Java {
    if (-not [string]::IsNullOrEmpty($env:JAVA_HOME)) {
        $j = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path -LiteralPath $j -PathType Leaf) { return $j }
    }
    $cmd = Get-Command 'java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) { return $cmd.Source }
    return $null
}

function Split-Opts([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return @() }
    return @($s.Trim() -split '\s+' | Where-Object { $_.Length -gt 0 })
}

function ConvertTo-ProcArg([string]$a) {
    # Windows のコマンドライン規則に従って 1 引数を引用する（空白や " を含む値のため）
    if ($a.Length -gt 0 -and $a -notmatch '[\s"]') { return $a }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $a.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)).Append('"'); $bs = 0; continue }
        if ($bs -gt 0) { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append('\' * ($bs * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

if ($Help) { Show-Usage; exit 0 }
if ($Version) { Write-Host ('Invoke-JmxScenario.ps1 {0} (Apache JMeter 5.6.3 対応)' -f $script:ToolVersion); exit 0 }

# ---------------------------------------------------------------- 入力チェック
if ([string]::IsNullOrEmpty($JmxFile)) { Show-Usage; Stop-Run '実行する JMX を -JmxFile で指定してください' 3 }
$jmxPath = Resolve-UserPath $JmxFile
if (-not (Test-Path -LiteralPath $jmxPath -PathType Leaf)) { Stop-Run ('JMX ファイルが見つかりません: ' + $JmxFile) 3 }
$jmxPath = (Resolve-Path -LiteralPath $jmxPath).ProviderPath
$jmxDir = Split-Path -Parent $jmxPath
$jmxName = [System.IO.Path]::GetFileNameWithoutExtension($jmxPath)
if ($ResultDir.Length -eq 0) { $resDir = Join-Path $jmxDir 'results' } else { $resDir = Resolve-UserPath $ResultDir }
try {
    New-Item -ItemType Directory -Force -Path $resDir | Out-Null
} catch {
    Stop-Run ('結果フォルダを作成できません: ' + $resDir) 3
}
$resDir = (Resolve-Path -LiteralPath $resDir).ProviderPath

$jmHome = Find-JMeterHome
if ($null -eq $jmHome) { Stop-Run 'JMeter が見つかりません。-JMeterHome で場所を指定するか、環境変数 JMETER_HOME を設定してください（JMeter 5.6.3 を想定）' 3 }
$java = Find-Java
if ($null -eq $java) { Stop-Run 'Java が見つかりません。JDK 17 以上をインストールし、JAVA_HOME か PATH を設定してください（例: winget install EclipseAdoptium.Temurin.17.JDK）' 3 }
$jv = Invoke-Capture $java @('-version')
$verLine = (($jv.Text -split "`r?`n") | Where-Object { $_ -match 'version' } | Select-Object -First 1)
if ($null -eq $verLine) { Stop-Run ('Java のバージョンを判定できません: ' + $jv.Text.Trim()) 3 }
$m = [regex]::Match($verLine, 'version "([0-9]+)(\.([0-9]+))?')
if (-not $m.Success) { Stop-Run ('Java のバージョンを判定できません: ' + $verLine) 3 }
$major = [int]$m.Groups[1].Value
if (($major -eq 1) -and $m.Groups[3].Success) { $major = [int]$m.Groups[3].Value }
if ($major -lt 8) { Stop-Run ('JMeter 5.6.3 には Java 8 以上が必要です（検出: ' + $verLine.Trim() + '）') 3 }
if ($major -lt 17) { Write-Host ('[WARN] Java {0} を検出しました。JMeter 5.6.3 では Java 17 以上を推奨します。' -f $major) }

# ---------------------------------------------------------------- 実行
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$base = Join-Path $resDir ($jmxName + '_' + $runId)
$n = 1
while ((Test-Path -LiteralPath ($base + '.jtl')) -or (Test-Path -LiteralPath ($base + '.log'))) {
    $n++
    $base = Join-Path $resDir ($jmxName + '_' + $runId + '-' + $n)
}
$jtl = $base + '.jtl'
$log = $base + '.log'

$jvm = New-Object 'System.Collections.Generic.List[string]'
if ($major -ge 9) {
    foreach ($o in @('--add-opens', 'java.desktop/sun.awt=ALL-UNNAMED', '--add-opens', 'java.desktop/sun.swing=ALL-UNNAMED',
            '--add-opens', 'java.desktop/javax.swing.text.html=ALL-UNNAMED', '--add-opens', 'java.desktop/java.awt=ALL-UNNAMED',
            '--add-opens', 'java.desktop/java.awt.font=ALL-UNNAMED', '--add-opens=java.base/java.lang=ALL-UNNAMED',
            '--add-opens=java.base/java.lang.invoke=ALL-UNNAMED', '--add-opens=java.base/java.lang.reflect=ALL-UNNAMED',
            '--add-opens=java.base/java.util=ALL-UNNAMED', '--add-opens=java.base/java.text=ALL-UNNAMED',
            '--add-opens=java.desktop/sun.awt.shell=ALL-UNNAMED')) { $jvm.Add($o) }
}
$jvm.Add('-XX:+HeapDumpOnOutOfMemoryError')
$heap = $env:HEAP; if ([string]::IsNullOrWhiteSpace($heap)) { $heap = '-Xms1g -Xmx1g -XX:MaxMetaspaceSize=256m' }
$gc = $env:GC_ALGO; if ([string]::IsNullOrWhiteSpace($gc)) { $gc = '-XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:G1ReservePercent=20' }
$lang = $env:JMETER_LANGUAGE; if ([string]::IsNullOrWhiteSpace($lang)) { $lang = '-Duser.language=en -Duser.region=EN' }
foreach ($o in (Split-Opts $heap)) { $jvm.Add($o) }
foreach ($o in (Split-Opts $gc)) { $jvm.Add($o) }
$jvm.Add('-Djava.security.egd=file:/dev/urandom')
foreach ($o in (Split-Opts ($lang -replace '"', ''))) { $jvm.Add($o) }
$jvm.Add('-Dfile.encoding=UTF-8')
foreach ($o in (Split-Opts $env:JVM_ARGS)) { $jvm.Add($o) }

$jmArgs = New-Object 'System.Collections.Generic.List[string]'
foreach ($o in @('-jar', (Join-Path $jmHome 'bin\ApacheJMeter.jar'), '-n', '-t', $jmxPath, '-j', $log,
        ('-JjtlFile=' + $jtl), ('-JresultDir=' + $resDir), ('-JrunId=' + $runId))) { $jmArgs.Add($o) }
if ($TargetHost.Length -gt 0) { $jmArgs.Add('-Jhost=' + $TargetHost) }
if ($Port.Length -gt 0) { $jmArgs.Add('-Jport=' + $Port) }
if ($Protocol.Length -gt 0) { $jmArgs.Add('-Jprotocol=' + $Protocol) }
if ($BasePath.Length -gt 0) { $jmArgs.Add('-JbasePath=' + $BasePath) }
if ($ApiKey.Length -gt 0) { $jmArgs.Add('-JapiKey=' + $ApiKey) }
if ($AuthToken.Length -gt 0) { $jmArgs.Add('-JauthToken=' + $AuthToken) }
if ($Threads.Length -gt 0) { $jmArgs.Add('-Jthreads=' + $Threads) }
if ($RampUp.Length -gt 0) { $jmArgs.Add('-JrampUp=' + $RampUp) }
if ($Loops.Length -gt 0) { $jmArgs.Add('-Jloops=' + $Loops) }
foreach ($a in @($JMeterArgs | Where-Object { $_.Length -gt 0 })) { $jmArgs.Add($a) }

Write-Host ('[INFO] JMeter     : ' + $jmHome)
Write-Host ('[INFO] Java       : ' + $verLine.Trim() + ' (' + $java + ')')
Write-Host ('[INFO] シナリオ   : ' + $jmxPath)
Write-Host ('[INFO] 結果 JTL   : ' + $jtl)
Write-Host ('[INFO] ログ       : ' + $log)
Write-Host ('[INFO] 実行開始   : ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

# 標準出力・標準エラーはそのままコンソールへ流す（進捗の summary 行が見えるように）
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $java
$all = New-Object 'System.Collections.Generic.List[string]'
foreach ($a in $jvm) { $all.Add((ConvertTo-ProcArg $a)) }
foreach ($a in $jmArgs) { $all.Add((ConvertTo-ProcArg $a)) }
$psi.Arguments = [string]::Join(' ', $all)
$psi.UseShellExecute = $false
$psi.WorkingDirectory = $jmxDir
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit()
$jmRc = $proc.ExitCode
Write-Host ('[INFO] 実行終了   : {0}（JMeter 終了コード {1}）' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $jmRc)

# ---------------------------------------------------------------- 結果の集計
if (-not (Test-Path -LiteralPath $jtl -PathType Leaf) -or ((Get-Item -LiteralPath $jtl).Length -eq 0)) {
    [Console]::Error.WriteLine('[ERROR] JTL が出力されていません。ログを確認してください: ' + $log)
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log -Encoding UTF8 | Select-String -Pattern ' (ERROR|FATAL) ' | Select-Object -Last 20 | ForEach-Object { [Console]::Error.WriteLine($_.Line) }
    }
    exit 2
}
$total = 0
$failed = 0
try {
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($jtl)
    foreach ($node in $xml.DocumentElement.ChildNodes) {
        if (($node.NodeType -eq [System.Xml.XmlNodeType]::Element) -and (($node.Name -eq 'httpSample') -or ($node.Name -eq 'sample'))) {
            $total++
            if ($node.GetAttribute('s') -ne 'true') { $failed++ }
        }
    }
} catch {
    # テストが途中で強制終了された場合など、XML が閉じていないときは行単位で数える
    $lines = Get-Content -LiteralPath $jtl -Encoding UTF8
    foreach ($l in $lines) {
        if ($l -match '^<(httpSample|sample) ') {
            $total++
            if ($l -match ' s="false"') { $failed++ }
        }
    }
}

Write-Host '----------------------------------------------------------------------'
if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Encoding UTF8 | Where-Object { $_.Contains('[API-RESULT]') } | ForEach-Object { Write-Host ($_.Substring($_.IndexOf('[API-RESULT]'))) }
}
Write-Host '----------------------------------------------------------------------'
Write-Host ('[INFO] リクエスト {0} 件 / 成功 {1} 件 / 失敗 {2} 件' -f $total, ($total - $failed), $failed)
Write-Host ('[INFO] JTL を JMeter GUI で見る: GUI 起動 →「結果をツリーで表示」等のリスナーの［参照］で {0} を選択' -f $jtl)

if ($jmRc -ne 0) { exit 2 }
if ($total -eq 0) {
    [Console]::Error.WriteLine('[ERROR] リクエストが 1 件も実行されていません。ログを確認してください: ' + $log)
    exit 2
}
if ($failed -gt 0) { exit 1 }
exit 0
