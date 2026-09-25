# -*- coding: utf-8 -*-
"""04 以外のシート（はじめに／全体像／歴史／流れ／レビュー所見／JMeter／用語集／参考資料）"""

ART_TREE = r"""
orders-api.openapi.json
+-- openapi ............................................ A-1  "3.0.3"
+-- info (title / description / version / contact) ..... A-2 - A-5
+-- servers[0] (url / description) ..................... A-6 - A-7
+-- x-amazon-apigateway-endpoint-configuration ......... B-1 - B-2
+-- x-amazon-apigateway-binary-media-types ............. B-3
+-- x-amazon-apigateway-minimum-compression-size ....... B-4
+-- x-amazon-apigateway-api-key-source ................. B-5
+-- x-amazon-apigateway-request-validators / -validator  B-6 - B-8
+-- x-amazon-apigateway-policy ......................... B-9 - B-14
+-- x-amazon-apigateway-gateway-responses .............. B-15 - B-21
+-- tags ............................................... A-8
+-- paths
|   +-- /orders ........................................ C-1
|   |   +-- get      listOrders ........................ C-2 - C-19
|   |   +-- post     createOrder ....................... D-1 - D-5
|   |   +-- options  (CORS / mock) ..................... E-1 - E-6
|   +-- /orders/{orderId}
|   |   +-- parameters (orderId) ....................... F-1
|   |   +-- get      getOrder .......................... F-2 - F-3
|   +-- /{proxy+}
|       +-- x-amazon-apigateway-any-method  proxyAll ... G-1 - G-6
+-- components
    +-- securitySchemes / CognitoM2M ................... H-1 - H-6
    +-- schemas / Order, OrderItem, OrderList, CreateOrderRequest ... I-1 - I-13
"""

ART_SYSTEM = r"""
 [VPC 内のクライアント]  (業務システム / JMeter)
      |   GET https://api.private.example.com/orders
      |   Authorization: <Cognito アクセストークン>   X-API-Key: <API キー>
      v
 [Route 53 プライベートホストゾーン] --名前解決--> [インターフェイス VPC エンドポイント vpce-0123456789abcdef0]
      |   AWS PrivateLink (インターネットを通らない / TLS 1.2)
      v
 +--------------------- Amazon API Gateway  REST API "OrdersApi"  (PRIVATE) ---------------------+
 |  (1) カスタムドメイン -> API マッピング -> リソースとメソッドの決定 (/orders + GET)            |
 |  (2) Cognito オーソライザー (CognitoM2M): トークン検証 + スコープ orders.read の確認         |
 |  (3) リソースポリシー: aws:SourceVpce = vpce-0123456789abcdef0 なら Allow                   |
 |  (4) リクエスト検証 (all): 必須パラメータ / ボディのスキーマ                                 |
 |  (5) 統合: http_proxy (GET/POST/ANY)   mock (OPTIONS は API Gateway がその場で応答)         |
 +-----------------------------------------------------------------------------------------------+
      |   VPC リンク V2  ( ${stageVariables.vpcLinkV2Id} )
      v
 [内部 ALB  internal-alb]  --HTTPS  Host: backend.internal.example.com:443-->  [受注バックエンド]
"""

ART_FLOW = r"""
 クライアント        API Gateway (PRIVATE)                                 ALB / バックエンド
     |  (1) DNS -> VPC エンドポイント -> TLS 1.2                                    |
     |------------------------------->|                                             |
     |                                | (2) パスとメソッドの決定 (/orders, GET)     |
     |                                | (3) Cognito: トークン検証 / スコープ確認   |
     |    401 UNAUTHORIZED <----------|     NG のとき                              |
     |                                | (4) リソースポリシー: SourceVpce 確認      |
     |    403 ACCESS_DENIED <---------|     NG のとき                              |
     |                                | (5) リクエスト検証 (all)                    |
     |    400 BAD_REQUEST_* <---------|     NG のとき                              |
     |                                | (6) http_proxy: X-Client-Id を追加          |
     |                                |---- VPC リンク V2 -> ALB (Host/TLS 確認) -->|
     |                                |                                             | (7) 業務処理
     |                                |<------------- 応答 (29 秒以内) -------------|
     |    500 (本来 504) <-------------|     29 秒を超えたとき (DEFAULT_5XX で 500)  |
     |<-------- 応答 (そのまま) --------| (8) 1024B 以上 + Accept-Encoding なら圧縮    |
"""


def sheet_intro(info):
    return {
        "name": "01_はじめに", "title": "このドキュメントについて（対象ファイル・読み方・3つのキーワード）",
        "widths": [20, 42, 80],
        "blocks": [
            ("h1", "このドキュメントの目的"),
            ("p", "このドキュメントは、Amazon API Gateway（REST API）で使うために用意された OpenAPI 3.0.3 形式の定義ファイル（JSON）を読み込み、"
                  "そこに書かれている設定を1つずつ、「何のための設定か」「中で何が起きるか（動作原理）」「たとえると何か（動作イメージ）」"
                  "「いつ・なぜ生まれたか（歴史と背景）」「気を付けること（最新情報）」の順で、小学生にも分かる言葉で説明したものです。"),
            ("p", "内容は 2026年9月26日時点の AWS 公式ドキュメントと OpenAPI 公式サイトで確認しています（09_参考資料）。"
                  "あわせて、この定義から JMeter 5.6.3 のテストシナリオ（JMX）を自動生成するツールとの対応も 07_JMeterシナリオ にまとめています。"),
            ("h1", "対象ファイル"),
            ("kv", [
                ["ファイル名", info["file_name"]],
                ["格納場所", info["file_path"]],
                ["元ファイル", info["source_path"]],
                ["SHA-256", info["sha256"]],
                ["サイズ", info["size"]],
                ["OpenAPI のバージョン", info["openapi"]],
                ["API の名前 / バージョン", info["title"] + " / " + info["version"]],
                ["定義されている API", info["op_summary"]],
                ["解説した設定項目", info["item_count"]],
                ["資料の作成日", "2026年9月26日"],
            ]),
            ("h1", "04_項目別詳細解説 の読み方（列の意味）"),
            ("table", ["列", "意味"], [
                ["No.", "項目番号。A=基本情報、B=API 全体の AWS 設定、C〜G=各 API、H=認可、I=データの形。"],
                ["区分", "OpenAPI の標準項目か、AWS 独自の拡張（x-amazon-apigateway-*）か、IAM ポリシーの書き方か、JSON Schema か。"],
                ["JSON パス", "ファイルの中の場所。「›」で階層を区切っています（例：paths › /orders › get）。"],
                ["設定値", "ファイルに実際に書かれている値（資料の作成時にファイルから自動で読み取っています）。"],
                ["ひとことで", "小学生向けの一文の説明。"],
                ["詳しい意味", "その設定が何を決めているのか。"],
                ["動作原理", "API Gateway やツールの中で、実際にどういう処理が行われるのか。"],
                ["動作イメージ", "身近なものにたとえた説明（レストランの受付・厨房・入館証など）。"],
                ["歴史・背景・経緯", "その仕組みがいつ・なぜ必要になって生まれたのか（日付は公式の改訂履歴などで確認）。"],
                ["注意点・最新情報", "間違えやすい点、2026年9月時点の最新情報、このファイルで気になる点。"],
                ["JMeter での扱い", "自動生成する JMeter シナリオで、その設定をどう使うか（使わないか）。"],
            ]),
            ("h1", "まず覚える 3つのキーワード"),
            ("table", ["言葉", "ひとことで", "たとえると"], [
                ["API", "プログラム同士が決まった形でお願いと返事をやりとりする「窓口」。",
                 "お店の注文窓口。決まった注文票で頼むと、決まった形で料理が出てくる。"],
                ["OpenAPI", "API の窓口の場所・頼み方・返事の形を、世界共通のルールで書いた「説明書（設計図）」。",
                 "メニュー表とお店のルールブック。これを見れば、どの窓口で何を頼めるか分かる。"],
                ["Amazon API Gateway", "API の入口を AWS が代わりに運営してくれるサービス。認証・検証・流量制限・転送をまとめて引き受ける。",
                 "お店の受付係。入館証を確かめ、注文票を確認し、厨房（バックエンド）に取り次ぎ、料理を渡す。"],
            ]),
            ("h1", "区分の凡例"),
            ("table", ["区分", "説明"], [
                ["OpenAPI標準", "OpenAPI Specification 3.0.3 で決められた項目。どのツールでも同じ意味で読める。"],
                ["AWS拡張（x-amazon-apigateway-*）", "API Gateway だけが読む独自の追加項目。OpenAPI は x- で始まる独自項目を自由に追加できる決まりになっている。"],
                ["AWS拡張（IAMポリシー構文）", "リソースポリシーの中身。AWS の権限の書き方（IAM ポリシー言語）で書く。"],
                ["OpenAPI標準（JSON Schema）", "データの形（型・必須項目・桁数など）を決める部分。JSON Schema を土台にした OpenAPI の書き方。"],
            ]),
        ],
    }


