#!/usr/bin/env bash
# =============================================================================
#  run_jmx.sh
#    openapi2jmx.sh で生成した JMX を Apache JMeter 5.6.3 の CLI（非 GUI）モードで実行し、
#    結果を JTL（XML・詳細付き。JMeter GUI で閲覧可）とログファイルに出力します。
#
#  対象 OS : RHEL 9.8 ほか Linux 全般（bash 4 以上）
#  前提    : Java 8 以上（17 以上推奨）と Apache JMeter 5.6.3
#
#  出力（既定: JMX と同じフォルダの results/）
#    <JMX名>_<実行ID>.jtl  … テスト結果（XML）。GUI の「結果をツリーで表示」等の［参照］で開けます
#    <JMX名>_<実行ID>.log  … JMeter のログ。1 リクエスト 1 行の [API-RESULT] 行を含みます
#
#  終了コード: 0=全リクエスト成功 / 1=失敗したリクエストあり / 2=JMeter の実行エラー / 3=前提条件エラー
# =============================================================================
set -Eeuo pipefail

readonly TOOL_VERSION="1.0.0"
SCRIPT_NAME="$(basename -- "$0")"
readonly SCRIPT_NAME

usage() {
  cat <<EOF
使い方:
  ${SCRIPT_NAME} -t <シナリオ.jmx> [オプション] [-- JMeter へそのまま渡す引数...]

必須:
  -t, --jmx FILE            実行する JMX ファイル

任意:
  -r, --result-dir DIR      JTL とログの出力先（既定: JMX と同じフォルダの results/）
  -H, --jmeter-home DIR     JMeter のインストール先
                            （既定: \$JMETER_HOME → PATH 上の jmeter → /opt/apache-jmeter-5.6.3 → /opt/jmeter）
      --host HOST           接続先ホスト           （-Jhost=）
      --port PORT           接続先ポート           （-Jport=）
      --protocol PROTO      http / https           （-Jprotocol=）
      --base-path PATH      パスの先頭に付ける値   （-JbasePath=）
      --api-key KEY         X-API-KEY ヘッダの値   （-JapiKey=）
      --auth-token TOKEN    Authorization ヘッダの値（-JauthToken=。JMX 側で要素を有効化した場合のみ使用）
      --threads N           スレッド数             （-Jthreads=）
      --ramp-up SEC         ランプアップ秒         （-JrampUp=）
      --loops N             ループ回数             （-Jloops=）
  -h, --help                このヘルプを表示
  -V, --version             バージョンを表示

例:
  ${SCRIPT_NAME} -t ./OrdersApi.jmx
  ${SCRIPT_NAME} -t ./OrdersApi.jmx --host 10.0.0.10 --port 8080 --api-key MyKey
  ${SCRIPT_NAME} -t ./OrdersApi.jmx -- -JconnectTimeout=5000

終了コード: 0=全リクエスト成功 / 1=失敗あり / 2=JMeter 実行エラー / 3=前提条件エラー
EOF
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 3
}

need_value() {
  if [[ "$2" -lt 2 ]]; then
    die "オプション $1 には値が必要です（--help を参照）"
  fi
}

