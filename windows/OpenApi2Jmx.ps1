<#
.SYNOPSIS
    OpenAPI 3.0.x 定義ファイル（JSON）から Apache JMeter 5.6.3 用のテスト計画（.jmx）を自動生成します。

.DESCRIPTION
    Windows 11 標準の Windows PowerShell 5.1 と PowerShell 7 の両方で動作します（追加モジュール不要）。

    生成されるテスト計画の既定値:
      - 接続先       : http://localhost:8080
      - 共通ヘッダ   : X-API-KEY = XXXXXXXXXXXX（固定）
      - スレッド     : 1 スレッド / ランプアップ 1 秒 / ループ 1 回（各 API を 1 回ずつ）
      - テストデータ : OpenAPI のデータ型定義からランダム生成
      - 結果         : JTL（XML・詳細付き、JMeter GUI で閲覧可）とログ（[API-RESULT] 行）

    RHEL 版 linux/openapi2jmx.sh と同一仕様・同一乱数アルゴリズムです。
    同じ入力ファイル・同じ -Seed なら、両者は 1 バイトも違わない JMX を出力します。

.PARAMETER InputFile
    OpenAPI 3.0.x 定義ファイル（JSON 形式）。必須。

.PARAMETER OutputFile
    出力する JMX ファイル。省略時はカレントフォルダの <APIタイトル>.jmx。

.PARAMETER Force
    出力先に同名ファイルがあっても上書きします。

.PARAMETER TargetHost
    接続先ホストの既定値（既定: localhost）。

.PARAMETER Port
    接続先ポートの既定値（既定: 8080）。

.PARAMETER Protocol
    http または https（既定: http）。

.PARAMETER BasePath
    全 API パスの先頭に付けるパス（既定: 空。例: /prod）。

.PARAMETER ApiKey
    X-API-KEY ヘッダの既定値（既定: XXXXXXXXXXXX）。

.PARAMETER Seed
    テストデータ用の乱数シード（0 以上の整数・12 桁以内）。同じシードなら同じテストデータを再生成します。

.PARAMETER AnyMethod
    x-amazon-apigateway-any-method（ANY）を送るメソッド。GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS（既定: GET）。

.PARAMETER RequiredOnly
    必須（required）のパラメータ・プロパティだけを生成します。

.PARAMETER UseExamples
    example / default が定義されていればランダム値より優先します。

.PARAMETER PlaceholderValue
    値の位置に引用符なしで書かれた ${...}（後で置換するプレースホルダ。例: "timeoutInMillis": ${integration_timeout_ms}）は
    JSON として読めないため、この数値に置き換えて読み込みます（既定: 3000）。置き換えた箇所は警告として表示します。

.EXAMPLE
    .\OpenApi2Jmx.ps1 -InputFile .\openapi.json

.EXAMPLE
    .\OpenApi2Jmx.ps1 -InputFile .\openapi.json -OutputFile .\OrdersApi.jmx -Seed 12345 -Force
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$InputFile = '',
    [string]$OutputFile = '',
    [switch]$Force,
    [string]$TargetHost = 'localhost',
    [string]$Port = '8080',
    [string]$Protocol = 'http',
    [string]$BasePath = '',
    [string]$ApiKey = 'XXXXXXXXXXXX',
    [string]$Seed = '',
    [string]$AnyMethod = 'GET',
    [switch]$RequiredOnly,
    [switch]$UseExamples,
    # 値の位置に引用符なしで書かれた ${...}（後で置換するプレースホルダ）に入れる数値の既定値
    [string]$PlaceholderValue = '3000',
    [switch]$Help,
    [switch]$Version
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ToolName = 'openapi2jmx'
$script:ToolVersion = '1.0.0'
$script:JMeterVersion = '5.6.3'
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:NL = "`n"

# =============================================================================
#  ※ linux/openapi2jmx.sh 内の Python 実装と 1 関数ずつ対応させています。
#     どちらかを修正する場合は、必ずもう一方も同じように修正してください。
# =============================================================================

class JNum {
    [string]$Text
    JNum([string]$t) { $this.Text = $t }
}

$script:SKIP = New-Object System.Object

function Stop-Gen([string]$Message) {
    $ex = New-Object System.InvalidOperationException($Message)
    $ex.Data['OA2J'] = $true
    throw $ex
}

function Show-Usage {
    # Write-Host で表示する（関数の戻り値に混ざって呼び出し元に吸収されないように）
    $n = 'OpenApi2Jmx.ps1'
    Write-Host @"
使い方:
  .\$n -InputFile <OpenAPI定義.json> [オプション]

必須:
  -InputFile FILE      OpenAPI 3.0.x 定義ファイル（JSON 形式）

任意:
  -OutputFile FILE     出力する JMX ファイル（既定: カレントフォルダの <APIタイトル>.jmx）
  -Force               出力先に同名ファイルがあっても上書きする
  -TargetHost HOST     接続先ホストの既定値            （既定: localhost）
  -Port PORT           接続先ポートの既定値            （既定: 8080）
  -Protocol PROTO      http または https               （既定: http）
  -BasePath PATH       全 API パスの先頭に付けるパス   （既定: 空。例: /prod）
  -ApiKey KEY          X-API-KEY ヘッダの既定値        （既定: XXXXXXXXXXXX）
  -Seed N              テストデータ用乱数シード（0 以上の整数・12 桁以内）
                       同じシードなら同じテストデータを再生成します（既定: 毎回ランダム）
  -AnyMethod M         x-amazon-apigateway-any-method（ANY）を送るメソッド
                       GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS（既定: GET）
  -RequiredOnly        必須（required）のパラメータ・プロパティだけを生成する
  -UseExamples         example / default が定義されていればランダム値より優先する
  -PlaceholderValue N  値の位置に引用符なしで書かれた `${...}（後で置換するプレースホルダ）に
                       仮に入れる数値（既定: 3000）。置き換えた箇所は警告として表示します
  -Help               このヘルプを表示
  -Version             バージョンを表示

例:
  .\$n -InputFile .\openapi.json
  .\$n -InputFile .\openapi.json -OutputFile .\OrdersApi.jmx -Seed 12345 -Force

生成した JMX は次のように実行できます（結果: JTL とログ）:
  .\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx
"@
}

# ----------------------------------------------------------------- 乱数（両実装共通）
$script:RngState = 1L

function Initialize-Rng([long]$SeedValue) {
    $script:RngState = ($SeedValue % 2147483646L) + 1L
}

function Get-Next31 {
    $script:RngState = ($script:RngState * 48271L) % 2147483647L
    return $script:RngState
}

function Get-Between([long]$Lo, [long]$Hi) {
    if ($Hi -le $Lo) { return $Lo }
    $span = $Hi - $Lo + 1L
    if ($span -le 2147483646L) {
        $n = Get-Next31
        return [long]($Lo + (($n - 1L) % $span))
    }
    $a = (Get-Next31) - 1L
    $b = (Get-Next31) - 1L
    $r = $a * 2147483646L + $b
    return [long]($Lo + ($r % $span))
}

# ----------------------------------------------------------------- 値の判定・取得
$script:UNITS_LIMIT = 1000000000000000000L
$script:MAX_DECIMALS = 12
$script:MAX_DEPTH = 12
$script:ALNUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
$script:LOWER_ALNUM = 'abcdefghijklmnopqrstuvwxyz0123456789'
$script:HEXD = '0123456789abcdef'
$script:EPOCH_START = 1735689600L
$script:EPOCH_END = 1798761599L

function Test-Obj($x) { return ($x -is [System.Collections.IDictionary]) }
function Test-Arr($x) { return (($x -is [System.Collections.IList]) -and -not ($x -is [string])) }
function Test-Str($x) { return ($x -is [string]) }
function Test-Bool($x) { return ($x -is [bool]) }
function Test-Int($x) { return (($x -is [long]) -or ($x -is [int])) }
function Test-Dec($x) { return ($x -is [decimal]) }
function Test-Num($x) { return ((Test-Int $x) -or (Test-Dec $x)) }
function Test-Skip($x) { return [object]::ReferenceEquals($x, $script:SKIP) }

function Test-Has($o, [string]$k) {
    if ($o -is [System.Collections.Generic.Dictionary[string, object]]) { return $o.ContainsKey($k) }
    if ($o -is [System.Collections.Specialized.OrderedDictionary]) { return $o.Contains($k) }
    if ($o -is [System.Collections.IDictionary]) { return $o.Contains($k) }
    return $false
}

function Get-Prop($o, [string]$k) {
    if (Test-Has $o $k) { return , ($o[$k]) }
    return $null
}

function New-OMap { return , (New-Object System.Collections.Specialized.OrderedDictionary) }
function New-OList { return , (New-Object 'System.Collections.Generic.List[object]') }

function Copy-OMap($src) {
    $r = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($k in @($src.Keys)) { $r[[string]$k] = $src[$k] }
    return , $r
}

function ConvertTo-Dec($x) {
    if (Test-Int $x) { return [decimal]$x }
    if (Test-Dec $x) { return $x }
    return $null
}

function Format-Dec([decimal]$d) { return $d.ToString($script:Inv) }

function Limit-DecTo([decimal]$d, [decimal]$Lim) {
    if ($d -gt $Lim) { return $Lim }
    if ($d -lt (-$Lim)) { return (-$Lim) }
    return $d
}

function Get-IntOrNull($x) {
    if (Test-Int $x) { if ($x -ge 0) { return [long]$x } else { return $null } }
    if ((Test-Dec $x) -and ([decimal]::Truncate($x) -eq $x) -and ($x -ge 0)) { return [long]$x }
    return $null
}

function Get-Pow10([int]$d) {
    $p = 1L
    for ($i = 0; $i -lt $d; $i++) { $p = $p * 10L }
    return $p
}

function Get-FloorDiv([long]$a, [long]$b) {
    $rem = 0L
    $q = [System.Math]::DivRem($a, $b, [ref]$rem)
    if (($rem -ne 0) -and (($rem -lt 0) -ne ($b -lt 0))) { $q = $q - 1L }
    return [long]$q
}

function Get-CeilDiv([long]$a, [long]$b) { return [long](-(Get-FloorDiv (-$a) $b)) }

function ConvertTo-GenValue($x) {
    if ($null -eq $x) { return $null }
    if ($x -is [bool]) { return $x }
    if (Test-Int $x) { return [JNum]::new(([long]$x).ToString($script:Inv)) }
    if (Test-Dec $x) { return [JNum]::new((Format-Dec $x)) }
    if ($x -is [string]) { return $x }
    if (Test-Arr $x) {
        $l = New-Object 'System.Collections.Generic.List[object]'
        foreach ($i in $x) { $l.Add((ConvertTo-GenValue $i)) }
        return , $l
    }
    if (Test-Obj $x) {
        $o = New-Object System.Collections.Specialized.OrderedDictionary
        foreach ($k in @($x.Keys)) { $o[[string]$k] = (ConvertTo-GenValue $x[$k]) }
        return , $o
    }
    return [string]$x
}

# ----------------------------------------------------------------- 文字列の整形
function Get-CleanText([string]$s) {
    if ($null -eq $s) { return '' }
    $sb = New-Object System.Text.StringBuilder
    $n = $s.Length
    for ($i = 0; $i -lt $n; $i++) {
        $c = [int]$s[$i]
        if (($c -ge 0xD800) -and ($c -le 0xDBFF)) {
            if (($i + 1 -lt $n) -and ([int]$s[$i + 1] -ge 0xDC00) -and ([int]$s[$i + 1] -le 0xDFFF)) {
                [void]$sb.Append($s[$i]).Append($s[$i + 1])
                $i++
            }
            continue
        }
        if (($c -ge 0xDC00) -and ($c -le 0xDFFF)) { continue }
        if (($c -eq 9) -or ($c -eq 10) -or ($c -eq 13) -or (($c -ge 0x20) -and ($c -le 0xD7FF)) -or (($c -ge 0xE000) -and ($c -le 0xFFFD))) {
            [void]$sb.Append($s[$i])
        }
    }
    return $sb.ToString()
}

function Get-XmlEscape([string]$s) {
    $s = Get-CleanText $s
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;').Replace("`r", '&#xd;')
}

function Get-JsonStr([string]$s) {
    $s = Get-CleanText $s
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch -CaseSensitive ($ch) {
            '"' { [void]$sb.Append('\"'); break }
            '\' { [void]$sb.Append('\\'); break }
            "`n" { [void]$sb.Append('\n'); break }
            "`r" { [void]$sb.Append('\r'); break }
            "`t" { [void]$sb.Append('\t'); break }
            default { [void]$sb.Append($ch) }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-JsonText($v, [int]$Indent, [bool]$Pretty) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [JNum]) { return $v.Text }
    if ($v -is [string]) { return (Get-JsonStr $v) }
    if (Test-Obj $v) {
        if ($v.Count -eq 0) { return '{}' }
        $parts = New-Object 'System.Collections.Generic.List[string]'
        if (-not $Pretty) {
            foreach ($k in @($v.Keys)) { $parts.Add((Get-JsonStr ([string]$k)) + ':' + (ConvertTo-JsonText $v[$k] 0 $false)) }
            return '{' + [string]::Join(',', $parts) + '}'
        }
        $pad = '  ' * ($Indent + 1)
        foreach ($k in @($v.Keys)) { $parts.Add($pad + (Get-JsonStr ([string]$k)) + ': ' + (ConvertTo-JsonText $v[$k] ($Indent + 1) $true)) }
        return "{`n" + [string]::Join(",`n", $parts) + "`n" + ('  ' * $Indent) + '}'
    }
    if (Test-Arr $v) {
        if ($v.Count -eq 0) { return '[]' }
        $parts = New-Object 'System.Collections.Generic.List[string]'
        if (-not $Pretty) {
            foreach ($x in $v) { $parts.Add((ConvertTo-JsonText $x 0 $false)) }
            return '[' + [string]::Join(',', $parts) + ']'
        }
        $pad = '  ' * ($Indent + 1)
        foreach ($x in $v) { $parts.Add($pad + (ConvertTo-JsonText $x ($Indent + 1) $true)) }
        return "[`n" + [string]::Join(",`n", $parts) + "`n" + ('  ' * $Indent) + ']'
    }
    return (Get-JsonStr ([string]$v))
}

function Get-ScalarStr($v) {
    if ($null -eq $v) { return '' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [JNum]) { return $v.Text }
    if ($v -is [string]) { return $v }
    return (ConvertTo-JsonText $v 0 $false)
}

function Get-PctEncode([string]$s, [bool]$KeepSlash) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-CleanText $s))
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) {
        $isUnreserved = (($b -ge 0x41) -and ($b -le 0x5A)) -or (($b -ge 0x61) -and ($b -le 0x7A)) -or (($b -ge 0x30) -and ($b -le 0x39)) -or ($b -eq 0x2D) -or ($b -eq 0x2E) -or ($b -eq 0x5F) -or ($b -eq 0x7E)
        if ($isUnreserved -or ($KeepSlash -and ($b -eq 0x2F))) {
            [void]$sb.Append([char]$b)
        } else {
            [void]$sb.Append('%').Append($b.ToString('X2'))
        }
    }
    return $sb.ToString()
}

