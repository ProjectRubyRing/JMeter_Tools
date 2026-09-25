# OpenAPI → JMeter 5.6.3 シナリオ自動生成ツール ＋ OpenAPI 定義 完全解説

Amazon API Gateway（REST API）用の **OpenAPI 3.0.3 定義ファイル（JSON）** を読み込み、

1. 定義に書かれている全設定を、動作原理・動作イメージ・歴史と背景まで含めて小学生にも分かるように解説した資料（**Excel／Markdown**）
2. 定義されている API を呼び出す **Apache JMeter 5.6.3 用のテストシナリオ（.jmx）を自動生成するツール**（**RHEL 9.8 用シェルスクリプト**／**Windows 11 用 PowerShell スクリプト**）

をまとめたものです。

---

## ファイル構成

```
JMeter_Tools/
├── README.md                              このファイル
├── openapi/
│   └── orders-api.openapi.json            対象の OpenAPI 3.0.3 定義（APIGateway_OpenAPI_List の 03_sample と同一内容）
├── docs/
│   ├── OrdersApi_OpenAPI定義_完全解説.xlsx  解説資料（Excel：Meiryo UI・モノトーン）
│   ├── OrdersApi_OpenAPI定義_完全解説.md    解説資料（Markdown）
│   └── _build/                            解説資料の生成プログラム（python docs/_build/build_docs.py）
├── linux/                                 RHEL 9.8 用
│   ├── openapi2jmx.sh                     OpenAPI → JMX 生成
│   └── run_jmx.sh                         JMX 実行（JTL・ログ出力、成否の集計）
├── windows/                               Windows 11 用
│   ├── OpenApi2Jmx.ps1                    OpenAPI → JMX 生成
│   ├── Invoke-JmxScenario.ps1             JMX 実行（JTL・ログ出力、成否の集計）
│   ├── openapi2jmx.bat                    コマンドプロンプト用ラッパー（実行ポリシーの影響なし）
│   └── run_jmx.bat                        同上
├── samples/
│   └── OrdersApi.jmx                      生成例（--seed 20260926）
└── tests/
    ├── mock_api_server.py                 検証用の模擬 API サーバー（受信内容を記録）
    ├── verify_requests.py                 送信内容を OpenAPI 定義と突き合わせて検証
    ├── Compare-Generators.ps1             RHEL 版と Windows 版の出力一致テスト
    └── fixtures/feature-coverage.openapi.json  網羅テスト用の定義（allOf／oneOf／各 style／フォーム等）
```

---

## 1. 解説資料（Excel／Markdown）

`docs/OrdersApi_OpenAPI定義_完全解説.xlsx`（と同じ内容の `.md`）は次のシートで構成されています。

| シート | 内容 |
| --- | --- |
| 00_目次 | 各シートへのリンク |
| 01_はじめに | 対象ファイル（SHA-256 付き）、読み方、3つのキーワード、区分の凡例 |
| 02_全体像 | ひとことで、たとえ話（社員専用レストラン）、ファイルの地図、構成図、API 一覧 |
| 03_歴史と背景 | Swagger 誕生（2010年）〜 OpenAPI 3.2.1（2026年9月）、API Gateway の機能追加の年表 |
| 04_項目別詳細解説 | **定義内のすべての設定（末端 180 個）を 87 項目で解説**：ひとことで／詳しい意味／動作原理／動作イメージ／歴史・経緯／注意点・最新情報／JMeter での扱い |
| 05_リクエストの流れ | リクエストが処理される順番、CORS の流れ、ステータスコードの見分け方 |
| 06_レビュー所見 | 公式ドキュメントと照合した注意点（例：DEFAULT_5XX の 500 指定で 504 も 500 になる 等） |
| 07_JMeterシナリオ | OpenAPI → JMX の対応、初期設定の推奨値と理由、テストデータ生成ルール、検証結果 |
| 08_用語集 / 09_参考資料 | 用語の説明、確認した公式情報の URL |

