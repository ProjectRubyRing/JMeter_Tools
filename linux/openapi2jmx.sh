#!/usr/bin/env bash
# =============================================================================
#  openapi2jmx.sh
#    OpenAPI 3.0.x 定義ファイル（JSON）から Apache JMeter 5.6.3 用の
#    テスト計画（.jmx）を自動生成します。
#
#  対象 OS : RHEL 9.8（bash 5.1 / python3 3.9 は OS 標準搭載）ほか Linux 全般
#  依存    : bash 4 以上、python3 3.6 以上（標準ライブラリのみ使用。pip 不要）
#
#  生成されるテスト計画の既定値
#    - 接続先        : http://localhost:8080
#    - 共通ヘッダ    : X-API-KEY = XXXXXXXXXXXX（固定）
#    - スレッド      : 1 スレッド / ランプアップ 1 秒 / ループ 1 回（各 API を 1 回ずつ）
#    - テストデータ  : OpenAPI のデータ型定義からランダム生成
#    - 結果          : JTL（XML・詳細付き、JMeter GUI で閲覧可）と
#                      ログ（[API-RESULT] 行）を出力
#
#  Windows 版 windows/OpenApi2Jmx.ps1 と同一仕様・同一乱数アルゴリズムです。
#  同じ入力ファイル・同じ --seed なら、両者は 1 バイトも違わない JMX を出力します。
# =============================================================================
set -Eeuo pipefail

readonly TOOL_VERSION="1.0.0"
SCRIPT_NAME="$(basename -- "$0")"
readonly SCRIPT_NAME

usage() {
  cat <<EOF
使い方:
  ${SCRIPT_NAME} -i <OpenAPI定義.json> [オプション]

必須:
  -i, --input FILE        OpenAPI 3.0.x 定義ファイル（JSON 形式）

任意:
  -o, --output FILE       出力する JMX ファイル
                          （既定: カレントディレクトリの <APIタイトル>.jmx）
  -f, --force             出力先に同名ファイルがあっても上書きする
      --host HOST         接続先ホストの既定値            （既定: localhost）
      --port PORT         接続先ポートの既定値            （既定: 8080）
      --protocol PROTO    http または https               （既定: http）
      --base-path PATH    全 API パスの先頭に付けるパス   （既定: 空。例: /prod）
      --api-key KEY       X-API-KEY ヘッダの既定値        （既定: XXXXXXXXXXXX）
      --seed N            テストデータ用乱数シード（0 以上の整数・12 桁以内）
                          同じシードなら同じテストデータを再生成します（既定: 毎回ランダム）
      --any-method M      x-amazon-apigateway-any-method（ANY）を送るメソッド
                          GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS（既定: GET）
      --required-only     必須（required）のパラメータ・プロパティだけを生成する
      --use-examples      example / default が定義されていればランダム値より優先する
      --placeholder-value N
                          値の位置に引用符なしで書かれた \${...}（後で置換するプレースホルダ）に
                          仮に入れる数値（既定: 3000）。置き換えた箇所は警告として表示します
  -h, --help              このヘルプを表示
  -V, --version           バージョンを表示

環境変数:
  OPENAPI2JMX_PYTHON      使用する Python 3 のパス（未指定時は python3 を自動検出）

例:
  ${SCRIPT_NAME} -i openapi.json
  ${SCRIPT_NAME} -i openapi.json -o ./OrdersApi.jmx --seed 12345 --force

生成した JMX は次のように実行できます（結果: JTL とログ）:
  ./run_jmx.sh -t ./OrdersApi.jmx
  jmeter -n -t ./OrdersApi.jmx -j ./results/OrdersApi.log
EOF
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

need_value() {
  # $1 = オプション名, $2 = 残り引数の数
  if [[ "$2" -lt 2 ]]; then
    die "オプション $1 には値が必要です（--help を参照）"
  fi
}

# ---------------------------------------------------------------- 既定値
INPUT=""
OUTPUT=""
FORCE="0"
HOST="localhost"
PORT="8080"
PROTOCOL="http"
BASE_PATH=""
API_KEY="XXXXXXXXXXXX"
SEED=""
ANY_METHOD="GET"
REQUIRED_ONLY="0"
USE_EXAMPLES="0"
# 値の位置に引用符なしで書かれた ${...}（例: "timeoutInMillis": ${integration_timeout_ms}）は
# JSON として読めないため、この数値に置き換えて読み込む（--placeholder-value で変更可）
PLACEHOLDER_VALUE="3000"

# ---------------------------------------------------------------- 引数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)      need_value "$1" "$#"; INPUT="$2"; shift 2 ;;
    --input=*)       INPUT="${1#*=}"; shift ;;
    -o|--output)     need_value "$1" "$#"; OUTPUT="$2"; shift 2 ;;
    --output=*)      OUTPUT="${1#*=}"; shift ;;
    -f|--force)      FORCE="1"; shift ;;
    --host)          need_value "$1" "$#"; HOST="$2"; shift 2 ;;
    --host=*)        HOST="${1#*=}"; shift ;;
    --port)          need_value "$1" "$#"; PORT="$2"; shift 2 ;;
    --port=*)        PORT="${1#*=}"; shift ;;
    --protocol)      need_value "$1" "$#"; PROTOCOL="$2"; shift 2 ;;
    --protocol=*)    PROTOCOL="${1#*=}"; shift ;;
    --base-path)     need_value "$1" "$#"; BASE_PATH="$2"; shift 2 ;;
    --base-path=*)   BASE_PATH="${1#*=}"; shift ;;
    --api-key)       need_value "$1" "$#"; API_KEY="$2"; shift 2 ;;
    --api-key=*)     API_KEY="${1#*=}"; shift ;;
    --seed)          need_value "$1" "$#"; SEED="$2"; shift 2 ;;
    --seed=*)        SEED="${1#*=}"; shift ;;
    --any-method)    need_value "$1" "$#"; ANY_METHOD="$2"; shift 2 ;;
    --any-method=*)  ANY_METHOD="${1#*=}"; shift ;;
    --required-only) REQUIRED_ONLY="1"; shift ;;
    --use-examples)  USE_EXAMPLES="1"; shift ;;
    --placeholder-value)   need_value "$1" "$#"; PLACEHOLDER_VALUE="$2"; shift 2 ;;
    --placeholder-value=*) PLACEHOLDER_VALUE="${1#*=}"; shift ;;
    -h|--help)       usage; exit 0 ;;
    -V|--version)    printf '%s %s (Apache JMeter 5.6.3 対応)\n' "${SCRIPT_NAME}" "${TOOL_VERSION}"; exit 0 ;;
    --)              shift; break ;;
    -*)              die "不明なオプションです: $1（--help を参照）" ;;
    *)
      if [[ -z "${INPUT}" ]]; then
        INPUT="$1"; shift
      else
        die "余分な引数があります: $1（--help を参照）"
      fi
      ;;
  esac