function Get-HeaderSafe([string]$s) {
    return (Get-CleanText $s).Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
}

function Get-FuncArg([string]$s) {
    return $s.Replace('\', '\\').Replace(',', '\,').Replace('$', '\$')
}

function Get-JavaHash([string]$s) {
    $h = 0L
    foreach ($ch in $s.ToCharArray()) {
        $h = (31L * $h + [long][int]$ch) % 4294967296L
    }
    if ($h -ge 2147483648L) { $h = $h - 4294967296L }
    return [long]$h
}

function Get-SafeName([string]$s) {
    $s = [regex]::Replace($s, '[^A-Za-z0-9._-]+', '_')
    $s = [regex]::Replace($s, '_+', '_').Trim([char[]]@('_', '.'))
    if ($s.Length -eq 0) { return 'openapi' }
    return $s
}

function Get-CpLen([string]$s) {
    $n = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if (-not (($c -ge 0xDC00) -and ($c -le 0xDFFF))) { $n++ }
    }
    return $n
}

function ConvertFrom-CodePoint([int]$c) { return [char]::ConvertFromUtf32($c) }

# ----------------------------------------------------------------- 生成コンテキスト
$script:Doc = $null
$script:SeedValue = 0L
$script:OptRequiredOnly = $false
$script:OptUseExamples = $false
$script:OptAnyMethod = 'GET'
$script:Warnings = New-Object 'System.Collections.Generic.List[string]'

function Add-Warn([string]$m) {
    if (-not $script:Warnings.Contains($m)) { $script:Warnings.Add($m) }
}

function Get-UnescapedToken([string]$tok) {
    if ($tok.Contains('%')) {
        try { $tok = [System.Uri]::UnescapeDataString($tok) } catch { }
    }
    return $tok.Replace('~1', '/').Replace('~0', '~')
}

function Resolve-Ref($ref) {
    if (-not (Test-Str $ref)) { return $null }
    if (-not $ref.StartsWith('#', [System.StringComparison]::Ordinal)) { return $null }
    if (($ref -ceq '#') -or ($ref -ceq '#/')) { return , $script:Doc }
    if (-not $ref.StartsWith('#/', [System.StringComparison]::Ordinal)) { return $null }
    $cur = $script:Doc
    foreach ($tok in $ref.Substring(2).Split([char]'/')) {
        $key = Get-UnescapedToken $tok
        if ((Test-Obj $cur) -and (Test-Has $cur $key)) {
            $cur = $cur[$key]
        } elseif ((Test-Arr $cur) -and ($key -cmatch '^(0|[1-9][0-9]*)$') -and ([long]$key -lt $cur.Count)) {
            $cur = $cur[[int]$key]
        } else {
            return $null
        }
    }
    return , $cur
}

function Get-RefText($ref) {
    if (Test-Str $ref) { return $ref }
    return '(不正な $ref)'
}

function Resolve-Deref($obj, [string]$What) {
    $seen = New-Object 'System.Collections.Generic.List[string]'
    while ((Test-Obj $obj) -and (Test-Has $obj '$ref')) {
        $rt = Get-RefText $obj['$ref']
        if ($seen.Contains($rt) -or ($seen.Count -gt 32)) {
            Add-Warn ('{0} の $ref が循環しています: {1}' -f $What, $rt)
            return $null
        }
        $seen.Add($rt)
        $target = Resolve-Ref $obj['$ref']
        if ($null -eq $target) {
            Add-Warn ('{0} の $ref を解決できません（外部ファイル参照は未対応）: {1}' -f $What, $rt)
            return $null
        }
        $obj = $target
    }
    return , $obj
}

# ----------------------------------------------------------------- スキーマ → テストデータ
$script:TYPES = @('object', 'array', 'integer', 'number', 'boolean', 'string', 'null')

function Get-SchemaType($schema) {
    $t = Get-Prop $schema 'type'
    if (Test-Arr $t) {
        $names = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in $t) { if (Test-Str $x) { $names.Add($x) } }
        $nonNull = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in $names) { if ($x -cne 'null') { $nonNull.Add($x) } }
        if ($nonNull.Count -gt 0) { $t = $nonNull[0] }
        elseif ($names.Count -gt 0) { $t = 'null' }
        else { $t = $null }
    }
    if ((Test-Str $t) -and ($script:TYPES -ccontains $t)) { return $t }
    if ((Test-Has $schema 'properties') -or (Test-Has $schema 'additionalProperties') -or (Test-Has $schema 'minProperties') -or (Test-Has $schema 'maxProperties')) { return 'object' }
    if ((Test-Has $schema 'items') -or (Test-Has $schema 'minItems') -or (Test-Has $schema 'maxItems')) { return 'array' }
    $fmt = Get-Prop $schema 'format'
    if ((Test-Str $fmt) -and (($fmt -ceq 'int32') -or ($fmt -ceq 'int64'))) { return 'integer' }
    if ((Test-Str $fmt) -and (($fmt -ceq 'float') -or ($fmt -ceq 'double'))) { return 'number' }
    if ((Test-Has $schema 'minimum') -or (Test-Has $schema 'maximum') -or (Test-Has $schema 'multipleOf') -or (Test-Has $schema 'exclusiveMinimum') -or (Test-Has $schema 'exclusiveMaximum')) { return 'number' }
    return 'string'
}

function Test-ListContains($list, $value) {
    foreach ($x in $list) {
        if (($x -is [string]) -and ($value -is [string])) { if ($x -ceq $value) { return $true } }
        elseif ([object]::Equals($x, $value)) { return $true }
    }
    return $false
}

function Merge-Schemas($a, $b) {
    $r = Copy-OMap $a
    foreach ($k in @($b.Keys)) {
        $key = [string]$k
        $v = $b[$k]
        if (($key -ceq 'properties') -and (Test-Obj $v)) {
            $cur = Get-Prop $r 'properties'
            if (Test-Obj $cur) { $props = Copy-OMap $cur } else { $props = New-OMap }
            foreach ($pk in @($v.Keys)) { if (-not $props.Contains([string]$pk)) { $props[[string]$pk] = $v[$pk] } }
            $r['properties'] = $props
        } elseif (($key -ceq 'required') -and (Test-Arr $v)) {
            $req = New-Object 'System.Collections.Generic.List[object]'
            $cur = Get-Prop $r 'required'
            if (Test-Arr $cur) { foreach ($x in $cur) { $req.Add($x) } }
            foreach ($x in $v) { if (-not (Test-ListContains $req $x)) { $req.Add($x) } }
            $r['required'] = $req
        } elseif (-not $r.Contains($key)) {
            $r[$key] = $v
        }
    }
    return , $r
}

# 戻り値: @{ S = 実体 or $null; Stack = List[string]; State = 'ok'|'cycle'|'unresolved' }
function Resolve-SchemaRef($s, $stack) {
    $cur = $s
    $st = $stack
    while ((Test-Obj $cur) -and (Test-Has $cur '$ref')) {
        $rt = Get-RefText $cur['$ref']
        if ($st.Contains($rt)) { return @{ S = $null; Stack = $st; State = 'cycle' } }
        $t = Resolve-Ref $cur['$ref']
        if ($null -eq $t) {
            Add-Warn ('スキーマの $ref を解決できません（外部ファイル参照は未対応）: ' + $rt)
            return @{ S = $null; Stack = $st; State = 'unresolved' }
        }
        $ns = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in $st) { $ns.Add($x) }
        $ns.Add($rt)
        $st = $ns
        $cur = $t
    }
    return @{ S = $cur; Stack = $st; State = 'ok' }
}

function Merge-AllOf($schema, $stack) {
    $result = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($k in @($schema.Keys)) { if ([string]$k -cne 'allOf') { $result[[string]$k] = $schema[$k] } }
    foreach ($sub in $schema['allOf']) {
        $res = Resolve-SchemaRef $sub $stack
        if (($res.State -cne 'ok') -or -not (Test-Obj $res.S)) { continue }
        $s = $res.S
        if (Test-Arr (Get-Prop $s 'allOf')) { $s = Merge-AllOf $s $res.Stack }
        $result = Merge-Schemas $result $s
    }
    return , $result
}

function New-Gen($schema, [int]$Depth, $stack) {
    if (($null -eq $schema) -or (($schema -is [bool]) -and $schema)) { $schema = New-OMap }
    if (($schema -is [bool]) -or -not (Test-Obj $schema)) { return $script:SKIP }
    if (Test-Has $schema '$ref') {
        $res = Resolve-SchemaRef $schema $stack
        if ($res.State -ceq 'cycle') { return $script:SKIP }
        if ($res.State -ceq 'unresolved') { return 'UNRESOLVED_REF' }
        return , (New-Gen $res.S $Depth $res.Stack)
    }
    if ($Depth -gt $script:MAX_DEPTH) { return $script:SKIP }
    if (Test-Arr (Get-Prop $schema 'allOf')) { $schema = Merge-AllOf $schema $stack }
    foreach ($key in @('oneOf', 'anyOf')) {
        $alts = Get-Prop $schema $key
        if ((Test-Arr $alts) -and ($alts.Count -gt 0)) {
            $base = New-Object System.Collections.Specialized.OrderedDictionary
            foreach ($k in @($schema.Keys)) { if (([string]$k -cne 'oneOf') -and ([string]$k -cne 'anyOf')) { $base[[string]$k] = $schema[$k] } }
            $res = Resolve-SchemaRef $alts[0] $stack
            if ($res.State -ceq 'cycle') { return $script:SKIP }
            if ($res.State -ceq 'unresolved') { return 'UNRESOLVED_REF' }
            $alt = $res.S
            if (-not (Test-Obj $alt)) { $alt = New-OMap }
            return , (New-Gen (Merge-Schemas $base $alt) $Depth $res.Stack)
        }
    }
    if ($script:OptUseExamples) {
        if (Test-Has $schema 'example') { return , (ConvertTo-GenValue $schema['example']) }
        $exs = Get-Prop $schema 'examples'
        if ((Test-Arr $exs) -and ($exs.Count -gt 0)) { return , (ConvertTo-GenValue $exs[0]) }
        if (Test-Has $schema 'default') { return , (ConvertTo-GenValue $schema['default']) }
    }
    if (Test-Has $schema 'const') { return , (ConvertTo-GenValue $schema['const']) }
    $enum = Get-Prop $schema 'enum'
    if ((Test-Arr $enum) -and ($enum.Count -gt 0)) {
        $cands = New-Object 'System.Collections.Generic.List[object]'
        foreach ($e in $enum) { if ($null -ne $e) { $cands.Add($e) } }
        if ($cands.Count -eq 0) { return $null }
        return , (ConvertTo-GenValue $cands[[int](Get-Between 0 ($cands.Count - 1))])
    }
    $t = Get-SchemaType $schema
    switch -CaseSensitive ($t) {
        'object' { return , (New-GenObject $schema $Depth $stack) }
        'array' { return , (New-GenArray $schema $Depth $stack) }
        'integer' { return (New-GenInteger $schema) }
        'number' { return (New-GenNumber $schema) }
        'boolean' { return ((Get-Between 0 1) -eq 1) }
        'null' { return $null }
    }
    return (New-GenString $schema)
}

function Test-ReadOnly($pschema) {
    $s = $pschema
    $guard = 0
    while ((Test-Obj $s) -and (Test-Has $s '$ref') -and ($guard -lt 32)) {
        $s = Resolve-Ref $s['$ref']
        $guard++
    }
    if (-not (Test-Obj $s)) { return $false }
    $ro = Get-Prop $s 'readOnly'
    return (($ro -is [bool]) -and $ro)
}

function New-GenObject($schema, [int]$Depth, $stack) {
    $result = New-Object System.Collections.Specialized.OrderedDictionary
    $props = Get-Prop $schema 'properties'
    $req = Get-Prop $schema 'required'
    $required = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Arr $req) { foreach ($x in $req) { if (Test-Str $x) { $required.Add($x) } } }
    if (Test-Obj $props) {
        foreach ($nk in @($props.Keys)) {
            $name = [string]$nk
            if ($script:OptRequiredOnly -and -not $required.Contains($name)) { continue }
            $pschema = $props[$nk]
            if (Test-ReadOnly $pschema) { continue }
            $v = New-Gen $pschema ($Depth + 1) $stack
            if (Test-Skip $v) { continue }
            $result[$name] = $v
        }
    }
    $addl = Get-Prop $schema 'additionalProperties'
    $propsCount = 0
    if (Test-Obj $props) { $propsCount = $props.Count }
    if (($result.Count -eq 0) -and ($propsCount -eq 0) -and (Test-Obj $addl) -and ($addl.Count -gt 0) -and -not $script:OptRequiredOnly) {
        $v = New-Gen $addl ($Depth + 1) $stack
        if (-not (Test-Skip $v)) { $result['key1'] = $v }
    }
    return , $result
}

function New-GenArray($schema, [int]$Depth, $stack) {
    $items = Get-Prop $schema 'items'
    if (-not (Test-Obj $items)) { $items = New-OMap }
    $mn = Get-IntOrNull (Get-Prop $schema 'minItems')
    $mx = Get-IntOrNull (Get-Prop $schema 'maxItems')
    $n = 0L
    if ($null -ne $mn) { $n = $mn }
    if ($n -lt 1) { $n = 1L }
    if (($null -ne $mx) -and ($n -gt $mx)) { $n = $mx }
    if ($n -gt 50) { $n = 50L }
    $uq = Get-Prop $schema 'uniqueItems'
    $unique = (($uq -is [bool]) -and $uq)
    $result = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $n; $i++) {
        $v = New-Gen $items ($Depth + 1) $stack
        if (Test-Skip $v) { break }
        if ($unique) {
            $key = ConvertTo-JsonText $v 0 $false
            $tries = 0
            while ($seen.Contains($key) -and ($tries -lt 10)) {
                $v = New-Gen $items ($Depth + 1) $stack
                if (Test-Skip $v) { break }
                $key = ConvertTo-JsonText $v 0 $false
                $tries++
            }
            if (Test-Skip $v) { break }
            $seen.Add($key)
        }
        $result.Add($v)
    }
    return , $result
}