- フォントはすべて **Meiryo UI**、配色は黒〜グレー〜白の**モノトーン**です。見出し行の固定、オートフィルタ、折り返し、行の高さの自動算出（Excel の自動調整で全 2,189 セルが収まることを検証済み）、A3 横・幅に合わせた印刷設定をしています。
- 設定値の列は定義ファイルから自動で読み取っており、定義の全設定が解説されているかを生成時に検査します。
- 再生成: `python docs/_build/build_docs.py`（Python 3.8 以降と openpyxl が必要）

---

## 2. JMeter シナリオ自動生成（RHEL 9.8）

### 前提

| 項目 | 内容 |
| --- | --- |
| OS | RHEL 9.8（ほかの Linux でも可） |
| 生成 | bash 4 以上、python3 3.6 以上（**RHEL 9 は標準で bash 5.1・python3 3.9**。追加インストール不要） |
| 実行 | Java 8 以上（17 以上推奨。`sudo dnf install -y java-17-openjdk-headless`）、Apache JMeter 5.6.3 |

Windows からコピーした場合は実行権限を付けてください（改行コードは LF のまま転送してください）。

```bash
chmod +x linux/*.sh
# もし CRLF に変換されてしまった場合: sed -i 's/\r$//' linux/*.sh
```

### 生成

```bash
./linux/openapi2jmx.sh -i openapi/orders-api.openapi.json -o ./OrdersApi.jmx
```

### 実行（JTL とログを出力）

```bash
./linux/run_jmx.sh -t ./OrdersApi.jmx                          # 既定: http://localhost:8080
./linux/run_jmx.sh -t ./OrdersApi.jmx --host 10.0.0.10 --api-key MyKey
./linux/run_jmx.sh -t ./OrdersApi.jmx -H /opt/apache-jmeter-5.6.3 -- -JconnectTimeout=5000
```

## 3. JMeter シナリオ自動生成（Windows 11）

### 前提

Windows PowerShell 5.1（Windows 11 標準）または PowerShell 7、Java 8 以上（17 以上推奨）、Apache JMeter 5.6.3。

実行ポリシーでスクリプトが止められる場合は、`.bat` ラッパーを使うか、`powershell -ExecutionPolicy Bypass -File ...` で起動してください。インターネットから取得したファイルは `Unblock-File` が必要な場合があります。

### 生成

```powershell
.\windows\OpenApi2Jmx.ps1 -InputFile .\openapi\orders-api.openapi.json -OutputFile .\OrdersApi.jmx
```

```bat
windows\openapi2jmx.bat -InputFile openapi\orders-api.openapi.json -OutputFile OrdersApi.jmx
```

### 実行（JTL とログを出力）

```powershell
.\windows\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx
.\windows\Invoke-JmxScenario.ps1 -JmxFile .\OrdersApi.jmx -TargetHost 10.0.0.10 -ApiKey MyKey -JMeterHome C:\Tools\apache-jmeter-5.6.3
```

> `jmeter.bat` は異常終了時に `pause` で入力待ちになり自動実行が止まるため、`Invoke-JmxScenario.ps1` は
> `jmeter.bat` と同じ JVM オプション（HEAP・GC_ALGO・JVM_ARGS・JMETER_LANGUAGE の環境変数も反映）で `java.exe` を直接起動します。

---

## 4. 生成オプション（RHEL 版／Windows 版は同じ機能）

| RHEL（openapi2jmx.sh） | Windows（OpenApi2Jmx.ps1） | 既定値 | 説明 |
| --- | --- | --- | --- |
| `-i, --input` | `-InputFile` | （必須） | OpenAPI 3.0.x 定義ファイル（JSON） |
| `-o, --output` | `-OutputFile` | `<APIタイトル>.jmx` | 出力する JMX |
| `-f, --force` | `-Force` | 上書きしない | 同名ファイルを上書き |
| `--host` | `-TargetHost` | `localhost` | 接続先ホストの既定値 |
| `--port` | `-Port` | `8080` | 接続先ポートの既定値 |
| `--protocol` | `-Protocol` | `http` | http／https |
| `--base-path` | `-BasePath` | 空 | 全パスの先頭に付けるパス（例: `/prod`） |
| `--api-key` | `-ApiKey` | `XXXXXXXXXXXX` | X-API-KEY ヘッダの既定値 |
| `--seed` | `-Seed` | 毎回ランダム | テストデータの乱数シード。**同じシードなら RHEL 版と Windows 版で 1 バイトも違わない JMX を生成** |
| `--any-method` | `-AnyMethod` | `GET` | x-amazon-apigateway-any-method（ANY）で送るメソッド |
| `--required-only` | `-RequiredOnly` | オフ | 必須のパラメータ・プロパティだけ生成 |
| `--use-examples` | `-UseExamples` | オフ | example／default があれば優先 |
| `-h, --help` / `-V, --version` | `-Help` / `-Version` | | |