JMX=""
RESULT_DIR=""
JMETER_HOME_OPT=""
declare -a JPROPS=()
declare -a EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--jmx)          need_value "$1" "$#"; JMX="$2"; shift 2 ;;
    --jmx=*)           JMX="${1#*=}"; shift ;;
    -r|--result-dir)   need_value "$1" "$#"; RESULT_DIR="$2"; shift 2 ;;
    --result-dir=*)    RESULT_DIR="${1#*=}"; shift ;;
    -H|--jmeter-home)  need_value "$1" "$#"; JMETER_HOME_OPT="$2"; shift 2 ;;
    --jmeter-home=*)   JMETER_HOME_OPT="${1#*=}"; shift ;;
    --host)            need_value "$1" "$#"; JPROPS+=("-Jhost=$2"); shift 2 ;;
    --port)            need_value "$1" "$#"; JPROPS+=("-Jport=$2"); shift 2 ;;
    --protocol)        need_value "$1" "$#"; JPROPS+=("-Jprotocol=$2"); shift 2 ;;
    --base-path)       need_value "$1" "$#"; JPROPS+=("-JbasePath=$2"); shift 2 ;;
    --api-key)         need_value "$1" "$#"; JPROPS+=("-JapiKey=$2"); shift 2 ;;
    --auth-token)      need_value "$1" "$#"; JPROPS+=("-JauthToken=$2"); shift 2 ;;
    --threads)         need_value "$1" "$#"; JPROPS+=("-Jthreads=$2"); shift 2 ;;
    --ramp-up)         need_value "$1" "$#"; JPROPS+=("-JrampUp=$2"); shift 2 ;;
    --loops)           need_value "$1" "$#"; JPROPS+=("-Jloops=$2"); shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    -V|--version)      printf '%s %s (Apache JMeter 5.6.3 対応)\n' "${SCRIPT_NAME}" "${TOOL_VERSION}"; exit 0 ;;
    --)                shift; EXTRA=("$@"); break ;;
    -*)                die "不明なオプションです: $1（JMeter へ渡す引数は -- の後ろに書いてください）" ;;
    *)
      if [[ -z "${JMX}" ]]; then
        JMX="$1"; shift
      else
        die "余分な引数があります: $1（--help を参照）"
      fi
      ;;
  esac
done

# ---------------------------------------------------------------- 入力チェック
[[ -n "${JMX}" ]] || { usage >&2; die "実行する JMX を -t で指定してください"; }
[[ -f "${JMX}" ]] || die "JMX ファイルが見つかりません: ${JMX}"
[[ -r "${JMX}" ]] || die "JMX ファイルを読み取れません: ${JMX}"
JMX_DIR="$(cd -- "$(dirname -- "${JMX}")" && pwd -P)"
JMX_ABS="${JMX_DIR}/$(basename -- "${JMX}")"
JMX_NAME="$(basename -- "${JMX}")"
JMX_NAME="${JMX_NAME%.*}"

if [[ -z "${RESULT_DIR}" ]]; then
  RESULT_DIR="${JMX_DIR}/results"
fi
mkdir -p -- "${RESULT_DIR}" || die "結果フォルダを作成できません: ${RESULT_DIR}"
RESULT_DIR="$(cd -- "${RESULT_DIR}" && pwd -P)"
[[ -w "${RESULT_DIR}" ]] || die "結果フォルダに書き込めません: ${RESULT_DIR}"

# ---------------------------------------------------------------- JMeter の検出
find_jmeter() {
  local home cand
  local -a homes=()
  if [[ -n "${JMETER_HOME_OPT}" ]]; then
    homes+=("${JMETER_HOME_OPT}")
  else
    if [[ -n "${JMETER_HOME:-}" ]]; then
      homes+=("${JMETER_HOME}")
    fi
    if cand="$(command -v jmeter 2>/dev/null)"; then
      cand="$(readlink -f -- "${cand}" 2>/dev/null || printf '%s' "${cand}")"
      homes+=("$(dirname -- "$(dirname -- "${cand}")")")
    fi
    homes+=("/opt/apache-jmeter-5.6.3" "/opt/jmeter" "${HOME}/apache-jmeter-5.6.3")
  fi
  for home in "${homes[@]}"; do
    if [[ -x "${home}/bin/jmeter" && -f "${home}/bin/ApacheJMeter.jar" ]]; then
      printf '%s' "$(cd -- "${home}" && pwd -P)"
      return 0
    fi
  done
  return 1
}

JMETER_HOME_DIR="$(find_jmeter)" \
  || die "JMeter が見つかりません。-H で場所を指定するか、環境変数 JMETER_HOME を設定してください（JMeter 5.6.3 を想定）"
JMETER_BIN="${JMETER_HOME_DIR}/bin/jmeter"

# ---------------------------------------------------------------- Java の確認
if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
  JAVA_CMD="${JAVA_HOME}/bin/java"
elif JAVA_CMD="$(command -v java 2>/dev/null)"; then
  :
else
  die "Java が見つかりません。RHEL 9 では 'sudo dnf install -y java-17-openjdk-headless' で導入できます"