done
if [[ $# -gt 0 ]]; then
  die "余分な引数があります: $1（--help を参照）"
fi

# ---------------------------------------------------------------- 入力チェック
# （正規表現は変数に入れて [[ =~ ]] に渡す。直接書くとクォートの解釈差で誤動作しやすいため）
readonly RE_PORT='^[0-9]{1,5}$'
readonly RE_HOST='^[A-Za-z0-9._:-]+$'
readonly RE_HOST6='^\[[0-9A-Fa-f:.]+\]$'
readonly RE_BASE_PATH='^(/[A-Za-z0-9._~%-]+)+$'
readonly RE_SEED='^[0-9]{1,12}$'
readonly RE_NUMBER='^-?(0|[1-9][0-9]{0,14})([.][0-9]{1,12})?$'
readonly RE_CNTRL='[[:cntrl:]]'

[[ -n "${INPUT}" ]] || { usage >&2; die "OpenAPI 定義ファイルを -i で指定してください"; }
[[ -e "${INPUT}" ]] || die "入力ファイルが見つかりません: ${INPUT}"
[[ -f "${INPUT}" ]] || die "入力はファイルを指定してください: ${INPUT}"
[[ -r "${INPUT}" ]] || die "入力ファイルを読み取れません（権限を確認してください）: ${INPUT}"

if ! [[ "${PORT}" =~ ${RE_PORT} ]] || (( 10#${PORT} < 1 || 10#${PORT} > 65535 )); then
  die "--port は 1〜65535 の整数で指定してください: ${PORT}"
fi
PORT="$((10#${PORT}))"

PROTOCOL="${PROTOCOL,,}"
if [[ "${PROTOCOL}" != "http" && "${PROTOCOL}" != "https" ]]; then
  die "--protocol は http または https を指定してください: ${PROTOCOL}"
fi

if ! [[ "${HOST}" =~ ${RE_HOST} || "${HOST}" =~ ${RE_HOST6} ]]; then
  die "--host に使用できない文字が含まれています: ${HOST}"
fi

if [[ -n "${BASE_PATH}" ]] && ! [[ "${BASE_PATH}" =~ ${RE_BASE_PATH} ]]; then
  die "--base-path は /prod のように / で始まる英数字のパスで指定してください（末尾の / は不要）: ${BASE_PATH}"
fi

[[ -n "${API_KEY}" ]] || die "--api-key に空文字は指定できません"
if [[ "${API_KEY}" == *"("* || "${API_KEY}" == *")"* || "${API_KEY}" =~ ${RE_CNTRL} ]]; then
  die "--api-key に括弧・制御文字は使用できません（その場合は実行時に -JapiKey=... で指定してください）"
fi

if [[ -n "${SEED}" ]]; then
  [[ "${SEED}" =~ ${RE_SEED} ]] || die "--seed は 0 以上の整数（12 桁以内）で指定してください: ${SEED}"
  SEED="$((10#${SEED}))"
fi

if ! [[ "${PLACEHOLDER_VALUE}" =~ ${RE_NUMBER} ]]; then
  die "--placeholder-value は JSON の数値（例: 3000、-1、2.5。整数部 15 桁・小数部 12 桁以内）で指定してください: ${PLACEHOLDER_VALUE}"
fi

ANY_METHOD="${ANY_METHOD^^}"
case "${ANY_METHOD}" in
  GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) ;;
  *) die "--any-method は GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS のいずれかです: ${ANY_METHOD}" ;;
esac

# ---------------------------------------------------------------- Python 3 の検出
find_python() {
  local cand
  local -a cands=()
  if [[ -n "${OPENAPI2JMX_PYTHON:-}" ]]; then
    cands+=("${OPENAPI2JMX_PYTHON}")
  fi
  cands+=(python3 /usr/bin/python3 /usr/libexec/platform-python python3.12 python3.11 python3.9 python)
  for cand in "${cands[@]}"; do
    if command -v "${cand}" >/dev/null 2>&1 \
       && "${cand}" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then
      command -v "${cand}"
      return 0
    fi
  done
  return 1
}

PYTHON_BIN="$(find_python)" \
  || die "Python 3.6 以上が見つかりません。RHEL 9 では 'sudo dnf install -y python3' で導入できます（OPENAPI2JMX_PYTHON で場所を指定することもできます）"

# ---------------------------------------------------------------- 生成処理（Python 本体）
exec "${PYTHON_BIN}" - \
  "input=${INPUT}" "output=${OUTPUT}" "force=${FORCE}" \
  "host=${HOST}" "port=${PORT}" "protocol=${PROTOCOL}" "base_path=${BASE_PATH}" \
  "api_key=${API_KEY}" "seed=${SEED}" "any_method=${ANY_METHOD}" \
  "required_only=${REQUIRED_ONLY}" "use_examples=${USE_EXAMPLES}" \
  "placeholder_value=${PLACEHOLDER_VALUE}" \
  "tool_version=${TOOL_VERSION}" <<'PYEOF'
# -*- coding: utf-8 -*-
# =============================================================================
#  openapi2jmx 本体（Python 3.6 以上・標準ライブラリのみ）
#  ※ windows/OpenApi2Jmx.ps1 と同一のアルゴリズム・同一の乱数列で実装しています。
#     どちらかを修正する場合は、必ずもう一方も同じように修正してください。
# =============================================================================
import base64
import datetime
import io
import json
import os
import re
import sys
from collections import OrderedDict
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR

JMETER_VERSION = '5.6.3'
TOOL_NAME = 'openapi2jmx'


class GenError(Exception):
    """利用者に伝えるべき入力エラー"""


# ----------------------------------------------------------------- 乱数（両実装共通）
MOD31 = 2147483647


class Rng(object):
    """Park-Miller 最小標準乱数（乗数 48271）。PowerShell 版と完全に同じ数列を返す。"""

    def __init__(self, seed):
        self.state = (seed % (MOD31 - 1)) + 1

    def next31(self):
        self.state = (self.state * 48271) % MOD31
        return self.state

    def between(self, lo, hi):
        if hi <= lo:
            return lo
        span = hi - lo + 1
        if span <= MOD31 - 1:
            return lo + (self.next31() - 1) % span
        r = (self.next31() - 1) * (MOD31 - 1) + (self.next31() - 1)
        return lo + r % span


# ----------------------------------------------------------------- 値の表現
class JNum(object):
    """JSON に数値として書き出す値（表記を文字列で厳密に保持する）"""
    __slots__ = ('text',)

    def __init__(self, text):
        self.text = text


SKIP = object()          # 生成しない（循環参照・深さ超過など）
UNITS_LIMIT = 10 ** 18   # 数値の生成範囲の上限（最小単位に換算した整数で。64bit 整数に収めるため）
MAX_DECIMALS = 12        # 数値の小数桁の上限
MAX_DEPTH = 12           # スキーマの入れ子の上限

ALNUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
LOWER_ALNUM = 'abcdefghijklmnopqrstuvwxyz0123456789'
HEXD = '0123456789abcdef'
EPOCH_START = 1735689600     # 2025-01-01T00:00:00Z
EPOCH_END = 1798761599       # 2026-12-31T23:59:59Z


def is_obj(x):
    return isinstance(x, dict)


def is_arr(x):
    return isinstance(x, list)


def is_str(x):
    return isinstance(x, str)


def is_bool(x):
    return isinstance(x, bool)


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def is_dec(x):
    return isinstance(x, Decimal)


def is_num(x):
    return is_int(x) or is_dec(x)


def get(o, k):
    return o.get(k) if isinstance(o, dict) else None


def has(o, k):
    return isinstance(o, dict) and k in o


def to_dec(x):
    if is_int(x):
        return Decimal(x)
    if is_dec(x):
        return x
    return None


def dec_plain(d):
    return format(d, 'f')


def clamp_to(d, lim):
    if d > lim:
        return lim
    if d < -lim:
        return -lim
    return d


def int_or_none(x):
    if is_int(x):
        return x if x >= 0 else None
    if is_dec(x) and x == x.to_integral_value() and x >= 0:
        return int(x)
    return None


def dceil(d):
    return int(d.to_integral_value(rounding=ROUND_CEILING))


def dfloor(d):
    return int(d.to_integral_value(rounding=ROUND_FLOOR))


def to_gen(x):
    """OpenAPI 定義上の値（example/enum など）を生成値の表現へ変換する"""
    if x is None or is_bool(x):
        return x
    if is_int(x):
        return JNum(str(x))
    if is_dec(x):
        return JNum(dec_plain(x))
    if is_str(x):
        return x
    if is_arr(x):
        return [to_gen(i) for i in x]
    if is_obj(x):
        o = OrderedDict()
        for k, v in x.items():
            o[k] = to_gen(v)
        return o
    return str(x)


# ----------------------------------------------------------------- 文字列の整形
def clean_text(s):
    """XML 1.0 で使えない文字（制御文字・孤立サロゲート等）を取り除く"""
    out = []
    for ch in s:
        c = ord(ch)
        if c == 9 or c == 10 or c == 13 or 0x20 <= c <= 0xD7FF or 0xE000 <= c <= 0xFFFD or c >= 0x10000:
            out.append(ch)
    return ''.join(out)


def xml_escape(s):
    s = clean_text(s)
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            .replace('"', '&quot;').replace("'", '&apos;').replace('\r', '&#xd;'))


def json_str(s):
    s = clean_text(s)
    out = ['"']
    for ch in s:
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def to_json(v, indent, pretty):
    if v is None:
        return 'null'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, JNum):
        return v.text
    if is_str(v):
        return json_str(v)
    if is_obj(v):
        if len(v) == 0:
            return '{}'
        if not pretty:
            return '{' + ','.join(json_str(k) + ':' + to_json(x, 0, False) for k, x in v.items()) + '}'
        pad = '  ' * (indent + 1)
        items = [pad + json_str(k) + ': ' + to_json(x, indent + 1, True) for k, x in v.items()]
        return '{\n' + ',\n'.join(items) + '\n' + '  ' * indent + '}'
    if is_arr(v):
        if len(v) == 0:
            return '[]'
        if not pretty:
            return '[' + ','.join(to_json(x, 0, False) for x in v) + ']'
        pad = '  ' * (indent + 1)
        items = [pad + to_json(x, indent + 1, True) for x in v]
        return '[\n' + ',\n'.join(items) + '\n' + '  ' * indent + ']'
    return json_str(str(v))


def scalar_str(v):
    if v is None:
        return ''
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, JNum):
        return v.text
    if is_str(v):
        return v
    return to_json(v, 0, False)