def sheet_overview(ops_rows):
    return {
        "name": "02_全体像", "title": "全体像（ひとことで・たとえ話・ファイルの地図・構成図・API 一覧）",
        "widths": [7, 18, 22, 18, 30, 26, 24, 16],
        "blocks": [
            ("h1", "ひとことで言うと"),
            ("p", "このファイルは、社内（VPC）からしか呼べない「受注API（OrdersApi）」を API Gateway に作らせるための設計図です。"
                  "Cognito の入館証（アクセストークン）とスコープで「読む人」「書く人」を分け、社内専用の入口（VPC エンドポイント）から来た"
                  "通信だけを通し、注文票の書き方をチェックしたうえで、専用通路（VPC リンク V2）の先にある内部 ALB 経由で受注バックエンドへ"
                  "取り次ぎます。"),
            ("h1", "たとえ話で見る全体像（社員専用レストラン）"),
            ("table", ["本物", "たとえ", "このファイルでの設定"], [
                ["OpenAPI 定義ファイル", "メニュー表＋お店のルールブック", "ファイル全体（A〜I）"],
                ["API Gateway", "受付係", "x-amazon-apigateway-* の各設定"],
                ["プライベート API / VPC エンドポイント", "社員食堂と、社内にある専用の入口", "B-1・B-2"],
                ["リソースポリシー", "門番のルール表（どの入口から来た人を通すか）", "B-9〜B-14"],
                ["Cognito のアクセストークン / スコープ", "入館証と、そこに書かれた「入ってよい部屋」", "C-7・D-2・G-4・H-1〜H-6"],
                ["API キー（X-API-Key）", "会員カード（誰が何回注文したか数える）", "B-5"],
                ["リクエストバリデーター", "注文票の書き方チェック係", "B-6〜B-8、I-*"],
                ["ゲートウェイレスポンス", "受付が渡す定型のお断りカード", "B-15〜B-21"],
                ["統合（http_proxy）", "注文票をそのまま厨房へ渡す取り次ぎ", "C-10〜C-19 ほか"],
                ["mock 統合", "厨房に聞かずに受付がその場で答える", "E-3〜E-6"],
                ["VPC リンク V2 / 内部 ALB", "関係者専用通路と、厨房の振り分け係", "C-12〜C-15"],
                ["スキーマ（components.schemas）", "注文票・品目カードの書式見本", "I-1〜I-13"],
            ], {"spans": [2, 3, 3]}),
            ("h1", "ファイルの地図（どこに何が書いてあるか）"),
            ("art", ART_TREE),
            ("h1", "システム構成図（リクエストが通る道）"),
            ("art", ART_SYSTEM),
            ("h1", "定義されている API（5つ）"),
            ("table", ["No.", "メソッド", "パス", "operationId", "用途", "必要な許可（スコープ）", "統合", "成功コード"], ops_rows),
            ("note", "x-amazon-apigateway-any-method（ANY）は GET・POST・PUT・PATCH・DELETE・HEAD・OPTIONS のすべてを受け付けます。"
                     "JMeter シナリオでは代表として GET で送ります（生成時のオプションで変更可）。"),
        ],
    }