fi
JAVA_VER_LINE="$("${JAVA_CMD}" -version 2>&1 | head -n 1 || true)"
JAVA_MAJOR="$(printf '%s\n' "${JAVA_VER_LINE}" | awk -F'"' '/version/ {v=$2; sub(/^1\./, "", v); sub(/[^0-9].*$/, "", v); print v}')"
if [[ -z "${JAVA_MAJOR}" || ! "${JAVA_MAJOR}" =~ ^[0-9]+$ ]]; then
  die "Java のバージョンを判定できません: ${JAVA_VER_LINE}"
fi
if (( JAVA_MAJOR < 8 )); then
  die "JMeter 5.6.3 には Java 8 以上が必要です（検出: ${JAVA_VER_LINE}）"
fi
if (( JAVA_MAJOR < 17 )); then
  printf '[WARN] Java %s を検出しました。JMeter 5.6.3 では Java 17 以上を推奨します。\n' "${JAVA_MAJOR}"
fi

# ---------------------------------------------------------------- 実行
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
BASE="${RESULT_DIR}/${JMX_NAME}_${RUN_ID}"
n=1
while [[ -e "${BASE}.jtl" || -e "${BASE}.log" ]]; do
  n=$((n + 1))
  BASE="${RESULT_DIR}/${JMX_NAME}_${RUN_ID}-${n}"
done
JTL="${BASE}.jtl"
LOG="${BASE}.log"

# ログを UTF-8 で書かせる（ロケールが C でも日本語が化けないように）
export JVM_ARGS="${JVM_ARGS:-} -Dfile.encoding=UTF-8"

printf '[INFO] JMeter     : %s\n' "${JMETER_HOME_DIR}"
printf '[INFO] Java       : %s\n' "${JAVA_VER_LINE}"
printf '[INFO] シナリオ   : %s\n' "${JMX_ABS}"
printf '[INFO] 結果 JTL   : %s\n' "${JTL}"
printf '[INFO] ログ       : %s\n' "${LOG}"
printf '[INFO] 実行開始   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

set +e
"${JMETER_BIN}" -n -t "${JMX_ABS}" -j "${LOG}" \
  "-JjtlFile=${JTL}" "-JresultDir=${RESULT_DIR}" "-JrunId=${RUN_ID}" \
  ${JPROPS[@]+"${JPROPS[@]}"} ${EXTRA[@]+"${EXTRA[@]}"}
JM_RC=$?
set -e
printf '[INFO] 実行終了   : %s（JMeter 終了コード %d）\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${JM_RC}"

# ---------------------------------------------------------------- 結果の集計
if [[ ! -s "${JTL}" ]]; then
  printf '[ERROR] JTL が出力されていません。ログを確認してください: %s\n' "${LOG}" >&2
  if [[ -f "${LOG}" ]]; then
    grep -E ' (ERROR|FATAL) ' "${LOG}" | tail -n 20 >&2 || true
  fi
  exit 2
fi
TOTAL="$(grep -cE '^<(httpSample|sample) ' "${JTL}" || true)"
FAILED="$(grep -E '^<(httpSample|sample) ' "${JTL}" | grep -c ' s="false"' || true)"
TOTAL="${TOTAL:-0}"
FAILED="${FAILED:-0}"

echo '----------------------------------------------------------------------'
if [[ -f "${LOG}" ]]; then
  grep -F '[API-RESULT]' "${LOG}" | sed -e 's/^.*\[API-RESULT\]/[API-RESULT]/' || true
fi
echo '----------------------------------------------------------------------'
printf '[INFO] リクエスト %s 件 / 成功 %s 件 / 失敗 %s 件\n' "${TOTAL}" "$((TOTAL - FAILED))" "${FAILED}"
printf '[INFO] JTL を JMeter GUI で見る: GUI 起動 →「結果をツリーで表示」等のリスナーの［参照］で %s を選択\n' "${JTL}"

if (( JM_RC != 0 )); then
  exit 2
fi
if (( TOTAL == 0 )); then
  printf '[ERROR] リクエストが 1 件も実行されていません。ログを確認してください: %s\n' "${LOG}" >&2
  exit 2
fi
if (( FAILED > 0 )); then
  exit 1
fi
exit 0