# 戻り値: @(lo, hi)（scale 単位の整数）
function Get-NumBounds($schema, [long]$Scale) {
    $mn = ConvertTo-Dec (Get-Prop $schema 'minimum')
    $mx = ConvertTo-Dec (Get-Prop $schema 'maximum')
    $exmin = Get-Prop $schema 'exclusiveMinimum'
    $exmax = Get-Prop $schema 'exclusiveMaximum'
    $exLo = (($exmin -is [bool]) -and $exmin)
    $exHi = (($exmax -is [bool]) -and $exmax)
    if (Test-Num $exmin) {
        $e = ConvertTo-Dec $exmin
        if (($null -eq $mn) -or ($e -ge $mn)) { $mn = $e; $exLo = $true }
    }
    if (Test-Num $exmax) {
        $e = ConvertTo-Dec $exmax
        if (($null -eq $mx) -or ($e -le $mx)) { $mx = $e; $exHi = $true }
    }
    $vlim = [decimal](Get-FloorDiv $script:UNITS_LIMIT $Scale)
    $lo = $null
    $hi = $null
    if ($null -ne $mn) {
        $v = (Limit-DecTo $mn $vlim) * [decimal]$Scale
        $lo = [long][decimal]::Ceiling($v)
        if ($exLo -and ([decimal]$lo -eq $v)) { $lo = $lo + 1L }
    }
    if ($null -ne $mx) {
        $v = (Limit-DecTo $mx $vlim) * [decimal]$Scale
        $hi = [long][decimal]::Floor($v)
        if ($exHi -and ([decimal]$hi -eq $v)) { $hi = $hi - 1L }
    }
    $one = $Scale
    if (($null -eq $lo) -and ($null -eq $hi)) {
        $lo = $one
        $hi = 100L * $one
    } elseif ($null -eq $hi) {
        $hi = $lo + 99L * $one
    } elseif ($null -eq $lo) {
        if ($hi -ge $one) { $lo = $one } else { $lo = $hi - 99L * $one }
    }
    if ($lo -gt $hi) { $hi = $lo }
    return @([long]$lo, [long]$hi)
}

function New-GenInteger($schema) {
    $b = Get-NumBounds $schema 1L
    $lo = [long]$b[0]
    $hi = [long]$b[1]
    $fmt = Get-Prop $schema 'format'
    if ((Test-Str $fmt) -and ($fmt -ceq 'int32')) {
        if ($lo -lt -2147483648L) { $lo = -2147483648L }
        if ($hi -gt 2147483647L) { $hi = 2147483647L }
        if ($lo -gt $hi) { $hi = $lo }
    }
    $m = ConvertTo-Dec (Get-Prop $schema 'multipleOf')
    if (($null -ne $m) -and ($m -gt 0) -and ([decimal]::Truncate($m) -eq $m)) {
        $mi = [long]$m
        $kmin = Get-CeilDiv $lo $mi
        $kmax = Get-FloorDiv $hi $mi
        if ($kmin -le $kmax) { return [JNum]::new(((Get-Between $kmin $kmax) * $mi).ToString($script:Inv)) }
        return [JNum]::new($lo.ToString($script:Inv))
    }
    return [JNum]::new((Get-Between $lo $hi).ToString($script:Inv))
}

function Get-DecimalsOf([decimal]$d) {
    $s = Format-Dec $d
    $i = $s.IndexOf('.')
    if ($i -ge 0) { return $s.Substring($i + 1).TrimEnd([char]'0').Length }
    return 0
}

function Format-Units([long]$Units, [int]$D) {
    $neg = ($Units -lt 0)
    if ($neg) { $a = -$Units } else { $a = $Units }
    if ($D -eq 0) {
        $s = $a.ToString($script:Inv)
    } else {
        $p = Get-Pow10 $D
        $rem = 0L
        $q = [System.Math]::DivRem([long]$a, [long]$p, [ref]$rem)
        $s = ([long]$q).ToString($script:Inv) + '.' + ([long]$rem).ToString($script:Inv).PadLeft($D, [char]'0')
    }
    if ($neg) { return '-' + $s }
    return $s
}

function New-GenNumber($schema) {
    $m = ConvertTo-Dec (Get-Prop $schema 'multipleOf')
    if (($null -ne $m) -and ($m -le 0)) { $m = $null }
    if ($null -ne $m) { $d = Get-DecimalsOf $m } else { $d = 2 }
    if ($d -gt $script:MAX_DECIMALS) { $d = $script:MAX_DECIMALS }
    $scale = Get-Pow10 $d
    $b = Get-NumBounds $schema $scale
    $lo = [long]$b[0]
    $hi = [long]$b[1]
    $units = $null
    if ($null -ne $m) {
        $mu = $m * [decimal]$scale
        if (($mu -gt 0) -and ([decimal]::Truncate($mu) -eq $mu)) {
            $mi = [long]$mu
            $kmin = Get-CeilDiv $lo $mi
            $kmax = Get-FloorDiv $hi $mi
            if ($kmin -le $kmax) { $units = (Get-Between $kmin $kmax) * $mi } else { $units = $lo }
        }
    }
    if ($null -eq $units) { $units = Get-Between $lo $hi }
    return [JNum]::new((Format-Units ([long]$units) $d))
}

function Get-RandStr([string]$Pool, [long]$N) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $N; $i++) {
        [void]$sb.Append($Pool[[int](Get-Between 0 ($Pool.Length - 1))])
    }
    return $sb.ToString()
}

function Get-ChooseLen($minL, $maxL) {
    $lo = 0L
    if ($null -ne $minL) { $lo = [long]$minL }
    if ($lo -lt 8) { $lo = 8L }
    if (($null -ne $maxL) -and ($lo -gt $maxL)) { $lo = [long]$maxL }
    if ($null -eq $maxL) {
        $hi = [System.Math]::Max($lo, 16L)
    } else {
        $hi = [System.Math]::Min([long]$maxL, [System.Math]::Max($lo, 16L))
    }
    if ($hi -lt $lo) { $hi = $lo }
    return (Get-Between $lo $hi)
}

function Get-UtcFromEpoch([long]$Secs) {
    return ([datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)).AddSeconds([double]$Secs)
}

function New-GenString($schema) {
    $fmt = Get-Prop $schema 'format'
    if (-not (Test-Str $fmt)) { $fmt = '' }
    $minL = Get-IntOrNull (Get-Prop $schema 'minLength')
    $maxL = Get-IntOrNull (Get-Prop $schema 'maxLength')
    $pattern = Get-Prop $schema 'pattern'
    if ((Test-Str $pattern) -and ($pattern.Length -gt 0)) {
        $s = New-FromPattern $pattern $minL $maxL
        if ($null -ne $s) { return $s }
    }
    switch -CaseSensitive ($fmt) {
        'date-time' {
            return (Get-UtcFromEpoch (Get-Between $script:EPOCH_START $script:EPOCH_END)).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", $script:Inv)
        }
        'date' {
            $days = Get-Between ([long][System.Math]::Floor($script:EPOCH_START / 86400)) ([long][System.Math]::Floor($script:EPOCH_END / 86400))
            return (Get-UtcFromEpoch ($days * 86400L)).ToString("yyyy'-'MM'-'dd", $script:Inv)
        }
        'time' {
            $secs = Get-Between 0 86399
            $hh = Get-FloorDiv $secs 3600
            $mm = Get-FloorDiv ($secs % 3600L) 60
            $ss = $secs % 60L
            return ('{0}:{1}:{2}' -f ([long]$hh).ToString('00', $script:Inv), ([long]$mm).ToString('00', $script:Inv), ([long]$ss).ToString('00', $script:Inv))
        }
        'email' { return (Get-RandStr $script:LOWER_ALNUM 8) + '@example.com' }
        'uuid' {
            $sb = New-Object System.Text.StringBuilder
            for ($i = 0; $i -lt 32; $i++) {
                if ($i -eq 12) { [void]$sb.Append('4') }
                elseif ($i -eq 16) { [void]$sb.Append($script:HEXD[[int](8 + (Get-Between 0 3))]) }
                else { [void]$sb.Append($script:HEXD[[int](Get-Between 0 15)]) }
            }
            $u = $sb.ToString()
            return $u.Substring(0, 8) + '-' + $u.Substring(8, 4) + '-' + $u.Substring(12, 4) + '-' + $u.Substring(16, 4) + '-' + $u.Substring(20, 12)
        }
        'uri' { return 'https://example.com/' + (Get-RandStr $script:LOWER_ALNUM 8) }
        'url' { return 'https://example.com/' + (Get-RandStr $script:LOWER_ALNUM 8) }
        'uri-reference' { return 'https://example.com/' + (Get-RandStr $script:LOWER_ALNUM 8) }
        'iri' { return 'https://example.com/' + (Get-RandStr $script:LOWER_ALNUM 8) }
        'iri-reference' { return 'https://example.com/' + (Get-RandStr $script:LOWER_ALNUM 8) }
        'hostname' { return (Get-RandStr $script:LOWER_ALNUM 8) + '.example.com' }
        'idn-hostname' { return (Get-RandStr $script:LOWER_ALNUM 8) + '.example.com' }
        'ipv4' { return '192.0.2.' + (Get-Between 1 254).ToString($script:Inv) }
        'ipv6' { return '2001:db8::' + (Get-Between 1 65535).ToString('x') }
        'byte' {
            $raw = New-Object byte[] 12
            for ($i = 0; $i -lt 12; $i++) { $raw[$i] = [byte](Get-Between 0 255) }
            return [System.Convert]::ToBase64String($raw)
        }
        'password' { return (Get-RandStr $script:ALNUM 12) }
        'binary' { return (Get-RandStr $script:ALNUM 16) }
    }
    return (Get-RandStr $script:ALNUM (Get-ChooseLen $minL $maxL))
}

# ----------------------------------------------------------------- pattern（正規表現）から文字列を生成
function New-CodeRange([int]$a, [int]$b) {
    $l = New-Object 'System.Collections.Generic.List[int]'
    for ($c = $a; $c -le $b; $c++) { $l.Add($c) }
    return , $l
}

function New-SortedCodes($list) {
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($c in $list) { [void]$set.Add([int]$c) }
    $l = New-Object 'System.Collections.Generic.List[int]' (, [int[]]@($set))
    $l.Sort()
    return , ($l.ToArray())
}

$script:DIGIT_SET = (New-CodeRange 0x30 0x39).ToArray()
$script:UPPER_SET = (New-CodeRange 0x41 0x5A).ToArray()
$script:LOWER_SET = (New-CodeRange 0x61 0x7A).ToArray()
$script:ALNUM_SET = [int[]]($script:DIGIT_SET + $script:UPPER_SET + $script:LOWER_SET)
$script:WORD_SET = New-SortedCodes ([int[]]($script:ALNUM_SET + @(0x5F)))
$script:NONDIGIT_SET = [int[]]($script:UPPER_SET + $script:LOWER_SET)
$script:NONWORD_SET = [int[]]@(0x2D, 0x2E)
$script:SPACE_SET = [int[]]@(0x20)
$script:NEG_BASE = New-SortedCodes ([int[]]($script:ALNUM_SET + @(0x2D, 0x2E, 0x5F)))
$script:PRINTABLE_SET = (New-CodeRange 0x21 0x7E).ToArray()

function Test-ValidCode([int]$c) {
    return (($c -eq 9) -or ($c -eq 10) -or ($c -eq 13) -or (($c -ge 0x20) -and ($c -le 0xD7FF)) -or (($c -ge 0xE000) -and ($c -le 0xFFFD)) -or (($c -ge 0x10000) -and ($c -le 0x10FFFF)))
}

# パターン文字列はコードポイント単位の配列で扱う（Python の str と同じ単位）
$script:PP = $null
$script:PI = 0

function Stop-Pattern([string]$m) {
    $ex = New-Object System.FormatException($m)
    $ex.Data['PATTERN'] = $true
    throw $ex
}

function Get-PPeek([int]$k = 0) {
    $j = $script:PI + $k
    if ($j -lt $script:PP.Count) { return $script:PP[$j] }
    return $null
}

function Get-PTake {
    $ch = $script:PP[$script:PI]
    $script:PI++
    return $ch
}

function New-PNode([string]$T) { return @{ T = $T } }

function Read-PAlt {
    $options = New-Object 'System.Collections.Generic.List[object]'
    $options.Add((Read-PSeq))
    while ((Get-PPeek) -ceq '|') {
        [void](Get-PTake)
        $options.Add((Read-PSeq))
    }
    if ($options.Count -eq 1) { return $options[0] }
    $n = New-PNode 'alt'
    $n.Items = $options
    return $n
}

function Read-PSeq {
    $items = New-Object 'System.Collections.Generic.List[object]'
    while ($true) {
        $ch = Get-PPeek
        if (($null -eq $ch) -or ($ch -ceq '|') -or ($ch -ceq ')')) { break }
        $items.Add((Read-PQuant (Read-PAtom)))
    }
    $n = New-PNode 'seq'
    $n.Items = $items
    return $n
}

function Get-EmptySeq {
    $n = New-PNode 'seq'
    $n.Items = New-Object 'System.Collections.Generic.List[object]'
    return $n
}

function New-PLit([int]$c) { $n = New-PNode 'lit'; $n.C = $c; return $n }
function New-PSet($pool) { $n = New-PNode 'set'; $n.Pool = [int[]]$pool; return $n }

function Read-PAtom {
    $ch = Get-PTake
    if ($ch -ceq '(') {
        if ((Get-PPeek) -ceq '?') {
            [void](Get-PTake)
            $c2 = Get-PPeek
            if ($c2 -ceq ':') { [void](Get-PTake) }
            elseif (($c2 -ceq 'P') -and ((Get-PPeek 1) -ceq '<')) { Skip-PGroupName 2 }
            elseif (($c2 -ceq '<') -and ($null -ne (Get-PPeek 1)) -and ((Get-PPeek 1) -cne '=') -and ((Get-PPeek 1) -cne '!')) { Skip-PGroupName 1 }
            else { Stop-Pattern 'unsupported group' }
        }
        $node = Read-PAlt
        if ((Get-PPeek) -cne ')') { Stop-Pattern 'unbalanced' }
        [void](Get-PTake)
        return $node
    }
    if ($ch -ceq '[') { return (Read-PClass) }
    if ($ch -ceq '.') { return (New-PSet $script:ALNUM_SET) }
    if (($ch -ceq '^') -or ($ch -ceq '$')) { return (Get-EmptySeq) }
    if ($ch -ceq '\') { return (Read-PEscape $false) }
    if (($ch -ceq '*') -or ($ch -ceq '+') -or ($ch -ceq '?') -or ($ch -ceq ')')) { Stop-Pattern 'quantifier without target' }
    return (New-PLit ([char]::ConvertToUtf32($ch, 0)))
}

function Skip-PGroupName([int]$k) {
    for ($i = 0; $i -lt $k; $i++) { [void](Get-PTake) }
    while ($true) {
        $c = Get-PPeek
        if ($null -eq $c) { Stop-Pattern 'bad group name' }
        [void](Get-PTake)
        if ($c -ceq '>') { return }
    }
}

function Read-PHex([int]$Count) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Count; $i++) {
        $c = Get-PPeek $i
        if ($null -eq $c) { Stop-Pattern 'bad hex escape' }
        [void]$sb.Append($c)
    }
    $s = $sb.ToString()
    if (-not ($s -cmatch '^[0-9A-Fa-f]+$')) { Stop-Pattern 'bad hex escape' }
    $script:PI += $Count
    return [System.Convert]::ToInt32($s, 16)
}