HISTORY_ROWS = [
    ["2000年ごろ", "SOAP／WSDL や独自形式の API が混在", "API ごとに説明書の書き方がバラバラで、使うたびに読み解く手間がかかった。",
     "（課題の時代）", "API の説明書を共通化する動きの出発点。"],
    ["2000年", "Roy Fielding 氏が博士論文で REST を提唱", "Web の仕組みを使った分かりやすい API の設計方法が求められていた。",
     "URL（パス）と HTTP メソッドで操作を表す考え方が広まった。", "paths と get/post などの書き方の土台（C-1）。"],
    ["2010年", "米 Wordnik 社の Tony Tam 氏が Swagger を開発", "自社 API の説明書とテスト画面を手作業で保守するのが大変だった。",
     "説明書（仕様）から画面や SDK を自動で作れるようになった。", "OpenAPI の原点（A-1）。"],
    ["2011年8月10日", "Swagger 仕様を公開", "API を公開する企業が増え、共通の書き方が求められた。", "オープンな仕様として普及が始まった。", "—"],
    ["2014年9月8日", "Swagger 2.0 公開", "1.x は書き方が複数ファイルに分かれて扱いにくかった。", "1つの JSON／YAML で API 全体を書けるようになった。",
     "API Gateway の最初の OpenAPI 対応は 2.0 だった。"],
    ["2015年3月", "SmartBear 社が Swagger を取得", "—", "Swagger UI・Editor などのツールの開発が加速。", "—"],
    ["2015年7月9日", "Amazon API Gateway 公開", "API の入口（認証・流量制限・監視）を自前で作る負担が大きかった。",
     "API の入口を AWS に任せられるようになった。", "このファイルの読み手（API Gateway）の誕生。"],
    ["2015年7月21日", "API Gateway が Swagger インポートツールを公開（x-amazon-apigateway 拡張）", "画面操作で API を1つずつ作るのは手間で、再現性もなかった。",
     "定義ファイルから API を作れるようになった（Infrastructure as Code の第一歩）。", "B〜H の AWS 拡張の始まり。"],
    ["2015年9月1日", "mock 統合", "バックエンドが無いと API を試せなかった。", "API Gateway だけで応答を返せるようになった。", "E-3（OPTIONS）。"],
    ["2015年11月5日", "ステージ変数", "環境（dev／prod）ごとに API を作り分ける必要があった。", "同じ API をステージごとの値で切り替えられるようになった。", "C-13（connectionId）。"],
    ["2015年11月", "OpenAPI Initiative 設立（Linux Foundation）", "特定企業の持ち物では業界標準にしにくかった。",
     "Google・Microsoft・IBM などが参加する中立の標準になった。", "—"],
    ["2016年1月1日", "Swagger 仕様を「OpenAPI Specification」に改名", "—", "仕様は OpenAPI、ツールは Swagger という呼び分けになった。", "A-1。"],
    ["2016年4月5日", "API Gateway が Import API を正式機能化", "外部ツールに頼らず定義を取り込みたかった。", "API Gateway 自体がインポート・更新できるようになった。", "このファイルの取り込み方法。"],
    ["2016年7月28日", "Cognito ユーザープールでのメソッド認可", "認証のために Lambda を書く必要があった。", "Cognito のトークンだけで認可できるようになった。", "H-1〜H-6。"],
    ["2016年8月11日", "使用量プランと API キー", "利用者ごとの回数制限・利用量の把握ができなかった。", "API キーごとにクォータ・スロットリングを設定できるようになった。", "B-5。"],
    ["2016年9月20日", "プロキシ統合・{proxy+}・ANY メソッド", "パスを1つずつ定義し、変換テンプレートを書くのが大変だった。",
     "既存アプリをまるごと API Gateway の後ろに置けるようになった。", "C-10、G-1〜G-6。"],
    ["2016年11月17日", "バイナリ対応（binaryMediaTypes）", "画像・PDF が壊れて返せなかった。", "バイナリを正しく扱えるようになった。", "B-3。"],
    ["2017年4月11日", "リクエスト検証（バリデーター）", "不正なリクエストもバックエンドまで届いていた。", "入口で 400 として止められるようになった。", "B-6〜B-8。"],
    ["2017年6月6日", "ゲートウェイレスポンスのカスタマイズ", "API Gateway のエラーの形を変えられなかった。", "エラーの本文・ヘッダ・番号を揃えられるようになった。", "B-15〜B-21。"],
    ["2017年7月26日", "OpenAPI 3.0.0 公開", "2.0 はリクエスト本文や複数サーバーの表現が弱かった。",
     "requestBody・components・servers などで表現力が大きく向上した。", "このファイルの書き方。"],
    ["2017年11月30日", "プライベート統合と VPC リンク（NLB 経由）", "VPC 内のサーバーを API にするには公開が必要だった。", "インターネットに出さずにつなげられるようになった。", "C-12。"],
    ["2017年12月14日", "Cognito で OAuth 2 スコープによる認可", "Cognito では「誰か」しか確認できなかった。", "「何をしてよいか（スコープ）」で認可できるようになった。", "C-7・D-2・G-4。"],
    ["2017年12月19日", "ペイロード圧縮 / API キーをオーソライザーから取得", "通信量の削減、キーの受け渡し方法の柔軟化が求められた。", "応答の圧縮と、AUTHORIZER からのキー取得ができるようになった。", "B-4・B-5。"],
    ["2018年4月2日", "リソースポリシー", "「どこから来た通信か」で API を守れなかった。", "送信元 IP・VPC・アカウントで許可／拒否できるようになった。", "B-9〜B-14。"],
    ["2018年6月14日", "プライベート API", "社内専用の API もインターネット向けの入口しか作れなかった。", "VPC エンドポイント経由でのみ呼べる API を作れるようになった。", "B-1。"],
    ["2018年9月27日", "API Gateway が OpenAPI 3.0 に対応", "3.0 で書いた定義をそのまま取り込めなかった。", "3.0 のインポート・エクスポートができるようになった。", "A-1。"],
    ["2019年9月18日", "プライベート API の Route 53 エイリアス", "Host ヘッダなどを付けないと呼べず面倒だった。", "vpcEndpointIds で専用の DNS 名が作られるようになった。", "B-2。"],
    ["2020年2月20日", "OpenAPI 3.0.3 公開", "3.0.0〜3.0.2 のあいまいな文章でツールごとに解釈が違った。", "3.0 系の説明が明確になった（書ける項目は同じ）。", "A-1（このファイルの版）。"],
    ["2021年2月15日", "OpenAPI 3.1.0 公開", "JSON Schema との細かな違いがツール間の混乱を招いた。", "JSON Schema 2020-12 と完全に互換になった。", "API Gateway は 3.0 系が前提のため採用せず（A-1）。"],
    ["2024年6月4日", "統合タイムアウトを 29 秒超に引き上げ可能に（リージョン／プライベート）", "生成 AI など 29 秒を超える処理を API にできなかった。",
     "Service Quotas で上限を上げられるようになった。", "C-17。"],
    ["2024年10月24日", "OpenAPI 3.0.4 / 3.1.1 公開", "—", "説明文の修正・明確化。", "—"],
    ["2024年11月21日", "プライベート API のカスタムドメイン名", "プライベート API の URL が長く読みにくかった。", "api.private.example.com のような名前で呼べるようになった。", "A-6。"],
    ["2025年3月28日", "デュアルスタック（IPv4＋IPv6）エンドポイント", "IPv6 だけの環境から呼べなかった。", "REST・HTTP・WebSocket API で IPv6 に対応。", "プライベート API はデュアルスタックのみ（B-1）。"],
    ["2025年6月3日", "REST API のルーティングルール", "カスタムドメインでヘッダなどによる振り分けができなかった。", "ヘッダやパスの条件で API へ振り分けられるようになった。", "A-6（多階層パスの代替）。"],
    ["2025年9月19日", "OpenAPI 3.2.0 / 3.1.2 公開", "—", "タグの入れ子、追加の HTTP メソッド、ストリーミングなどに対応。", "—"],
    ["2025年11月19日", "REST API のレスポンスストリーミング／TLS セキュリティポリシーの強化／開発者ポータル", "大きな応答を返し終わるまで待たされた、など。",
     "応答を少しずつ返せる（responseTransferMode: STREAM）など。", "B-3（ストリーミング時はバイナリ設定が不要）。"],
    ["2025年11月21日", "REST API から ALB への直接のプライベート統合（VPC リンク V2・integrationTarget）", "ALB の前に NLB を置く必要があり、遅延・費用・複雑さが増えていた。",
     "NLB なしで ALB に直接つなげられるようになった。", "C-12〜C-14（このファイルの中心的な構成）。"],
    ["2026年9月10日", "OpenAPI 3.2.1 公開（2026年9月時点の最新）", "—", "説明文の修正・明確化。", "API Gateway 向けには 3.0.3 のままが安全（A-1）。"],
]

VERSION_ROWS = [
    ["Swagger 2.0", "2014年9月8日", "先頭に swagger: 2.0 と書く形式。host／basePath／definitions で記述。", "インポート可能（API Gateway の最初の対応版）。"],
    ["OpenAPI 3.0.0〜3.0.2", "2017年7月26日〜2018年10月", "requestBody・components・servers・callbacks などを導入。", "インポート可能（2018年9月27日〜）。"],
    ["OpenAPI 3.0.3", "2020年2月20日", "3.0 系の説明の明確化（項目は 3.0.0 と同じ）。", "インポート可能。このファイルの版。"],
    ["OpenAPI 3.0.4", "2024年10月24日", "3.0 系のさらなる説明の修正。", "構造は 3.0.3 と同じ。互換性の観点から 3.0.3 の表記が無難。"],
    ["OpenAPI 3.1.0〜3.1.2", "2021年2月15日〜2025年9月19日", "JSON Schema 2020-12 と完全互換、webhooks、nullable の廃止（type: [..., \"null\"]）など。",
     "AWS の公式ドキュメント上、REST API のインポート対象として記載なし。"],
    ["OpenAPI 3.2.0〜3.2.1", "2025年9月19日〜2026年9月10日", "タグの入れ子、QUERY などの追加メソッド、ストリーミング（SSE など）。", "同上。"],
]


def sheet_history():
    return {
        "name": "03_歴史と背景", "title": "歴史と背景（なぜ API の説明書と API Gateway が必要になったのか）",
        "widths": [16, 34, 44, 40, 34],
        "blocks": [
            ("h1", "なぜ「API の説明書」が必要になったのか"),
            ("p", "インターネットでシステム同士がつながるようになると、あちこちで API が作られました。ところが API ごとに説明書の書き方がバラバラで、"
                  "使う人は毎回読み解き、作る人は説明書とプログラムのずれに悩まされました。そこで「説明書を決まった形式で書けば、人も機械も読めて、"
                  "画面や呼び出しプログラム（SDK）、テストまで自動で作れる」という発想で生まれたのが Swagger で、それが業界全体の標準になったのが "
                  "OpenAPI です。"),
            ("p", "一方、API の入口では「本人確認」「許可の確認」「注文票のチェック」「混雑の制御」「記録」など、どの API にも共通の仕事があります。"
                  "これを毎回自分で作る負担をなくすために生まれたのが Amazon API Gateway です。API Gateway は OpenAPI の定義ファイルを読み込んで"
                  "入口を作れるため、「設計図（OpenAPI）を書けば、入口（API Gateway）ができあがる」という流れが定着しました。"
                  "ただし OpenAPI には AWS 固有の設定（VPC リンクや Cognito など）を書く欄が無いため、AWS は x-amazon-apigateway- で始まる"
                  "独自項目（拡張）を追加し、そこに書く方式を採りました。"),
            ("h1", "年表（日付は公式の改訂履歴・リリース情報で確認）"),
            ("table", ["年月日", "出来事", "背景（困っていたこと）", "何が良くなったか", "このファイルとの関係"], HISTORY_ROWS, "filter"),
            ("h1", "OpenAPI のバージョンの違いと API Gateway での扱い"),
            ("table", ["版", "公開日", "主な内容", "API Gateway（REST API）での扱い"], VERSION_ROWS, {"spans": [1, 1, 2, 1]}),
            ("note", "2026年9月時点で OpenAPI の最新版は 3.2.1 ですが、API Gateway の REST API に取り込む定義は 3.0 系で書くのが安全です。"
                     "このファイルが 3.0.3 なのは正しい選択です。"),
        ],
    }