生成時の終了コード: 0=成功 / 1=入力エラー（ファイルなし・JSON 不正・Swagger 2.0・上書き防止など） / 2=予期しないエラー

---

## 5. 生成されるテスト計画（初期設定はすべて推奨値）

```
テスト計画（ユーザー定義変数に接続先・API キー・スレッド数などを集約）
├── HTTP リクエスト初期値設定     ${PROTOCOL}://${HOST}:${PORT}、UTF-8、HttpClient4、接続 10 秒／応答 60 秒
├── HTTP ヘッダマネージャ         X-API-KEY: ${API_KEY}（全リクエストに固定で付与）
├── HTTP ヘッダマネージャ（無効）  Authorization: ${AUTH_TOKEN}（OpenAPI に security がある場合のみ。API Gateway 経由時に有効化）
├── スレッドグループ              1 スレッド・ランプアップ 1 秒・ループ 1 回（各 API を 1 回ずつ）、エラー時は続行
│   ├── HTTP リクエスト × API 数  パス・クエリ・ヘッダ・ボディにデータ型に合ったランダム値
│   │   ├── HTTP ヘッダマネージャ Content-Type／Accept／ヘッダ・クッキーパラメータ
│   │   └── 応答アサーション      OpenAPI の 2xx と応答コードが一致するか
│   └── JSR223 リスナー（Groovy）  [API-RESULT] 行をログへ（失敗時は理由と応答本文も）
├── 結果をツリーで表示／統計レポート（GUI 確認用）
└── シンプルデータライタ           JTL（XML・リクエスト／レスポンスのヘッダと本文付き）
```

### 実行時に変更できる値（`-J` オプション／実行スクリプトの引数）

| プロパティ | 既定値 | 意味 |
| --- | --- | --- |
| `protocol` `host` `port` `basePath` | http / localhost / 8080 / 空 | 接続先 |
| `apiKey` | XXXXXXXXXXXX | X-API-KEY の値 |
| `authToken` | 空 | Authorization の値（無効化中の要素を有効にしたとき） |
| `threads` `rampUp` `loops` | 1 / 1 / 1 | 負荷条件 |
| `connectTimeout` `responseTimeout` | 10000 / 60000 | タイムアウト（ミリ秒） |
| `jtlFile` / `resultDir` / `runId` | ~/results/<名前>_<開始時刻>.jtl | JTL の出力先（~/ は JMX のあるフォルダ） |

### 結果ファイル

実行スクリプトは `results/`（既定: JMX と同じフォルダ）に次の 2 つを出力します。

- `<JMX名>_<実行ID>.jtl` … 結果（XML）。JMeter GUI で開けます。
- `<JMX名>_<実行ID>.log` … JMeter のログ。1 リクエスト 1 行の `[API-RESULT] OK|NG | ラベル | メソッド URL | code=… | …ms | …bytes` を含みます。

**JTL を JMeter GUI で見る手順**：JMeter を起動 →「ファイル」→「開く」で JMX を開く → ツリーの「結果をツリーで表示（GUI 確認用）」（または「統計レポート」）を選択 → 画面上部の「ファイル名」欄の［参照］で JTL を選ぶ → 各リクエストの「サンプラー結果」「リクエスト（ヘッダ・本文）」「レスポンスデータ」が表示されます（どのテスト計画に追加したリスナーからでも開けます）。

実行スクリプトの終了コード: 0=全リクエスト成功 / 1=失敗したリクエストあり / 2=JMeter の実行エラー / 3=前提条件エラー（JMX・JMeter・Java が見つからない等）

---

## 6. テストデータの生成ルール（要約）