function Read-PEscape([bool]$InClass) {
    if ($script:PI -ge $script:PP.Count) { Stop-Pattern 'trailing backslash' }
    $ch = Get-PTake
    switch -CaseSensitive ($ch) {
        'd' { return (New-PSet $script:DIGIT_SET) }
        'D' { return (New-PSet $script:NONDIGIT_SET) }
        'w' { return (New-PSet $script:WORD_SET) }
        'W' { return (New-PSet $script:NONWORD_SET) }
        's' { return (New-PSet $script:SPACE_SET) }
        'S' { return (New-PSet $script:ALNUM_SET) }
        't' { return (New-PLit 9) }
        'n' { return (New-PLit 10) }
        'r' { return (New-PLit 13) }
        'u' {
            $c = Read-PHex 4
            if (-not (Test-ValidCode $c)) { Stop-Pattern 'bad code point' }
            return (New-PLit $c)
        }
        'x' {
            $c = Read-PHex 2
            if (-not (Test-ValidCode $c)) { Stop-Pattern 'bad code point' }
            return (New-PLit $c)
        }
    }
    if (@('b', 'B', 'A', 'z', 'Z', 'G') -ccontains $ch) {
        if ($InClass) { Stop-Pattern 'unsupported escape in class' }
        return (Get-EmptySeq)
    }
    if ('0123456789'.Contains($ch) -or (@('p', 'P', 'k', 'c', 'f', 'v', 'e', 'a', 'Q', 'E') -ccontains $ch)) { Stop-Pattern 'unsupported escape' }
    return (New-PLit ([char]::ConvertToUtf32($ch, 0)))
}

function Read-PClassItem {
    $ch = Get-PTake
    if ($ch -ceq '\') { return (Read-PEscape $true) }
    if (($ch -ceq '[') -and ((Get-PPeek) -ceq ':')) { Stop-Pattern 'posix class' }
    return (New-PLit ([char]::ConvertToUtf32($ch, 0)))
}

function Read-PClass {
    $negate = $false
    if ((Get-PPeek) -ceq '^') { [void](Get-PTake); $negate = $true }
    $codes = New-Object 'System.Collections.Generic.HashSet[int]'
    $first = $true
    while ($true) {
        if ($script:PI -ge $script:PP.Count) { Stop-Pattern 'unterminated class' }
        if (((Get-PPeek) -ceq ']') -and -not $first) { [void](Get-PTake); break }
        $first = $false
        $item = Read-PClassItem
        if (($item.T -ceq 'lit') -and ((Get-PPeek) -ceq '-') -and ($null -ne (Get-PPeek 1)) -and ((Get-PPeek 1) -cne ']')) {
            [void](Get-PTake)
            $item2 = Read-PClassItem
            if ($item2.T -cne 'lit') { Stop-Pattern 'bad range' }
            $a = [int]$item.C
            $b = [int]$item2.C
            if (($a -gt $b) -or (($b - $a) -gt 70000)) { Stop-Pattern 'bad range' }
            for ($c = $a; $c -le $b; $c++) { [void]$codes.Add($c) }
        } elseif ($item.T -ceq 'lit') {
            [void]$codes.Add([int]$item.C)
        } elseif ($item.T -ceq 'set') {
            foreach ($c in $item.Pool) { [void]$codes.Add([int]$c) }
        } else {
            Stop-Pattern 'bad class item'
        }
    }
    $pool = New-Object 'System.Collections.Generic.List[int]'
    if ($negate) {
        foreach ($c in $script:NEG_BASE) { if (-not $codes.Contains($c)) { $pool.Add($c) } }
        if ($pool.Count -eq 0) {
            foreach ($c in $script:PRINTABLE_SET) { if (-not $codes.Contains($c)) { $pool.Add($c) } }
        }
    } else {
        foreach ($c in $codes) { $pool.Add($c) }
        $pool.Sort()
    }
    $valid = New-Object 'System.Collections.Generic.List[int]'
    foreach ($c in $pool) { if (Test-ValidCode $c) { $valid.Add($c) } }
    if ($valid.Count -eq 0) { Stop-Pattern 'empty class' }
    return (New-PSet $valid.ToArray())
}

function Read-PQuant($node) {
    while ($true) {
        $ch = Get-PPeek
        if ($ch -ceq '*') { [void](Get-PTake); $mn = 0; $mx = -1 }
        elseif ($ch -ceq '+') { [void](Get-PTake); $mn = 1; $mx = -1 }
        elseif ($ch -ceq '?') { [void](Get-PTake); $mn = 0; $mx = 1 }
        elseif ($ch -ceq '{') {
            $sb = New-Object System.Text.StringBuilder
            for ($j = $script:PI; $j -lt $script:PP.Count; $j++) { [void]$sb.Append($script:PP[$j]) }
            $m = [regex]::Match($sb.ToString(), '^\{([0-9]+)(,([0-9]*))?\}')
            if (-not $m.Success) { return $node }
            $script:PI += $m.Value.Length
            $mn = [int]::Parse($m.Groups[1].Value, $script:Inv)
            if (-not $m.Groups[2].Success) { $mx = $mn }
            elseif ($m.Groups[3].Value -ceq '') { $mx = -1 }
            else { $mx = [int]::Parse($m.Groups[3].Value, $script:Inv) }
            if ((($mx -ne -1) -and ($mx -lt $mn)) -or ($mn -gt 1000)) { Stop-Pattern 'bad quantifier' }
        } else {
            return $node
        }
        if (((Get-PPeek) -ceq '?') -or ((Get-PPeek) -ceq '+')) { [void](Get-PTake) }
        $r = New-PNode 'rep'
        $r.Node = $node
        $r.Min = $mn
        $r.Max = $mx
        $node = $r
    }
}

function Write-PNode($node, [System.Text.StringBuilder]$Out) {
    switch -CaseSensitive ($node.T) {
        'lit' { [void]$Out.Append((ConvertFrom-CodePoint $node.C)) }
        'set' {
            $pool = $node.Pool
            [void]$Out.Append((ConvertFrom-CodePoint $pool[[int](Get-Between 0 ($pool.Length - 1))]))
        }
        'seq' { foreach ($x in $node.Items) { Write-PNode $x $Out } }
        'alt' {
            $opts = $node.Items
            Write-PNode $opts[[int](Get-Between 0 ($opts.Count - 1))] $Out
        }
        'rep' {
            $mn = [long]$node.Min
            $mx = [long]$node.Max
            if ($mx -eq -1) { $mx = $mn + 5 }
            $cap = [System.Math]::Max($mn, 16L)
            if ($mx -gt $cap) { $mx = $cap }
            $k = Get-Between $mn $mx
            for ($i = 0; $i -lt $k; $i++) { Write-PNode $node.Node $Out }
        }
    }
}

function ConvertTo-CodePointList([string]$s) {
    $l = New-Object 'System.Collections.Generic.List[string]'
    $i = 0
    while ($i -lt $s.Length) {
        if ([char]::IsHighSurrogate($s[$i]) -and ($i + 1 -lt $s.Length) -and [char]::IsLowSurrogate($s[$i + 1])) {
            $l.Add($s.Substring($i, 2))
            $i += 2
        } else {
            $l.Add([string]$s[$i])
            $i++
        }
    }
    return , $l
}

function New-FromPattern([string]$Pattern, $minL, $maxL) {
    $script:PP = ConvertTo-CodePointList $Pattern
    $script:PI = 0
    try {
        $ast = Read-PAlt
        if ($script:PI -ne $script:PP.Count) { Stop-Pattern 'unexpected' }
    } catch {
        if ($_.Exception.Data.Contains('PATTERN')) {
            Add-Warn ('pattern を解釈できないためランダム英数字で代用しました: ' + $Pattern)
            return $null
        }
        throw
    }
    $rx = $null
    try { $rx = New-Object System.Text.RegularExpressions.Regex($Pattern) } catch { $rx = $null }
    $last = $null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $sb = New-Object System.Text.StringBuilder
        Write-PNode $ast $sb
        $s = $sb.ToString()
        $last = $s
        if (($null -ne $rx) -and -not $rx.IsMatch($s)) { continue }
        if (($null -ne $minL) -and ((Get-CpLen $s) -lt $minL)) { continue }
        if (($null -ne $maxL) -and ((Get-CpLen $s) -gt $maxL)) { continue }
        return $s
    }
    if (($null -ne $last) -and (($null -eq $rx) -or $rx.IsMatch($last))) { return $last }
    Add-Warn ('pattern に一致する値を生成できないためランダム英数字で代用しました: ' + $Pattern)
    return $null
}

# ----------------------------------------------------------------- パラメータ
$script:METHOD_KEYS = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
$script:ANY_KEY = 'x-amazon-apigateway-any-method'
$script:SKIP_HEADERS = @('accept', 'content-type', 'authorization')
$script:MANAGED_HEADERS = @('content-length', 'host', 'transfer-encoding', 'connection')

function Get-Params($item, $op) {
    $table = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($src in @((Get-Prop $item 'parameters'), (Get-Prop $op 'parameters'))) {
        if (-not (Test-Arr $src)) { continue }
        foreach ($p in $src) {
            $rp = Resolve-Deref $p 'parameter'
            if (-not (Test-Obj $rp)) { continue }
            $name = Get-Prop $rp 'name'
            $loc = Get-Prop $rp 'in'
            if (-not (Test-Str $name) -or -not (Test-Str $loc) -or ($name.Length -eq 0)) { continue }
            $table[$loc + "`n" + $name] = $rp
        }
    }
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($v in $table.Values) { $list.Add($v) }
    return , $list
}

function Get-FirstValue($d) {
    foreach ($k in @($d.Keys)) { return , ($d[$k]) }
    return $null
}

function Get-ParamValue($p) {
    if ($script:OptUseExamples) {
        if (Test-Has $p 'example') { return , (ConvertTo-GenValue $p['example']) }
        $exs = Get-Prop $p 'examples'
        if ((Test-Obj $exs) -and ($exs.Count -gt 0)) {
            $first = Resolve-Deref (Get-FirstValue $exs) 'example'
            if ((Test-Obj $first) -and (Test-Has $first 'value')) { return , (ConvertTo-GenValue $first['value']) }
        }
    }
    $schema = Get-Prop $p 'schema'
    if ($null -eq $schema) {
        $content = Get-Prop $p 'content'
        if ((Test-Obj $content) -and ($content.Count -gt 0)) { $schema = Get-Prop (Get-FirstValue $content) 'schema' }
    }
    if ($null -eq $schema) {
        $schema = New-OMap
        $schema['type'] = 'string'
    }
    $empty = New-Object 'System.Collections.Generic.List[string]'
    $v = New-Gen $schema 0 $empty
    if (Test-Skip $v) { $v = '' }
    return , $v
}

function Get-SimpleStyle($v, [bool]$Explode) {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Arr $v) {
        foreach ($x in $v) { $parts.Add((Get-ScalarStr $x)) }
        return [string]::Join(',', $parts)
    }
    if (Test-Obj $v) {
        foreach ($k in @($v.Keys)) {
            if ($Explode) { $parts.Add([string]$k + '=' + (Get-ScalarStr $v[$k])) }
            else { $parts.Add([string]$k + ',' + (Get-ScalarStr $v[$k])) }
        }
        return [string]::Join(',', $parts)
    }
    return (Get-ScalarStr $v)
}

function New-Pair([string]$Name, [string]$Value) { return , @($Name, $Value) }

function Get-QueryPairs([string]$Name, $v, [string]$Style, [bool]$Explode) {
    $pairs = New-Object 'System.Collections.Generic.List[object]'
    if (Test-Arr $v) {
        if (($Style -ceq 'form') -and $Explode) {
            foreach ($x in $v) { $pairs.Add((New-Pair $Name (Get-ScalarStr $x))) }
            return , $pairs
        }
        if ($Style -ceq 'spaceDelimited') { $sep = ' ' } elseif ($Style -ceq 'pipeDelimited') { $sep = '|' } else { $sep = ',' }
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($x in $v) { $parts.Add((Get-ScalarStr $x)) }
        $pairs.Add((New-Pair $Name ([string]::Join($sep, $parts))))
        return , $pairs
    }
    if (Test-Obj $v) {
        if ($Style -ceq 'deepObject') {
            foreach ($k in @($v.Keys)) { $pairs.Add((New-Pair ($Name + '[' + [string]$k + ']') (Get-ScalarStr $v[$k]))) }
            return , $pairs
        }
        if ($Explode) {
            foreach ($k in @($v.Keys)) { $pairs.Add((New-Pair ([string]$k) (Get-ScalarStr $v[$k]))) }
            return , $pairs
        }
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in @($v.Keys)) { $parts.Add([string]$k + ',' + (Get-ScalarStr $v[$k])) }
        $pairs.Add((New-Pair $Name ([string]::Join(',', $parts))))
        return , $pairs
    }
    $pairs.Add((New-Pair $Name (Get-ScalarStr $v)))
    return , $pairs
}

# ----------------------------------------------------------------- リクエストボディ
function Get-MediaBase([string]$mt) { return $mt.Split([char]';', 2)[0].Trim().ToLowerInvariant() }

function Select-Media($keys) {
    # JSON 系 → フォーム → マルチパート の順に優先し、どれも無ければ定義の先頭のメディアタイプを使う
    for ($pi = 0; $pi -lt 5; $pi++) {
        foreach ($k in $keys) {
            $b = Get-MediaBase $k
            $hit = $false
            switch ($pi) {
                0 { $hit = ($b -ceq 'application/json') }
                1 { $hit = $b.EndsWith('+json', [System.StringComparison]::Ordinal) }
                2 { $hit = $b.Contains('json') }
                3 { $hit = ($b -ceq 'application/x-www-form-urlencoded') }
                4 { $hit = ($b -ceq 'multipart/form-data') }
            }
            if ($hit) { return $k }
        }
    }
    return $keys[0]
}

function Get-MediaKind([string]$mt) {
    $b = Get-MediaBase $mt
    if (($b -ceq 'application/json') -or $b.EndsWith('+json', [System.StringComparison]::Ordinal) -or $b.Contains('json') -or ($b -ceq '*/*') -or ($b -ceq 'application/*')) { return 'json' }
    if ($b -ceq 'application/x-www-form-urlencoded') { return 'form' }
    if ($b.StartsWith('multipart/', [System.StringComparison]::Ordinal)) { return 'multipart' }
    if ($b.EndsWith('/xml', [System.StringComparison]::Ordinal) -or $b.EndsWith('+xml', [System.StringComparison]::Ordinal)) { return 'xml' }
    if ($b.StartsWith('text/', [System.StringComparison]::Ordinal)) { return 'text' }
    return 'binary'
}

function Get-ContentTypeFor([string]$mt, [string]$Kind) {
    if ((Get-MediaBase $mt).Contains('*')) {
        switch -CaseSensitive ($Kind) {
            'json' { return 'application/json' }
            'xml' { return 'application/xml' }
            'text' { return 'text/plain' }
        }
        return 'application/octet-stream'
    }
    return $mt.Trim()
}