FLOW_ROWS = [
    ["1", "クライアント（VPC 内）", "api.private.example.com を名前解決し、インターフェイス VPC エンドポイントの IP アドレスへ接続する。",
     "名前解決の失敗、接続できない。", "A-6、B-2", "お店の住所を調べて、社員通用口まで歩いていく。"],
    ["2", "VPC エンドポイント", "TLS 1.2 で暗号化して接続し、AWS PrivateLink（インターネットを通らない道）で API Gateway へ届ける。",
     "TLS のエラー。", "B-1、A-6", "社内の専用通路を通って受付へ行く。"],
    ["3", "API Gateway", "カスタムドメインの API マッピングで OrdersApi のステージを特定し、パス（/orders）とメソッド（GET）から処理する設定を決める。",
     "該当するパス・メソッドが無いとき 403（MISSING_AUTHENTICATION_TOKEN）。このファイルでは /{proxy+} が残りのパスを受け止める。",
     "C-1、G-1", "受付係が「一覧の窓口ですね」と用件を確認する。"],
    ["4", "API Gateway（Cognito オーソライザー）", "Authorization ヘッダのトークン（JWT）の署名・期限を確認し、スコープに orders.read が含まれるかを調べる。",
     "401（UNAUTHORIZED）。本文は B-17 の形。", "C-7、H-1〜H-6、B-15〜B-17", "入館証が本物で「閲覧室に入ってよい」と書いてあるかを確認する。"],
    ["5", "API Gateway（リソースポリシー）", "Cognito の認証が成功したら、リソースポリシーを評価する。aws:SourceVpce が指定の VPC エンドポイントなら明示的な Allow。",
     "403（ACCESS_DENIED）。本文は B-19 の形。", "B-9〜B-14、B-18〜B-19", "門番が「社員通用口 No.0 から来たか」を確認する。"],
    ["6", "API Gateway（API キー・流量制御）", "API キーが必須のメソッドなら X-API-Key を使用量プランと照合する（このファイルでは必須のメソッドは無い）。"
     "ステージ・アカウントの流量の上限もここで効く。", "キー不正は 403、上限超過は 429（THROTTLED／QUOTA_EXCEEDED）。", "B-5",
     "会員カードで利用回数を数える（今は数えていない）。混雑しすぎたら入場制限。"],
    ["7", "API Gateway（リクエスト検証 all）", "必須のパラメータの有無と、ボディ（POST のとき）が CreateOrderRequest の形に合うかを調べる。",
     "400（BAD_REQUEST_PARAMETERS／BAD_REQUEST_BODY）。", "B-6〜B-8、D-3、I-8、I-13", "注文票の書き方をチェック係が確認する。"],
    ["8", "API Gateway（統合リクエスト）", "http_proxy なので本文やヘッダはほぼそのまま。requestParameters で X-Client-Id（トークンの client_id）を追加する。",
     "—", "C-10、C-16", "伝票に依頼元を書き添えて、厨房へ回す準備をする。"],
    ["9", "VPC リンク V2 → 内部 ALB", "ステージ変数 vpcLinkV2Id の VPC リンクを通り、integrationTarget の ALB へ。uri のホスト名で Host ヘッダと証明書を確認する。",
     "つながらない・証明書の不一致などは統合エラー（本来 504 → このファイルでは 500）。", "C-12〜C-15、B-20", "関係者専用通路を通って、厨房の振り分け係へ渡す。"],
    ["10", "バックエンド", "受注サービスが処理して応答を返す。29 秒以内に返らないと API Gateway は待つのをやめる。",
     "29 秒超は INTEGRATION_TIMEOUT（本来 504 → このファイルでは 500）。", "C-17、B-20、B-21", "料理人が料理を作る。時間切れなら受付がお詫びする。"],
    ["11", "API Gateway（応答）", "プロキシなのでバックエンドの応答（番号・ヘッダ・本文）をそのまま返す。Accept-Encoding があり 1024 バイト以上なら圧縮する。",
     "—", "C-19、B-4", "料理をそのままお客さんに渡す（大きい料理は圧縮袋に入れる）。"],
]

OPTIONS_ROWS = [
    ["1", "ブラウザ", "本番のリクエストの前に、OPTIONS /orders に Origin・Access-Control-Request-Method・Access-Control-Request-Headers を付けて問い合わせる。",
     "E-1", "「こういう用事で入っていいですか？」と電話で確認する。"],
    ["2", "API Gateway", "OPTIONS には認可（security）が無いので、トークンの確認はしない（プライベート API のためリソースポリシーは評価される）。",
     "E-1、B-9〜B-14", "確認の電話には入館証はいらない。"],
    ["3", "API Gateway（mock 統合）", "requestTemplates の {\"statusCode\": 200} により、200 の統合レスポンスを選ぶ。バックエンドは呼ばない。", "E-3、E-4", "受付係がメモを見て、その場で返事を決める。"],
    ["4", "API Gateway（統合レスポンス）", "Access-Control-Allow-Origin／-Methods／-Headers を付け、本文 {} で 200 を返す。", "E-2、E-5、E-6", "「app.example.com 社の人なら、見る・注文・確認は OK」と答える。"],
    ["5", "ブラウザ", "許可の内容を見て、本番の GET／POST を送るかどうかを決める。", "E-5", "OK をもらったので、本番の用事に向かう。"],
]

ERROR_ROWS = [
    ["400", "API Gateway（バリデーター）／バックエンド", "必須パラメータが無い、ボディの形が定義と違う（余計な項目・型・範囲・pattern）。", "B-6〜B-8、D-3、I-8、I-13",
     "アクセスログの $context.error.responseType（BAD_REQUEST_BODY など）で API Gateway かバックエンドかを区別。"],
    ["401", "API Gateway（Cognito）", "トークンが無い・期限切れ・署名不正、スコープ不足。", "C-7、D-2、G-4、H-*、B-15〜B-17", "本文の code が UNAUTHORIZED。"],
    ["403", "API Gateway", "リソースポリシーで拒否（ACCESS_DENIED）、存在しないパス／メソッド（MISSING_AUTHENTICATION_TOKEN）、WAF によるブロックなど。",
     "B-9〜B-14、B-18〜B-19", "本文の code が FORBIDDEN なら ACCESS_DENIED。既定の本文なら別の種類。"],
    ["404 など", "バックエンド", "業務上の「見つからない」など（プロキシなのでそのまま返る）。", "F-2", "バックエンドのログを確認。"],
    ["429", "API Gateway", "流量の上限（スロットリング）やクォータの超過。", "B-5（使用量プラン）", "時間をおいて再試行。"],
    ["500", "API Gateway（DEFAULT_5XX）／バックエンド", "API Gateway 側の 5xx はすべて 500 に変換される（統合タイムアウト・統合失敗の 504 も含む）。", "B-20、B-21",
     "本文の code が INTERNAL_ERROR なら API Gateway。requestId で CloudWatch Logs を調べる。"],
    ["504（本来）", "API Gateway", "統合タイムアウト（29 秒超）・統合失敗。このファイルでは 500 として返る。", "C-17、B-20", "B-20 の修正（statusCode の削除）を推奨。"],
]


def sheet_flow():
    return {
        "name": "05_リクエストの流れ", "title": "リクエストの流れ（動作原理と動作イメージを順番に）",
        "widths": [7, 22, 56, 36, 24, 36],
        "blocks": [
            ("h1", "GET /orders（注文一覧）が処理される順番"),
            ("art", ART_FLOW),
            ("table", ["順番", "場所", "何が起きるか（動作原理）", "失敗したときの応答", "関係する設定", "たとえ話（動作イメージ）"], FLOW_ROWS),
            ("note", "Cognito オーソライザーとリソースポリシーの順番は、AWS 公式の説明（まず Cognito で認証し、成功した後にリソースポリシーを独立して評価）"
                     "にもとづきます。API キー・流量制御・検証の細かな順番は、実際の実行ログ（CloudWatch Logs の実行ログ）で確認できます。"),
            ("h1", "OPTIONS /orders（CORS のプリフライト）の流れ"),
            ("table", ["順番", "場所", "何が起きるか（動作原理）", "関係する設定", "たとえ話（動作イメージ）"], OPTIONS_ROWS),
            ("h1", "返ってくる番号（ステータスコード）の見分け方"),
            ("table", ["番号", "返す人", "主な原因", "関係する設定", "見分け方・調べ方"], ERROR_ROWS),
        ],
    }