UNRESERVED = set(b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~')


def pct_encode(s, keep_slash):
    out = []
    for b in clean_text(s).encode('utf-8'):
        if b in UNRESERVED or (keep_slash and b == 0x2F):
            out.append(chr(b))
        else:
            out.append('%%%02X' % b)
    return ''.join(out)


def header_safe(s):
    return clean_text(s).replace('\r', ' ').replace('\n', ' ').replace('\t', ' ')


def func_arg(s):
    """JMeter 関数（__P など）の引数に埋め込むためのエスケープ"""
    return s.replace('\\', '\\\\').replace(',', '\\,').replace('$', '\\$')


def java_hash(s):
    """Java の String.hashCode() と同じ値（JMeter が test_strings の名前に使う）"""
    h = 0
    data = s.encode('utf-16-le')
    for i in range(0, len(data), 2):
        h = (31 * h + (data[i] | (data[i + 1] << 8))) & 0xFFFFFFFF
    if h >= 0x80000000:
        h -= 0x100000000
    return h


def safe_name(s):
    s = re.sub(r'[^A-Za-z0-9._-]+', '_', s)
    s = re.sub(r'_+', '_', s).strip('_.')
    return s if s else 'openapi'


def cp_len(s):
    return len(s)


# ----------------------------------------------------------------- 生成コンテキスト
class Ctx(object):
    def __init__(self, doc, seed, opts):
        self.doc = doc
        self.seed = seed
        self.rng = Rng(seed)
        self.required_only = opts['required_only']
        self.use_examples = opts['use_examples']
        self.any_method = opts['any_method']
        self.warnings = []

    def warn(self, msg):
        if msg not in self.warnings:
            self.warnings.append(msg)


def unescape_token(tok):
    if '%' in tok:
        try:
            from urllib.parse import unquote
            tok = unquote(tok, encoding='utf-8', errors='strict')
        except Exception:
            pass
    return tok.replace('~1', '/').replace('~0', '~')


def resolve_ref(ctx, ref):
    if not is_str(ref) or not ref.startswith('#'):
        return None
    if ref == '#' or ref == '#/':
        return ctx.doc
    if not ref.startswith('#/'):
        return None
    cur = ctx.doc
    for tok in ref[2:].split('/'):
        key = unescape_token(tok)
        if is_obj(cur) and key in cur:
            cur = cur[key]
        elif is_arr(cur) and re.match(r'^(0|[1-9][0-9]*)$', key) and int(key) < len(cur):
            cur = cur[int(key)]
        else:
            return None
    return cur


def ref_text(ref):
    return ref if is_str(ref) else '(不正な $ref)'


def deref(ctx, obj, what):
    """$ref を辿って実体を返す（Parameter / RequestBody / Response / Example / PathItem 用）"""
    seen = []
    while is_obj(obj) and '$ref' in obj:
        rt = ref_text(obj['$ref'])
        if rt in seen or len(seen) > 32:
            ctx.warn('%s の $ref が循環しています: %s' % (what, rt))
            return None
        seen.append(rt)
        target = resolve_ref(ctx, obj['$ref'])
        if target is None:
            ctx.warn('%s の $ref を解決できません（外部ファイル参照は未対応）: %s' % (what, rt))
            return None
        obj = target
    return obj


# ----------------------------------------------------------------- スキーマ → テストデータ
TYPES = ('object', 'array', 'integer', 'number', 'boolean', 'string', 'null')


def schema_type(schema):
    t = get(schema, 'type')
    if is_arr(t):
        names = [x for x in t if is_str(x)]
        non_null = [x for x in names if x != 'null']
        if non_null:
            t = non_null[0]
        elif names:
            t = 'null'
        else:
            t = None
    if is_str(t) and t in TYPES:
        return t
    if has(schema, 'properties') or has(schema, 'additionalProperties') or has(schema, 'minProperties') \
            or has(schema, 'maxProperties'):
        return 'object'
    if has(schema, 'items') or has(schema, 'minItems') or has(schema, 'maxItems'):
        return 'array'
    fmt = get(schema, 'format')
    if fmt == 'int32' or fmt == 'int64':
        return 'integer'
    if fmt == 'float' or fmt == 'double':
        return 'number'
    if has(schema, 'minimum') or has(schema, 'maximum') or has(schema, 'multipleOf') \
            or has(schema, 'exclusiveMinimum') or has(schema, 'exclusiveMaximum'):
        return 'number'
    return 'string'


def merge_schemas(a, b):
    r = OrderedDict(a)
    for k, v in b.items():
        if k == 'properties' and is_obj(v):
            props = OrderedDict(r['properties']) if is_obj(get(r, 'properties')) else OrderedDict()
            for pk, pv in v.items():
                if pk not in props:
                    props[pk] = pv
            r['properties'] = props
        elif k == 'required' and is_arr(v):
            req = list(r['required']) if is_arr(get(r, 'required')) else []
            for x in v:
                if x not in req:
                    req.append(x)
            r['required'] = req
        elif k not in r:
            r[k] = v
    return r


def follow_schema_ref(ctx, s, stack):
    """スキーマの $ref を辿る。戻り値: (実体 or None, 新しいスタック, 状態 'ok'|'cycle'|'unresolved')"""
    while is_obj(s) and '$ref' in s:
        rt = ref_text(s['$ref'])
        if rt in stack:
            return None, stack, 'cycle'
        t = resolve_ref(ctx, s['$ref'])
        if t is None:
            ctx.warn('スキーマの $ref を解決できません（外部ファイル参照は未対応）: ' + rt)
            return None, stack, 'unresolved'
        stack = stack + [rt]
        s = t
    return s, stack, 'ok'


def merge_all_of(ctx, schema, stack):
    result = OrderedDict((k, v) for k, v in schema.items() if k != 'allOf')
    for sub in schema['allOf']:
        s, s_stack, state = follow_schema_ref(ctx, sub, stack)
        if state != 'ok' or not is_obj(s):
            continue
        if is_arr(get(s, 'allOf')):
            s = merge_all_of(ctx, s, s_stack)
        result = merge_schemas(result, s)
    return result


def gen_value(ctx, schema, depth, stack):
    if schema is None or schema is True:
        schema = OrderedDict()
    if schema is False or not is_obj(schema):
        return SKIP
    if '$ref' in schema:
        s, new_stack, state = follow_schema_ref(ctx, schema, stack)
        if state == 'cycle':
            return SKIP
        if state == 'unresolved':
            return 'UNRESOLVED_REF'
        return gen_value(ctx, s, depth, new_stack)
    if depth > MAX_DEPTH:
        return SKIP
    if is_arr(get(schema, 'allOf')):
        schema = merge_all_of(ctx, schema, stack)
    for key in ('oneOf', 'anyOf'):
        alts = get(schema, key)
        if is_arr(alts) and len(alts) > 0:
            base = OrderedDict((k, v) for k, v in schema.items() if k != 'oneOf' and k != 'anyOf')
            alt, alt_stack, state = follow_schema_ref(ctx, alts[0], stack)
            if state == 'cycle':
                return SKIP
            if state == 'unresolved':
                return 'UNRESOLVED_REF'
            if not is_obj(alt):
                alt = OrderedDict()
            return gen_value(ctx, merge_schemas(base, alt), depth, alt_stack)
    if ctx.use_examples:
        if 'example' in schema:
            return to_gen(schema['example'])
        exs = get(schema, 'examples')
        if is_arr(exs) and len(exs) > 0:
            return to_gen(exs[0])
        if 'default' in schema:
            return to_gen(schema['default'])
    if 'const' in schema:
        return to_gen(schema['const'])
    enum = get(schema, 'enum')
    if is_arr(enum) and len(enum) > 0:
        cands = [e for e in enum if e is not None]
        if not cands:
            return None
        return to_gen(cands[ctx.rng.between(0, len(cands) - 1)])
    t = schema_type(schema)
    if t == 'object':
        return gen_object(ctx, schema, depth, stack)
    if t == 'array':
        return gen_array(ctx, schema, depth, stack)
    if t == 'integer':
        return gen_integer(ctx, schema)
    if t == 'number':
        return gen_number(ctx, schema)
    if t == 'boolean':
        return ctx.rng.between(0, 1) == 1
    if t == 'null':
        return None
    return gen_string(ctx, schema)


def is_read_only(ctx, pschema):
    s = pschema
    guard = 0
    while is_obj(s) and '$ref' in s and guard < 32:
        s = resolve_ref(ctx, s['$ref'])
        guard += 1
    return is_obj(s) and get(s, 'readOnly') is True


def gen_object(ctx, schema, depth, stack):
    result = OrderedDict()
    props = get(schema, 'properties')
    req = get(schema, 'required')
    required = [x for x in req if is_str(x)] if is_arr(req) else []
    if is_obj(props):
        for name, pschema in props.items():
            if ctx.required_only and name not in required:
                continue
            if is_read_only(ctx, pschema):
                continue
            v = gen_value(ctx, pschema, depth + 1, stack)
            if v is SKIP:
                continue
            result[name] = v
    addl = get(schema, 'additionalProperties')
    if len(result) == 0 and not (is_obj(props) and len(props) > 0) and is_obj(addl) and len(addl) > 0 \
            and not ctx.required_only:
        v = gen_value(ctx, addl, depth + 1, stack)
        if v is not SKIP:
            result['key1'] = v
    return result


def gen_array(ctx, schema, depth, stack):
    items = get(schema, 'items')
    if not is_obj(items):
        items = OrderedDict()
    mn = int_or_none(get(schema, 'minItems'))
    mx = int_or_none(get(schema, 'maxItems'))
    n = max(mn if mn is not None else 0, 1)
    if mx is not None and n > mx:
        n = mx
    if n > 50:
        n = 50
    unique = get(schema, 'uniqueItems') is True
    result = []
    seen = []
    for _ in range(n):
        v = gen_value(ctx, items, depth + 1, stack)
        if v is SKIP:
            break
        if unique:
            key = to_json(v, 0, False)
            tries = 0
            while key in seen and tries < 10:
                v = gen_value(ctx, items, depth + 1, stack)
                if v is SKIP:
                    break
                key = to_json(v, 0, False)
                tries += 1
            if v is SKIP:
                break
            seen.append(key)
        result.append(v)
    return result


def num_bounds(schema, scale):
    """minimum/maximum 等を scale（10 の d 乗）単位の整数範囲に変換する"""
    mn = to_dec(get(schema, 'minimum'))
    mx = to_dec(get(schema, 'maximum'))
    exmin = get(schema, 'exclusiveMinimum')
    exmax = get(schema, 'exclusiveMaximum')
    ex_lo = exmin is True
    ex_hi = exmax is True
    if is_num(exmin):
        e = to_dec(exmin)
        if mn is None or e >= mn:
            mn = e
            ex_lo = True
    if is_num(exmax):
        e = to_dec(exmax)
        if mx is None or e <= mx:
            mx = e
            ex_hi = True
    vlim = Decimal(UNITS_LIMIT // scale)
    lo = None
    hi = None
    if mn is not None:
        v = clamp_to(mn, vlim) * scale
        lo = dceil(v)
        if ex_lo and Decimal(lo) == v:
            lo += 1
    if mx is not None:
        v = clamp_to(mx, vlim) * scale
        hi = dfloor(v)
        if ex_hi and Decimal(hi) == v:
            hi -= 1
    one = scale
    if lo is None and hi is None:
        lo = one
        hi = 100 * one
    elif hi is None:
        hi = lo + 99 * one
    elif lo is None:
        lo = one if hi >= one else hi - 99 * one
    if lo > hi:
        hi = lo
    return lo, hi


def ceil_div(a, b):
    return -((-a) // b)


def gen_integer(ctx, schema):
    lo, hi = num_bounds(schema, 1)
    if get(schema, 'format') == 'int32':
        lo = max(lo, -2147483648)
        hi = min(hi, 2147483647)
        if lo > hi:
            hi = lo
    m = to_dec(get(schema, 'multipleOf'))
    if m is not None and m > 0 and m == m.to_integral_value():
        mi = int(m)
        kmin = ceil_div(lo, mi)
        kmax = hi // mi
        if kmin <= kmax:
            return JNum(str(ctx.rng.between(kmin, kmax) * mi))
        return JNum(str(lo))
    return JNum(str(ctx.rng.between(lo, hi)))


def decimals_of(d):
    s = dec_plain(d)
    if '.' in s:
        return len(s.split('.', 1)[1].rstrip('0'))
    return 0


def fmt_units(units, d):
    neg = units < 0
    a = -units if neg else units
    if d == 0:
        s = str(a)
    else:
        p = 10 ** d
        s = str(a // p) + '.' + str(a % p).rjust(d, '0')
    return '-' + s if neg else s


def gen_number(ctx, schema):
    m = to_dec(get(schema, 'multipleOf'))
    if m is not None and m <= 0:
        m = None
    d = decimals_of(m) if m is not None else 2
    if d > MAX_DECIMALS:
        d = MAX_DECIMALS
    scale = 10 ** d
    lo, hi = num_bounds(schema, scale)
    units = None
    if m is not None:
        mu = m * scale
        if mu > 0 and mu == mu.to_integral_value():
            mi = int(mu)
            kmin = ceil_div(lo, mi)
            kmax = hi // mi
            units = ctx.rng.between(kmin, kmax) * mi if kmin <= kmax else lo
    if units is None:
        units = ctx.rng.between(lo, hi)
    return JNum(fmt_units(units, d))


def rand_str(ctx, pool, n):
    out = []
    for _ in range(n):
        out.append(pool[ctx.rng.between(0, len(pool) - 1)])
    return ''.join(out)


def choose_len(ctx, min_l, max_l):
    lo = max(min_l if min_l is not None else 0, 8)
    if max_l is not None and lo > max_l:
        lo = max_l
    if max_l is None:
        hi = max(lo, 16)
    else:
        hi = min(max_l, max(lo, 16))
    if hi < lo:
        hi = lo
    return ctx.rng.between(lo, hi)


def epoch_to_utc(secs):
    return datetime.datetime(1970, 1, 1) + datetime.timedelta(seconds=secs)


def gen_string(ctx, schema):
    fmt = get(schema, 'format')
    fmt = fmt if is_str(fmt) else ''
    min_l = int_or_none(get(schema, 'minLength'))
    max_l = int_or_none(get(schema, 'maxLength'))
    pattern = get(schema, 'pattern')
    if is_str(pattern) and pattern != '':
        s = gen_from_pattern(ctx, pattern, min_l, max_l)
        if s is not None:
            return s
    if fmt == 'date-time':
        return epoch_to_utc(ctx.rng.between(EPOCH_START, EPOCH_END)).strftime('%Y-%m-%dT%H:%M:%SZ')
    if fmt == 'date':
        days = ctx.rng.between(EPOCH_START // 86400, EPOCH_END // 86400)
        return epoch_to_utc(days * 86400).strftime('%Y-%m-%d')
    if fmt == 'time':
        secs = ctx.rng.between(0, 86399)
        return '%02d:%02d:%02d' % (secs // 3600, (secs % 3600) // 60, secs % 60)
    if fmt == 'email':
        return rand_str(ctx, LOWER_ALNUM, 8) + '@example.com'
    if fmt == 'uuid':
        chars = []
        for i in range(32):
            if i == 12:
                chars.append('4')
            elif i == 16:
                chars.append(HEXD[8 + ctx.rng.between(0, 3)])
            else:
                chars.append(HEXD[ctx.rng.between(0, 15)])
        u = ''.join(chars)
        return u[0:8] + '-' + u[8:12] + '-' + u[12:16] + '-' + u[16:20] + '-' + u[20:32]
    if fmt in ('uri', 'url', 'uri-reference', 'iri', 'iri-reference'):
        return 'https://example.com/' + rand_str(ctx, LOWER_ALNUM, 8)
    if fmt in ('hostname', 'idn-hostname'):
        return rand_str(ctx, LOWER_ALNUM, 8) + '.example.com'
    if fmt == 'ipv4':
        return '192.0.2.' + str(ctx.rng.between(1, 254))
    if fmt == 'ipv6':
        return '2001:db8::' + ('%x' % ctx.rng.between(1, 65535))
    if fmt == 'byte':
        raw = bytearray()
        for _ in range(12):
            raw.append(ctx.rng.between(0, 255))
        return base64.b64encode(bytes(raw)).decode('ascii')
    if fmt == 'password':
        return rand_str(ctx, ALNUM, 12)
    if fmt == 'binary':
        return rand_str(ctx, ALNUM, 16)
    return rand_str(ctx, ALNUM, choose_len(ctx, min_l, max_l))


# ----------------------------------------------------------------- pattern（正規表現）から文字列を生成
class PatternError(Exception):
    pass


def _codes(a, b):
    return list(range(a, b + 1))


DIGIT_SET = _codes(0x30, 0x39)
UPPER_SET = _codes(0x41, 0x5A)
LOWER_SET = _codes(0x61, 0x7A)
ALNUM_SET = DIGIT_SET + UPPER_SET + LOWER_SET
WORD_SET = sorted(ALNUM_SET + [0x5F])
NONDIGIT_SET = UPPER_SET + LOWER_SET
NONWORD_SET = [0x2D, 0x2E]
SPACE_SET = [0x20]
NEG_BASE = sorted(ALNUM_SET + [0x2D, 0x2E, 0x5F])
PRINTABLE_SET = _codes(0x21, 0x7E)


def valid_code(c):
    return c == 9 or c == 10 or c == 13 or 0x20 <= c <= 0xD7FF or 0xE000 <= c <= 0xFFFD or 0x10000 <= c <= 0x10FFFF


class PatternParser(object):
    def __init__(self, pattern):
        self.p = pattern
        self.i = 0
        self.n = len(pattern)

    def peek(self, k=0):
        j = self.i + k
        return self.p[j] if j < self.n else None

    def take(self):
        ch = self.p[self.i]
        self.i += 1
        return ch

    def parse(self):
        node = self.alt()
        if self.i != self.n:
            raise PatternError('unexpected')
        return node

    def alt(self):
        options = [self.seq()]
        while self.peek() == '|':
            self.take()
            options.append(self.seq())
        if len(options) == 1:
            return options[0]
        return ('alt', options)

    def seq(self):
        items = []
        while True:
            ch = self.peek()
            if ch is None or ch == '|' or ch == ')':
                break
            items.append(self.quant(self.atom()))
        return ('seq', items)

    def atom(self):
        ch = self.take()
        if ch == '(':
            if self.peek() == '?':
                self.take()
                c2 = self.peek()
                if c2 == ':':
                    self.take()
                elif c2 == 'P' and self.peek(1) == '<':
                    self.skip_group_name(2)
                elif c2 == '<' and self.peek(1) is not None and self.peek(1) not in ('=', '!'):
                    self.skip_group_name(1)
                else:
                    raise PatternError('unsupported group')
            node = self.alt()
            if self.peek() != ')':
                raise PatternError('unbalanced')
            self.take()
            return node
        if ch == '[':
            return self.char_class()
        if ch == '.':
            return ('set', ALNUM_SET)
        if ch == '^' or ch == '$':
            return ('seq', [])
        if ch == '\\':
            return self.escape(False)
        if ch in ('*', '+', '?', ')'):
            raise PatternError('quantifier without target')
        return ('lit', ord(ch))

    def skip_group_name(self, k):
        for _ in range(k):
            self.take()
        while True:
            c = self.peek()
            if c is None:
                raise PatternError('bad group name')
            self.take()
            if c == '>':
                return

    def hex_digits(self, count):
        s = self.p[self.i:self.i + count]
        if len(s) != count or not re.match(r'^[0-9A-Fa-f]+$', s):
            raise PatternError('bad hex escape')
        self.i += count
        return int(s, 16)

    def escape(self, in_class):
        if self.i >= self.n:
            raise PatternError('trailing backslash')
        ch = self.take()
        if ch == 'd':
            return ('set', DIGIT_SET)
        if ch == 'D':
            return ('set', NONDIGIT_SET)
        if ch == 'w':
            return ('set', WORD_SET)
        if ch == 'W':
            return ('set', NONWORD_SET)
        if ch == 's':
            return ('set', SPACE_SET)
        if ch == 'S':
            return ('set', ALNUM_SET)
        if ch == 't':
            return ('lit', 9)
        if ch == 'n':
            return ('lit', 10)
        if ch == 'r':
            return ('lit', 13)
        if ch == 'u':
            c = self.hex_digits(4)
            if not valid_code(c):
                raise PatternError('bad code point')
            return ('lit', c)
        if ch == 'x':
            c = self.hex_digits(2)
            if not valid_code(c):
                raise PatternError('bad code point')
            return ('lit', c)
        if ch in ('b', 'B', 'A', 'z', 'Z', 'G'):
            if in_class:
                raise PatternError('unsupported escape in class')
            return ('seq', [])
        if ch in '0123456789' or ch in ('p', 'P', 'k', 'c', 'f', 'v', 'e', 'a', 'Q', 'E'):
            raise PatternError('unsupported escape')
        return ('lit', ord(ch))

    def class_item(self):
        ch = self.take()
        if ch == '\\':
            return self.escape(True)
        if ch == '[' and self.peek() == ':':
            raise PatternError('posix class')
        return ('lit', ord(ch))

    def char_class(self):
        negate = False
        if self.peek() == '^':
            self.take()
            negate = True
        codes = set()
        first = True
        while True:
            if self.i >= self.n:
                raise PatternError('unterminated class')
            if self.peek() == ']' and not first:
                self.take()
                break
            first = False
            item = self.class_item()
            if item[0] == 'lit' and self.peek() == '-' and self.peek(1) is not None and self.peek(1) != ']':
                self.take()
                item2 = self.class_item()
                if item2[0] != 'lit':
                    raise PatternError('bad range')
                a = item[1]
                b = item2[1]
                if a > b or b - a > 70000:
                    raise PatternError('bad range')
                for c in range(a, b + 1):
                    codes.add(c)
            elif item[0] == 'lit':
                codes.add(item[1])
            elif item[0] == 'set':
                for c in item[1]:
                    codes.add(c)
            else:
                raise PatternError('bad class item')
        if negate:
            pool = [c for c in NEG_BASE if c not in codes]
            if not pool:
                pool = [c for c in PRINTABLE_SET if c not in codes]
        else:
            pool = sorted(codes)
        pool = [c for c in pool if valid_code(c)]
        if not pool:
            raise PatternError('empty class')
        return ('set', pool)

    def quant(self, node):
        while True:
            ch = self.peek()
            if ch == '*':
                self.take()
                mn, mx = 0, None
            elif ch == '+':
                self.take()
                mn, mx = 1, None
            elif ch == '?':
                self.take()
                mn, mx = 0, 1
            elif ch == '{':
                m = re.match(r'\{([0-9]+)(,([0-9]*))?\}', self.p[self.i:])
                if m is None:
                    return node
                self.i += len(m.group(0))
                mn = int(m.group(1))
                if m.group(2) is None:
                    mx = mn
                elif m.group(3) == '':
                    mx = None
                else:
                    mx = int(m.group(3))
                if (mx is not None and mx < mn) or mn > 1000:
                    raise PatternError('bad quantifier')
            else:
                return node
            if self.peek() == '?' or self.peek() == '+':
                self.take()
            node = ('rep', node, mn, mx)


def gen_node(ctx, node, out):
    t = node[0]
    if t == 'lit':
        out.append(chr(node[1]))
    elif t == 'set':
        pool = node[1]
        out.append(chr(pool[ctx.rng.between(0, len(pool) - 1)]))
    elif t == 'seq':
        for x in node[1]:
            gen_node(ctx, x, out)
    elif t == 'alt':
        opts = node[1]
        gen_node(ctx, opts[ctx.rng.between(0, len(opts) - 1)], out)
    elif t == 'rep':
        mn = node[2]
        mx = node[3]
        if mx is None:
            mx = mn + 5
        cap = max(mn, 16)
        if mx > cap:
            mx = cap
        for _ in range(ctx.rng.between(mn, mx)):
            gen_node(ctx, node[1], out)


def gen_from_pattern(ctx, pattern, min_l, max_l):
    try:
        ast = PatternParser(pattern).parse()
    except PatternError:
        ctx.warn('pattern を解釈できないためランダム英数字で代用しました: ' + pattern)
        return None
    try:
        rx = re.compile(pattern)
    except Exception:
        rx = None
    last = None
    for _ in range(10):
        out = []
        gen_node(ctx, ast, out)
        s = ''.join(out)
        last = s
        if rx is not None and rx.search(s) is None:
            continue
        if min_l is not None and cp_len(s) < min_l:
            continue
        if max_l is not None and cp_len(s) > max_l:
            continue
        return s
    if last is not None and (rx is None or rx.search(last) is not None):
        return last
    ctx.warn('pattern に一致する値を生成できないためランダム英数字で代用しました: ' + pattern)
    return None


# ----------------------------------------------------------------- パラメータ
METHOD_KEYS = ('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
ANY_KEY = 'x-amazon-apigateway-any-method'
SKIP_HEADERS = ('accept', 'content-type', 'authorization')
MANAGED_HEADERS = ('content-length', 'host', 'transfer-encoding', 'connection')


def collect_params(ctx, item, op):
    table = OrderedDict()
    for src in (get(item, 'parameters'), get(op, 'parameters')):
        if not is_arr(src):
            continue
        for p in src:
            rp = deref(ctx, p, 'parameter')
            if not is_obj(rp):
                continue
            name = get(rp, 'name')
            loc = get(rp, 'in')
            if not is_str(name) or not is_str(loc) or name == '':
                continue
            table[loc + '\n' + name] = rp
    return list(table.values())


def first_value(d):
    for k in d:
        return d[k]
    return None


def param_value(ctx, p):
    if ctx.use_examples:
        if 'example' in p:
            return to_gen(p['example'])
        exs = get(p, 'examples')
        if is_obj(exs) and len(exs) > 0:
            first = deref(ctx, first_value(exs), 'example')
            if is_obj(first) and 'value' in first:
                return to_gen(first['value'])
    schema = get(p, 'schema')
    if schema is None:
        content = get(p, 'content')
        if is_obj(content) and len(content) > 0:
            schema = get(first_value(content), 'schema')
    if schema is None:
        schema = OrderedDict([('type', 'string')])
    v = gen_value(ctx, schema, 0, [])
    if v is SKIP:
        v = ''
    return v


def simple_style(v, explode):
    if is_arr(v):
        return ','.join(scalar_str(x) for x in v)
    if is_obj(v):
        if explode:
            return ','.join(k + '=' + scalar_str(x) for k, x in v.items())
        return ','.join(k + ',' + scalar_str(x) for k, x in v.items())
    return scalar_str(v)


def query_pairs(name, v, style, explode):
    if is_arr(v):
        if style == 'form' and explode:
            return [(name, scalar_str(x)) for x in v]
        if style == 'spaceDelimited':
            sep = ' '
        elif style == 'pipeDelimited':
            sep = '|'
        else:
            sep = ','
        return [(name, sep.join(scalar_str(x) for x in v))]
    if is_obj(v):
        if style == 'deepObject':
            return [(name + '[' + k + ']', scalar_str(x)) for k, x in v.items()]
        if explode:
            return [(k, scalar_str(x)) for k, x in v.items()]
        return [(name, ','.join(k + ',' + scalar_str(x) for k, x in v.items()))]
    return [(name, scalar_str(v))]


# ----------------------------------------------------------------- リクエストボディ
def media_base(mt):
    return mt.split(';', 1)[0].strip().lower()


def choose_media(keys):
    # JSON 系 → フォーム → マルチパート の順に優先し、どれも無ければ定義の先頭のメディアタイプを使う
    preds = (
        lambda b: b == 'application/json',
        lambda b: b.endswith('+json'),
        lambda b: 'json' in b,
        lambda b: b == 'application/x-www-form-urlencoded',
        lambda b: b == 'multipart/form-data',
    )
    for pred in preds:
        for k in keys:
            if pred(media_base(k)):
                return k
    return keys[0]


def media_kind(mt):
    b = media_base(mt)
    if b == 'application/json' or b.endswith('+json') or 'json' in b or b == '*/*' or b == 'application/*':
        return 'json'
    if b == 'application/x-www-form-urlencoded':
        return 'form'
    if b.startswith('multipart/'):
        return 'multipart'
    if b.endswith('/xml') or b.endswith('+xml'):
        return 'xml'
    if b.startswith('text/'):
        return 'text'
    return 'binary'


def content_type_for(mt, kind):
    if '*' in media_base(mt):
        if kind == 'json':
            return 'application/json'
        if kind == 'xml':
            return 'application/xml'
        if kind == 'text':
            return 'text/plain'
        return 'application/octet-stream'
    return mt.strip()


def xml_name(n):
    n = re.sub(r'[^A-Za-z0-9_.-]', '_', n)
    if n == '' or not re.match(r'^[A-Za-z_]', n):
        n = '_' + n
    return n


def xml_text(s):
    return clean_text(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def to_xml(v, name, indent):
    pad = '  ' * indent
    if is_obj(v):
        if len(v) == 0:
            return pad + '<' + name + '/>'
        lines = [pad + '<' + name + '>']
        for k, x in v.items():
            kn = xml_name(k)
            if is_arr(x):
                for it in x:
                    lines.append(to_xml(it, kn, indent + 1))
            else:
                lines.append(to_xml(x, kn, indent + 1))
        lines.append(pad + '</' + name + '>')
        return '\n'.join(lines)
    if is_arr(v):
        if len(v) == 0:
            return pad + '<' + name + '/>'
        return '\n'.join(to_xml(it, name, indent) for it in v)
    return pad + '<' + name + '>' + xml_text(scalar_str(v)) + '</' + name + '>'


def xml_root_name(ctx, schema):
    s = schema
    name = None
    guard = 0
    while is_obj(s) and '$ref' in s and guard < 32:
        ref = s['$ref']
        if is_str(ref):
            name = ref.split('/')[-1]
        s = resolve_ref(ctx, ref)
        guard += 1
    x = get(s, 'xml')
    if is_obj(x) and is_str(get(x, 'name')) and x['name'] != '':
        name = x['name']
    if not name:
        name = 'root'
    return xml_name(name)


def build_body(ctx, op):
    if not has(op, 'requestBody'):
        return None
    rb = deref(ctx, op['requestBody'], 'requestBody')
    content = get(rb, 'content')
    if not is_obj(content) or len(content) == 0:
        return None
    mt = choose_media(list(content.keys()))
    media = content[mt]
    schema = get(media, 'schema')
    kind = media_kind(mt)
    have = False
    value = None
    if ctx.use_examples and is_obj(media):
        if 'example' in media:
            value = to_gen(media['example'])
            have = True
        else:
            exs = get(media, 'examples')
            if is_obj(exs) and len(exs) > 0:
                first = deref(ctx, first_value(exs), 'example')
                if is_obj(first) and 'value' in first:
                    value = to_gen(first['value'])
                    have = True
    if not have:
        if schema is None:
            value = OrderedDict() if kind in ('json', 'form', 'multipart', 'xml') else rand_str(ctx, ALNUM, 16)
        else:
            value = gen_value(ctx, schema, 0, [])
            if value is SKIP:
                value = OrderedDict()
    ctype = content_type_for(mt, kind)
    if kind == 'json':
        return {'kind': kind, 'ctype': ctype, 'text': to_json(value, 0, True), 'pairs': []}
    if kind == 'form' or kind == 'multipart':
        pairs = []
        if is_obj(value):
            for k, x in value.items():
                if is_arr(x):
                    for it in x:
                        pairs.append((k, scalar_str(it)))
                else:
                    pairs.append((k, scalar_str(x)))
        else:
            pairs.append(('value', scalar_str(value)))
        return {'kind': kind, 'ctype': ctype, 'text': '', 'pairs': pairs}
    if kind == 'xml':
        text = '<?xml version="1.0" encoding="UTF-8"?>\n' + to_xml(value, xml_root_name(ctx, schema), 0)
        return {'kind': kind, 'ctype': ctype, 'text': text, 'pairs': []}
    text = value if is_str(value) else to_json(value, 0, True)
    return {'kind': kind, 'ctype': ctype, 'text': text, 'pairs': []}


# ----------------------------------------------------------------- レスポンス（Accept・期待ステータス）
def is_2xx(k):
    return re.match(r'^2[0-9][0-9]$', k) is not None or k == '2XX'


def pick_accept(ctx, op):
    responses = get(op, 'responses')
    if not is_obj(responses):
        return None
    for k, resp in responses.items():
        if not is_2xx(str(k).strip().upper()):
            continue
        r = deref(ctx, resp, 'response')
        content = get(r, 'content')
        if is_obj(content) and len(content) > 0:
            mt = list(content.keys())[0]
            if '*' in mt:
                return None
            return mt.strip()
    return None


def success_codes(op):
    responses = get(op, 'responses')
    codes = []
    has_range = False
    if is_obj(responses):
        for k in responses.keys():
            ks = str(k).strip().upper()
            if re.match(r'^2[0-9][0-9]$', ks):
                if ks not in codes:
                    codes.append(ks)
            elif ks == '2XX':
                has_range = True
    return codes, has_range


# ----------------------------------------------------------------- セキュリティ
def effective_security(ctx, op):
    if has(op, 'security'):
        return get(op, 'security')
    return get(ctx.doc, 'security')


def security_text(ctx, op):
    sec = effective_security(ctx, op)
    if not is_arr(sec):
        return None
    if len(sec) == 0:
        return 'なし（認証不要）'
    alts = []
    for req in sec:
        if not is_obj(req):
            continue
        if len(req) == 0:
            alts.append('認証なしも可')
            continue
        parts = []
        for name, scopes in req.items():
            sc = [x for x in scopes if is_str(x)] if is_arr(scopes) else []
            parts.append(name + ('[' + ', '.join(sc) + ']' if sc else ''))
        alts.append(' かつ '.join(parts))
    return ' または '.join(alts) if alts else None


def scheme_uses_authorization(scheme):
    if not is_obj(scheme):
        return False
    t = get(scheme, 'type')
    if t == 'oauth2' or t == 'openIdConnect' or t == 'http':
        return True
    if t == 'apiKey':
        return get(scheme, 'in') == 'header' and is_str(get(scheme, 'name')) \
            and scheme['name'].lower() == 'authorization'
    return False


def needs_auth_header(ctx, ops):
    schemes = get(get(ctx.doc, 'components'), 'securitySchemes')
    for info in ops:
        sec = effective_security(ctx, info['op'])
        if not is_arr(sec):
            continue
        for req in sec:
            if not is_obj(req):
                continue
            for name in req.keys():
                sch = deref(ctx, get(schemes, name), 'securityScheme')
                if scheme_uses_authorization(sch):
                    return True
    return False


# ----------------------------------------------------------------- オペレーション
def collect_operations(ctx):
    ops = []
    paths = get(ctx.doc, 'paths')
    for path, item in paths.items():
        if path.startswith('x-'):
            continue
        item = deref(ctx, item, 'pathItem')
        if not is_obj(item):
            continue
        for key, op in item.items():
            k = key.lower()
            if k in METHOD_KEYS:
                method = k.upper()
                is_any = False
            elif k == ANY_KEY:
                method = ctx.any_method
                is_any = True
            else:
                continue
            if not is_obj(op):
                continue
            ops.append({'path': path, 'item': item, 'op': op, 'key': key, 'method': method, 'is_any': is_any})
    return ops


PLACEHOLDER_RE = re.compile(r'\{([^{}]+)\}')


def build_operation(ctx, info, label):
    path = info['path']
    item = info['item']
    op = info['op']
    method = info['method']
    params = collect_params(ctx, item, op)

    # 1. パスパラメータ
    path_vals = OrderedDict()
    for p in params:
        if get(p, 'in') == 'path':
            path_vals[p['name']] = (param_value(ctx, p), get(p, 'explode') is True)
    for m in PLACEHOLDER_RE.finditer(path):
        ph = m.group(1)
        base = ph[:-1] if ph.endswith('+') else ph
        if base not in path_vals:
            ctx.warn('%s: パス変数 {%s} のパラメータ定義が無いため英数字 8 文字を仮設定しました' % (label, base))
            path_vals[base] = (rand_str(ctx, ALNUM, 8), False)
    parts = []
    pos = 0
    for m in PLACEHOLDER_RE.finditer(path):
        parts.append(path[pos:m.start()])
        ph = m.group(1)
        greedy = ph.endswith('+')
        base = ph[:-1] if greedy else ph
        v, explode = path_vals[base]
        parts.append(pct_encode(simple_style(v, explode), greedy))
        pos = m.end()
    parts.append(path[pos:])
    real_path = ''.join(parts)
    if not real_path.startswith('/'):
        real_path = '/' + real_path

    # 2. クエリパラメータ
    qpairs = []
    for p in params:
        if get(p, 'in') != 'query':
            continue
        if ctx.required_only and get(p, 'required') is not True:
            continue
        v = param_value(ctx, p)
        style = get(p, 'style')
        style = style if is_str(style) else 'form'
        explode = get(p, 'explode')
        explode = explode if is_bool(explode) else (style == 'form')
        qpairs.extend(query_pairs(p['name'], v, style, explode))

    # 3. ヘッダパラメータ
    hparams = []
    for p in params:
        if get(p, 'in') != 'header':
            continue
        name = p['name']
        lname = name.lower()
        if lname in SKIP_HEADERS:
            continue
        if lname == 'x-api-key':
            ctx.warn('%s: ヘッダ %s は共通の X-API-KEY（固定値）を優先するため個別には生成しません' % (label, name))
            continue
        if lname in MANAGED_HEADERS:
            ctx.warn('%s: ヘッダ %s は HTTP クライアントが自動設定するため生成しません' % (label, name))
            continue
        if ctx.required_only and get(p, 'required') is not True:
            continue
        v = param_value(ctx, p)
        hparams.append((name, header_safe(simple_style(v, get(p, 'explode') is True))))

    # 4. クッキーパラメータ
    cookies = []
    for p in params:
        if get(p, 'in') != 'cookie':
            continue
        if ctx.required_only and get(p, 'required') is not True:
            continue
        v = param_value(ctx, p)
        cookies.append(p['name'] + '=' + pct_encode(simple_style(v, False), False))

    # 5. リクエストボディ
    body = build_body(ctx, op)

    # 6. 組み立て
    final_path = '${BASE_PATH}' + real_path
    args = []
    if qpairs:
        if method == 'GET' and body is None:
            args = qpairs
        else:
            final_path += '?' + '&'.join(pct_encode(k, False) + '=' + pct_encode(v, False) for k, v in qpairs)
    raw_body = None
    multipart = False
    headers = []
    if body is not None:
        if body['kind'] == 'form':
            args = body['pairs']
            headers.append(('Content-Type', body['ctype']))
        elif body['kind'] == 'multipart':
            args = body['pairs']
            multipart = True
        else:
            raw_body = body['text']
            headers.append(('Content-Type', body['ctype']))
    accept = pick_accept(ctx, op)
    if accept is not None:
        headers.append(('Accept', accept))
    headers.extend(hparams)
    if cookies:
        headers.append(('Cookie', '; '.join(cookies)))

    codes, has_range = success_codes(op)
    has_data = len(path_vals) > 0 or len(qpairs) > 0 or len(hparams) > 0 or len(cookies) > 0 or body is not None
    return {'label': label, 'path': final_path, 'method': method, 'args': args, 'raw_body': raw_body,
            'multipart': multipart, 'headers': headers, 'codes': codes, 'has_range': has_range,
            'comment': operation_comment(ctx, info, body, has_data), 'body_kind': body['kind'] if body else None}


def operation_comment(ctx, info, body, has_data):
    op = info['op']
    lines = []
    summary = get(op, 'summary')
    if is_str(summary) and summary.strip():
        lines.append('概要: ' + summary.strip())
    desc = get(op, 'description')
    if is_str(desc) and desc.strip():
        lines.append('説明: ' + desc.strip())
    lines.append('OpenAPI 定義: ' + info['key'] + ' ' + info['path'])
    op_id = get(op, 'operationId')
    if is_str(op_id) and op_id:
        lines.append('operationId: ' + op_id)
    if info['is_any']:
        lines.append('ANY メソッド（x-amazon-apigateway-any-method）のため ' + info['method']
                     + ' で代表して送信します（生成時の --any-method / -AnyMethod で変更可）。')
    sec = security_text(ctx, op)
    if sec is not None:
        lines.append('認可（security）: ' + sec)
    integ = get(op, 'x-amazon-apigateway-integration')
    if is_obj(integ):
        items = []
        for k in ('type', 'httpMethod', 'uri', 'connectionType'):
            if is_str(get(integ, k)):
                items.append(k + '=' + integ[k])
        if items:
            lines.append('API Gateway 統合: ' + ', '.join(items))
    if get(op, 'deprecated') is True:
        lines.append('※ deprecated（非推奨）に指定された API です。')
    if body is not None and body['kind'] == 'multipart':
        lines.append('※ multipart/form-data はファイル項目もテキスト値で送信します。実ファイルを送る場合は「ファイルアップロード」タブで設定してください。')
    if has_data:
        lines.append('テストデータ: OpenAPI のデータ型定義からランダム生成（乱数シード ' + str(ctx.seed) + '）')
    return '\n'.join(lines)


# ----------------------------------------------------------------- JMX 出力
class Xml(object):
    def __init__(self):
        self.lines = []

    def add(self, ind, text):
        self.lines.append('  ' * ind + text)

    def text(self):
        return '\n'.join(self.lines) + '\n'


def x_str(x, ind, name, value):
    x.add(ind, '<stringProp name="' + xml_escape(name) + '">' + xml_escape(value) + '</stringProp>')


def x_bool(x, ind, name, value):
    x.add(ind, '<boolProp name="' + name + '">' + ('true' if value else 'false') + '</boolProp>')


def x_int(x, ind, name, value):
    x.add(ind, '<intProp name="' + name + '">' + str(value) + '</intProp>')


def x_open(x, ind, tag, guiclass, testclass, testname, enabled=True):
    attrs = 'guiclass="' + guiclass + '" testclass="' + testclass + '" testname="' + xml_escape(testname) + '"'
    if not enabled:
        attrs += ' enabled="false"'
    x.add(ind, '<' + tag + ' ' + attrs + '>')


def x_headers(x, ind, testname, headers, comment, enabled=True):
    x_open(x, ind, 'HeaderManager', 'HeaderPanel', 'HeaderManager', testname, enabled)
    if comment:
        x_str(x, ind + 1, 'TestPlan.comments', comment)
    x.add(ind + 1, '<collectionProp name="HeaderManager.headers">')
    for name, value in headers:
        x.add(ind + 2, '<elementProp name="" elementType="Header">')
        x_str(x, ind + 3, 'Header.name', name)
        x_str(x, ind + 3, 'Header.value', value)
        x.add(ind + 2, '</elementProp>')
    x.add(ind + 1, '</collectionProp>')
    x.add(ind, '</HeaderManager>')
    x.add(ind, '<hashTree/>')


SAVE_CONFIG_DETAIL = (
    ('time', 'true'), ('latency', 'true'), ('timestamp', 'true'), ('success', 'true'), ('label', 'true'),
    ('code', 'true'), ('message', 'true'), ('threadName', 'true'), ('dataType', 'true'), ('encoding', 'true'),
    ('assertions', 'true'), ('subresults', 'true'), ('responseData', 'true'), ('samplerData', 'true'),
    ('xml', 'true'), ('fieldNames', 'true'), ('responseHeaders', 'true'), ('requestHeaders', 'true'),
    ('responseDataOnError', 'false'), ('saveAssertionResultsFailureMessage', 'true'),
    ('assertionsResultsToSave', '0'), ('bytes', 'true'), ('sentBytes', 'true'), ('url', 'true'),
    ('fileName', 'true'), ('hostname', 'true'), ('threadCounts', 'true'), ('sampleCount', 'true'),
    ('idleTime', 'true'), ('connectTime', 'true'),
)


def x_collector(x, ind, guiclass, testname, comment, filename):
    x_open(x, ind, 'ResultCollector', guiclass, 'ResultCollector', testname)
    x_str(x, ind + 1, 'TestPlan.comments', comment)
    x_bool(x, ind + 1, 'ResultCollector.error_logging', False)
    x.add(ind + 1, '<objProp>')
    x.add(ind + 2, '<name>saveConfig</name>')
    x.add(ind + 2, '<value class="SampleSaveConfiguration">')
    for k, v in SAVE_CONFIG_DETAIL:
        x.add(ind + 3, '<' + k + '>' + v + '</' + k + '>')
    x.add(ind + 2, '</value>')
    x.add(ind + 1, '</objProp>')
    x_str(x, ind + 1, 'filename', filename)
    x.add(ind, '</ResultCollector>')
    x.add(ind, '<hashTree/>')


def x_arg(x, ind, name, value, desc):
    x.add(ind, '<elementProp name="' + xml_escape(name) + '" elementType="Argument">')
    x_str(x, ind + 1, 'Argument.name', name)
    x_str(x, ind + 1, 'Argument.value', value)
    if desc:
        x_str(x, ind + 1, 'Argument.desc', desc)
    x_str(x, ind + 1, 'Argument.metadata', '=')
    x.add(ind, '</elementProp>')


def x_http_arg(x, ind, name, value):
    x.add(ind, '<elementProp name="' + xml_escape(name) + '" elementType="HTTPArgument">')
    x_bool(x, ind + 1, 'HTTPArgument.always_encode', True)
    x_str(x, ind + 1, 'Argument.name', name)
    x_str(x, ind + 1, 'Argument.value', value)
    x_str(x, ind + 1, 'Argument.metadata', '=')
    x_bool(x, ind + 1, 'HTTPArgument.use_equals', True)
    x.add(ind, '</elementProp>')


RESULT_LOG_SCRIPT = '\n'.join([
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
    "}",
])


def build_jmx(ctx, meta, requests, use_auth):
    name = meta['name']
    x = Xml()
    x.add(0, '<?xml version="1.0" encoding="UTF-8"?>')
    x.add(0, '<jmeterTestPlan version="1.2" properties="5.0" jmeter="' + JMETER_VERSION + '">')
    x.add(1, '<hashTree>')

    # --- テスト計画
    plan_name = '%s %s - API疎通確認（OpenAPI %s から自動生成）' % (meta['title'], meta['api_version'], meta['openapi'])
    c = [
        'このテスト計画は ' + TOOL_NAME + ' ' + meta['tool_version'] + ' が OpenAPI 定義ファイルから自動生成しました（Apache JMeter '
        + JMETER_VERSION + ' 対応）。',
        '入力ファイル : ' + meta['input_name'] + '（OpenAPI ' + meta['openapi'] + ' / ' + meta['title'] + ' ' + meta['api_version'] + '）',
        'リクエスト数 : ' + str(len(requests)) + ' 件（各 API を 1 回ずつ呼び出す最小構成）',
        'テストデータ : OpenAPI のデータ型定義からランダム生成（乱数シード ' + str(ctx.seed) + '。同じシードを指定すると同じデータを再生成できます）',
        '既定の接続先 : ' + meta['protocol'] + '://' + meta['host'] + ':' + str(meta['port']) + meta['base_path']
        + '（実行時に -Jprotocol= -Jhost= -Jport= -JbasePath= で上書きできます）',
        '共通ヘッダ   : X-API-KEY（ユーザー定義変数 API_KEY の値。実行時に -JapiKey= で上書きできます）',
        '結果（JTL）  : RESULT_DIR/' + name + '_RUN_ID.jtl（XML 形式・リクエスト/レスポンス詳細付き。JMeter GUI のリスナーで開けます）',
        '結果（ログ） : jmeter.log（CLI 実行時は -j で指定したファイル）に [API-RESULT] 行を 1 リクエスト 1 行で出力します。',
    ]
    if ctx.warnings:
        c.append('')
        c.append('【生成時の注意】')
        for w in ctx.warnings:
            c.append('・' + w)
    x_open(x, 2, 'TestPlan', 'TestPlanGui', 'TestPlan', plan_name)
    x_str(x, 3, 'TestPlan.comments', '\n'.join(c))
    x_bool(x, 3, 'TestPlan.functional_mode', False)
    x_bool(x, 3, 'TestPlan.tearDown_on_shutdown', True)
    x_bool(x, 3, 'TestPlan.serialize_threadgroups', False)
    x.add(3, '<elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" '
             'testclass="Arguments" testname="User Defined Variables">')
    x.add(4, '<collectionProp name="Arguments.arguments">')
    udvs = [
        ('PROTOCOL', '${__P(protocol,' + func_arg(meta['protocol']) + ')}',
         '接続プロトコル（http / https）。実行時に -Jprotocol=https のように上書きできます。'),
        ('HOST', '${__P(host,' + func_arg(meta['host']) + ')}',
         '接続先ホスト名。実行時に -Jhost=... で上書きできます。'),
        ('PORT', '${__P(port,' + func_arg(str(meta['port'])) + ')}',
         '接続先ポート番号。実行時に -Jport=... で上書きできます。'),
        ('BASE_PATH', '${__P(basePath,' + func_arg(meta['base_path']) + ')}',
         '全 API パスの先頭に付けるパス（例: /prod）。実行時に -JbasePath=... で上書きできます。'),
        ('API_KEY', '${__P(apiKey,' + func_arg(meta['api_key']) + ')}',
         'X-API-KEY ヘッダに固定で設定する値。実行時に -JapiKey=... で上書きできます。'),
    ]
    if use_auth:
        udvs.append(('AUTH_TOKEN', '${__P(authToken,)}',
                     'Authorization ヘッダの値（無効化してあるヘッダマネージャで使用）。実行時に -JauthToken=... で指定します。'))
    udvs.extend([
        ('THREADS', '${__P(threads,1)}',
         'スレッド数（同時に動く仮想ユーザー数）。最小構成は 1。実行時に -Jthreads=... で上書きできます。'),
        ('RAMP_UP', '${__P(rampUp,1)}',
         '全スレッドを起動し終えるまでの秒数。最小構成は 1。実行時に -JrampUp=... で上書きできます。'),
        ('LOOPS', '${__P(loops,1)}',
         '各スレッドの繰り返し回数。最小構成は 1。実行時に -Jloops=... で上書きできます。'),
        ('CONNECT_TIMEOUT', '${__P(connectTimeout,10000)}',
         '接続タイムアウト（ミリ秒）。実行時に -JconnectTimeout=... で上書きできます。'),
        ('RESPONSE_TIMEOUT', '${__P(responseTimeout,60000)}',
         '応答タイムアウト（ミリ秒）。API Gateway の統合タイムアウト既定値 29 秒より長くしています。実行時に -JresponseTimeout=... で上書きできます。'),
        ('RESULT_DIR', '${__P(resultDir,~/results)}',
         'JTL の出力フォルダ。~/ は「この JMX ファイルがあるフォルダ」を表す JMeter の記法です。実行時に -JresultDir=... で上書きできます。'),
        ('RUN_ID', '${__P(runId,${__time(yyyyMMdd-HHmmss,)})}',
         '結果ファイル名に付ける実行 ID（既定: テスト開始時刻）。実行時に -JrunId=... で上書きできます。'),
    ])
    for n, v, d in udvs:
        x_arg(x, 5, n, v, d)
    x.add(4, '</collectionProp>')
    x.add(3, '</elementProp>')
    x_str(x, 3, 'TestPlan.user_define_classpath', '')
    x.add(2, '</TestPlan>')
    x.add(2, '<hashTree>')

    # --- HTTP リクエスト初期値設定
    x_open(x, 3, 'ConfigTestElement', 'HttpDefaultsGui', 'ConfigTestElement', 'HTTPリクエスト初期値設定')
    x_str(x, 4, 'TestPlan.comments',
          '全リクエスト共通の接続先・文字コード・タイムアウト。値はテスト計画のユーザー定義変数を参照しており、'
          '実行時に -Jhost= などで上書きできます。実装は HttpClient4（JMeter 5.6.3 の既定・推奨）です。')
    x.add(4, '<elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" '
             'testclass="Arguments" testname="User Defined Variables">')
    x.add(5, '<collectionProp name="Arguments.arguments"/>')
    x.add(4, '</elementProp>')
    x_str(x, 4, 'HTTPSampler.domain', '${HOST}')
    x_str(x, 4, 'HTTPSampler.port', '${PORT}')
    x_str(x, 4, 'HTTPSampler.protocol', '${PROTOCOL}')
    x_str(x, 4, 'HTTPSampler.contentEncoding', 'UTF-8')
    x_str(x, 4, 'HTTPSampler.path', '')
    x_str(x, 4, 'HTTPSampler.implementation', 'HttpClient4')
    x_str(x, 4, 'HTTPSampler.connect_timeout', '${CONNECT_TIMEOUT}')
    x_str(x, 4, 'HTTPSampler.response_timeout', '${RESPONSE_TIMEOUT}')
    x_bool(x, 4, 'HTTPSampler.image_parser', False)
    x_bool(x, 4, 'HTTPSampler.concurrentDwn', False)
    x_str(x, 4, 'HTTPSampler.embedded_url_re', '')
    x.add(3, '</ConfigTestElement>')
    x.add(3, '<hashTree/>')

    # --- 共通ヘッダ（X-API-KEY）
    x_headers(x, 3, 'HTTPヘッダマネージャ（共通: X-API-KEY）', [('X-API-KEY', '${API_KEY}')],
              '全リクエストに X-API-KEY ヘッダを固定で付与します（値はユーザー定義変数 API_KEY、既定 XXXXXXXXXXXX）。')
    if use_auth:
        x_headers(x, 3, 'HTTPヘッダマネージャ（Authorization・無効化中）', [('Authorization', '${AUTH_TOKEN}')],
                  'OpenAPI 定義に認可（security）があるため用意した Authorization ヘッダです。API Gateway 経由で'
                  'オーソライザー（Cognito 等）を通す場合は、この要素を有効化し -JauthToken=トークン を指定してください。',
                  enabled=False)

    # --- スレッドグループ
    x_open(x, 3, 'ThreadGroup', 'ThreadGroupGui', 'ThreadGroup', 'TG01_' + name)
    x_str(x, 4, 'TestPlan.comments',
          '最小構成（スレッド 1・ランプアップ 1 秒・ループ 1 回）で各 API を 1 回ずつ呼び出し、疎通を確認します。'
          'エラー後も続行するため、1 件失敗しても残りの API をすべて確認できます。')
    x_str(x, 4, 'ThreadGroup.on_sample_error', 'continue')
    x.add(4, '<elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" '
             'testclass="LoopController" testname="Loop Controller">')
    x_str(x, 5, 'LoopController.loops', '${LOOPS}')
    x_bool(x, 5, 'LoopController.continue_forever', False)
    x.add(4, '</elementProp>')
    x_str(x, 4, 'ThreadGroup.num_threads', '${THREADS}')
    x_str(x, 4, 'ThreadGroup.ramp_time', '${RAMP_UP}')
    x_bool(x, 4, 'ThreadGroup.scheduler', False)
    x_str(x, 4, 'ThreadGroup.duration', '')
    x_str(x, 4, 'ThreadGroup.delay', '')
    x_bool(x, 4, 'ThreadGroup.same_user_on_next_iteration', True)
    x_bool(x, 4, 'ThreadGroup.delayedStart', False)
    x.add(3, '</ThreadGroup>')
    x.add(3, '<hashTree>')

    for r in requests:
        x_open(x, 4, 'HTTPSamplerProxy', 'HttpTestSampleGui', 'HTTPSamplerProxy', r['label'])
        x_str(x, 5, 'TestPlan.comments', r['comment'])
        if r['raw_body'] is not None:
            x_bool(x, 5, 'HTTPSampler.postBodyRaw', True)
            x.add(5, '<elementProp name="HTTPsampler.Arguments" elementType="Arguments">')
            x.add(6, '<collectionProp name="Arguments.arguments">')
            x.add(7, '<elementProp name="" elementType="HTTPArgument">')
            x_bool(x, 8, 'HTTPArgument.always_encode', False)
            x_str(x, 8, 'Argument.value', r['raw_body'])
            x_str(x, 8, 'Argument.metadata', '=')
            x.add(7, '</elementProp>')
            x.add(6, '</collectionProp>')
            x.add(5, '</elementProp>')
        else:
            x.add(5, '<elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" '
                     'testclass="Arguments" testname="User Defined Variables">')
            if r['args']:
                x.add(6, '<collectionProp name="Arguments.arguments">')
                for an, av in r['args']:
                    x_http_arg(x, 7, an, av)
                x.add(6, '</collectionProp>')
            else:
                x.add(6, '<collectionProp name="Arguments.arguments"/>')
            x.add(5, '</elementProp>')
        x_str(x, 5, 'HTTPSampler.domain', '')
        x_str(x, 5, 'HTTPSampler.port', '')
        x_str(x, 5, 'HTTPSampler.protocol', '')
        x_str(x, 5, 'HTTPSampler.contentEncoding', '')
        x_str(x, 5, 'HTTPSampler.path', r['path'])
        x_str(x, 5, 'HTTPSampler.method', r['method'])
        x_bool(x, 5, 'HTTPSampler.follow_redirects', True)
        x_bool(x, 5, 'HTTPSampler.auto_redirects', False)
        x_bool(x, 5, 'HTTPSampler.use_keepalive', True)
        x_bool(x, 5, 'HTTPSampler.DO_MULTIPART_POST', r['multipart'])
        if r['raw_body'] is None:
            x_bool(x, 5, 'HTTPSampler.postBodyRaw', False)
        x_str(x, 5, 'HTTPSampler.embedded_url_re', '')
        x_str(x, 5, 'HTTPSampler.connect_timeout', '')
        x_str(x, 5, 'HTTPSampler.response_timeout', '')
        x.add(4, '</HTTPSamplerProxy>')
        children = bool(r['headers']) or bool(r['codes']) or r['has_range']
        if not children:
            x.add(4, '<hashTree/>')
            continue
        x.add(4, '<hashTree>')
        if r['headers']:
            x_headers(x, 5, 'HTTPヘッダマネージャ（この API 用）', r['headers'],
                      'この API 固有のヘッダ（Content-Type / Accept / OpenAPI のヘッダ・クッキーパラメータ）です。')
        if r['codes'] or r['has_range']:
            if r['codes']:
                patterns = r['codes']
                test_type = 8 if len(patterns) == 1 else 40
                expect = ' / '.join(patterns)
            else:
                patterns = ['2[0-9][0-9]']
                test_type = 1
                expect = '2XX'
            x_open(x, 5, 'ResponseAssertion', 'AssertionGui', 'ResponseAssertion', 'ステータスコード検証（' + expect + '）')
            x_str(x, 6, 'TestPlan.comments', 'OpenAPI 定義の成功レスポンス（' + expect + '）と応答コードが一致するかを検証します。')
            x.add(6, '<collectionProp name="Asserion.test_strings">')
            for pt in patterns:
                x_str(x, 7, str(java_hash(pt)), pt)
            x.add(6, '</collectionProp>')
            x_str(x, 6, 'Assertion.custom_message', '応答コードが OpenAPI 定義の成功コード（' + expect + '）と一致しません')
            x_str(x, 6, 'Assertion.test_field', 'Assertion.response_code')
            x_bool(x, 6, 'Assertion.assume_success', False)
            x_int(x, 6, 'Assertion.test_type', test_type)
            x.add(5, '</ResponseAssertion>')
            x.add(5, '<hashTree/>')
        x.add(4, '</hashTree>')

    x_open(x, 4, 'JSR223Listener', 'TestBeanGUI', 'JSR223Listener', '結果ログ出力（1 リクエスト 1 行）')
    x_str(x, 5, 'TestPlan.comments', '各 API の結果（OK/NG・応答コード・応答時間）をログファイルへ 1 行ずつ出力します。')
    x_str(x, 5, 'scriptLanguage', 'groovy')
    x_str(x, 5, 'parameters', '')
    x_str(x, 5, 'filename', '')
    x_str(x, 5, 'cacheKey', 'true')
    x_str(x, 5, 'script', RESULT_LOG_SCRIPT)
    x.add(4, '</JSR223Listener>')
    x.add(4, '<hashTree/>')
    x.add(3, '</hashTree>')

    # --- リスナー
    x_collector(x, 3, 'ViewResultsFullVisualizer', '結果をツリーで表示（GUI 確認用）',
                'GUI 実行時にリクエスト/レスポンスの中身を確認できます。保存済みの JTL を見る場合は'
                '「ファイル名」欄の［参照］から JTL ファイルを選択してください。', '')
    x_collector(x, 3, 'SummaryReport', '統計レポート（GUI 確認用）',
                'GUI 実行時に件数・応答時間・エラー率を集計表示します。保存済みの JTL も［参照］から読み込めます。', '')
    x_collector(x, 3, 'SimpleDataWriter', 'JTL出力（XML・詳細付き）',
                '結果を JTL ファイルへ XML 形式（リクエスト/レスポンスのヘッダ・本文付き）で保存します。'
                'JMeter GUI の「結果をツリーで表示」「統計レポート」等の［参照］から開いて確認できます。'
                'CLI 実行時は -JjtlFile=出力先 で保存場所を指定できます。',
                '${__P(jtlFile,${RESULT_DIR}/' + name + '_${RUN_ID}.jtl)}')
    x.add(2, '</hashTree>')
    x.add(1, '</hashTree>')
    x.add(0, '</jmeterTestPlan>')
    return x.text()


# ----------------------------------------------------------------- 入出力
def setup_stdio():
    for stream_name in ('stdout', 'stderr'):
        stream = getattr(sys, stream_name)
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except AttributeError:
            try:
                setattr(sys, stream_name, io.TextIOWrapper(stream.buffer, encoding='utf-8', errors='replace',
                                                           line_buffering=True))
            except Exception:
                pass
        except Exception:
            pass


# JSON 文字列（エスケープ込み）と ${...} を先頭から順に拾う。文字列は読み飛ばし、${...} だけを置き換える。
# 直後が : の ${...} はキーの位置なので置き換えない（PowerShell 5.1 の JSON 解析は引用符なしのキーを
# 受け付けてしまい、実装間で結果が変わるため。置き換えなければどの実装でも構文エラーになる）
PLACEHOLDER_SCAN = re.compile(r'"[^"\\]*(?:\\.[^"\\]*)*"|\$\{[^{}"\r\n]+\}(?![ \t\r\n]*:)', re.S)
PLACEHOLDER_LINES_SHOWN = 10


def fill_placeholders(text, value):
    """JSON 文字列の外に引用符なしで書かれた ${...}（後で置換するプレースホルダ）を数値 value に置き換える。
    文字列の中の ${...}（"${stageVariables.x}" など）は正しい JSON なので変更しない。
    戻り値: (置換後の文字列, [(プレースホルダ, [行番号, ...]), ...]（初出順）)"""
    if '${' not in text:
        return text, []
    found = OrderedDict()
    out = []
    pos = 0
    line = 1
    for m in PLACEHOLDER_SCAN.finditer(text):
        s = m.start()
        if text[s] != '$':
            continue    # 文字列（読み飛ばすだけ）
        line += text.count('\n', pos, s)
        out.append(text[pos:s])
        out.append(value)
        found.setdefault(m.group(0), []).append(line)
        pos = m.end()
    out.append(text[pos:])
    return ''.join(out), list(found.items())


def placeholder_warning(name, lines, value):
    shown = ', '.join(str(n) for n in lines[:PLACEHOLDER_LINES_SHOWN])
    more = ' ほか' if len(lines) > PLACEHOLDER_LINES_SHOWN else ''
    return ('引用符なしのプレースホルダ %s は JSON として読めないため、数値 %s に置き換えて読み込みました（%d 箇所・行 %s%s）'
            % (name, value, len(lines), shown, more))


def load_json(path, placeholder_value):
    with open(path, 'rb') as f:
        raw = f.read()
    try:
        if raw[:3] == b'\xef\xbb\xbf':
            text = raw[3:].decode('utf-8')
        elif raw[:2] == b'\xff\xfe':
            text = raw[2:].decode('utf-16-le')
        elif raw[:2] == b'\xfe\xff':
            text = raw[2:].decode('utf-16-be')
        else:
            text = raw.decode('utf-8')
    except UnicodeDecodeError:
        raise GenError('入力ファイルの文字コードを UTF-8 として読めません: ' + path)

    def bad_constant(name):
        raise ValueError('JSON では使えない値です: ' + name)

    text, placeholders = fill_placeholders(text, placeholder_value)
    try:
        doc = json.loads(text, object_pairs_hook=OrderedDict, parse_float=Decimal, parse_constant=bad_constant)
    except ValueError as e:
        raise GenError('JSON の構文エラーです（YAML 形式は未対応です）: ' + str(e))
    return doc, placeholders


def parse_kv(argv):
    opts = {}
    for a in argv:
        if '=' in a:
            k, v = a.split('=', 1)
            opts[k] = v
    return opts


def main():
    setup_stdio()
    o = parse_kv(sys.argv[1:])
    input_path = o.get('input', '')
    output_path = o.get('output', '')
    force = o.get('force') == '1'
    seed_text = o.get('seed', '')
    if seed_text:
        seed = int(seed_text)
    else:
        seed = int.from_bytes(os.urandom(4), 'big') % 1000000000
    opts = {
        'required_only': o.get('required_only') == '1',
        'use_examples': o.get('use_examples') == '1',
        'any_method': o.get('any_method', 'GET'),
    }

    placeholder_value = o.get('placeholder_value', '3000')
    doc, placeholders = load_json(input_path, placeholder_value)
    if not is_obj(doc):
        raise GenError('OpenAPI 定義のルートが JSON オブジェクトではありません')
    if has(doc, 'swagger'):
        raise GenError('Swagger 2.0 形式には対応していません。OpenAPI 3.0.x 形式（"openapi": "3.0.3" など）に変換してください')
    ver = get(doc, 'openapi')
    if not is_str(ver) or not re.match(r'^3\.[0-9]+(\.[0-9]+)?', ver):
        raise GenError('"openapi" フィールドが 3.x ではありません（OpenAPI 3.0.x の JSON を指定してください）')
    if not ver.startswith('3.0'):
        print('[WARN] OpenAPI %s は 3.0.x 以外です。3.0.x と共通の項目のみを解釈します。' % ver)
    if not is_obj(get(doc, 'paths')):
        raise GenError('"paths" が定義されていません')

    info = get(doc, 'info')
    title = get(info, 'title')
    title = title.strip() if is_str(title) and title.strip() else 'OpenAPI'
    api_version = get(info, 'version')
    api_version = api_version.strip() if is_str(api_version) and api_version.strip() else '-'
    name = safe_name(title)

    ctx = Ctx(doc, seed, opts)
    for ph_name, ph_lines in placeholders:
        ctx.warn(placeholder_warning(ph_name, ph_lines, placeholder_value))
    ops = collect_operations(ctx)
    if not ops:
        raise GenError('"paths" に呼び出し可能な操作（get/post/put/delete など）が 1 件もありません')

    width = max(2, len(str(len(ops))))
    requests = []
    for idx, info_op in enumerate(ops):
        num = str(idx + 1).rjust(width, '0')
        mdisp = ('ANY(' + info_op['method'] + ')') if info_op['is_any'] else info_op['method']
        label = num + ' ' + mdisp + ' ' + info_op['path']
        op_id = get(info_op['op'], 'operationId')
        if is_str(op_id) and op_id:
            label += ' [' + op_id + ']'
        requests.append(build_operation(ctx, info_op, label))

    use_auth = needs_auth_header(ctx, ops)
    meta = {
        'name': name, 'title': title, 'api_version': api_version, 'openapi': ver,
        'input_name': os.path.basename(input_path), 'tool_version': o.get('tool_version', '0'),
        'host': o.get('host', 'localhost'), 'port': o.get('port', '8080'), 'protocol': o.get('protocol', 'http'),
        'base_path': o.get('base_path', ''), 'api_key': o.get('api_key', 'XXXXXXXXXXXX'),
    }
    text = build_jmx(ctx, meta, requests, use_auth)

    if not output_path:
        output_path = os.path.join(os.getcwd(), name + '.jmx')
    output_path = os.path.abspath(output_path)
    out_dir = os.path.dirname(output_path)
    if not os.path.isdir(out_dir):
        raise GenError('出力先フォルダが存在しません: ' + out_dir)
    if os.path.isdir(output_path):
        raise GenError('出力先がフォルダです。ファイル名まで指定してください: ' + output_path)
    if os.path.exists(output_path) and not force:
        raise GenError('出力先に同名ファイルがあります（上書きする場合は --force を指定）: ' + output_path)
    tmp = output_path + '.tmp.' + str(os.getpid())
    try:
        with io.open(tmp, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        os.replace(tmp, output_path)
    except OSError as e:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass
        raise GenError('JMX を書き込めません: ' + output_path + ' (' + str(e) + ')')

    print('[INFO] 入力       : %s（OpenAPI %s / %s %s）' % (input_path, ver, title, api_version))
    print('[INFO] 乱数シード : %d（--seed %d を指定すると同じテストデータを再生成できます）' % (seed, seed))
    print('[INFO] 生成した API リクエスト: %d 件' % len(requests))
    for r in requests:
        extra = []
        if r['args']:
            extra.append('パラメータ %d 件' % len(r['args']))
        if r['body_kind']:
            extra.append('ボディ ' + r['body_kind'])
        if r['codes']:
            extra.append('期待 ' + '/'.join(r['codes']))
        print('         %s%s' % (r['label'], ('  (' + ', '.join(extra) + ')') if extra else ''))
    for w in ctx.warnings:
        print('[WARN] ' + w)
    if placeholders:
        print('[INFO] 引用符なしの ${...} に入れる数値は --placeholder-value で変更できます')
    print('[INFO] 出力       : ' + output_path)
    print('[INFO] 既定の接続先: %s://%s:%s%s / X-API-KEY は -JapiKey= で上書き可' % (
        meta['protocol'], meta['host'], meta['port'], meta['base_path']))
    print('[INFO] 実行例     : jmeter -n -t "%s" -j "results/%s.log"' % (output_path, name))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except GenError as e:
        sys.stderr.write('[ERROR] ' + str(e) + '\n')
        sys.exit(1)
    except KeyboardInterrupt:
        sys.stderr.write('[ERROR] 中断されました\n')
        sys.exit(130)
PYEOF