function Get-XmlName([string]$n) {
    $n = [regex]::Replace($n, '[^A-Za-z0-9_.-]', '_')
    if (($n.Length -eq 0) -or -not ($n -cmatch '^[A-Za-z_]')) { $n = '_' + $n }
    return $n
}

function Get-XmlText([string]$s) {
    return (Get-CleanText $s).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function ConvertTo-XmlText($v, [string]$Name, [int]$Indent) {
    $pad = '  ' * $Indent
    if (Test-Obj $v) {
        if ($v.Count -eq 0) { return $pad + '<' + $Name + '/>' }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add($pad + '<' + $Name + '>')
        foreach ($k in @($v.Keys)) {
            $kn = Get-XmlName ([string]$k)
            $x = $v[$k]
            if (Test-Arr $x) {
                foreach ($it in $x) { $lines.Add((ConvertTo-XmlText $it $kn ($Indent + 1))) }
            } else {
                $lines.Add((ConvertTo-XmlText $x $kn ($Indent + 1)))
            }
        }
        $lines.Add($pad + '</' + $Name + '>')
        return [string]::Join("`n", $lines)
    }
    if (Test-Arr $v) {
        if ($v.Count -eq 0) { return $pad + '<' + $Name + '/>' }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($it in $v) { $lines.Add((ConvertTo-XmlText $it $Name $Indent)) }
        return [string]::Join("`n", $lines)
    }
    return $pad + '<' + $Name + '>' + (Get-XmlText (Get-ScalarStr $v)) + '</' + $Name + '>'
}

function Get-XmlRootName($schema) {
    $s = $schema
    $name = $null
    $guard = 0
    while ((Test-Obj $s) -and (Test-Has $s '$ref') -and ($guard -lt 32)) {
        $ref = $s['$ref']
        if (Test-Str $ref) {
            $segs = $ref.Split([char]'/')
            $name = $segs[$segs.Length - 1]
        }
        $s = Resolve-Ref $ref
        $guard++
    }
    $x = Get-Prop $s 'xml'
    if ((Test-Obj $x) -and (Test-Str (Get-Prop $x 'name')) -and ($x['name'].Length -gt 0)) { $name = $x['name'] }
    if ([string]::IsNullOrEmpty($name)) { $name = 'root' }
    return (Get-XmlName $name)
}

function New-Body($op) {
    if (-not (Test-Has $op 'requestBody')) { return $null }
    $rb = Resolve-Deref $op['requestBody'] 'requestBody'
    $content = Get-Prop $rb 'content'
    if (-not (Test-Obj $content) -or ($content.Count -eq 0)) { return $null }
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in @($content.Keys)) { $keys.Add([string]$k) }
    $mt = Select-Media $keys
    $media = $content[$mt]
    $schema = Get-Prop $media 'schema'
    $kind = Get-MediaKind $mt
    $have = $false
    $value = $null
    if ($script:OptUseExamples -and (Test-Obj $media)) {
        if (Test-Has $media 'example') {
            $value = ConvertTo-GenValue $media['example']
            $have = $true
        } else {
            $exs = Get-Prop $media 'examples'
            if ((Test-Obj $exs) -and ($exs.Count -gt 0)) {
                $first = Resolve-Deref (Get-FirstValue $exs) 'example'
                if ((Test-Obj $first) -and (Test-Has $first 'value')) {
                    $value = ConvertTo-GenValue $first['value']
                    $have = $true
                }
            }
        }
    }
    if (-not $have) {
        if ($null -eq $schema) {
            if (@('json', 'form', 'multipart', 'xml') -ccontains $kind) { $value = New-OMap } else { $value = Get-RandStr $script:ALNUM 16 }
        } else {
            $empty = New-Object 'System.Collections.Generic.List[string]'
            $value = New-Gen $schema 0 $empty
            if (Test-Skip $value) { $value = New-OMap }
        }
    }
    $ctype = Get-ContentTypeFor $mt $kind
    $pairs = New-Object 'System.Collections.Generic.List[object]'
    if ($kind -ceq 'json') {
        return @{ Kind = $kind; CType = $ctype; Text = (ConvertTo-JsonText $value 0 $true); Pairs = $pairs }
    }
    if (($kind -ceq 'form') -or ($kind -ceq 'multipart')) {
        if (Test-Obj $value) {
            foreach ($k in @($value.Keys)) {
                $x = $value[$k]
                if (Test-Arr $x) {
                    foreach ($it in $x) { $pairs.Add((New-Pair ([string]$k) (Get-ScalarStr $it))) }
                } else {
                    $pairs.Add((New-Pair ([string]$k) (Get-ScalarStr $x)))
                }
            }
        } else {
            $pairs.Add((New-Pair 'value' (Get-ScalarStr $value)))
        }
        return @{ Kind = $kind; CType = $ctype; Text = ''; Pairs = $pairs }
    }
    if ($kind -ceq 'xml') {
        $text = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + (ConvertTo-XmlText $value (Get-XmlRootName $schema) 0)
        return @{ Kind = $kind; CType = $ctype; Text = $text; Pairs = $pairs }
    }
    if ($value -is [string]) { $text = $value } else { $text = ConvertTo-JsonText $value 0 $true }
    return @{ Kind = $kind; CType = $ctype; Text = $text; Pairs = $pairs }
}

# ----------------------------------------------------------------- レスポンス（Accept・期待ステータス）
function Test-Is2xx([string]$k) { return (($k -cmatch '^2[0-9][0-9]$') -or ($k -ceq '2XX')) }

function Get-Accept($op) {
    $responses = Get-Prop $op 'responses'
    if (-not (Test-Obj $responses)) { return $null }
    foreach ($k in @($responses.Keys)) {
        if (-not (Test-Is2xx (([string]$k).Trim().ToUpperInvariant()))) { continue }
        $r = Resolve-Deref $responses[$k] 'response'
        $content = Get-Prop $r 'content'
        if ((Test-Obj $content) -and ($content.Count -gt 0)) {
            $mt = [string](@($content.Keys)[0])
            if ($mt.Contains('*')) { return $null }
            return $mt.Trim()
        }
    }
    return $null
}

function Get-SuccessCodes($op) {
    $responses = Get-Prop $op 'responses'
    $codes = New-Object 'System.Collections.Generic.List[string]'
    $hasRange = $false
    if (Test-Obj $responses) {
        foreach ($k in @($responses.Keys)) {
            $ks = ([string]$k).Trim().ToUpperInvariant()
            if ($ks -cmatch '^2[0-9][0-9]$') {
                if (-not $codes.Contains($ks)) { $codes.Add($ks) }
            } elseif ($ks -ceq '2XX') {
                $hasRange = $true
            }
        }
    }
    return @{ Codes = $codes; HasRange = $hasRange }
}

# ----------------------------------------------------------------- セキュリティ
function Get-EffectiveSecurity($op) {
    if (Test-Has $op 'security') { return , ($op['security']) }
    return , (Get-Prop $script:Doc 'security')
}

function Get-SecurityText($op) {
    $sec = Get-EffectiveSecurity $op
    if (-not (Test-Arr $sec)) { return $null }
    if ($sec.Count -eq 0) { return 'なし（認証不要）' }
    $alts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($req in $sec) {
        if (-not (Test-Obj $req)) { continue }
        if ($req.Count -eq 0) { $alts.Add('認証なしも可'); continue }
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($nk in @($req.Keys)) {
            $scopes = $req[$nk]
            $sc = New-Object 'System.Collections.Generic.List[string]'
            if (Test-Arr $scopes) { foreach ($x in $scopes) { if (Test-Str $x) { $sc.Add($x) } } }
            if ($sc.Count -gt 0) { $parts.Add([string]$nk + '[' + [string]::Join(', ', $sc) + ']') } else { $parts.Add([string]$nk) }
        }
        $alts.Add([string]::Join(' かつ ', $parts))
    }
    if ($alts.Count -eq 0) { return $null }
    return [string]::Join(' または ', $alts)
}

function Test-SchemeUsesAuthorization($scheme) {
    if (-not (Test-Obj $scheme)) { return $false }
    $t = Get-Prop $scheme 'type'
    if (-not (Test-Str $t)) { return $false }
    if (($t -ceq 'oauth2') -or ($t -ceq 'openIdConnect') -or ($t -ceq 'http')) { return $true }
    if ($t -ceq 'apiKey') {
        $in = Get-Prop $scheme 'in'
        $nm = Get-Prop $scheme 'name'
        return ((Test-Str $in) -and ($in -ceq 'header') -and (Test-Str $nm) -and ($nm.ToLowerInvariant() -ceq 'authorization'))
    }
    return $false
}

function Test-NeedsAuthHeader($ops) {
    $schemes = Get-Prop (Get-Prop $script:Doc 'components') 'securitySchemes'
    foreach ($info in $ops) {
        $sec = Get-EffectiveSecurity $info.Op
        if (-not (Test-Arr $sec)) { continue }
        foreach ($req in $sec) {
            if (-not (Test-Obj $req)) { continue }
            foreach ($nk in @($req.Keys)) {
                $sch = Resolve-Deref (Get-Prop $schemes ([string]$nk)) 'securityScheme'
                if (Test-SchemeUsesAuthorization $sch) { return $true }
            }
        }
    }
    return $false
}

# ----------------------------------------------------------------- オペレーション
function Get-Operations {
    $ops = New-Object 'System.Collections.Generic.List[object]'
    $paths = Get-Prop $script:Doc 'paths'
    foreach ($pk in @($paths.Keys)) {
        $path = [string]$pk
        if ($path.StartsWith('x-', [System.StringComparison]::Ordinal)) { continue }
        $item = Resolve-Deref $paths[$pk] 'pathItem'
        if (-not (Test-Obj $item)) { continue }
        foreach ($kk in @($item.Keys)) {
            $key = [string]$kk
            $k = $key.ToLowerInvariant()
            if ($script:METHOD_KEYS -ccontains $k) {
                $method = $k.ToUpperInvariant()
                $isAny = $false
            } elseif ($k -ceq $script:ANY_KEY) {
                $method = $script:OptAnyMethod
                $isAny = $true
            } else {
                continue
            }
            $op = $item[$kk]
            if (-not (Test-Obj $op)) { continue }
            $ops.Add(@{ Path = $path; Item = $item; Op = $op; Key = $key; Method = $method; IsAny = $isAny })
        }
    }
    return , $ops
}

$script:PLACEHOLDER_RE = New-Object System.Text.RegularExpressions.Regex('\{([^{}]+)\}')

function New-OperationRequest($info, [string]$Label) {
    $path = $info.Path
    $op = $info.Op
    $method = $info.Method
    $params = Get-Params $info.Item $op

    # 1. パスパラメータ
    $pathVals = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($p in $params) {
        if ((Get-Prop $p 'in') -ceq 'path') {
            $ex = Get-Prop $p 'explode'
            $pathVals[[string]$p['name']] = @{ V = (Get-ParamValue $p); Explode = (($ex -is [bool]) -and $ex) }
        }
    }
    foreach ($m in $script:PLACEHOLDER_RE.Matches($path)) {
        $ph = $m.Groups[1].Value
        if ($ph.EndsWith('+', [System.StringComparison]::Ordinal)) { $base = $ph.Substring(0, $ph.Length - 1) } else { $base = $ph }
        if (-not $pathVals.Contains($base)) {
            Add-Warn ('{0}: パス変数 {{{1}}} のパラメータ定義が無いため英数字 8 文字を仮設定しました' -f $Label, $base)
            $pathVals[$base] = @{ V = (Get-RandStr $script:ALNUM 8); Explode = $false }
        }
    }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($m in $script:PLACEHOLDER_RE.Matches($path)) {
        [void]$sb.Append($path.Substring($pos, $m.Index - $pos))
        $ph = $m.Groups[1].Value
        $greedy = $ph.EndsWith('+', [System.StringComparison]::Ordinal)
        if ($greedy) { $base = $ph.Substring(0, $ph.Length - 1) } else { $base = $ph }
        $pv = $pathVals[$base]
        [void]$sb.Append((Get-PctEncode (Get-SimpleStyle $pv.V $pv.Explode) $greedy))
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($path.Substring($pos))
    $realPath = $sb.ToString()
    if (-not $realPath.StartsWith('/', [System.StringComparison]::Ordinal)) { $realPath = '/' + $realPath }

    # 2. クエリパラメータ
    $qpairs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $params) {
        if ((Get-Prop $p 'in') -cne 'query') { continue }
        $rq = Get-Prop $p 'required'
        if ($script:OptRequiredOnly -and -not (($rq -is [bool]) -and $rq)) { continue }
        $v = Get-ParamValue $p
        $style = Get-Prop $p 'style'
        if (-not (Test-Str $style)) { $style = 'form' }
        $explode = Get-Prop $p 'explode'
        if (-not ($explode -is [bool])) { $explode = ($style -ceq 'form') }
        foreach ($pair in (Get-QueryPairs ([string]$p['name']) $v $style $explode)) { $qpairs.Add($pair) }
    }

    # 3. ヘッダパラメータ
    $hparams = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $params) {
        if ((Get-Prop $p 'in') -cne 'header') { continue }
        $name = [string]$p['name']
        $lname = $name.ToLowerInvariant()
        if ($script:SKIP_HEADERS -ccontains $lname) { continue }
        if ($lname -ceq 'x-api-key') {
            Add-Warn ('{0}: ヘッダ {1} は共通の X-API-KEY（固定値）を優先するため個別には生成しません' -f $Label, $name)
            continue
        }
        if ($script:MANAGED_HEADERS -ccontains $lname) {
            Add-Warn ('{0}: ヘッダ {1} は HTTP クライアントが自動設定するため生成しません' -f $Label, $name)
            continue
        }
        $rq = Get-Prop $p 'required'
        if ($script:OptRequiredOnly -and -not (($rq -is [bool]) -and $rq)) { continue }
        $v = Get-ParamValue $p
        $ex = Get-Prop $p 'explode'
        $hparams.Add((New-Pair $name (Get-HeaderSafe (Get-SimpleStyle $v (($ex -is [bool]) -and $ex)))))
    }

    # 4. クッキーパラメータ
    $cookies = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $params) {
        if ((Get-Prop $p 'in') -cne 'cookie') { continue }
        $rq = Get-Prop $p 'required'
        if ($script:OptRequiredOnly -and -not (($rq -is [bool]) -and $rq)) { continue }
        $v = Get-ParamValue $p
        $cookies.Add([string]$p['name'] + '=' + (Get-PctEncode (Get-SimpleStyle $v $false) $false))
    }

    # 5. リクエストボディ
    $body = New-Body $op

    # 6. 組み立て
    $finalPath = '${BASE_PATH}' + $realPath
    $args2 = New-Object 'System.Collections.Generic.List[object]'
    if ($qpairs.Count -gt 0) {
        if (($method -ceq 'GET') -and ($null -eq $body)) {
            foreach ($pair in $qpairs) { $args2.Add($pair) }
        } else {
            $qs = New-Object 'System.Collections.Generic.List[string]'
            foreach ($pair in $qpairs) { $qs.Add((Get-PctEncode $pair[0] $false) + '=' + (Get-PctEncode $pair[1] $false)) }
            $finalPath = $finalPath + '?' + [string]::Join('&', $qs)
        }
    }
    $rawBody = $null
    $multipart = $false
    $headers = New-Object 'System.Collections.Generic.List[object]'
    if ($null -ne $body) {
        if ($body.Kind -ceq 'form') {
            $args2 = $body.Pairs
            $headers.Add((New-Pair 'Content-Type' $body.CType))
        } elseif ($body.Kind -ceq 'multipart') {
            $args2 = $body.Pairs
            $multipart = $true
        } else {
            $rawBody = $body.Text
            $headers.Add((New-Pair 'Content-Type' $body.CType))
        }
    }
    $accept = Get-Accept $op
    if ($null -ne $accept) { $headers.Add((New-Pair 'Accept' $accept)) }
    foreach ($h in $hparams) { $headers.Add($h) }
    if ($cookies.Count -gt 0) { $headers.Add((New-Pair 'Cookie' ([string]::Join('; ', $cookies)))) }

    $sc = Get-SuccessCodes $op
    $hasData = ($pathVals.Count -gt 0) -or ($qpairs.Count -gt 0) -or ($hparams.Count -gt 0) -or ($cookies.Count -gt 0) -or ($null -ne $body)
    $bodyKind = $null
    if ($null -ne $body) { $bodyKind = $body.Kind }
    return @{
        Label = $Label; Path = $finalPath; Method = $method; Args = $args2; RawBody = $rawBody; Multipart = $multipart
        Headers = $headers; Codes = $sc.Codes; HasRange = $sc.HasRange; Comment = (Get-OperationComment $info $body $hasData)
        BodyKind = $bodyKind
    }
}