REVIEW_ROWS = [
    ["1", "高", "B-20 DEFAULT_5XX の statusCode", "5xx の既定応答の番号を 500 に上書きしている。",
     "AWS の説明どおり、ほかのすべての 5XX（統合タイムアウト・統合失敗の 504 など）も 500 になり、原因の区別・監視・再試行の判断ができなくなる。",
     "statusCode を削除して本文（responseTemplates）だけを設定する。", "AWS「Gateway response types for API Gateway」の DEFAULT_5XX の説明"],
    ["2", "高", "B-5 API キー", "api-key-source は HEADER だが、API キーを必須にしているメソッドが無い。",
     "X-API-Key を送っても送らなくても API Gateway は確認しない。使用量プランによる利用者ごとの流量制御・利用量の把握が効かない。",
     "必要なら securitySchemes に api_key（type: apiKey／name: x-api-key／in: header）を定義し、各メソッドの security に追加。使用量プランに API のステージを関連付ける。",
     "AWS「Configure a method to use API keys with an OpenAPI definition」"],
    ["3", "高", "G-4 /{proxy+} の ANY", "読み取りのスコープ（orders.read）だけで、すべてのメソッドを受け付けている。",
     "書き込み・削除系の処理がプロキシ経由でバックエンドに届く可能性がある。",
     "受ける必要がある操作は明示的なパスで定義し、プロキシは不要なら削除、必要ならメソッドを限定・スコープを分ける。バックエンドでもメソッドごとに認可する。", "設計上の確認事項"],
    ["4", "中", "B-1 endpoint-configuration", "公式のプロパティ一覧に types が無く、OpenAPI 3.0 では servers の要素の中に書く決まりになっている。",
     "想定どおり PRIVATE にならない、vpcEndpointIds が関連付かない可能性がある。",
     "インポート時に --parameters endpointConfigurationTypes=PRIVATE を指定（または IaC で指定）し、インポート後に get-rest-api で確認する。",
     "AWS「x-amazon-apigateway-endpoint-configuration object」「Import a Regional API into API Gateway」"],
    ["5", "中", "C-14 integrationTarget", "AWS のドキュメント内で integrationTarget／integration-target の表記ゆれがある。",
     "表記によってはインポートで無視され、ALB に届かないおそれがある。", "インポート後に get-integration で integrationTarget が設定されているか確認する。",
     "AWS「x-amazon-apigateway-integration object」「Set up a private integration」"],
    ["6", "中", "C-15・F-3・G-6 の uri（プライベート統合）", "プライベート統合ではステージ名を含むパスがバックエンドに送られる場合があると公式に記載されている。",
     "バックエンドで 404 になる可能性がある。", "ALB のアクセスログで実際に届くパスを確認し、必要なら $context.requestOverride.path で上書きする。",
     "AWS「Private integrations for REST APIs in API Gateway」の Considerations"],
    ["7", "中", "E-5 CORS", "Allow-Headers に X-Api-Key が無く、エラー応答（401／403／5xx）に CORS ヘッダが無い。",
     "ブラウザから X-API-KEY 付きで呼べない。エラーの内容をブラウザが読めない。",
     "ブラウザから使うなら Allow-Headers に X-Api-Key などを追加し、ゲートウェイレスポンスにも Access-Control-Allow-Origin を付ける。M2M 専用なら CORS の定義自体の削除も検討。",
     "CORS の仕様（WHATWG Fetch）"],
    ["8", "低", "B-17・B-19 のテンプレート", "\"$context.error.message\" を引用符の中に埋め込んでいる。", "メッセージに \" が含まれると JSON が壊れる可能性がある。",
     "$context.error.messageString（エスケープ済み・引用符付き）を使う。", "AWS のゲートウェイレスポンスの例"],
    ["9", "低", "C-5 limit", "範囲（1〜100）が説明文にしか無い。", "範囲外の値もバックエンドまで届く（API Gateway は型・範囲を検証しない）。",
     "schema に minimum／maximum を書き、バックエンドでも検証する。", "AWS「Request validation for REST APIs」"],
    ["10", "低", "I-6・I-13 items", "minItems が無い。", "品目 0 件の注文が検証を通る。", "業務ルールに合わせて minItems: 1 を付ける。", "—"],
    ["11", "低", "F-2 getOrder", "summary が無い。", "ドキュメントが不親切になる。", "summary を追加する。", "—"],
    ["12", "低", "F-3・G-6", "timeoutInMillis／passthroughBehavior を省略している（既定値が使われる）。", "設定の意図が読み取りにくい。", "ほかのメソッドと同じく明記する。", "—"],
    ["13", "情報", "H-6 authorizerResultTtlInSeconds", "Cognito オーソライザーでのキャッシュの動きがコンソールでは見えない。", "トークンを取り消した直後の扱いが想定と違う可能性。",
     "実際の環境で確認する。", "AWS「CreateAuthorizer」"],
    ["14", "情報", "C-19・D-5 などの統合レスポンス", "プロキシ統合に統合レスポンスの設定がある。", "基本的に使われない（応答はそのまま返る）。", "意図を明確にする（削除してもよい）。", "—"],
    ["15", "情報", "A-1 openapi", "最新の OpenAPI は 3.2.1。", "—", "API Gateway 向けには 3.0.3 のまま維持する。", "OpenAPI 公式サイト、AWS のインポートの説明"],
]


def sheet_review():
    return {
        "name": "06_レビュー所見", "title": "レビュー所見（注意点と改善の提案）",
        "widths": [6, 8, 24, 42, 42, 46, 34],
        "blocks": [
            ("p", "定義ファイルを、AWS の公式ドキュメント（2026年9月26日時点）と照らし合わせて確認した結果です。"
                  "重要度「高」は動作や安全性に影響する可能性が高いもの、「中」は環境によっては問題になるもの、「低」は品質の改善、「情報」は参考です。"),
            ("table", ["No.", "重要度", "対象", "内容", "起きること", "推奨する対応", "根拠（公式情報）"], REVIEW_ROWS, "filter"),
        ],
    }