データ型（type／format／pattern／enum／minimum／maximum／multipleOf／minLength／maxLength／minItems／maxItems／uniqueItems／required／readOnly／additionalProperties）から、定義を満たすランダム値を作ります。
pattern は正規表現を解析して一致する文字列を作り、正規表現エンジンで一致を確認します。数値は 10 進数で正確に計算するため、`multipleOf: 0.01` なども誤差なく満たします。
詳しくは解説資料の「07_JMeterシナリオ」を参照してください。

## 7. 制限事項

- 入力は **OpenAPI 3.0.x の JSON** です（YAML と Swagger 2.0 は対象外。3.1 以降は 3.0 と共通の項目だけを解釈）。
- 外部ファイルへの `$ref` は解決しません（警告を出し、プレースホルダ値を入れます）。
- ANY メソッドは代表 1 メソッド（既定 GET）で送ります。
- multipart のファイル項目はテキスト値として送ります（実ファイルは JMeter の「ファイルアップロード」タブで設定）。
- ランダム値は「定義上正しい値」であり、実在する ID ではありません。実データでの確認時は値を書き換えてください（`--required-only` で任意項目を省くこともできます）。

---

## 8. 検証結果（2026年9月26日）

| 検証 | 結果 |
| --- | --- |
| JMeter 5.6.3 での JMX 読み込み（SaveService・GUI） | 合格：全要素を読み込み、GUI クラスがすべて存在。JMeter の再保存との差はプロパティの並び順だけ |
| CLI 実行と JTL／ログ出力 | 合格（Windows 11・Java 17／RHEL 9.8 相当の UBI 9.8・OpenJDK 17） |
| JTL の GUI 読み込み（［参照］と同じ処理） | 合格：リクエストヘッダ・送信データ・応答本文を確認 |
| 送信データの定義への適合（模擬サーバーで受信して検証） | 合格：OrdersApi 5 件、網羅用定義 12 件で不合格 0 件 |
| RHEL 9.8（UBI 9.8：bash 5.1.8・Python 3.9.25） | 合格：生成・実行・検証、既定の localhost:8080 で 5/5 成功 |
| RHEL 版と Windows 版（PowerShell 5.1／7.6）の出力一致 | 合格：4 定義 × 4 オプション × 3 シード＝48 通りでバイト一致 |
| 失敗時の動作 | 合格：応答コード不一致→1、接続拒否→1、JMX／JMeter なし→3、入力エラー→1 |

自分の環境で検証する場合（例）:

```bash
python3 tests/mock_api_server.py --port 8080 --log /tmp/requests.jsonl &
./linux/run_jmx.sh -t samples/OrdersApi.jmx
python3 tests/verify_requests.py --spec openapi/orders-api.openapi.json --requests /tmp/requests.jsonl
```

---

## 9. 実装上の注意点（実測して対処したもの）

- **JMeter の結果ファイルの相対パスは「JMX の場所」ではなく「カレントディレクトリ」基準**です。JMX 基準にするには JMeter 独自の `~/` 接頭辞が必要なため、既定を `~/results` にしています。
- **テスト計画のユーザー定義変数は、同じ表の中の別の変数を参照できません**（未解決のまま残る）。JTL のファイル名はリスナー側で組み立てています。
- **JMeter 5.6.3 の HTTP リクエストの「パラメータ」表は、DELETE ではボディにも送られ、HEAD では捨てられます**。そのため GET 以外はクエリをパスに直接埋め込んでいます。
- **`jmeter.bat` は異常終了時に `pause` する**ため、Windows の実行スクリプトは java.exe を直接起動します。
- **Windows PowerShell 5.1 は BOM の無い .ps1 を ANSI（cp932）として読む**ため、.ps1 はすべて BOM 付き UTF-8 です（.sh は BOM なし・LF、.bat は ASCII・CRLF）。
- **`#Requires` をコメントベースのヘルプより前に書くと `Get-Help` がヘルプを認識しない**ため、ヘルプの後ろに置いています。
- PowerShell 5.1 の `ConvertFrom-Json` は大文字小文字だけが違うキーを扱えないため、JSON は大文字小文字を区別する方法（5.1: JavaScriptSerializer、7: System.Text.Json）で読み込んでいます。