function Get-OperationComment($info, $body, [bool]$HasData) {
    $op = $info.Op
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $summary = Get-Prop $op 'summary'
    if ((Test-Str $summary) -and ($summary.Trim().Length -gt 0)) { $lines.Add('概要: ' + $summary.Trim()) }
    $desc = Get-Prop $op 'description'
    if ((Test-Str $desc) -and ($desc.Trim().Length -gt 0)) { $lines.Add('説明: ' + $desc.Trim()) }
    $lines.Add('OpenAPI 定義: ' + $info.Key + ' ' + $info.Path)
    $opId = Get-Prop $op 'operationId'
    if ((Test-Str $opId) -and ($opId.Length -gt 0)) { $lines.Add('operationId: ' + $opId) }
    if ($info.IsAny) {
        $lines.Add('ANY メソッド（x-amazon-apigateway-any-method）のため ' + $info.Method + ' で代表して送信します（生成時の --any-method / -AnyMethod で変更可）。')
    }
    $sec = Get-SecurityText $op
    if ($null -ne $sec) { $lines.Add('認可（security）: ' + $sec) }
    $integ = Get-Prop $op 'x-amazon-apigateway-integration'
    if (Test-Obj $integ) {
        $items = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in @('type', 'httpMethod', 'uri', 'connectionType')) {
            $iv = Get-Prop $integ $k
            if (Test-Str $iv) { $items.Add($k + '=' + $iv) }
        }
        if ($items.Count -gt 0) { $lines.Add('API Gateway 統合: ' + [string]::Join(', ', $items)) }
    }
    $dep = Get-Prop $op 'deprecated'
    if (($dep -is [bool]) -and $dep) { $lines.Add('※ deprecated（非推奨）に指定された API です。') }
    if (($null -ne $body) -and ($body.Kind -ceq 'multipart')) {
        $lines.Add('※ multipart/form-data はファイル項目もテキスト値で送信します。実ファイルを送る場合は「ファイルアップロード」タブで設定してください。')
    }
    if ($HasData) {
        $lines.Add('テストデータ: OpenAPI のデータ型定義からランダム生成（乱数シード ' + $script:SeedValue.ToString($script:Inv) + '）')
    }
    return [string]::Join("`n", $lines)
}

# ----------------------------------------------------------------- JMX 出力
$script:X = $null

function Add-X([int]$Ind, [string]$Text) { $script:X.Add(('  ' * $Ind) + $Text) }

function Add-XStr([int]$Ind, [string]$Name, [string]$Value) {
    Add-X $Ind ('<stringProp name="' + (Get-XmlEscape $Name) + '">' + (Get-XmlEscape $Value) + '</stringProp>')
}

function Add-XBool([int]$Ind, [string]$Name, [bool]$Value) {
    if ($Value) { $t = 'true' } else { $t = 'false' }
    Add-X $Ind ('<boolProp name="' + $Name + '">' + $t + '</boolProp>')
}

function Add-XInt([int]$Ind, [string]$Name, [long]$Value) {
    Add-X $Ind ('<intProp name="' + $Name + '">' + $Value.ToString($script:Inv) + '</intProp>')
}

function Add-XOpen([int]$Ind, [string]$Tag, [string]$GuiClass, [string]$TestClass, [string]$TestName, [bool]$Enabled = $true) {
    $attrs = 'guiclass="' + $GuiClass + '" testclass="' + $TestClass + '" testname="' + (Get-XmlEscape $TestName) + '"'
    if (-not $Enabled) { $attrs += ' enabled="false"' }
    Add-X $Ind ('<' + $Tag + ' ' + $attrs + '>')
}

function Add-XHeaders([int]$Ind, [string]$TestName, $Headers, [string]$Comment, [bool]$Enabled = $true) {
    Add-XOpen $Ind 'HeaderManager' 'HeaderPanel' 'HeaderManager' $TestName $Enabled
    if ($Comment.Length -gt 0) { Add-XStr ($Ind + 1) 'TestPlan.comments' $Comment }
    Add-X ($Ind + 1) '<collectionProp name="HeaderManager.headers">'
    foreach ($h in $Headers) {
        Add-X ($Ind + 2) '<elementProp name="" elementType="Header">'
        Add-XStr ($Ind + 3) 'Header.name' $h[0]
        Add-XStr ($Ind + 3) 'Header.value' $h[1]
        Add-X ($Ind + 2) '</elementProp>'
    }
    Add-X ($Ind + 1) '</collectionProp>'
    Add-X $Ind '</HeaderManager>'
    Add-X $Ind '<hashTree/>'
}

$script:SAVE_CONFIG_DETAIL = @(
    @('time', 'true'), @('latency', 'true'), @('timestamp', 'true'), @('success', 'true'), @('label', 'true'),
    @('code', 'true'), @('message', 'true'), @('threadName', 'true'), @('dataType', 'true'), @('encoding', 'true'),
    @('assertions', 'true'), @('subresults', 'true'), @('responseData', 'true'), @('samplerData', 'true'),
    @('xml', 'true'), @('fieldNames', 'true'), @('responseHeaders', 'true'), @('requestHeaders', 'true'),
    @('responseDataOnError', 'false'), @('saveAssertionResultsFailureMessage', 'true'),
    @('assertionsResultsToSave', '0'), @('bytes', 'true'), @('sentBytes', 'true'), @('url', 'true'),
    @('fileName', 'true'), @('hostname', 'true'), @('threadCounts', 'true'), @('sampleCount', 'true'),
    @('idleTime', 'true'), @('connectTime', 'true')
)

function Add-XCollector([int]$Ind, [string]$GuiClass, [string]$TestName, [string]$Comment, [string]$FileName) {
    Add-XOpen $Ind 'ResultCollector' $GuiClass 'ResultCollector' $TestName
    Add-XStr ($Ind + 1) 'TestPlan.comments' $Comment
    Add-XBool ($Ind + 1) 'ResultCollector.error_logging' $false
    Add-X ($Ind + 1) '<objProp>'
    Add-X ($Ind + 2) '<name>saveConfig</name>'
    Add-X ($Ind + 2) '<value class="SampleSaveConfiguration">'
    foreach ($kv in $script:SAVE_CONFIG_DETAIL) { Add-X ($Ind + 3) ('<' + $kv[0] + '>' + $kv[1] + '</' + $kv[0] + '>') }
    Add-X ($Ind + 2) '</value>'
    Add-X ($Ind + 1) '</objProp>'
    Add-XStr ($Ind + 1) 'filename' $FileName
    Add-X $Ind '</ResultCollector>'
    Add-X $Ind '<hashTree/>'
}

function Add-XArg([int]$Ind, [string]$Name, [string]$Value, [string]$Desc) {
    Add-X $Ind ('<elementProp name="' + (Get-XmlEscape $Name) + '" elementType="Argument">')
    Add-XStr ($Ind + 1) 'Argument.name' $Name
    Add-XStr ($Ind + 1) 'Argument.value' $Value
    if ($Desc.Length -gt 0) { Add-XStr ($Ind + 1) 'Argument.desc' $Desc }
    Add-XStr ($Ind + 1) 'Argument.metadata' '='
    Add-X $Ind '</elementProp>'
}

function Add-XHttpArg([int]$Ind, [string]$Name, [string]$Value) {
    Add-X $Ind ('<elementProp name="' + (Get-XmlEscape $Name) + '" elementType="HTTPArgument">')
    Add-XBool ($Ind + 1) 'HTTPArgument.always_encode' $true
    Add-XStr ($Ind + 1) 'Argument.name' $Name
    Add-XStr ($Ind + 1) 'Argument.value' $Value
    Add-XStr ($Ind + 1) 'Argument.metadata' '='
    Add-XBool ($Ind + 1) 'HTTPArgument.use_equals' $true
    Add-X $Ind '</elementProp>'
}

$script:RESULT_LOG_SCRIPT = [string]::Join("`n", @(
    "// 各 API の結果を JMeter ログ（GUI 実行: jmeter.log / CLI 実行: -j で指定したファイル）へ 1 行ずつ出力します。",
    "// 形式: [API-RESULT] OK|NG | ラベル | メソッド URL | code=応答コード | 応答時間 ms | 受信バイト数 bytes",
    "import org.apache.jmeter.protocol.http.sampler.HTTPSampleResult",
    "",
    "def r = sampleResult",
    "if (r == null) {",
    "    return",
    "}",
    "String status = r.isSuccessful() ? 'OK' : 'NG'",
    "String method = (r instanceof HTTPSampleResult) ? ((HTTPSampleResult) r).getHTTPMethod() : '-'",
    "String url = r.getUrlAsString() ?: '-'",
    "String line = String.format('[API-RESULT] %s | %s | %s %s | code=%s | %d ms | %d bytes',",
    "        status, r.getSampleLabel(), method, url, r.getResponseCode(), r.getTime(), r.getBytesAsLong())",
    "if (r.isSuccessful()) {",
    "    log.info(line)",
    "} else {",
    "    log.warn(line)",
    "    String msg = r.getResponseMessage()",
    "    if (msg) {",
    "        log.warn('[API-RESULT]     message  : ' + msg)",
    "    }",
    "    r.getAssertionResults().each { a ->",
    "        if (a.isFailure() || a.isError()) {",
    "            log.warn('[API-RESULT]     assertion: ' + a.getName() + ' : ' + a.getFailureMessage())",
    "        }",
    "    }",
    "    String body = r.getResponseDataAsString()",
    "    if (body != null && body.length() > 2000) {",
    "        body = body.substring(0, 2000) + ' ...(truncated)'",
    "    }",
    "    log.warn('[API-RESULT]     response : ' + (body ?: '(empty)'))",
    "}"
))