def sheet_jmeter():
    return {
        "name": "07_JMeterシナリオ", "title": "JMeter 5.6.3 シナリオ自動生成との対応（初期設定の推奨値・テストデータ・実行方法・検証結果）",
        "widths": [30, 30, 36, 70],
        "blocks": [
            ("h1", "ツール一式"),
            ("table", ["ファイル", "対象", "役割"], [
                ["linux/openapi2jmx.sh", "RHEL 9.8（bash＋OS 標準の python3）", "OpenAPI 定義（JSON）から JMX を生成する。"],
                ["linux/run_jmx.sh", "RHEL 9.8", "JMX を CLI モードで実行し、JTL（XML）とログを出力、成否を集計する。"],
                ["windows/OpenApi2Jmx.ps1", "Windows 11（PowerShell 5.1／7）", "OpenAPI 定義（JSON）から JMX を生成する（RHEL 版と同じ出力）。"],
                ["windows/Invoke-JmxScenario.ps1", "Windows 11", "JMX を CLI モードで実行し、JTL（XML）とログを出力、成否を集計する。"],
                ["windows/openapi2jmx.bat・run_jmx.bat", "Windows 11（コマンドプロンプト）", "実行ポリシーの影響を受けずに上の2つを起動するラッパー。"],
                ["tests/", "両方", "模擬 API サーバー・送信内容の検証・実装間の一致テスト。"],
            ]),
            ("h1", "OpenAPI の項目 → JMeter の要素"),
            ("table", ["OpenAPI の項目", "JMeter の要素", "生成内容"], [
                ["info.title / version", "テスト計画・スレッドグループの名前", "OrdersApi 1.0.0 - API疎通確認… / TG01_OrdersApi"],
                ["paths の各操作（get/post/…、ANY）", "HTTP リクエスト（1操作に1つ）", "名前は「番号 メソッド パス [operationId]」。ANY は既定で GET。"],
                ["パスパラメータ", "HTTP リクエストのパス", "型に合った乱数を URL エンコードして埋め込む。"],
                ["クエリパラメータ", "パラメータ表（GET）／パスの ?以降（GET 以外）", "style・explode（form／spaceDelimited／pipeDelimited／deepObject）に従う。"],
                ["ヘッダ・クッキーパラメータ", "API 用の HTTP ヘッダマネージャ", "Accept・Content-Type・Authorization・X-API-KEY は仕様・要件に従い除外。"],
                ["requestBody", "Body Data（JSON／XML／テキスト）、フォーム、マルチパート", "スキーマから生成。Content-Type は定義のメディアタイプ。"],
                ["responses の 2xx", "応答アサーション（応答コード）", "1つなら「等しい」、複数なら OR、2XX は正規表現。"],
                ["成功応答の content", "Accept ヘッダ", "最初の 2xx 応答の最初のメディアタイプ。"],
                ["security", "無効化した Authorization ヘッダマネージャ", "API Gateway 経由で試すときに有効化し -JauthToken で指定。"],
                ["x-amazon-apigateway-integration", "サンプラーのコメント", "type・httpMethod・uri・connectionType を記載。"],
            ]),
            ("h1", "テスト計画の初期設定（推奨値とその理由）"),
            ("table", ["要素", "設定項目", "値", "理由"], [
                ["テスト計画", "機能テストモード", "オフ", "オンにすると全リスナーに応答データを保存して重くなる。詳細は JTL 側で保存する。"],
                ["テスト計画", "tearDown を停止時に実行／スレッドグループを順に実行", "オン／オフ", "JMeter の既定値。"],
                ["ユーザー定義変数", "PROTOCOL・HOST・PORT", "${__P(protocol,http)}・${__P(host,localhost)}・${__P(port,8080)}",
                 "ご要望の既定値（localhost:8080）。__P 関数により、JMX を編集せず -Jhost= 等で切り替えられる（JMeter のベストプラクティス）。"],
                ["ユーザー定義変数", "API_KEY", "${__P(apiKey,XXXXXXXXXXXX)}", "ご要望の既定値。本物のキーを JMX に書かずに、実行時に -JapiKey= で渡せる。"],
                ["ユーザー定義変数", "THREADS・RAMP_UP・LOOPS", "1・1・1", "ご要望の最小構成（各 API を 1 回ずつ）。負荷試験時は -Jthreads= 等で変更。"],
                ["ユーザー定義変数", "CONNECT_TIMEOUT・RESPONSE_TIMEOUT", "10000・60000（ミリ秒）", "無制限（JMeter の既定）だと固まるおそれ。API Gateway の 29 秒タイムアウトの応答を受け取れる長さにしている。"],
                ["ユーザー定義変数", "RESULT_DIR・RUN_ID", "~/results・開始時刻", "~/ は JMX のあるフォルダ。GUI 実行でも JTL が JMX の横の results に作られる。"],
                ["HTTP リクエスト初期値設定", "実装／文字コード", "HttpClient4／UTF-8", "HttpClient4 は 5.6.3 の既定で推奨の実装。日本語データを正しく送るため UTF-8。"],
                ["HTTP リクエスト初期値設定", "埋め込みリソースの取得", "オフ", "API には画像などの埋め込みリソースが無いため。"],
                ["HTTP ヘッダマネージャ（共通）", "X-API-KEY", "${API_KEY}", "ご要望どおり全リクエストに固定で付ける。"],
                ["スレッドグループ", "エラー時の動作", "続行", "1件失敗しても残りの API をすべて確認するため。"],
                ["スレッドグループ", "各繰り返しで同じユーザー／スケジューラ", "オン／オフ", "JMeter の既定値。"],
                ["HTTP リクエスト", "KeepAlive／リダイレクトに従う", "オン／オン", "JMeter の既定値（接続を使い回して効率よく送る）。"],
                ["HTTP リクエスト", "クエリの置き場所", "GET はパラメータ表、それ以外はパス", "JMeter 5.6.3 の実測で、DELETE はパラメータ表の値をボディにも送り、HEAD は捨てるため。"],
                ["応答アサーション", "応答コード", "OpenAPI の 2xx と一致", "定義どおりの成功コードかを自動で判定する。"],
                ["JSR223 リスナー（Groovy）", "結果ログ出力", "[API-RESULT] 行", "ログファイルだけで各 API の成否・応答時間が分かるようにする。失敗時は理由と本文も出力。"],
                ["結果をツリーで表示／統計レポート", "ファイル名", "なし", "GUI での確認用（保存済みの JTL は［参照］で開ける）。"],
                ["シンプルデータライタ", "JTL", "XML・リクエスト/レスポンスのヘッダと本文付き", "GUI の「結果をツリーで表示」で送受信の中身まで確認できるようにするため。"],
            ]),
            ("h1", "テストデータの生成ルール（データ型からランダムに作成）"),
            ("table", ["型・形式", "作り方", "例"], [
                ["string（形式なし）", "英数字 8〜16 文字（minLength／maxLength を守る）", "byX0eYQ8"],
                ["string + pattern", "正規表現を解析して一致する文字列を作成し、正規表現エンジンで一致を確認", "^C[0-9]{8}$ → C05558498"],
                ["string + enum", "選択肢からランダムに1つ", "NEW"],
                ["date-time／date／time", "2025〜2026年のランダムな UTC 日時", "2026-03-14T08:21:45Z"],
                ["email／uuid／uri／hostname", "example.com などの予約ドメイン・UUID v4", "dq4x2a7n@example.com"],
                ["ipv4／ipv6", "説明用のアドレス範囲（RFC 5737・RFC 3849）", "192.0.2.10 / 2001:db8::6db4"],
                ["byte／binary／password", "Base64／英数字", "V0jIzoM038h2RCjo"],
                ["integer", "minimum〜maximum（指定なしは 1〜100）、multipleOf を守る", "qty（1〜999）→ 355"],
                ["number", "小数第2位（multipleOf があればその桁）で、10進数で正確に計算", "unitPrice → 57.60"],
                ["boolean", "true／false をランダム", "false"],
                ["array", "minItems 件（最低1件、maxItems 以内）。uniqueItems なら重複しないように作成", "[ {...} ]"],
                ["object", "properties の全項目（readOnly は除外）。additionalProperties のみなら key1 を1つ", "{ \"sku\": ..., \"qty\": ... }"],
                ["allOf／oneOf／anyOf", "allOf は統合、oneOf／anyOf は最初の選択肢", "—"],
                ["$ref の循環", "循環を検出して打ち切り（無限ループしない）", "TreeNode.children → []"],
                ["オプション --required-only", "必須のパラメータ・プロパティだけ", "—"],
                ["オプション --use-examples", "example／default があればそれを優先", "—"],
                ["オプション --seed N", "同じシードなら RHEL・Windows で同じデータ（同じ JMX）を再生成", "--seed 12345"],
            ]),
            ("h1", "実行方法と結果ファイル"),
            ("table", ["環境", "生成", "実行", "結果"], [
                ["RHEL 9.8", "./linux/openapi2jmx.sh -i openapi/orders-api.openapi.json -o OrdersApi.jmx",
                 "./linux/run_jmx.sh -t OrdersApi.jmx", "results/OrdersApi_<実行ID>.jtl と .log"],
                ["Windows 11（PowerShell）", ".\\windows\\OpenApi2Jmx.ps1 -InputFile .\\openapi\\orders-api.openapi.json -OutputFile .\\OrdersApi.jmx",
                 ".\\windows\\Invoke-JmxScenario.ps1 -JmxFile .\\OrdersApi.jmx", "results\\OrdersApi_<実行ID>.jtl と .log"],
                ["JMeter GUI で JTL を見る", "—", "JMeter を起動し、テスト計画の「結果をツリーで表示」（または統計レポート）の［参照］で JTL を選ぶ",
                 "送ったリクエスト（ヘッダ・本文）と受け取った応答が表示される"],
            ]),
            ("h1", "動作検証の結果（2026年9月26日に実施）"),
            ("table", ["検証内容", "環境", "結果", "内容"], [
                ["JMeter 5.6.3 での読み込み", "Windows 11・Java 17", "合格", "SaveService で 22 要素を読み込み、GUI クラスがすべて存在。JMeter の再保存と比べ、違いはプロパティの並び順だけ。"],
                ["GUI での読み込み", "Windows 11・JMeter 5.6.3", "合格", "GUI で JMX を開き、ツリーを表示。ログに WARN／ERROR なし。"],
                ["CLI 実行と JTL・ログ出力", "Windows 11／RHEL 9.8（UBI 9.8）", "合格", "5 件すべて成功。results に JTL（XML）とログ（[API-RESULT] 行）を出力。"],
                ["JTL の GUI 読み込み", "JMeter 5.6.3", "合格", "GUI の［参照］と同じ処理で 5 件を読み込み、リクエストヘッダ・送信データ・応答本文を確認。"],
                ["送信データの定義への適合", "模擬 API サーバー＋検証スクリプト", "合格", "OrdersApi 5 件、網羅用の定義 12 件で不合格 0 件（型・必須・pattern・enum・範囲・additionalProperties・クエリの各 style）。"],
                ["RHEL 9.8 での実行", "UBI 9.8（bash 5.1.8・Python 3.9.25・OpenJDK 17）", "合格", "生成・実行・検証をすべて実施。既定の localhost:8080 で 5/5 成功。"],
                ["実装間の一致", "bash＋Python／PowerShell 5.1／PowerShell 7.6", "合格", "4 種類の定義 × 4 種類のオプション × 3 種類のシード＝48 通りで、出力 JMX がバイト単位で一致。"],
                ["失敗時の動き", "Windows 11／RHEL 9.8", "合格", "定義と違う応答コード→終了コード 1（ログに理由と本文）、接続拒否→1、JMX／JMeter なし→3、入力エラー→1。"],
            ]),
        ],
    }


GLOSSARY = [
    ["API", "エーピーアイ", "プログラム同士のお願いと返事の窓口。", "Application Programming Interface。決められた形式でリクエストを送ると、決められた形式でレスポンスが返る。"],
    ["REST", "レスト", "URL とメソッドで「何に」「何をするか」を表す API の作り方。", "2000年に Roy Fielding 氏が提唱した設計スタイル。Web API の主流。"],
    ["HTTP メソッド", "エイチティーティーピー メソッド", "お願いの種類（見る・作る・変える・消す）。", "GET（取得）・POST（作成）・PUT／PATCH（更新）・DELETE（削除）・OPTIONS（確認）など。"],
    ["ステータスコード", "ステータスコード", "返事に付く番号。200 番台は成功、400 番台はお願いの間違い、500 番台はお店側の問題。", "HTTP の仕様（RFC 9110）で決められた3桁の数字。"],
    ["JSON", "ジェイソン", "データを {} や [] で書く、決まった書き方。", "JavaScript Object Notation。API のデータのやりとりで最もよく使われる形式。"],
    ["OpenAPI", "オープンエーピーアイ", "API の説明書を書く世界共通のルール。", "OpenAPI Specification。Linux Foundation の OpenAPI Initiative が管理。"],
    ["Swagger", "スワッガー", "OpenAPI の元になった仕組みと、関連ツールの名前。", "2016年に仕様は OpenAPI に改名。Swagger UI・Swagger Editor などのツール名として残る。"],
    ["JSON Schema", "ジェイソン スキーマ", "JSON の形（書式）を決めるルール。", "型・必須項目・桁数などを定義する仕様。OpenAPI 3.0 はその一部を拡張して使う。"],
    ["$ref", "リフ（参照）", "「あっちに書いた定義を使ってね」という矢印。", "JSON Reference。#/components/schemas/Order のように場所を指す。"],
    ["Amazon API Gateway", "エーピーアイ ゲートウェイ", "API の受付係を AWS が引き受けてくれるサービス。", "認証・認可・検証・流量制御・監視・転送を提供するフルマネージドサービス。"],
    ["REST API（API Gateway）", "レスト エーピーアイ", "API Gateway の多機能な API の種類。", "API Gateway には REST API・HTTP API・WebSocket API の3種類がある。この定義は REST API 用。"],
    ["ステージ", "ステージ", "同じ API の「開発用」「本番用」のような版。", "デプロイ先の名前（dev・prod など）。ステージごとに設定・変数を持てる。"],
    ["ステージ変数", "ステージへんすう", "ステージごとに変えられるメモ。", "${stageVariables.名前} で参照する。環境ごとの切り替えに使う。"],
    ["統合（インテグレーション）", "とうごう", "受付から厨房（バックエンド）への取り次ぎ方。", "API Gateway のメソッドの裏側の処理。http_proxy・aws_proxy・mock など。"],
    ["プロキシ統合", "プロキシとうごう", "注文票をそのまま厨房に渡す方式。", "リクエストとレスポンスを変換せずに中継する統合（http_proxy・aws_proxy）。"],
    ["mock 統合", "モックとうごう", "厨房に聞かずに受付がその場で答える方式。", "バックエンドを呼ばずに API Gateway が応答を作る統合。"],
    ["VPC", "ブイピーシー", "AWS の中に作る、自分専用の塀で囲まれた土地（ネットワーク）。", "Virtual Private Cloud。論理的に分離された仮想ネットワーク。"],
    ["VPC エンドポイント（インターフェイス型）", "ブイピーシー エンドポイント", "塀の中にある、AWS のサービス専用の入口。", "VPC 内の IP を持つネットワークインターフェイス。AWS PrivateLink で AWS のサービスへ接続。"],
    ["AWS PrivateLink", "プライベートリンク", "インターネットを通らない専用の道。", "VPC から AWS のサービスへ、AWS のネットワーク内だけで接続する技術。"],
    ["プライベート API", "プライベート エーピーアイ", "塀の中（VPC）からしか呼べない API。", "API Gateway の REST API のエンドポイント種別の1つ（PRIVATE）。"],
    ["カスタムドメイン名", "カスタムドメインめい", "API に付ける覚えやすい住所。", "api.example.com のような独自の名前。プライベート API 用は 2024年11月から。"],
    ["Route 53", "ルートフィフティースリー", "インターネットの住所録（DNS）の AWS 版。", "AWS の DNS サービス。プライベートホストゾーンで VPC 内だけの名前も作れる。"],
    ["VPC リンク", "ブイピーシー リンク", "受付（API Gateway）から VPC の中の厨房への専用通路。", "プライベート統合のための接続。V2 は ALB／NLB に直接接続でき、REST API でも 2025年11月から利用可能。"],
    ["ALB", "エーエルビー", "HTTP の中身を見て振り分ける係。", "Application Load Balancer。パス・ヘッダでの振り分け、HTTP ヘルスチェックができる。"],
    ["NLB", "エヌエルビー", "中身を見ずに高速で振り分ける係。", "Network Load Balancer。レイヤー4（TCP など）で動く。"],
    ["ARN", "エーアールエヌ", "AWS の中のものに付いた「住所」。", "Amazon Resource Name。arn:aws:サービス:リージョン:アカウント:リソース の形。"],
    ["Amazon Cognito", "コグニート", "入館証（トークン）を発行する事務所。", "ユーザー認証・トークン発行のサービス。ユーザープールで利用者・アプリを管理する。"],
    ["JWT", "ジョット", "偽造できないように印鑑（署名）が押された入館証。", "JSON Web Token。ヘッダ・中身（クレーム）・署名から成るトークン。"],
    ["アクセストークン／ID トークン", "アクセストークン／アイディートークン", "「何をしてよいか」の入館証／「誰か」の身分証。", "スコープ付きのメソッドにはアクセストークン、スコープなしは ID トークンを使う（API Gateway の Cognito オーソライザー）。"],
    ["スコープ", "スコープ", "入館証に書かれた「入ってよい部屋」。", "OAuth 2.0 の権限の範囲。例：https://api.example.com/orders.read。"],
    ["OAuth 2.0 クライアントクレデンシャル", "オーオース", "システム同士が合言葉で入館証をもらう方法。", "M2M 用の OAuth 2.0 のフロー。アプリのクライアント ID とシークレットでアクセストークンを得る。"],
    ["M2M", "エムツーエム", "人ではなく機械（システム）同士の通信。", "Machine to Machine。"],
    ["オーソライザー", "オーソライザー", "入館証を確認する係。", "API Gateway の認可の仕組み。Cognito 型と Lambda 型（token・request）がある。"],
    ["リソースポリシー", "リソースポリシー", "門番のルール表。", "API に付ける IAM ポリシー形式のアクセス制御。送信元 VPC・IP・アカウントなどで許可／拒否する。"],
    ["API キー／使用量プラン", "エーピーアイキー／しようりょうプラン", "会員カードと、その利用回数のルール。", "API キーで利用者を識別し、使用量プランでクォータやスロットリングを設定する。"],
    ["スロットリング", "スロットリング", "混雑しすぎないように入場を制限すること。", "1秒あたりのリクエスト数などの上限。超えると 429。"],
    ["リクエストバリデーター", "リクエストバリデーター", "注文票の書き方チェック係。", "必須パラメータとボディのスキーマを API Gateway で検証する機能。"],
    ["ゲートウェイレスポンス", "ゲートウェイレスポンス", "受付が渡す定型のお断りカード。", "API Gateway 自身が返すエラー応答。種類ごとに番号・ヘッダ・本文を変えられる。"],
    ["CORS／プリフライト", "コルス／プリフライト", "よそのサイトから呼んでいいかの事前確認。", "Cross-Origin Resource Sharing。ブラウザが OPTIONS で事前に許可を確認する。"],
    ["VTL", "ブイティーエル", "返事の文章のひな形の書き方。", "Velocity Template Language。マッピングテンプレートやゲートウェイレスポンスの本文に使う。"],
    ["JMeter", "ジェイメーター", "API をたくさん呼んで性能や動きを試す道具。", "Apache JMeter。Java 製の負荷試験・機能試験ツール。本ツールは 5.6.3 に対応。"],
    ["JMX／JTL", "ジェイエムエックス／ジェイティーエル", "試験の手順書／試験の結果の記録。", "JMX は JMeter のテスト計画（XML）。JTL は結果ファイル（CSV または XML）。"],
    ["サンプラー／アサーション／リスナー", "サンプラー／アサーション／リスナー", "お願いを送る係／返事を採点する係／結果を記録・表示する係。", "JMeter のテスト計画を構成する要素。"],
]