function New-JmxText($Meta, $Requests, [bool]$UseAuth) {
    $name = $Meta.Name
    $script:X = New-Object 'System.Collections.Generic.List[string]'
    Add-X 0 '<?xml version="1.0" encoding="UTF-8"?>'
    Add-X 0 ('<jmeterTestPlan version="1.2" properties="5.0" jmeter="' + $script:JMeterVersion + '">')
    Add-X 1 '<hashTree>'

    # --- テスト計画
    $planName = '{0} {1} - API疎通確認（OpenAPI {2} から自動生成）' -f $Meta.Title, $Meta.ApiVersion, $Meta.OpenApi
    $c = New-Object 'System.Collections.Generic.List[string]'
    $c.Add('このテスト計画は ' + $script:ToolName + ' ' + $Meta.ToolVersion + ' が OpenAPI 定義ファイルから自動生成しました（Apache JMeter ' + $script:JMeterVersion + ' 対応）。')
    $c.Add('入力ファイル : ' + $Meta.InputName + '（OpenAPI ' + $Meta.OpenApi + ' / ' + $Meta.Title + ' ' + $Meta.ApiVersion + '）')
    $c.Add('リクエスト数 : ' + $Requests.Count.ToString($script:Inv) + ' 件（各 API を 1 回ずつ呼び出す最小構成）')
    $c.Add('テストデータ : OpenAPI のデータ型定義からランダム生成（乱数シード ' + $script:SeedValue.ToString($script:Inv) + '。同じシードを指定すると同じデータを再生成できます）')
    $c.Add('既定の接続先 : ' + $Meta.Protocol + '://' + $Meta.Host + ':' + $Meta.Port + $Meta.BasePath + '（実行時に -Jprotocol= -Jhost= -Jport= -JbasePath= で上書きできます）')
    $c.Add('共通ヘッダ   : X-API-KEY（ユーザー定義変数 API_KEY の値。実行時に -JapiKey= で上書きできます）')
    $c.Add('結果（JTL）  : RESULT_DIR/' + $name + '_RUN_ID.jtl（XML 形式・リクエスト/レスポンス詳細付き。JMeter GUI のリスナーで開けます）')
    $c.Add('結果（ログ） : jmeter.log（CLI 実行時は -j で指定したファイル）に [API-RESULT] 行を 1 リクエスト 1 行で出力します。')
    if ($script:Warnings.Count -gt 0) {
        $c.Add('')
        $c.Add('【生成時の注意】')
        foreach ($w in $script:Warnings) { $c.Add('・' + $w) }
    }
    Add-XOpen 2 'TestPlan' 'TestPlanGui' 'TestPlan' $planName
    Add-XStr 3 'TestPlan.comments' ([string]::Join("`n", $c))
    Add-XBool 3 'TestPlan.functional_mode' $false
    Add-XBool 3 'TestPlan.tearDown_on_shutdown' $true
    Add-XBool 3 'TestPlan.serialize_threadgroups' $false
    Add-X 3 '<elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables">'
    Add-X 4 '<collectionProp name="Arguments.arguments">'
    $udvs = New-Object 'System.Collections.Generic.List[object]'
    $udvs.Add(@('PROTOCOL', ('${__P(protocol,' + (Get-FuncArg $Meta.Protocol) + ')}'), '接続プロトコル（http / https）。実行時に -Jprotocol=https のように上書きできます。'))
    $udvs.Add(@('HOST', ('${__P(host,' + (Get-FuncArg $Meta.Host) + ')}'), '接続先ホスト名。実行時に -Jhost=... で上書きできます。'))
    $udvs.Add(@('PORT', ('${__P(port,' + (Get-FuncArg $Meta.Port) + ')}'), '接続先ポート番号。実行時に -Jport=... で上書きできます。'))
    $udvs.Add(@('BASE_PATH', ('${__P(basePath,' + (Get-FuncArg $Meta.BasePath) + ')}'), '全 API パスの先頭に付けるパス（例: /prod）。実行時に -JbasePath=... で上書きできます。'))
    $udvs.Add(@('API_KEY', ('${__P(apiKey,' + (Get-FuncArg $Meta.ApiKey) + ')}'), 'X-API-KEY ヘッダに固定で設定する値。実行時に -JapiKey=... で上書きできます。'))
    if ($UseAuth) {
        $udvs.Add(@('AUTH_TOKEN', '${__P(authToken,)}', 'Authorization ヘッダの値（無効化してあるヘッダマネージャで使用）。実行時に -JauthToken=... で指定します。'))
    }
    $udvs.Add(@('THREADS', '${__P(threads,1)}', 'スレッド数（同時に動く仮想ユーザー数）。最小構成は 1。実行時に -Jthreads=... で上書きできます。'))
    $udvs.Add(@('RAMP_UP', '${__P(rampUp,1)}', '全スレッドを起動し終えるまでの秒数。最小構成は 1。実行時に -JrampUp=... で上書きできます。'))
    $udvs.Add(@('LOOPS', '${__P(loops,1)}', '各スレッドの繰り返し回数。最小構成は 1。実行時に -Jloops=... で上書きできます。'))
    $udvs.Add(@('CONNECT_TIMEOUT', '${__P(connectTimeout,10000)}', '接続タイムアウト（ミリ秒）。実行時に -JconnectTimeout=... で上書きできます。'))
    $udvs.Add(@('RESPONSE_TIMEOUT', '${__P(responseTimeout,60000)}', '応答タイムアウト（ミリ秒）。API Gateway の統合タイムアウト既定値 29 秒より長くしています。実行時に -JresponseTimeout=... で上書きできます。'))
    $udvs.Add(@('RESULT_DIR', '${__P(resultDir,~/results)}', 'JTL の出力フォルダ。~/ は「この JMX ファイルがあるフォルダ」を表す JMeter の記法です。実行時に -JresultDir=... で上書きできます。'))
    $udvs.Add(@('RUN_ID', '${__P(runId,${__time(yyyyMMdd-HHmmss,)})}', '結果ファイル名に付ける実行 ID（既定: テスト開始時刻）。実行時に -JrunId=... で上書きできます。'))
    foreach ($u in $udvs) { Add-XArg 5 $u[0] $u[1] $u[2] }
    Add-X 4 '</collectionProp>'
    Add-X 3 '</elementProp>'
    Add-XStr 3 'TestPlan.user_define_classpath' ''
    Add-X 2 '</TestPlan>'
    Add-X 2 '<hashTree>'

    # --- HTTP リクエスト初期値設定
    Add-XOpen 3 'ConfigTestElement' 'HttpDefaultsGui' 'ConfigTestElement' 'HTTPリクエスト初期値設定'
    Add-XStr 4 'TestPlan.comments' '全リクエスト共通の接続先・文字コード・タイムアウト。値はテスト計画のユーザー定義変数を参照しており、実行時に -Jhost= などで上書きできます。実装は HttpClient4（JMeter 5.6.3 の既定・推奨）です。'
    Add-X 4 '<elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables">'
    Add-X 5 '<collectionProp name="Arguments.arguments"/>'
    Add-X 4 '</elementProp>'
    Add-XStr 4 'HTTPSampler.domain' '${HOST}'
    Add-XStr 4 'HTTPSampler.port' '${PORT}'
    Add-XStr 4 'HTTPSampler.protocol' '${PROTOCOL}'
    Add-XStr 4 'HTTPSampler.contentEncoding' 'UTF-8'
    Add-XStr 4 'HTTPSampler.path' ''
    Add-XStr 4 'HTTPSampler.implementation' 'HttpClient4'
    Add-XStr 4 'HTTPSampler.connect_timeout' '${CONNECT_TIMEOUT}'
    Add-XStr 4 'HTTPSampler.response_timeout' '${RESPONSE_TIMEOUT}'
    Add-XBool 4 'HTTPSampler.image_parser' $false
    Add-XBool 4 'HTTPSampler.concurrentDwn' $false
    Add-XStr 4 'HTTPSampler.embedded_url_re' ''
    Add-X 3 '</ConfigTestElement>'
    Add-X 3 '<hashTree/>'

    # --- 共通ヘッダ（X-API-KEY）
    $common = New-Object 'System.Collections.Generic.List[object]'
    $common.Add((New-Pair 'X-API-KEY' '${API_KEY}'))
    Add-XHeaders 3 'HTTPヘッダマネージャ（共通: X-API-KEY）' $common '全リクエストに X-API-KEY ヘッダを固定で付与します（値はユーザー定義変数 API_KEY、既定 XXXXXXXXXXXX）。'
    if ($UseAuth) {
        $auth = New-Object 'System.Collections.Generic.List[object]'
        $auth.Add((New-Pair 'Authorization' '${AUTH_TOKEN}'))
        Add-XHeaders 3 'HTTPヘッダマネージャ（Authorization・無効化中）' $auth 'OpenAPI 定義に認可（security）があるため用意した Authorization ヘッダです。API Gateway 経由でオーソライザー（Cognito 等）を通す場合は、この要素を有効化し -JauthToken=トークン を指定してください。' $false
    }

    # --- スレッドグループ
    Add-XOpen 3 'ThreadGroup' 'ThreadGroupGui' 'ThreadGroup' ('TG01_' + $name)
    Add-XStr 4 'TestPlan.comments' '最小構成（スレッド 1・ランプアップ 1 秒・ループ 1 回）で各 API を 1 回ずつ呼び出し、疎通を確認します。エラー後も続行するため、1 件失敗しても残りの API をすべて確認できます。'
    Add-XStr 4 'ThreadGroup.on_sample_error' 'continue'
    Add-X 4 '<elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller">'
    Add-XStr 5 'LoopController.loops' '${LOOPS}'
    Add-XBool 5 'LoopController.continue_forever' $false
    Add-X 4 '</elementProp>'
    Add-XStr 4 'ThreadGroup.num_threads' '${THREADS}'
    Add-XStr 4 'ThreadGroup.ramp_time' '${RAMP_UP}'
    Add-XBool 4 'ThreadGroup.scheduler' $false
    Add-XStr 4 'ThreadGroup.duration' ''
    Add-XStr 4 'ThreadGroup.delay' ''
    Add-XBool 4 'ThreadGroup.same_user_on_next_iteration' $true
    Add-XBool 4 'ThreadGroup.delayedStart' $false
    Add-X 3 '</ThreadGroup>'
    Add-X 3 '<hashTree>'

    foreach ($r in $Requests) {
        Add-XOpen 4 'HTTPSamplerProxy' 'HttpTestSampleGui' 'HTTPSamplerProxy' $r.Label
        Add-XStr 5 'TestPlan.comments' $r.Comment
        if ($null -ne $r.RawBody) {
            Add-XBool 5 'HTTPSampler.postBodyRaw' $true
            Add-X 5 '<elementProp name="HTTPsampler.Arguments" elementType="Arguments">'
            Add-X 6 '<collectionProp name="Arguments.arguments">'
            Add-X 7 '<elementProp name="" elementType="HTTPArgument">'
            Add-XBool 8 'HTTPArgument.always_encode' $false
            Add-XStr 8 'Argument.value' $r.RawBody
            Add-XStr 8 'Argument.metadata' '='
            Add-X 7 '</elementProp>'
            Add-X 6 '</collectionProp>'
            Add-X 5 '</elementProp>'
        } else {
            Add-X 5 '<elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables">'
            if ($r.Args.Count -gt 0) {
                Add-X 6 '<collectionProp name="Arguments.arguments">'
                foreach ($a in $r.Args) { Add-XHttpArg 7 $a[0] $a[1] }
                Add-X 6 '</collectionProp>'
            } else {
                Add-X 6 '<collectionProp name="Arguments.arguments"/>'
            }
            Add-X 5 '</elementProp>'
        }
        Add-XStr 5 'HTTPSampler.domain' ''
        Add-XStr 5 'HTTPSampler.port' ''
        Add-XStr 5 'HTTPSampler.protocol' ''
        Add-XStr 5 'HTTPSampler.contentEncoding' ''
        Add-XStr 5 'HTTPSampler.path' $r.Path
        Add-XStr 5 'HTTPSampler.method' $r.Method
        Add-XBool 5 'HTTPSampler.follow_redirects' $true
        Add-XBool 5 'HTTPSampler.auto_redirects' $false
        Add-XBool 5 'HTTPSampler.use_keepalive' $true
        Add-XBool 5 'HTTPSampler.DO_MULTIPART_POST' $r.Multipart
        if ($null -eq $r.RawBody) { Add-XBool 5 'HTTPSampler.postBodyRaw' $false }
        Add-XStr 5 'HTTPSampler.embedded_url_re' ''
        Add-XStr 5 'HTTPSampler.connect_timeout' ''
        Add-XStr 5 'HTTPSampler.response_timeout' ''
        Add-X 4 '</HTTPSamplerProxy>'
        $hasChildren = ($r.Headers.Count -gt 0) -or ($r.Codes.Count -gt 0) -or $r.HasRange
        if (-not $hasChildren) {
            Add-X 4 '<hashTree/>'
            continue
        }
        Add-X 4 '<hashTree>'
        if ($r.Headers.Count -gt 0) {
            Add-XHeaders 5 'HTTPヘッダマネージャ（この API 用）' $r.Headers 'この API 固有のヘッダ（Content-Type / Accept / OpenAPI のヘッダ・クッキーパラメータ）です。'
        }
        if (($r.Codes.Count -gt 0) -or $r.HasRange) {
            $patterns = New-Object 'System.Collections.Generic.List[string]'
            if ($r.Codes.Count -gt 0) {
                foreach ($cd in $r.Codes) { $patterns.Add($cd) }
                if ($patterns.Count -eq 1) { $testType = 8 } else { $testType = 40 }
                $expect = [string]::Join(' / ', $patterns)
            } else {
                $patterns.Add('2[0-9][0-9]')
                $testType = 1
                $expect = '2XX'
            }
            Add-XOpen 5 'ResponseAssertion' 'AssertionGui' 'ResponseAssertion' ('ステータスコード検証（' + $expect + '）')
            Add-XStr 6 'TestPlan.comments' ('OpenAPI 定義の成功レスポンス（' + $expect + '）と応答コードが一致するかを検証します。')
            Add-X 6 '<collectionProp name="Asserion.test_strings">'
            foreach ($pt in $patterns) { Add-XStr 7 ((Get-JavaHash $pt).ToString($script:Inv)) $pt }
            Add-X 6 '</collectionProp>'
            Add-XStr 6 'Assertion.custom_message' ('応答コードが OpenAPI 定義の成功コード（' + $expect + '）と一致しません')
            Add-XStr 6 'Assertion.test_field' 'Assertion.response_code'
            Add-XBool 6 'Assertion.assume_success' $false
            Add-XInt 6 'Assertion.test_type' $testType
            Add-X 5 '</ResponseAssertion>'
            Add-X 5 '<hashTree/>'
        }
        Add-X 4 '</hashTree>'
    }

    Add-XOpen 4 'JSR223Listener' 'TestBeanGUI' 'JSR223Listener' '結果ログ出力（1 リクエスト 1 行）'
    Add-XStr 5 'TestPlan.comments' '各 API の結果（OK/NG・応答コード・応答時間）をログファイルへ 1 行ずつ出力します。'
    Add-XStr 5 'scriptLanguage' 'groovy'
    Add-XStr 5 'parameters' ''
    Add-XStr 5 'filename' ''
    Add-XStr 5 'cacheKey' 'true'
    Add-XStr 5 'script' $script:RESULT_LOG_SCRIPT
    Add-X 4 '</JSR223Listener>'
    Add-X 4 '<hashTree/>'
    Add-X 3 '</hashTree>'

    # --- リスナー
    Add-XCollector 3 'ViewResultsFullVisualizer' '結果をツリーで表示（GUI 確認用）' 'GUI 実行時にリクエスト/レスポンスの中身を確認できます。保存済みの JTL を見る場合は「ファイル名」欄の［参照］から JTL ファイルを選択してください。' ''
    Add-XCollector 3 'SummaryReport' '統計レポート（GUI 確認用）' 'GUI 実行時に件数・応答時間・エラー率を集計表示します。保存済みの JTL も［参照］から読み込めます。' ''
    Add-XCollector 3 'SimpleDataWriter' 'JTL出力（XML・詳細付き）' '結果を JTL ファイルへ XML 形式（リクエスト/レスポンスのヘッダ・本文付き）で保存します。JMeter GUI の「結果をツリーで表示」「統計レポート」等の［参照］から開いて確認できます。CLI 実行時は -JjtlFile=出力先 で保存場所を指定できます。' ('${__P(jtlFile,${RESULT_DIR}/' + $name + '_${RUN_ID}.jtl)}')
    Add-X 2 '</hashTree>'
    Add-X 1 '</hashTree>'
    Add-X 0 '</jmeterTestPlan>'
    return ([string]::Join("`n", $script:X) + "`n")
}

# ----------------------------------------------------------------- JSON 読み込み
function ConvertFrom-JssValue($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [System.Collections.Generic.Dictionary[string, object]]) {
        $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($k in @($v.Keys)) { $d[$k] = (ConvertFrom-JssValue $v[$k]) }
        return , $d
    }
    if (($v -is [object[]]) -or ($v -is [System.Collections.ArrayList])) {
        $l = New-Object 'System.Collections.Generic.List[object]'
        foreach ($i in $v) { $l.Add((ConvertFrom-JssValue $i)) }
        return , $l
    }
    if ($v -is [int]) { return [long]$v }
    if ($v -is [double]) {
        return [decimal]::Parse($v.ToString('R', $script:Inv), [System.Globalization.NumberStyles]::Float, $script:Inv)
    }
    return $v
}

function ConvertFrom-JsonElementValue($el) {
    switch ([string]$el.ValueKind) {
        'Object' {
            $d = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
            foreach ($p in $el.EnumerateObject()) { $d[$p.Name] = (ConvertFrom-JsonElementValue $p.Value) }
            return , $d
        }
        'Array' {
            $l = New-Object 'System.Collections.Generic.List[object]'
            foreach ($i in $el.EnumerateArray()) { $l.Add((ConvertFrom-JsonElementValue $i)) }
            return , $l
        }
        'String' { return $el.GetString() }
        'Number' {
            $raw = $el.GetRawText()
            if ($raw -cmatch '^-?[0-9]+$') {
                $lv = 0L
                if ([long]::TryParse($raw, [System.Globalization.NumberStyles]::AllowLeadingSign, $script:Inv, [ref]$lv)) { return $lv }
            }
            return [decimal]::Parse($raw, [System.Globalization.NumberStyles]::Float, $script:Inv)
        }
        'True' { return $true }
        'False' { return $false }
    }
    return $null
}

# JSON 文字列（エスケープ込み）と ${...} を先頭から順に拾う。文字列は読み飛ばし、${...} だけを置き換える。
# 直後が : の ${...} はキーの位置なので置き換えない（5.1 の JavaScriptSerializer は引用符なしのキーを
# 受け付けてしまい、実装間で結果が変わるため。置き換えなければどの実装でも構文エラーになる）
$script:PlaceholderScan = New-Object System.Text.RegularExpressions.Regex('"[^"\\]*(?:\\.[^"\\]*)*"|\$\{[^{}"\r\n]+\}(?![ \t\r\n]*:)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:PlaceholderLinesShown = 10
$script:PlaceholderCount = 0

function Resolve-Placeholders([string]$Text, [string]$Value) {
    # JSON 文字列の外に引用符なしで書かれた ${...}（後で置換するプレースホルダ）を数値 $Value に置き換える。
    # 文字列の中の ${...}（"${stageVariables.x}" など）は正しい JSON なので変更しない。
    # 戻り値: @{ Text = 置換後の文字列; Names = プレースホルダ（初出順）; Lines = プレースホルダ → 行番号の一覧 }
    $names = New-Object 'System.Collections.Generic.List[string]'
    $lines = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    if ($Text.IndexOf('${', [System.StringComparison]::Ordinal) -lt 0) { return @{ Text = $Text; Names = $names; Lines = $lines } }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    $line = 1L
    foreach ($m in $script:PlaceholderScan.Matches($Text)) {
        $s = $m.Index
        if ($Text[$s] -cne [char]'$') { continue }    # 文字列（読み飛ばすだけ）
        $j = $Text.IndexOf([char]10, $pos)
        while (($j -ge 0) -and ($j -lt $s)) { $line++; $j = $Text.IndexOf([char]10, $j + 1) }
        [void]$sb.Append($Text, $pos, $s - $pos)
        [void]$sb.Append($Value)
        if (-not $lines.ContainsKey($m.Value)) {
            $names.Add($m.Value)
            $lines[$m.Value] = New-Object 'System.Collections.Generic.List[long]'
        }
        $lines[$m.Value].Add($line)
        $pos = $s + $m.Length
    }
    [void]$sb.Append($Text, $pos, $Text.Length - $pos)
    return @{ Text = $sb.ToString(); Names = $names; Lines = $lines }
}

function Get-PlaceholderWarning([string]$Name, $Lines, [string]$Value) {
    $shown = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; ($i -lt $Lines.Count) -and ($i -lt $script:PlaceholderLinesShown); $i++) { $shown.Add($Lines[$i].ToString($script:Inv)) }
    if ($Lines.Count -gt $script:PlaceholderLinesShown) { $more = ' ほか' } else { $more = '' }
    return ('引用符なしのプレースホルダ ' + $Name + ' は JSON として読めないため、数値 ' + $Value + ' に置き換えて読み込みました（' +
        $Lines.Count.ToString($script:Inv) + ' 箇所・行 ' + [string]::Join(', ', $shown) + $more + '）')
}

function Read-JsonFile([string]$Path, [string]$PlaceholderValue) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        if (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)) {
            $text = $strict.GetString($bytes, 3, $bytes.Length - 3)
        } elseif (($bytes.Length -ge 2) -and ($bytes[0] -eq 0xFF) -and ($bytes[1] -eq 0xFE)) {
            $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
        } elseif (($bytes.Length -ge 2) -and ($bytes[0] -eq 0xFE) -and ($bytes[1] -eq 0xFF)) {
            $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
        } else {
            $text = $strict.GetString($bytes)
        }
    } catch {
        Stop-Gen ('入力ファイルの文字コードを UTF-8 として読めません: ' + $Path)
    }
    $ph = Resolve-Placeholders $text $PlaceholderValue
    $text = $ph.Text
    try {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $opts = New-Object System.Text.Json.JsonDocumentOptions
            $opts.MaxDepth = 1024
            $jd = [System.Text.Json.JsonDocument]::Parse($text, $opts)
            try { $doc = ConvertFrom-JsonElementValue $jd.RootElement } finally { $jd.Dispose() }
        } else {
            Add-Type -AssemblyName System.Web.Extensions
            $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $jss.MaxJsonLength = [int]::MaxValue
            $jss.RecursionLimit = 1024
            $doc = ConvertFrom-JssValue ($jss.DeserializeObject($text))
        }
    } catch {
        if ($_.Exception.Data.Contains('OA2J')) { throw }
        Stop-Gen ('JSON の構文エラーです（YAML 形式は未対応です）: ' + $_.Exception.Message)
    }
    foreach ($nm in $ph.Names) { Add-Warn (Get-PlaceholderWarning $nm $ph.Lines[$nm] $PlaceholderValue) }
    $script:PlaceholderCount = $ph.Names.Count
    return , $doc
}

# ----------------------------------------------------------------- メイン
function Resolve-UserPath([string]$p) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
}

function Invoke-Main {
    if ($Help) { Show-Usage; return 0 }
    if ($Version) { Write-Host ('OpenApi2Jmx.ps1 {0} (Apache JMeter 5.6.3 対応)' -f $script:ToolVersion); return 0 }

    # --- 入力チェック（linux/openapi2jmx.sh と同じ規則）
    if ([string]::IsNullOrEmpty($InputFile)) { Show-Usage; Stop-Gen 'OpenAPI 定義ファイルを -InputFile で指定してください' }
    $inPath = Resolve-UserPath $InputFile
    if (-not (Test-Path -LiteralPath $inPath)) { Stop-Gen ('入力ファイルが見つかりません: ' + $InputFile) }
    if (-not (Test-Path -LiteralPath $inPath -PathType Leaf)) { Stop-Gen ('入力はファイルを指定してください: ' + $InputFile) }
    if (-not ($Port -cmatch '^[0-9]{1,5}$') -or ([int]$Port -lt 1) -or ([int]$Port -gt 65535)) { Stop-Gen ('-Port は 1〜65535 の整数で指定してください: ' + $Port) }
    $portText = ([int]$Port).ToString($script:Inv)
    $proto = $Protocol.ToLowerInvariant()
    if (($proto -cne 'http') -and ($proto -cne 'https')) { Stop-Gen ('-Protocol は http または https を指定してください: ' + $Protocol) }
    if (-not (($TargetHost -cmatch '^[A-Za-z0-9._:-]+$') -or ($TargetHost -cmatch '^\[[0-9A-Fa-f:.]+\]$'))) { Stop-Gen ('-TargetHost に使用できない文字が含まれています: ' + $TargetHost) }
    if (($BasePath.Length -gt 0) -and -not ($BasePath -cmatch '^(/[A-Za-z0-9._~%-]+)+$')) { Stop-Gen ('-BasePath は /prod のように / で始まる英数字のパスで指定してください（末尾の / は不要）: ' + $BasePath) }
    if ($ApiKey.Length -eq 0) { Stop-Gen '-ApiKey に空文字は指定できません' }
    if ($ApiKey.Contains('(') -or $ApiKey.Contains(')') -or ($ApiKey -cmatch '[\x00-\x1F\x7F]')) { Stop-Gen '-ApiKey に括弧・制御文字は使用できません（その場合は実行時に -JapiKey=... で指定してください）' }
    if ($Seed.Length -gt 0) {
        if (-not ($Seed -cmatch '^[0-9]{1,12}$')) { Stop-Gen ('-Seed は 0 以上の整数（12 桁以内）で指定してください: ' + $Seed) }
        $script:SeedValue = [long]::Parse($Seed, $script:Inv)
    } else {
        $buf = New-Object byte[] 4
        $rngc = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rngc.GetBytes($buf) } finally { $rngc.Dispose() }
        $u = ([long]$buf[0] * 16777216L) + ([long]$buf[1] * 65536L) + ([long]$buf[2] * 256L) + [long]$buf[3]
        $script:SeedValue = $u % 1000000000L
    }
    if (-not ($PlaceholderValue -cmatch '^-?(0|[1-9][0-9]{0,14})([.][0-9]{1,12})?\z')) { Stop-Gen ('-PlaceholderValue は JSON の数値（例: 3000、-1、2.5。整数部 15 桁・小数部 12 桁以内）で指定してください: ' + $PlaceholderValue) }
    $anyM =$AnyMethod.ToUpperInvariant()
    if (-not (@('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS') -ccontains $anyM)) { Stop-Gen ('-AnyMethod は GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS のいずれかです: ' + $AnyMethod) }
    $script:OptRequiredOnly = [bool]$RequiredOnly
    $script:OptUseExamples = [bool]$UseExamples
    $script:OptAnyMethod = $anyM

    # --- 読み込みと検証
    $doc = Read-JsonFile $inPath $PlaceholderValue
    if (-not (Test-Obj $doc)) { Stop-Gen 'OpenAPI 定義のルートが JSON オブジェクトではありません' }
    $script:Doc = $doc
    if (Test-Has $doc 'swagger') { Stop-Gen 'Swagger 2.0 形式には対応していません。OpenAPI 3.0.x 形式（"openapi": "3.0.3" など）に変換してください' }
    $ver = Get-Prop $doc 'openapi'
    if (-not (Test-Str $ver) -or -not ($ver -cmatch '^3\.[0-9]+(\.[0-9]+)?')) { Stop-Gen '"openapi" フィールドが 3.x ではありません（OpenAPI 3.0.x の JSON を指定してください）' }
    if (-not $ver.StartsWith('3.0', [System.StringComparison]::Ordinal)) { Write-Host ('[WARN] OpenAPI {0} は 3.0.x 以外です。3.0.x と共通の項目のみを解釈します。' -f $ver) }
    if (-not (Test-Obj (Get-Prop $doc 'paths'))) { Stop-Gen '"paths" が定義されていません' }

    $info = Get-Prop $doc 'info'
    $title = Get-Prop $info 'title'
    if ((Test-Str $title) -and ($title.Trim().Length -gt 0)) { $title = $title.Trim() } else { $title = 'OpenAPI' }
    $apiVersion = Get-Prop $info 'version'
    if ((Test-Str $apiVersion) -and ($apiVersion.Trim().Length -gt 0)) { $apiVersion = $apiVersion.Trim() } else { $apiVersion = '-' }
    $name = Get-SafeName $title

    Initialize-Rng $script:SeedValue
    $ops = Get-Operations
    if ($ops.Count -eq 0) { Stop-Gen '"paths" に呼び出し可能な操作（get/post/put/delete など）が 1 件もありません' }

    $width = [System.Math]::Max(2, $ops.Count.ToString($script:Inv).Length)
    $requests = New-Object 'System.Collections.Generic.List[object]'
    for ($idx = 0; $idx -lt $ops.Count; $idx++) {
        $io = $ops[$idx]
        $num = ($idx + 1).ToString($script:Inv).PadLeft($width, [char]'0')
        if ($io.IsAny) { $mdisp = 'ANY(' + $io.Method + ')' } else { $mdisp = $io.Method }
        $label = $num + ' ' + $mdisp + ' ' + $io.Path
        $opId = Get-Prop $io.Op 'operationId'
        if ((Test-Str $opId) -and ($opId.Length -gt 0)) { $label += ' [' + $opId + ']' }
        $requests.Add((New-OperationRequest $io $label))
    }

    $useAuth = Test-NeedsAuthHeader $ops
    $meta = @{
        Name = $name; Title = $title; ApiVersion = $apiVersion; OpenApi = $ver
        InputName = [System.IO.Path]::GetFileName($inPath); ToolVersion = $script:ToolVersion
        Host = $TargetHost; Port = $portText; Protocol = $proto; BasePath = $BasePath; ApiKey = $ApiKey
    }
    $text = New-JmxText $meta $requests $useAuth

    # --- 書き出し
    if ([string]::IsNullOrEmpty($OutputFile)) { $outPath = Join-Path (Get-Location).ProviderPath ($name + '.jmx') } else { $outPath = Resolve-UserPath $OutputFile }
    $outPath = [System.IO.Path]::GetFullPath($outPath)
    $outDir = [System.IO.Path]::GetDirectoryName($outPath)
    if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Stop-Gen ('出力先フォルダが存在しません: ' + $outDir) }
    if (Test-Path -LiteralPath $outPath -PathType Container) { Stop-Gen ('出力先がフォルダです。ファイル名まで指定してください: ' + $outPath) }
    if ((Test-Path -LiteralPath $outPath) -and -not $Force) { Stop-Gen ('出力先に同名ファイルがあります（上書きする場合は -Force を指定）: ' + $outPath) }
    $tmp = $outPath + '.tmp.' + $PID.ToString($script:Inv)
    try {
        [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $outPath -Force
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        Stop-Gen ('JMX を書き込めません: ' + $outPath + ' (' + $_.Exception.Message + ')')
    }

    Write-Host ('[INFO] 入力       : {0}（OpenAPI {1} / {2} {3}）' -f $InputFile, $ver, $title, $apiVersion)
    Write-Host ('[INFO] 乱数シード : {0}（-Seed {0} を指定すると同じテストデータを再生成できます）' -f $script:SeedValue)
    Write-Host ('[INFO] 生成した API リクエスト: {0} 件' -f $requests.Count)
    foreach ($r in $requests) {
        $extra = New-Object 'System.Collections.Generic.List[string]'
        if ($r.Args.Count -gt 0) { $extra.Add(('パラメータ {0} 件' -f $r.Args.Count)) }
        if ($null -ne $r.BodyKind) { $extra.Add('ボディ ' + $r.BodyKind) }
        if ($r.Codes.Count -gt 0) { $extra.Add('期待 ' + [string]::Join('/', $r.Codes)) }
        if ($extra.Count -gt 0) { $tail = '  (' + [string]::Join(', ', $extra) + ')' } else { $tail = '' }
        Write-Host ('         ' + $r.Label + $tail)
    }
    foreach ($w in $script:Warnings) { Write-Host ('[WARN] ' + $w) }
    if ($script:PlaceholderCount -gt 0) { Write-Host '[INFO] 引用符なしの ${...} に入れる数値は -PlaceholderValue で変更できます' }
    Write-Host ('[INFO] 出力       : ' + $outPath)
    Write-Host ('[INFO] 既定の接続先: {0}://{1}:{2}{3} / X-API-KEY は -JapiKey= で上書き可' -f $proto, $TargetHost, $portText, $BasePath)
    Write-Host ('[INFO] 実行例     : .\Invoke-JmxScenario.ps1 -JmxFile "{0}"' -f $outPath)
    return 0
}

try {
    $rc = Invoke-Main
    exit $rc
} catch {
    if ($_.Exception.Data.Contains('OA2J')) {
        [Console]::Error.WriteLine('[ERROR] ' + $_.Exception.Message)
        exit 1
    }
    [Console]::Error.WriteLine('[ERROR] 予期しないエラーが発生しました: ' + $_.Exception.Message)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 2
}