def sheet_glossary():
    return {
        "name": "08_用語集", "title": "用語集（小学生向けの説明と、詳しい説明）",
        "widths": [30, 26, 48, 70],
        "blocks": [("table", ["用語", "読み方", "小学生向けの説明", "詳しい説明"], GLOSSARY, "filter")],
    }


REFERENCES = [
    ["OpenAPI Specification v3.0.3", "https://spec.openapis.org/oas/v3.0.3.html", "各項目の定義、servers の既定、ヘッダパラメータの無視、style／explode の既定など。"],
    ["OpenAPI Specification（版の一覧）", "https://spec.openapis.org/oas/", "3.0.4／3.1.2／3.2.1 が各系列の最新であること。"],
    ["OAI/OpenAPI-Specification Releases", "https://github.com/OAI/OpenAPI-Specification/releases", "3.2.1（2026-09-10）、3.2.0・3.1.2（2025-09-19）、3.0.4・3.1.1（2024-10-24）などの公開日。"],
    ["OpenAPI Specification（Wikipedia）", "https://en.wikipedia.org/wiki/OpenAPI_Specification", "Swagger の誕生、2.0、SmartBear、OpenAPI Initiative、改名、3.0.0／3.1.0／3.2.0 の年表。"],
    ["API Gateway Developer Guide: Document history", "https://docs.aws.amazon.com/apigateway/latest/developerguide/history.html", "各機能の追加日（2015〜2025年）。"],
    ["x-amazon-apigateway-integration object", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration.html", "integrationTarget・responseTransferMode・timeoutInMillis などのプロパティ。"],
    ["Set up a private integration", "https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-private-integration.html", "VPC リンク V2 の設定、uri の役割（Host ヘッダ・証明書）、ステージ変数の利用。"],
    ["Private integrations for REST APIs", "https://docs.aws.amazon.com/apigateway/latest/developerguide/private-integration.html", "VPC リンク V1 はレガシー、ステージ名を含むパスの注意。"],
    ["Set up VPC links V2", "https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-vpc-links-v2.html", "VPC リンク V2 の仕組み、60 日無通信で INACTIVE。"],
    ["What's New: REST APIs private integration with ALB（2025-11-21）", "https://aws.amazon.com/about-aws/whats-new/2025/11/api-gateway-rest-apis-integration-load-balancer", "ALB への直接のプライベート統合の提供開始。"],
    ["What's New: Response streaming for REST APIs（2025-11-19）", "https://aws.amazon.com/about-aws/whats-new/2025/11/api-gateway-response-streaming-rest-apis", "レスポンスストリーミング。"],
    ["What's New: Integration timeout beyond 29 seconds（2024-06-04）", "https://aws.amazon.com/about-aws/whats-new/2024/06/amazon-api-gateway-integration-timeout-limit-29-seconds/", "統合タイムアウトの引き上げ。"],
    ["What's New: Custom domain names for private REST APIs（2024-11-21）", "https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-api-gateway-custom-domain-name-private-rest-apis/", "プライベートカスタムドメイン。"],
    ["Custom domain names for private APIs", "https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-private-custom-domains.html", "ドメイン名アクセス関連付け、TLS-1-2 固定、別のリソースポリシーが必要なこと。"],
    ["Private REST APIs in API Gateway", "https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-private-apis.html", "ベストプラクティス、TLS 1.2 のみ、HTTP/2 の扱い、デュアルスタックのみ。"],
    ["x-amazon-apigateway-endpoint-configuration object", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-endpoint-configuration.html", "プロパティは disableExecuteApiEndpoint・vpcEndpointIds・ipAddressType、OpenAPI 3.0 では Server オブジェクトに記述。"],
    ["Import a Regional API into API Gateway", "https://docs.aws.amazon.com/apigateway/latest/developerguide/import-export-api-endpoints.html", "endpointConfigurationTypes パラメータ。"],
    ["Set the OpenAPI basePath property", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-import-api-basePath.html", "servers の URL からのベースパスの判定（既定 ignore）。"],
    ["Gateway response types for API Gateway", "https://docs.aws.amazon.com/apigateway/latest/developerguide/supported-gateway-response-types.html", "各ゲートウェイレスポンスの既定の番号、DEFAULT_5XX の番号変更が他の 5XX に及ぶこと。"],
    ["Request validation for REST APIs", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-method-request-validation.html", "パラメータは存在の確認のみ、ボディは JSON Schema draft-04 のモデルで検証。"],
    ["Method request behavior for payloads without mapping templates", "https://docs.aws.amazon.com/apigateway/latest/developerguide/integration-passthrough-behaviors.html", "passthroughBehavior の3種類と 415。"],
    ["Binary media types for REST APIs", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-payload-encodings.html", "binaryMediaTypes と Accept ヘッダ（最初の1つ）の扱い。"],
    ["Payload compression for REST APIs", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-gzip-compression-decompression.html", "minimumCompressionSize の範囲と Accept-Encoding。"],
    ["x-amazon-apigateway-api-key-source property", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-api-key-source.html", "HEADER（X-API-Key）と AUTHORIZER。"],
    ["Configure a method to use API keys with an OpenAPI definition", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-key-usage-plan-oas.html", "api_key のセキュリティスキームで API キーを必須にする方法。"],
    ["x-amazon-apigateway-authorizer object", "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-authorizer.html", "Cognito オーソライザーの書き方、identitySource の説明。"],
    ["CreateAuthorizer（API Reference）", "https://docs.aws.amazon.com/apigateway/latest/api/API_CreateAuthorizer.html", "authorizerResultTtlInSeconds の既定 300・最大 3600、authType は動作に影響しないこと。"],
    ["Integrate a REST API with an Amazon Cognito user pool", "https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enable-cognito-user-pool.html", "スコープ指定時はアクセストークン、一致しなければ 401。"],
    ["How API Gateway resource policies affect authorization workflow", "https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-authorization-flow.html", "Cognito 認証の後にリソースポリシーを独立評価し、明示的な Allow が必要。"],
    ["Apache JMeter User's Manual: Best Practices", "https://jmeter.apache.org/usermanual/best-practices.html", "CLI モードでの実行、GUI リスナーの扱い、変数・プロパティの使い方。"],
    ["Apache JMeter Component Reference", "https://jmeter.apache.org/usermanual/component_reference.html", "HTTP リクエスト・ヘッダマネージャ・アサーション・リスナー・JSR223 の仕様。"],
]


def sheet_refs():
    return {
        "name": "09_参考資料", "title": "参考資料（2026年9月26日に確認した公式情報）",
        "widths": [44, 70, 60],
        "blocks": [("table", ["資料", "URL", "確認した内容"], REFERENCES)],
    }
