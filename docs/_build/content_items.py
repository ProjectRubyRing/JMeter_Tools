# -*- coding: utf-8 -*-
"""
「04_項目別詳細解説」の本体データ。
  path  : JSON のパス（表示用。設定値はビルド時にこのパスから自動取得）
  cover : 網羅チェックで「説明済み」とみなす範囲（省略時は path）
  container=True : 見出し的な項目（網羅チェックには数えない）
  value : 設定値の表示を上書きする場合のみ指定
"""

P = ["paths", "/orders", "get"]
PI = P + ["x-amazon-apigateway-integration"]
PP = ["paths", "/orders", "post"]
PO = ["paths", "/orders", "options"]
PG = ["paths", "/orders/{orderId}"]
PX = ["paths", "/{proxy+}"]
PXA = PX + ["x-amazon-apigateway-any-method"]
GR = ["x-amazon-apigateway-gateway-responses"]
POL = ["x-amazon-apigateway-policy"]
ST = POL + ["Statement", 0]
CS = ["components", "securitySchemes", "CognitoM2M"]
AU = CS + ["x-amazon-apigateway-authorizer"]
SC = ["components", "schemas"]

STD = "OpenAPI標準"
AWS = "AWS拡張（x-amazon-apigateway-*）"
IAM = "AWS拡張（IAMポリシー構文）"
JS = "OpenAPI標準（JSON Schema）"

ITEMS = [
    {"group": "A. 基本情報（OpenAPI 標準の共通項目）"},
    {
        "no": "A-1", "path": ["openapi"], "kind": STD + "・必須",
        "short": "「このファイルは OpenAPI という世界共通のルールの 3.0.3 版で書いてあります」という宣言です。",
        "detail": "ファイルがどの版の OpenAPI 仕様（API の説明書を書くための共通ルール）に従っているかを示す必須項目です。"
                  "値は「メジャー.マイナー.パッチ」の3つの数字で、3.0.3 は 3.0 系の3回目の修正版です。3.0.3 は 3.0.0〜3.0.2 の"
                  "あいまいな文章を直した改訂で、書ける項目そのものは 3.0.0 と同じです。",
        "principle": "ファイルを読むツール（API Gateway のインポート機能、Swagger UI、コード生成ツール、本ツール openapi2jmx など）は、"
                     "最初にこの値を読んで「どの文法で解釈するか」を決めます。AWS の公式ドキュメント上、API Gateway の REST API が"
                     "インポートできるのは OpenAPI 2.0（Swagger）と 3.0 形式です（3.1 以降は記載がありません）。",
        "image": "料理のレシピ本の表紙に「第3.0.3版の書き方で書いています」と印刷してあるイメージです。読む人は表紙を見て、"
                 "どの書き方のルールで読めばよいかが分かります。",
        "history": "2010年、米 Wordnik 社の Tony Tam 氏が社内 API の説明書づくりのために「Swagger」を作り、2011年8月に公開。"
                   "2014年9月8日に Swagger 2.0、2015年11月に Linux Foundation の OpenAPI Initiative へ寄贈され、2016年1月1日に"
                   "「OpenAPI Specification」へ改名されました。2017年7月26日に 3.0.0、2020年2月20日に 3.0.3 が公開され、"
                   "API Gateway は 2018年9月27日に OpenAPI 3.0 のインポート・エクスポートに対応しました。",
        "caution": "2026年9月時点の最新版は 3.2.1（2026年9月10日公開）、3.0 系の最新は 3.0.4（2024年10月24日公開・文章の修正のみ）です。"
                   "API Gateway の REST API は 3.0 系が前提のため「3.0.3」のままにするのが安全です。3.1 以降は nullable の廃止など"
                   "JSON Schema の扱いが変わるため、書き換えるとインポートで項目が無視・失敗する可能性があります。",
        "jmeter": "値が「3.」で始まることを確認します（swagger: 2.0 形式の場合は 3.0 形式への変換を促すエラー）。3.0.x 以外は警告を出し、"
                  "3.0 と共通の項目だけを解釈します。",
    },
    {
        "no": "A-2", "path": ["info", "title"], "kind": STD + "・必須",
        "short": "この API の名前です。",
        "detail": "API の人間向けの名前で、info オブジェクトの必須項目です。",
        "principle": "API Gateway にインポートすると、作成される REST API の名前になり、コンソールの API 一覧に表示されます。"
                     "API Gateway では同じ名前の API をいくつでも作れる（名前は一意ではない）ため、既存 API の更新は API ID を指定して行います。",
        "image": "お店の看板に書く店名「OrdersApi（受注API）」です。",
        "history": "Swagger 1.x の時代からある基本項目です。社内外で API が何十個も増え、「どれが何の API か分からない」問題を"
                   "解決するため、説明書の先頭に名前を書く決まりになりました。",
        "caution": "名前が重複できるため、スクリプトや IaC で「名前で検索して更新」すると別の API を変更する事故が起きます。"
                   "API ID（例: a1b2c3d4e5）で管理してください。",
        "jmeter": "テスト計画名（OrdersApi 1.0.0 - API疎通確認…）、スレッドグループ名（TG01_OrdersApi）、既定の出力ファイル名"
                  "（OrdersApi.jmx）、JTL のファイル名に使います（英数字と . _ - 以外は _ に置き換え）。",
    },
    {
        "no": "A-3", "path": ["info", "description"], "kind": STD,
        "short": "この API が何のためのものかを説明する文章です。",
        "detail": "API 全体の説明文で、Markdown（CommonMark）で書けます。ここでは「受注API（社内向け・プライベートREST API）」と、"
                  "利用範囲と API の種類が書かれています。",
        "principle": "API Gateway では REST API の説明として取り込まれ、コンソールに表示されます。API の動作には影響しません。",
        "image": "看板の下に書く「社員専用の注文受付窓口です」という案内文です。",
        "history": "API が社外公開・社内限定・取引先向けなどに分かれてきたため、「誰向けの API か」を説明書に明記する習慣が定着しました。",
        "caution": "動作に影響しない分、実態とずれやすい項目です。「プライベート」と書いてあっても、本当にプライベートかどうかは"
                   "エンドポイント種別（B-1）とリソースポリシー（B-9〜B-14）で決まります。",
        "jmeter": "使用しません。",
    },
    {
        "no": "A-4", "path": ["info", "version"], "kind": STD + "・必須",
        "short": "この API（設計図）そのもののバージョン番号です。",
        "detail": "API 定義のバージョンで、A-1 の openapi（ルールの版）とは別物です。互換性を壊す変更で1桁目、機能追加で2桁目、"
                  "修正で3桁目を上げる「セマンティックバージョニング」で付けるのが一般的です。",
        "principle": "API Gateway では REST API のバージョン情報として扱われ、エクスポート時にも info.version として出力されます。"
                     "ステージ（prod など）やデプロイの世代とは連動しません。",
        "image": "メニュー表の右下に書く「第1.0.0版」という刷り番号です。",
        "history": "API の変更で利用側のプログラムが突然動かなくなる事故が多かったため、「どの版の約束か」を明示する習慣が広まりました。",
        "caution": "openapi の値（3.0.3）と混同しないでください。この値を変えても URL（/v1/… など）は変わりません。",
        "jmeter": "テスト計画名とコメントに表示します。",
    },
    {
        "no": "A-5", "path": ["info", "contact"], "kind": STD,
        "short": "この API の問い合わせ先（担当チーム名とメールアドレス）です。",
        "detail": "contact は name（担当者・チーム名）・email・url を書ける任意項目です。ここでは「API基盤チーム」と"
                  "api@example.com が書かれています。",
        "principle": "API Gateway の動作には影響しません。Swagger UI などのドキュメント表示ツールで問い合わせ先として表示されます。",
        "image": "メニュー表の裏に書く「ご意見はこちら：API基盤チーム」という連絡先です。",
        "history": "API の利用者が増え、障害や仕様の質問をどこにすればよいか分からない問題が起きたため、説明書に連絡先欄が設けられました。",
        "caution": "example.com は説明用に予約されたドメイン（RFC 2606）です。実運用では、人事異動で消えない共有アドレスを書きます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "A-6", "path": ["servers", 0, "url"], "kind": STD,
        "short": "この API を呼ぶときの住所（URL）です。",
        "detail": "API の接続先 URL の一覧で、各 path（/orders など）はこの URL を基準にします。ここでは社内専用のカスタムドメイン "
                  "https://api.private.example.com が書かれています。",
        "principle": "API Gateway のインポートでは、servers の URL は「ベースパス（/v1 のような前置パス）」の判定にだけ使われます"
                     "（この URL にはパスが無いので影響なし。既定の扱いは ignore）。ドメイン名そのものはインポートでは作られません。"
                     "プライベート API のカスタムドメインは、API Gateway の「カスタムドメイン名」＋「API マッピング（ベースパスマッピング"
                     "またはルーティングルール）」＋VPC エンドポイントとの「ドメイン名アクセス関連付け」を別途作ることで使えるようになります。",
        "image": "名刺に書いた住所です。住所を書いただけでは家は建たず、家（ドメイン）は別に建てる必要があります。",
        "history": "Swagger 2.0 では host・basePath・schemes の3項目でしたが、OpenAPI 3.0 で servers（複数の URL と変数を書ける配列）"
                   "に統一されました。API Gateway のプライベート API 用カスタムドメインは 2024年11月21日に提供が始まり、それ以前は"
                   "https://{api-id}-{vpce-id}.execute-api.… のような読みにくい URL を使う必要がありました。",
        "caution": "プライベートカスタムドメインは、作成・関連付けにそれぞれ約15分かかります。TLS のセキュリティポリシーは TLS-1-2 固定で、"
                   "ドメイン名側にも API とは別のリソースポリシーが必要です。多階層のベースパス（/a/b）は使えず、ルーティングルールで代替します。",
        "jmeter": "使用しません。ご要望どおり接続先の初期値は localhost:8080 で、実行時に -Jprotocol / -Jhost / -Jport / -JbasePath "
                  "で上書きできます。",
    },
    {
        "no": "A-7", "path": ["servers", 0, "description"], "kind": STD,
        "short": "上の URL が何の URL かの説明です。",
        "detail": "servers の各要素に付ける説明文です。「プライベートカスタムドメイン」と書かれ、社内ネットワーク専用の住所であることを示しています。",
        "principle": "動作には影響しません。ドキュメントツールで URL の選択肢と一緒に表示されます。",
        "image": "住所の横に書く「（社員通用口）」という注記です。",
        "history": "開発用・検証用・本番用など複数の URL を並べることが増え、区別のために使われるようになりました。",
        "caution": "実際にプライベートかどうかは B-1・B-9〜B-14 の設定で決まります。",
        "jmeter": "使用しません。",
    },
    {
        "no": "A-8", "path": ["tags"], "kind": STD,
        "short": "API をグループ分けするための「見出しラベル」です。",
        "detail": "ファイル先頭の tags でタグ名（Orders）と説明（受注に関する操作）を定義し、各操作の tags で所属グループを指定します。",
        "principle": "Swagger UI などで API を見出しごとにまとめて表示するために使われます。API Gateway の動作や、AWS の"
                     "リソースタグ（費用管理・権限管理用のタグ）とは関係ありません。",
        "image": "メニュー表の「ごはんもの」「飲み物」といったコーナー見出しです。",
        "history": "API の数が増えると一覧が長くなって探せなくなるため、Swagger の初期からグループ化の仕組みがあります。"
                   "OpenAPI 3.2.0（2025年9月）ではタグの親子関係などが追加されました。",
        "caution": "AWS の「タグ」と名前が同じで紛らわしいので注意してください。3.0.3 ではタグ名はファイル内で重複できません。",
        "jmeter": "使用しません（サンプラーは番号・メソッド・パス・operationId で命名します）。",
    },

    {"group": "B. API 全体に効く AWS 拡張（x-amazon-apigateway-*）"},
    {
        "no": "B-1", "path": ["x-amazon-apigateway-endpoint-configuration", "types"], "kind": AWS,
        "short": "「この API は会社の中（VPC）からしか呼べない種類（PRIVATE）にする」という意図を表す指定です。",
        "detail": "API Gateway の REST API の入口（エンドポイント）には「エッジ最適化」「リージョン」「プライベート」の3種類があり、"
                  "PRIVATE は VPC の中から、インターフェイス VPC エンドポイント経由でしか呼べない種類です。",
        "principle": "AWS の公式リファレンスに載っている x-amazon-apigateway-endpoint-configuration のプロパティは "
                     "disableExecuteApiEndpoint・vpcEndpointIds・ipAddressType の3つで、types は載っていません。エンドポイント種別は、"
                     "インポート時のパラメータ（aws apigateway import-rest-api --parameters endpointConfigurationTypes=PRIVATE）や、"
                     "CloudFormation／Terraform の EndpointConfiguration.Types で指定するのが公式の手順です。プライベートの場合、"
                     "通信はインターネットに出ず AWS PrivateLink の中だけを通ります。",
        "image": "お店を「社員食堂」にする設定です。社外の人は入口にたどり着くことすらできません。",
        "history": "API Gateway は 2015年7月9日の公開時はインターネット向け（エッジ最適化）だけでした。2017年11月2日にリージョン型、"
                   "2018年6月14日にプライベート API が追加され、社内システム同士の連携にも使えるようになりました。",
        "caution": "【要確認】types がインポートで反映されるかは公式に保証されていません。インポート後に aws apigateway get-rest-api で "
                   "endpointConfiguration.types が PRIVATE になっているか必ず確認してください。また AWS の説明では、OpenAPI 3.0 の場合"
                   "この拡張は servers の各要素の中に書く決まりで、ルート直下の記述が効くかも同様の確認が必要です。プライベート API は"
                   " TLS 1.2 のみ、HTTP/2 のリクエストは HTTP/1.1 として処理、IP アドレス種別はデュアルスタックのみ、という制約があります。",
        "jmeter": "使用しません。プライベート API を JMeter から直接試す場合は、JMeter を VPC 内（または Direct Connect／VPN 経由）で実行します。",
    },
    {
        "no": "B-2", "path": ["x-amazon-apigateway-endpoint-configuration", "vpcEndpointIds"], "kind": AWS,
        "short": "どの VPC エンドポイント（社内専用の入口）とこの API を結び付けるかの一覧です。",
        "detail": "指定したインターフェイス VPC エンドポイントごとに、API Gateway が Route 53 のエイリアス DNS レコード"
                  "（https://{rest-api-id}-{vpce-id}.execute-api.{region}.amazonaws.com）を作ります。プライベート API 専用の設定です。",
        "principle": "VPC エンドポイントは VPC の中に IP アドレスを持つネットワークインターフェイスで、execute-api（API Gateway の実行系）"
                     "宛ての通信を AWS PrivateLink で API Gateway に届けます。関連付けておくと、VPC のプライベート DNS を使わなくても"
                     "上記のエイリアス名で呼び出せます。",
        "image": "社員食堂への「専用内線番号」を登録するイメージです。登録した内線（VPC エンドポイント）からは迷わず食堂につながります。",
        "history": "2019年9月18日に Route 53 エイリアスでの呼び出しが追加されました。それまでは Host ヘッダや x-apigw-api-id ヘッダを"
                   "付けて呼ぶ必要があり、面倒でした。",
        "caution": "ここに書いた VPC エンドポイントでも、リソースポリシー（B-9〜B-14）で許可されていなければ呼べません。AWS の推奨は"
                   "「1つの VPC エンドポイントを複数のプライベート API で共用」「VPC のプライベート DNS を有効化」「リソースポリシーで "
                   "aws:SourceVpc／aws:SourceVpce を指定」「VPC エンドポイントポリシーも設定」です。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-3", "path": ["x-amazon-apigateway-binary-media-types"], "kind": AWS,
        "short": "「PDF は文字ではなく、そのままのデータ（バイナリ）として扱う」という指定です。",
        "detail": "API Gateway に「テキストではなくバイナリとして扱うメディアタイプ」を教える一覧です。application/pdf を登録し、"
                  "PDF を壊さずに通せるようにしています。",
        "principle": "API Gateway は、リクエストの Content-Type と、クライアントの Accept ヘッダ（最初の1つだけ）がこの一覧に一致するかで"
                     "バイナリかテキストかを判断します。どちらも一致しない場合、データは UTF-8 の文字列として扱われるため、PDF や画像が"
                     "壊れることがあります（非プロキシ統合では contentHandling と組み合わせて変換方法が決まります）。",
        "image": "郵便局で「割れ物注意」のシールを貼るイメージです。シールが無いと普通の手紙と同じように扱われ、中身が壊れてしまいます。",
        "history": "当初の API Gateway は JSON などの文字データだけを想定していましたが、画像・PDF・圧縮ファイルを返したいという要望が多く、"
                   "2016年11月17日にバイナリ対応（binaryMediaTypes・contentHandling）が追加されました。",
        "caution": "API Gateway は Accept ヘッダの「最初の」メディアタイプしか見ません。ブラウザのように順番を制御できないクライアントでは "
                   "*/* を登録するなどの工夫が必要です。2025年11月19日に追加されたレスポンスストリーミング（responseTransferMode: STREAM）"
                   "を使うプロキシ統合では、バイナリメディアタイプの設定は不要です。",
        "jmeter": "成功応答が application/pdf の API があれば、その API の Accept を application/pdf にして送ります（この定義には該当 API はありません）。",
    },
    {
        "no": "B-4", "path": ["x-amazon-apigateway-minimum-compression-size"], "kind": AWS,
        "short": "1024 バイト（約1KB）以上の返事は圧縮して返してよい、という設定です。",
        "detail": "応答の圧縮を有効にし、圧縮する最小サイズを 1024 バイトにしています。0〜10485760（10MB）で指定でき、未指定（null）なら"
                  "圧縮しません。",
        "principle": "クライアントが Accept-Encoding（gzip・deflate・identity）ヘッダを付けて呼び、応答が 1024 バイト以上のとき、"
                     "API Gateway が圧縮して Content-Encoding を付けて返します。反対に、クライアントが圧縮した本文（Content-Encoding 付き）を"
                     "送れば、API Gateway が展開してから統合先に渡します。",
        "image": "大きな荷物だけ圧縮袋に入れて送るイメージです。小さな荷物は、袋に入れる手間のほうが大きいのでそのまま送ります。",
        "history": "2017年12月19日に追加されました。スマートフォンの回線など、通信量を減らしたいという要望に応えたものです。",
        "caution": "値を小さくしすぎると、圧縮・展開の計算時間でかえって遅くなることがあります（AWS も実測で最適値を決めるよう推奨）。"
                   "クライアントが Accept-Encoding を送らなければ圧縮されません。",
        "jmeter": "JMeter は既定では Accept-Encoding を送らないため圧縮は起きません。効果を測る場合は API 用ヘッダマネージャに "
                  "Accept-Encoding: gzip を追加してください。",
    },
    {
        "no": "B-5", "path": ["x-amazon-apigateway-api-key-source"], "kind": AWS,
        "short": "API キー（会員番号）を「X-API-Key ヘッダ」から読み取る、という設定です。",
        "detail": "API キーの取り出し元を、HEADER（リクエストの X-API-Key ヘッダ）か AUTHORIZER（Lambda オーソライザーが返す "
                  "usageIdentifierKey）から選びます。ここでは HEADER です。",
        "principle": "API キーが必須のメソッドでは、API Gateway が X-API-Key ヘッダの値を「使用量プラン」に登録されたキーと照合し、"
                     "回数の上限（クォータ）や1秒あたりの回数（スロットリング）を適用します。キーが無い・違うときは 403 になります。",
        "image": "会員カード（API キー）を「カードケース（X-API-Key ヘッダ）」から出して見せる決まりです。どのお客さんが何回注文したかを"
                 "数えるために使います。",
        "history": "2016年8月11日に使用量プランと API キーの仕組みが整い、2017年12月19日にキーの取り出し元として AUTHORIZER が"
                   "追加されたことで、この設定項目が必要になりました。",
        "caution": "【重要】この定義には、API キーを必須にする記述（securitySchemes に type: apiKey・name: x-api-key・in: header の"
                   "api_key を定義し、各メソッドの security に書くこと）がありません。つまり現状では、X-API-Key ヘッダを付けても付けなくても、"
                   "API Gateway はキーを確認しません。なお API キーは「認証」ではなく「利用量の識別」のためのもので、認証は Cognito などで行います。",
        "jmeter": "ご要望どおり全リクエストに X-API-KEY ヘッダ（初期値 XXXXXXXXXXXX）を固定で付けます。HTTP ヘッダ名は大文字小文字を区別"
                  "しないため、X-API-KEY は API Gateway の X-API-Key と同じヘッダとして扱われます。",
    },
    {
        "no": "B-6", "path": ["x-amazon-apigateway-request-validators", "all", "validateRequestBody"], "kind": AWS,
        "short": "「all」という名前のチェック係に「本文（ボディ）も調べる」と教える設定です。",
        "detail": "x-amazon-apigateway-request-validators は、名前付きのリクエスト検証ルール（バリデーター）を定義する場所です。"
                  "ここでは all という名前で、ボディの検証を ON にしています。",
        "principle": "ボディ検証が ON のメソッドでは、API Gateway がリクエストの Content-Type に対応する「モデル」（JSON Schema draft-04 形式）"
                     "で本文を調べ、合わなければ統合先に送る前に 400（BAD_REQUEST_BODY）で止め、結果を CloudWatch Logs に記録します。"
                     "Content-Type に合うモデルが無い場合は検証されません。",
        "image": "注文票の書き方（必須の欄・数字の範囲・書式）を確認する係です。書き方が間違っていれば厨房に回さず、その場で差し戻します。",
        "history": "2017年4月11日に追加されました。以前は明らかにおかしいリクエストでもバックエンドまで届き、無駄な負荷とエラー処理が発生していました。",
        "caution": "バリデーターは定義しただけでは効きません。B-8（API 全体の既定）かメソッドごとの指定で「使う」と決めて初めて有効になります。"
                   "API Gateway の検証は基本的なものなので、在庫の有無などの業務ルールはバックエンドで確認します。",
        "jmeter": "ボディは定義のスキーマ（required・pattern・enum・最小／最大・文字数など）を満たすように生成するため、このチェックを"
                  "通過する値になります（模擬サーバーで受信したボディを検証して確認済み）。",
    },
    {
        "no": "B-7", "path": ["x-amazon-apigateway-request-validators", "all", "validateRequestParameters"], "kind": AWS,
        "short": "同じ「all」係に「必須のパラメータがあるかどうかも調べる」と教える設定です。",
        "detail": "パラメータの検証を ON にしています。",
        "principle": "required: true のパス・クエリ文字列・ヘッダが「存在して空でない」ことを確認し、無ければ 400（BAD_REQUEST_PARAMETERS）"
                     "を返します。AWS の説明どおり存在の確認だけで、型（整数かどうか）や形式は調べません。",
        "image": "注文票の「お名前」欄が空欄でないかだけを見る係です。名前の書き方までは見ません。",
        "history": "B-6 と同じく 2017年4月11日に追加されました。",
        "caution": "この定義の limit・cursor は必須ではないため、検証の対象外です。limit の説明にある「1-100」は検査されないので、"
                   "範囲のチェックはバックエンドで行う必要があります。",
        "jmeter": "必須・任意にかかわらず、定義されたパラメータには型に合った値を入れて送ります（--required-only／-RequiredOnly で必須のみにできます）。",
    },
    {
        "no": "B-8", "path": ["x-amazon-apigateway-request-validator"], "kind": AWS,
        "short": "「この API のすべてのメソッドで all 係を使う」という既定値の指定です。",
        "detail": "ファイルのルート（API 全体）に書くと、全メソッドの既定のバリデーターになります。メソッド側に同じ名前の拡張を書けば、"
                  "そのメソッドだけ別のバリデーターに変えられます。",
        "principle": "インポート時に各メソッドの requestValidatorId に all が設定され、B-6・B-7 の検証が全メソッドで有効になります。",
        "image": "お店全体の決まりとして「すべての注文票は all 係が確認する」と掲示するイメージです。",
        "history": "バリデーター機能（2017年4月）と同時に OpenAPI 拡張として用意されました。",
        "caution": "ボディの形式が厳しい（additionalProperties: false）ため、クライアントが項目を1つ追加しただけで 400 になります（I-8・I-13 参照）。",
        "jmeter": "使用しません（生成データは検証を通る形で作ります）。",
    },
    {
        "no": "B-9", "path": POL + ["Version"], "kind": IAM,
        "short": "「このルール表は 2012-10-17 版の書き方です」という宣言です。",
        "detail": "x-amazon-apigateway-policy は API Gateway のリソースポリシー（API に付ける門番のルール表）で、書き方は IAM ポリシーと"
                  "同じ JSON です。Version はポリシー言語の版で、現行版の 2012-10-17 を指定しています。",
        "principle": "日付に見えますが「その日に作った」という意味ではなく、ポリシーの文法の版番号です。古い版（2008-10-17）では"
                     "ポリシー変数などの一部の機能が使えません。",
        "image": "門番に渡すルール表の用紙が「最新の様式」であることを示す欄です。",
        "history": "IAM ポリシー言語は 2012年10月17日版が現在まで使われ続けています。API Gateway のリソースポリシーは 2018年4月2日に追加されました。",
        "caution": "常に「2012-10-17」と書けば問題ありません。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-10", "path": ST + ["Effect"], "kind": IAM,
        "short": "「条件に合う相手を通す（許可する）」ルールであることを示します。",
        "detail": "Statement（ルールの1行）の効果です。Allow（許可）か Deny（拒否）を書きます。",
        "principle": "Cognito オーソライザーと併用する場合、API Gateway はまず Cognito で呼び出し元を認証し、成功した後にリソースポリシーを"
                     "独立して評価します。このとき「明示的な Allow」が必要で、Deny または「どちらでもない」は拒否になります（AWS 公式の評価フロー）。",
        "image": "門番のルール「この通用口から来た人は通してよい」の「通してよい」の部分です。",
        "history": "リソースポリシーは 2018年4月2日に追加され、2018年6月のプライベート API 登場で「どの VPC エンドポイントから来たか」で"
                   "通す使い方が定番になりました。",
        "caution": "プライベート API はリソースポリシーが無いと呼び出せません。「指定外の VPC エンドポイントは Deny」（StringNotEquals と Deny）"
                   "という書き方もよく使われます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-11", "path": ST + ["Principal"], "kind": IAM,
        "short": "「相手は誰でも」という意味です（誰かの確認は別の係が行います）。",
        "detail": "ルールの対象になる呼び出し元（プリンシパル）で、「*」はすべてを表します。",
        "principle": "相手は限定せず、次の Condition（どの VPC エンドポイントから来たか）で絞り込むのがプライベート API の定番の書き方です。"
                     "「誰か」の確認（認証）は Cognito が担当します。",
        "image": "「どなたでも」と書いた上で、下の条件で「社員通用口から来た人に限る」と絞り込むイメージです。",
        "history": "2018年のリソースポリシー導入以来の標準的な書き方です。",
        "caution": "Condition を消すと本当に誰でも許可になるため、Principal「*」と Condition は必ずセットで管理してください。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-12", "path": ST + ["Action"], "kind": IAM,
        "short": "「API を呼び出すこと」を対象にしたルールだと示します。",
        "detail": "許可・拒否する操作の種類です。execute-api:Invoke は API の呼び出しそのものを表します。",
        "principle": "API Gateway の実行系の権限は execute-api:Invoke（呼び出し）や execute-api:InvalidateCache（キャッシュの無効化）などに"
                     "分かれており、ここでは呼び出しだけを対象にしています。",
        "image": "ルール表の「対象の行為：注文すること」の欄です。",
        "history": "IAM で API の呼び出し権限を管理するための操作名として、API Gateway の公開当初からあります。",
        "caution": "API の設定を変える権限（apigateway:*）は別の仕組みで、ここでは管理されません。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-13", "path": ST + ["Resource"], "kind": IAM,
        "short": "「この API のすべてのステージ・メソッド・パス」を対象にする、という意味です。",
        "detail": "ルールの対象範囲です。execute-api:/* は、このポリシーを付けた API 自身のすべてを表す省略記法です。",
        "principle": "API Gateway はこの省略記法を arn:aws:execute-api:{リージョン}:{アカウント}:{API ID}/* に展開します。"
                     "/prod/GET/orders のように書けば、特定のステージ・メソッド・パスだけに絞れます。",
        "image": "ルール表の「対象の窓口：すべての窓口」の欄です。",
        "history": "API ID は API を作るまで決まらないため、インポートする定義ファイルに書けるよう、この省略記法が用意されました。",
        "caution": "リソースポリシーを変更したら API の再デプロイが必要です（デプロイするまで反映されません）。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-14", "path": ST + ["Condition"], "kind": IAM,
        "short": "「vpce-0123456789abcdef0 という社内専用の入口を通ってきた場合だけ」という条件です。",
        "detail": "リクエストが通ってきた VPC エンドポイントの ID（aws:SourceVpce）が、指定した ID と完全に一致（StringEquals）する場合だけ"
                  "Allow にします。",
        "principle": "通信が VPC エンドポイントを通ると、AWS がその ID をリクエストの情報として付けます。API Gateway はそれをポリシーの条件と"
                     "照らし合わせ、合わない呼び出しは明示的な Allow が無いため拒否（403）します。",
        "image": "「社員通用口 vpce-012… から入ってきた人だけ注文できる」という門番の条件です。",
        "history": "プライベート API（2018年6月）と一緒に使われ始めた条件です。2019年6月4日には VPC エンドポイント側に付けるポリシー"
                   "（エンドポイントポリシー）も使えるようになり、二重に守れるようになりました。",
        "caution": "VPC エンドポイントを作り直すと ID が変わり、ポリシーの修正と再デプロイが必要です。VPC 単位で許可したい場合は "
                   "aws:SourceVpc を使います。プライベートカスタムドメイン（A-6）を使う場合、ドメイン名側のリソースポリシーも別に必要です。",
        "jmeter": "使用しません（JMeter から API Gateway を呼ぶ場合、この VPC エンドポイントを通る場所で実行する必要があります）。",
    },
    {
        "no": "B-15", "path": GR + ["UNAUTHORIZED", "statusCode"], "kind": AWS,
        "short": "認証に失敗したとき（入館証が無い・無効）に返す番号を 401 にする設定です。",
        "detail": "x-amazon-apigateway-gateway-responses は、API Gateway 自身が作るエラー応答（ゲートウェイレスポンス）の中身を変える設定です。"
                  "UNAUTHORIZED は Cognito などのオーソライザーが呼び出し元を認証できなかったときの応答で、既定の番号も 401 です。",
        "principle": "トークンが無い・期限切れ・署名が不正などで認証に失敗すると、API Gateway はバックエンドを呼ばずに UNAUTHORIZED の"
                     "応答を返します。その番号・ヘッダ・本文をここで変えられます。",
        "image": "入館証が無い人に受付が渡す「お断りカード（401番）」です。",
        "history": "2017年6月6日に追加されました。以前は API Gateway 固有の決まった形のエラーしか返せず、「API ごとにエラーの形を揃えたい」"
                   "「CORS 用のヘッダを付けたい」という要望に応えたものです。",
        "caution": "既定値と同じ 401 なので、この行は「明示」の意味です。問題はありません。",
        "jmeter": "使用しません（成否は各 API の成功コードで判定します）。",
    },
    {
        "no": "B-16", "path": GR + ["UNAUTHORIZED", "responseParameters"], "kind": AWS,
        "short": "お断りの返事に「中身は JSON です」という荷札（Content-Type ヘッダ）を付ける設定です。",
        "detail": "gatewayresponse.header.Content-Type に 'application/json' を設定しています。値を囲むシングルクォートは「固定の文字列」を表します。",
        "principle": "ゲートウェイレスポンスでは gatewayresponse.header.{ヘッダ名} に、固定文字列（'…'）や method.request.header.X などの値を"
                     "割り当てて、ヘッダを追加できます。",
        "image": "お断りカードの封筒に「JSON 形式」と書くイメージです。",
        "history": "ゲートウェイレスポンス機能（2017年6月）と同時に使えるようになりました。よくある使い方は CORS 用の "
                   "Access-Control-Allow-Origin の付与です。",
        "caution": "ACCESS_DENIED と DEFAULT_5XX には Content-Type の指定がありません。ブラウザから呼ぶ API なら、エラー応答にも "
                   "Access-Control-Allow-Origin を付けないと、ブラウザがエラー内容を読めません。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-17", "path": GR + ["UNAUTHORIZED", "responseTemplates"], "kind": AWS,
        "short": "お断りの返事の本文を、この API 共通の JSON の形にする設定です。",
        "detail": "本文のテンプレート（VTL：Velocity Template Language）です。$ で始まる部分が、実際のエラーメッセージ（$context.error.message）"
                  "とリクエスト ID（$context.requestId）に置き換わります。",
        "principle": "エラーが起きると、API Gateway は $context 変数を埋め込んで本文を作ります。requestId は CloudWatch Logs で原因を調べる"
                     "ときの手がかりになります。",
        "image": "お断りカードの定型文「コード：UNAUTHORIZED／理由：〇〇／受付番号：〇〇」です。受付番号があれば後で問い合わせできます。",
        "history": "エラーの形をバックエンドの業務エラーと揃えたいという要望から、テンプレートで本文を作れるようになりました（2017年6月）。",
        "caution": '"$context.error.message" のようにダブルクォートの中に埋め込むと、メッセージに " が含まれた場合に JSON が壊れます。'
                   'AWS の例のように、JSON 用にエスケープ済みで引用符も付く $context.error.messageString を使う書き方（"message":$context.error.messageString）が安全です。',
        "jmeter": "使用しません。",
    },
    {
        "no": "B-18", "path": GR + ["ACCESS_DENIED", "statusCode"], "kind": AWS,
        "short": "許可されなかったとき（門番に止められた等）に返す番号を 403 にする設定です。",
        "detail": "ACCESS_DENIED は、オーソライザーやリソースポリシーによって拒否されたときのゲートウェイレスポンスで、既定の番号も 403 です。",
        "principle": "例えば Cognito の認証は通ったのにリソースポリシーの条件（B-14）に合わない場合、API Gateway はバックエンドを呼ばずに 403 を返します。",
        "image": "入館証は持っているが「この入口からは入れません」と止められたときのお断りカード（403番）です。",
        "history": "B-15 と同じく、2017年6月のゲートウェイレスポンス機能で変更できるようになりました。",
        "caution": "スコープ不足（例：orders.write が必要な POST を orders.read のトークンで呼ぶ）は、Cognito オーソライザーでは 401 になると"
                   "AWS の説明に書かれています。401 と 403 のどちらかで原因を切り分けられます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-19", "path": GR + ["ACCESS_DENIED", "responseTemplates"], "kind": AWS,
        "short": "許可されなかったときの返事の本文を、共通の JSON の形にします。",
        "detail": '{"code":"FORBIDDEN","message":"$context.error.message","requestId":"$context.requestId"} を返します。',
        "principle": "B-17 と同じ仕組みです。",
        "image": "「コード：FORBIDDEN」の定型のお断りカードです。",
        "history": "B-17 と同じです。",
        "caution": "B-17 と同じく $context.error.messageString の利用と、Content-Type ヘッダの明示をおすすめします。",
        "jmeter": "使用しません。",
    },
    {
        "no": "B-20", "path": GR + ["DEFAULT_5XX", "statusCode"], "kind": AWS,
        "short": "API Gateway 側で起きる 5xx エラー全般の「予備の返事」の番号を 500 にする設定です。",
        "detail": "DEFAULT_5XX は、個別に設定していない 5xx 系のゲートウェイレスポンス（統合タイムアウト・統合失敗・API 設定エラーなど）の既定値です。",
        "principle": "【重要】AWS の公式説明には「このフォールバック応答のステータスコードを変更すると、他のすべての 5XX 応答のステータスコードが"
                     "新しい値に変わる」と書かれています。つまり、本来 504 になる INTEGRATION_TIMEOUT（統合タイムアウト）や "
                     "INTEGRATION_FAILURE（統合失敗）も 500 で返るようになります。",
        "image": "「厨房が時間切れ（504番）」「厨房に届かない（504番）」など理由ごとに違う番号札を、全部「500番」の札に貼り替えてしまうイメージです。"
                 "お客さんからは何が起きたのか区別できなくなります。",
        "history": "ゲートウェイレスポンス（2017年6月）で、DEFAULT_4XX／DEFAULT_5XX による一括設定ができるようになりました。本文の形を揃える目的で"
                   "よく使われます。",
        "caution": "【修正を推奨】タイムアウト（504）と一般的なエラー（500）の区別がつかなくなり、監視・再試行の判断・障害調査が難しくなります。"
                   "本文を揃えたいだけなら statusCode を削除し（null に戻すと他の 5XX 応答は元の番号に戻ります）、responseTemplates だけを設定するのが安全です。",
        "jmeter": "API Gateway 経由で試験するとき、タイムアウトが 504 ではなく 500 に見える点に注意してください。JMeter の応答タイムアウトは 60 秒で、"
                  "API Gateway の 29 秒タイムアウト応答を受け取れるようにしています。",
    },
    {
        "no": "B-21", "path": GR + ["DEFAULT_5XX", "responseTemplates"], "kind": AWS,
        "short": "5xx エラーの返事の本文を、共通の JSON の形にします。",
        "detail": '{"code":"INTERNAL_ERROR","requestId":"$context.requestId"} を返します。エラーの詳しい中身は返さない設計です。',
        "principle": "内部の情報（統合先の名前など）を外に出さず、requestId だけを返して、詳しい原因は CloudWatch Logs（実行ログ・アクセスログ）で"
                     "調べる方式です。",
        "image": "「ただいま厨房でトラブルが起きています（受付番号〇〇）」とだけ伝えるお詫びカードです。",
        "history": "B-15 と同じです。",
        "caution": "本文を揃えるのはよい設計ですが、B-20 の statusCode の上書きと組み合わせると原因を区別できません。アクセスログに "
                   "$context.error.responseType や $context.integrationErrorMessage を出力すると調査が楽になります。",
        "jmeter": "使用しません。",
    },

    {"group": "C. GET /orders（注文一覧の取得：listOrders）"},
    {
        "no": "C-1", "path": ["paths", "/orders"], "kind": STD, "container": True, "value": "get / post / options の3操作",
        "short": "「/orders」という API の住所（パス）と、そこで使える操作の一覧です。",
        "detail": "paths の各キーが API のパス（URL の後半）で、その中に get・post・options などの HTTP メソッドごとの操作を書きます。"
                  "/orders には一覧の取得（GET）・注文の作成（POST）・CORS の確認（OPTIONS）の3つがあります。",
        "principle": "API Gateway にインポートすると、パスが「リソース」（ルート / の下の orders）に、メソッドが「メソッド」になります。"
                     "リクエストが来ると、API Gateway はパスとメソッドの組み合わせで、どの設定で処理するかを決めます。",
        "image": "お店の「注文コーナー」です。そこに「一覧を見る」「注文する」「利用確認」の3つの窓口があります。",
        "history": "パスとメソッドで操作を表す REST の考え方（2000年に Roy Fielding 氏が提唱）が Web API の主流になり、Swagger／OpenAPI も"
                   "この形で API を書き表します。",
        "caution": "パスは / で始めます。API Gateway のリソースパスに使える文字には制限があります（英数字・一部の記号・波かっこのパス変数など）。",
        "jmeter": "GET・POST・OPTIONS の3つのサンプラー（01〜03）を生成します。",
    },
    {
        "no": "C-2", "path": P + ["tags"], "kind": STD,
        "short": "この操作が「Orders」グループに入ることを示します。",
        "detail": "A-8 で定義したタグ名を指定します。",
        "principle": "ドキュメント表示でのグループ分けに使われます。動作には影響しません。",
        "image": "メニュー表のどのコーナーに載せるかの指定です。",
        "history": "A-8 と同じです。",
        "caution": "A-8 で定義していないタグ名も書けますが、定義して説明を付けるのが丁寧です。",
        "jmeter": "使用しません。",
    },
    {
        "no": "C-3", "path": P + ["operationId"], "kind": STD,
        "short": "この操作の「呼び名（ID）」です。",
        "detail": "API 全体で重複してはいけない（大文字小文字も区別する）操作の ID です。listOrders は「注文の一覧を取る」操作を表します。",
        "principle": "API Gateway ではメソッドの operationName（操作名）として取り込まれ、SDK を自動生成したときの関数名などに使われます。"
                     "コード生成ツールもこの名前で関数を作ります。",
        "image": "窓口に付けた「窓口番号：listOrders」の札です。",
        "history": "API から呼び出し用プログラム（SDK）を自動生成する文化が広まり、関数名の元として重要になりました。",
        "caution": "重複するとツールでエラーになります。OPTIONS には operationId がありませんが、任意項目なので問題はありません。",
        "jmeter": "サンプラー名の末尾に付けます（例：01 GET /orders [listOrders]）。",
    },
    {
        "no": "C-4", "path": P + ["summary"], "kind": STD,
        "short": "この操作の短い説明「注文一覧を取得する」です。",
        "detail": "操作の要約（1行の説明）です。長い説明は description に書きます。",
        "principle": "動作には影響しません。ドキュメントの一覧表示に使われます。",
        "image": "窓口の上の案内板「注文一覧のお問い合わせはこちら」です。",
        "history": "説明書を読む人が、一覧から目的の API を素早く探せるように設けられました。",
        "caution": "getOrder（F-2）には summary がありません。説明書の品質のため付けることをおすすめします。",
        "jmeter": "サンプラーのコメント（概要）に記載します。",
    },
    {
        "no": "C-5", "path": P + ["parameters", 0], "kind": STD,
        "short": "「何件取ってくるか」を URL の ? の後ろで指定する、書かなくてもよい数字（limit）です。",
        "detail": "in: query（クエリ文字列）、required: false（任意）、schema は integer（整数）です。説明文に「取得件数（1-100）」とあります。",
        "principle": "API Gateway では method.request.querystring.limit という任意のパラメータとして登録されます。http_proxy 統合では"
                     "クエリ文字列はそのまま統合先に渡されます。任意なので B-7 の検証対象外で、型や範囲も API Gateway は調べません。",
        "image": "「一覧は何件ほしいですか？（書かなくてもよい）」という注文票の欄です。",
        "history": "クエリ文字列で件数や続きを指定するページングは、REST API で最も一般的な方法です。",
        "caution": "「1-100」は説明文にしか書かれておらず、スキーマ（minimum: 1／maximum: 100）になっていません。ツールやバックエンドが"
                   "自動で範囲を守れるよう、schema に minimum と maximum を書くのが望ましいです。",
        "jmeter": "整数なので、範囲の指定が無い整数の既定範囲 1〜100 から乱数を選びます。GET なので JMeter の「パラメータ」タブに"
                  "URL エンコード有効で設定します。",
    },
    {
        "no": "C-6", "path": P + ["parameters", 1], "kind": STD,
        "short": "「続きはここから」を示す目印（cursor）を指定する、書かなくてもよい文字列です。",
        "detail": "in: query、required: false、schema は string です。前回の応答の nextCursor（I-12）を渡して続きのページを取る"
                  "「カーソル方式のページング」です。",
        "principle": "件数の多い一覧を少しずつ取るための仕組みです。サーバーは中身に意味を持たせない文字列を返し、クライアントはそれを"
                     "そのまま次の要求で送り返します。",
        "image": "本のしおりです。「前回はここまで読んだ」というしおりを渡すと、続きから読んでくれます。",
        "history": "大量のデータでは「何件目から」を指定する offset 方式が遅く不正確になるため、カーソル方式が広まりました。",
        "caution": "不正なカーソルをバックエンドがどう扱うか（400 を返すか無視するか）を決めておく必要があります。",
        "jmeter": "英数字 8〜16 文字の乱数を入れます。実在しないカーソルになるため、バックエンドによっては 400 になることがあります"
                  "（その場合は --required-only／-RequiredOnly で生成するか、値を実データに書き換えてください）。",
    },
    {
        "no": "C-7", "path": P + ["security"], "kind": STD + "（AWS の Cognito と連動）",
        "short": "この操作を使うには、入館証（トークン）に「orders.read（注文を読む）」の許可が必要、という指定です。",
        "detail": "security は「この操作に必要な認可」の一覧です。CognitoM2M（H-1〜H-6 で定義した Cognito オーソライザー）と、"
                  "必要なスコープ https://api.example.com/orders.read を指定しています。",
        "principle": "スコープを指定したメソッドでは、API Gateway は送られてきたトークンを「アクセストークン」として扱い、トークンのスコープに"
                     "指定スコープのどれか1つが含まれていれば許可、含まれていなければ 401 Unauthorized にします（スコープを指定しない場合は"
                     "ID トークンとして扱います）。M2M（マシン同士の通信）では、OAuth 2.0 のクライアントクレデンシャルフローで取得した"
                     "アクセストークンを Authorization ヘッダで送ります。",
        "image": "入館証に「閲覧室に入ってよい」と書かれている人だけが、一覧の窓口を使えるイメージです。",
        "history": "Cognito ユーザープールでのメソッド認可は 2016年7月28日に始まり、2017年12月14日に OAuth 2 のスコープによる認可が追加されました。"
                   "スコープで「読むだけ」「書ける」を分けられるため、システム間連携で広く使われています。",
        "caution": "スコープは「リソースサーバーの識別子/スコープ名」の完全な名前で指定します。",
        "jmeter": "認可が定義されているため、無効化した「HTTP ヘッダマネージャ（Authorization）」を用意します。API Gateway 経由で試すときは"
                  "有効化して -JauthToken=アクセストークン を指定します。サンプラーのコメントに必要なスコープを記載します。",
    },
    {
        "no": "C-8", "path": P + ["responses", "200"], "kind": STD,
        "short": "成功したときの返事（200番）の形の約束です。",
        "detail": "200（成功）の応答では、ヘッダ X-Request-Id（文字列）と、本文 application/json（OrderList＝注文の一覧、I-12）を返すと定義しています。",
        "principle": "API Gateway では「メソッドレスポンス」として登録されます。http_proxy 統合ではバックエンドの応答（ステータス・ヘッダ・本文）が"
                     "そのまま返るため、この定義は主に説明書や SDK 生成のための情報になります。",
        "image": "「一覧の窓口では、注文一覧の紙と受付番号（X-Request-Id）をお渡しします」という案内です。",
        "history": "応答の形を前もって約束しておけば、使う側が安心してプログラムを書けるため、Swagger の初期から中心となる項目です。",
        "caution": "プロキシ統合では、バックエンドが実際に返したステータスがそのまま届きます。定義と実装のずれはテストで確認します。",
        "jmeter": "2xx の定義（200）から「ステータスコード検証（200）」のアサーションを作ります。成功応答が application/json なので "
                  "Accept: application/json を付けて送ります。",
    },
    {
        "no": "C-9", "path": P + ["responses"], "kind": STD, "value": "400: リクエスト不正 / 401: 認証エラー / 403: 権限不足",
        "cover": [P + ["responses", "400"], P + ["responses", "401"], P + ["responses", "403"]],
        "short": "失敗したときの返事の番号（400 リクエスト不正・401 認証エラー・403 権限不足）の説明です。",
        "detail": "それぞれ説明文（description）だけで、本文の形は定義していません。",
        "principle": "このファイルの設定では、400 はバリデーター（B-6・B-7）、401 は Cognito の認証失敗・スコープ不足（B-15）、403 は"
                     "リソースポリシーなどでの拒否（B-18）のときに API Gateway が返します。バックエンドが返すこともあります。",
        "image": "「書き方の間違い（400）」「入館証なし（401）」「入ってはいけない場所（403）」というお断り理由の一覧です。",
        "history": "エラーの種類を番号で伝える HTTP の仕組み（現在は RFC 9110 で整理）をそのまま使っています。",
        "caution": "エラー本文の形（code・message・requestId）は B-17・B-19 で決めているので、その形もスキーマとして定義すると、使う側が扱いやすくなります。",
        "jmeter": "2xx 以外はアサーションの対象外です（成功コードだけを検証します）。",
    },
    {
        "no": "C-10", "path": PI + ["type"], "kind": AWS,
        "short": "「届いた注文を、ほぼそのまま厨房（バックエンドの HTTP サーバー）へ渡す」方式の指定です。",
        "detail": "x-amazon-apigateway-integration は、メソッドの裏側（統合先）の設定です。http_proxy は HTTP プロキシ統合で、"
                  "リクエストとレスポンスを変換せずに中継します。",
        "principle": "API Gateway は、メソッド・パス・クエリ・ヘッダ・本文を（C-15 の requestParameters で指定した追加・変更を加えて）統合先に送り、"
                     "戻ってきたステータス・ヘッダ・本文をそのままクライアントに返します。マッピングテンプレートや統合レスポンスによる変換は使いません。",
        "image": "受付係が注文票を書き直さずにそのまま厨房へ渡し、できた料理もそのままお客さんに出すイメージです。",
        "history": "当初は、テンプレートで変換する非プロキシ統合が中心でしたが、設定が大変なため、2016年9月20日にプロキシ統合と {proxy+}・ANY が"
                   "追加されました。「API Gateway は入口の管理、処理はバックエンド」という構成が主流になりました。",
        "caution": "type には他に http（非プロキシ）、aws（AWS サービス直結）、aws_proxy（Lambda プロキシ）、mock（E-3）があります。",
        "jmeter": "サンプラーのコメント（API Gateway 統合: type=…）に記載します。",
    },
    {
        "no": "C-11", "path": PI + ["httpMethod"], "kind": AWS,
        "short": "厨房に渡すときに使う HTTP メソッド（GET）です。",
        "detail": "統合リクエストで使う HTTP メソッドです。クライアントと同じ GET を指定しています。",
        "principle": "API Gateway はこのメソッドで統合先を呼びます。クライアントとは違うメソッドにすることもできます（Lambda を呼ぶ場合は必ず POST）。",
        "image": "厨房への伝え方「見せて（GET）」です。",
        "history": "API Gateway 公開当初からある基本項目です。",
        "caution": "http_proxy では、通常クライアントと同じメソッドにします。",
        "jmeter": "使用しません（JMeter はクライアント側のメソッドで送ります）。",
    },
    {
        "no": "C-12", "path": PI + ["connectionType"], "kind": AWS,
        "short": "厨房への専用通路（VPC リンク）を通って届ける、という指定です。",
        "detail": "統合先への接続方法です。INTERNET（インターネット経由）か VPC_LINK（VPC 内のプライベートなリソースへの専用接続）を選びます。",
        "principle": "VPC_LINK の場合、API Gateway は connectionId の VPC リンクが VPC 内に作ったネットワークインターフェイスを通じて、"
                     "VPC 内のロードバランサーに接続します。バックエンドをインターネットに公開する必要がありません。",
        "image": "受付と厨房の間の「関係者専用通路」を使う指定です。外からは通路が見えません。",
        "history": "2017年11月30日にプライベート統合（VPC リンク V1＝NLB 経由）が追加されました。2025年11月21日からは REST API でも"
                   "VPC リンク V2 が使えるようになり、NLB を挟まずに ALB へ直接つなげられるようになりました。",
        "caution": "AWS は現在 VPC リンク V1 を「レガシー」と位置付け、新しく作る場合は V2 を推奨しています。",
        "jmeter": "使用しません。",
    },
    {
        "no": "C-13", "path": PI + ["connectionId"], "kind": AWS,
        "short": "使う専用通路（VPC リンク）の ID を、ステージごとの設定値から読み取る指定です。",
        "detail": "VPC リンクの ID を直接書かずに、ステージ変数 vpcLinkV2Id を参照しています。",
        "principle": "ステージ変数は、ステージ（dev・stg・prod など）ごとに決められる変数で、実行時に ${stageVariables.名前} が実際の値に"
                     "置き換わります。同じ API 定義のまま、ステージごとに別の VPC リンク（別の環境）へ向けられます。",
        "image": "「通路の番号は、その店舗の掲示板（ステージ変数）を見てね」という書き方です。掲示板の番号を店舗ごとに変えれば、"
                 "同じマニュアルでどの店舗も動けます。",
        "history": "ステージ変数は 2015年11月5日に追加されました。VPC リンク ID にステージ変数を使う書き方は、AWS のプライベート統合の手順でも"
                   "公式に紹介されています。",
        "caution": "ステージに vpcLinkV2Id を設定し忘れると統合エラー（5xx）になります。AWS CLI で指定するときは $ のエスケープが必要です。",
        "jmeter": "使用しません。",
    },
    {
        "no": "C-14", "path": PI + ["integrationTarget"], "kind": AWS,
        "short": "専用通路の先にある、どのロードバランサー（ALB）へ届けるかの指定です。",
        "detail": "VPC リンク V2 を使うプライベート統合で、実際の届け先となる ALB（または NLB）を ARN で指定します。ここでは internal-alb という"
                  "内部向けの ALB です。",
        "principle": "VPC リンク V2 は1つで複数のロードバランサーに接続できる（1対多）ため、どれに送るかを integrationTarget で決めます。"
                     "ALB はレイヤー7（HTTP）でパスやヘッダによる振り分け・HTTP ヘルスチェックができ、ECS などのコンテナとも直接つながります。",
        "image": "専用通路の先にいる「厨房の振り分け係（ALB）」の指定です。振り分け係が、空いている料理人（サーバー）へ注文を回します。",
        "history": "2025年11月21日の「REST API の ALB へのプライベート統合」の提供開始で使えるようになった項目です。それまでは NLB を経由する"
                   "必要があり、余分な経路の遅延と費用がかかっていました。",
        "caution": "【表記ゆれに注意】AWS の拡張リファレンスでは integrationTarget（この表記）ですが、設定手順ページの OpenAPI の例には "
                   "integration-target という表記もあります。インポート後に aws apigateway get-integration で integrationTarget が設定されているか"
                   "確認してください。ロードバランサー・VPC リンク・API はすべて同じ AWS アカウントである必要があります。",
        "jmeter": "使用しません。",
    },
    {
        "no": "C-15", "path": PI + ["uri"], "kind": AWS,
        "short": "厨房側の住所（宛名）です。",
        "detail": "統合先の URL で、https://backend.internal.example.com:443/orders と書かれています。",
        "principle": "プライベート統合では、通信の実際の行き先は VPC リンクと integrationTarget（ALB）で決まり、uri は統合リクエストの Host ヘッダの"
                     "設定と、HTTPS の場合の証明書のドメイン名の照合に使われます（AWS 公式の説明）。https と書くことで、API Gateway と ALB の間も"
                     "暗号化されます（既定は HTTP）。",
        "image": "厨房への伝票に書く「宛名」です。配達は通路と振り分け係（VPC リンク・ALB）が行い、宛名は受け取り手の確認に使われます。",
        "history": "API Gateway の基本項目です。",
        "caution": "ALB のリスナー証明書が backend.internal.example.com を含んでいないと TLS エラーになります。また AWS の注意事項として、"
                   "プライベート統合ではステージ名を含むパスがバックエンドに送られる場合があるとされています。バックエンドに届くパスは ALB の"
                   "アクセスログで確認し、不要なら $context.requestOverride.path で上書きします。",
        "jmeter": "使用しません（JMeter の接続先は localhost:8080 など、試験したい相手を実行時に指定します）。",
    },
    {
        "no": "C-16", "path": PI + ["requestParameters"], "kind": AWS,
        "short": "厨房へ渡すとき、入館証に書かれた「クライアント ID」を X-Client-Id ヘッダに書き写して渡す指定です。",
        "detail": "統合リクエストのパラメータマッピングです。左側（integration.request.header.X-Client-Id）が統合先へ送るヘッダ、右側"
                  "（context.authorizer.claims.client_id）が値の出どころ（Cognito が検証したトークンの client_id）です。",
        "principle": "Cognito オーソライザーで検証済みのトークンの中身（クレーム）は context.authorizer.claims.* で参照できます。M2M 用の"
                     "アクセストークンには client_id（アプリクライアント ID）が入っているため、バックエンドは「どのシステムからの呼び出しか」を"
                     "安全に知ることができます。",
        "image": "受付係が入館証を確認したうえで、伝票に「依頼元：〇〇システム」と書き添えて厨房に渡すイメージです。厨房は入館証を"
                 "見直さなくても依頼元が分かります。",
        "history": "パラメータマッピングは API Gateway の初期からある機能です。",
        "caution": "クライアントが自分で X-Client-Id を付けて送っても、このマッピングの値が使われるため、なりすましを防げます"
                   "（API Gateway を通らずにバックエンドへ届く経路を塞いでおくことが前提です）。",
        "jmeter": "使用しません。バックエンド（localhost:8080）を直接試す場合 X-Client-Id は付かないので、バックエンドが必須とするなら"
                  "JMeter 側でヘッダを追加してください。",
    },
    {
        "no": "C-17", "path": PI + ["timeoutInMillis"], "kind": AWS,
        "short": "厨房の返事を最大 29 秒まで待つ、という設定です。",
        "detail": "統合タイムアウト（ミリ秒）で、50〜29000 の範囲、既定値も 29000（29秒）です。",
        "principle": "統合先から 29 秒以内に応答が無いと、API Gateway は待つのをやめて INTEGRATION_TIMEOUT（既定は 504）を返します"
                     "（このファイルでは B-20 のため 500 になります）。",
        "image": "「料理が 29 秒でできなければ、お客さんに『時間がかかりすぎました』と伝える」ルールです。",
        "history": "長い間 29 秒が上限でしたが、2024年6月4日から、リージョン API とプライベート API では Service Quotas で 29 秒より長くできる"
                   "ようになりました（アカウント全体のスロットリング上限が下がる場合があります）。生成 AI などの長い処理への対応です。",
        "caution": "29 秒は「API Gateway が待つ時間」で、バックエンドの処理自体は続いていることがあります。長い処理は、受付だけすぐ返して"
                   "結果は後で取りに行く「非同期」の形を検討してください。",
        "jmeter": "JMeter の応答タイムアウトは 60 秒（-JresponseTimeout で変更可）にして、API Gateway の 29 秒タイムアウトの応答を先に切らずに"
                  "受け取れるようにしています。",
    },
    {
        "no": "C-18", "path": PI + ["passthroughBehavior"], "kind": AWS,
        "short": "「変換ルール（テンプレート）に合う形式が無ければ、そのまま厨房に渡す」という指定です。",
        "detail": "マッピングテンプレートが無い（または一致しない）Content-Type の本文をどう扱うかの設定で、when_no_match・when_no_templates・"
                  "never の3種類があります。",
        "principle": "when_no_match は一致しない本文を変換せずに渡します。when_no_templates はテンプレートが1つでもあれば一致しないものを"
                     " 415 で拒否、never は常に拒否します。http_proxy 統合ではテンプレートを使わず本文はそのまま渡るため、この設定が"
                     "効く場面はほとんどありません。",
        "image": "「通訳係がいない言葉の手紙は、そのまま厨房に回す」ルールです。",
        "history": "非プロキシ統合で、想定外の Content-Type をどう扱うかを選べるように用意されました。",
        "caution": "非プロキシ統合では、AWS は when_no_templates を推奨しています（想定外の形式を 415 で止められるため）。",
        "jmeter": "使用しません。",
    },
    {
        "no": "C-19", "path": PI + ["responses"], "kind": AWS,
        "short": "厨房の返事をお客さんに返すときの変換ルール（既定：200番、X-Request-Id を書き写す）です。",
        "detail": "統合レスポンスの設定です。default は「どれにも当てはまらないとき」の規則で、statusCode 200 と、"
                  "method.response.header.X-Request-Id に integration.response.header.X-Request-Id（バックエンドの応答ヘッダ）を割り当てています。",
        "principle": "統合レスポンスは、非プロキシ統合でバックエンドの応答をメソッドレスポンスに変換する仕組みです。http_proxy 統合では"
                     "バックエンドの応答がそのまま返るため、この変換は基本的に使われません（バックエンドが X-Request-Id を返せば、そのまま届きます）。",
        "image": "厨房の料理を「お皿に盛り付け直すルール」ですが、プロキシ方式では料理をそのまま出すので、盛り付けルールの出番はありません。",
        "history": "非プロキシ統合の時代からある項目で、AWS の OpenAPI の例では、プロキシ統合にも default: 200 を書く形がよく見られます。",
        "caution": "プロキシ統合で応答を加工したい場合は、バックエンド側で対応するか、エラー時ならゲートウェイレスポンス（B-15〜B-21）を使います。",
        "jmeter": "使用しません。",
    },

    {"group": "D. POST /orders（注文の作成：createOrder）"},
    {
        "no": "D-1", "path": PP, "kind": STD, "value": "tags: [Orders] / operationId: createOrder / summary: 注文を作成する",
        "cover": [PP + ["tags"], PP + ["operationId"], PP + ["summary"]],
        "short": "「/orders に新しい注文を作る（POST）」操作の定義です。",
        "detail": "tags は Orders、operationId は createOrder、summary は「注文を作成する」です。GET と同じパスでも、メソッドが違えば別の操作になります。",
        "principle": "API Gateway では /orders リソースの POST メソッドになり、GET とは別に認可（スコープ）・検証・統合を設定できます。",
        "image": "同じ「注文コーナー」の中の「新規注文の窓口」です。",
        "history": "作成は POST・取得は GET という HTTP メソッドの使い分けは、REST の基本です。",
        "caution": "POST は同じ内容を2回送ると2件作られる（べき等ではない）ため、通信エラー時の再送で二重注文にならない工夫（冪等キーなど）が"
                   "バックエンドで必要です。",
        "jmeter": "サンプラー「02 POST /orders [createOrder]」を生成し、ボディにランダムな注文データを入れます。",
    },
    {
        "no": "D-2", "path": PP + ["security"], "kind": STD + "（AWS の Cognito と連動）",
        "short": "注文を作るには、入館証に「orders.write（注文を書く）」の許可が必要、という指定です。",
        "detail": "GET の orders.read とは別のスコープを求めています。",
        "principle": "C-7 と同じ仕組みで、トークンのスコープに orders.write が無ければ 401 になります。読むだけのシステムに書き込みをさせない"
                     "「最小権限」の実装です。",
        "image": "入館証に「記入室に入ってよい」と書かれた人だけが、注文を書けるイメージです。",
        "history": "C-7 と同じく、2017年12月の OAuth 2 スコープ対応によって実現できるようになりました。",
        "caution": "/{proxy+}（G-4）は orders.read だけで全メソッドを受け付けるため、プロキシ経由で書き込み系の処理ができてしまわないか"
                   "確認が必要です（06_レビュー所見を参照）。",
        "jmeter": "C-7 と同じです（無効化した Authorization ヘッダを用意）。",
    },
    {
        "no": "D-3", "path": PP + ["requestBody"], "kind": STD,
        "short": "注文を作るときに送る「注文票（本文）」の形の指定です。本文は必須です。",
        "detail": "required: true（本文が必須）で、application/json の本文は CreateOrderRequest スキーマ（I-13）に従うと定義しています。",
        "principle": "API Gateway では、メソッドリクエストのモデル（application/json → CreateOrderRequest）として登録され、B-6 のボディ検証に使われます。"
                     "Content-Type が application/json の本文がスキーマに合わなければ 400 になります。",
        "image": "新規注文の窓口では「決められた書式の注文票」を必ず出す決まりです。",
        "history": "Swagger 2.0 では in: body のパラメータで表していたものが、OpenAPI 3.0 で requestBody として独立し、メディアタイプ（JSON・XML など）"
                   "ごとに形を書けるようになりました。",
        "caution": "API Gateway のモデルは JSON Schema draft-04 形式のため、OpenAPI 3.0 独自のキーワード（nullable など）は検証で解釈されないことが"
                   "あります。また Content-Type を application/json 以外（text/plain など）で送ると、対応するモデルが無いため検証されずに通ってしまいます。",
        "jmeter": "CreateOrderRequest に従ったランダムな JSON（customerId は ^C[0-9]{8}$ に一致する値など）を「Body Data」に入れ、"
                  "Content-Type: application/json を付けて送ります。",
    },
    {
        "no": "D-4", "path": PP + ["responses"], "kind": STD, "value": "201: 作成成功（Order） / 400: リクエスト不正",
        "short": "作成に成功したら 201（作りました）、書き方が不正なら 400、という返事の約束です。",
        "detail": "201 の本文は Order スキーマ（作られた注文、I-1）です。",
        "principle": "201 Created は「新しいものを作った」ことを表す HTTP のステータスです。プロキシ統合なので、実際のステータスはバックエンドが決めます。",
        "image": "「ご注文を承りました（201）。こちらが注文内容の控えです」という返事です。",
        "history": "作成時に 200 ではなく 201 を返す作法は HTTP の仕様にもとづくもので、REST API の設計で広く推奨されています。",
        "caution": "バックエンドが 200 を返すと定義と食い違います。JMeter のテストで検出できます。",
        "jmeter": "「ステータスコード検証（201）」のアサーションを付けます。バックエンドが 200 を返した場合は NG として検出します。",
    },
    {
        "no": "D-5", "path": PP + ["x-amazon-apigateway-integration"], "kind": AWS, "value": "http_proxy / POST / VPC_LINK / ${stageVariables.vpcLinkV2Id} / internal-alb / https://backend.internal.example.com:443/orders / 29000ms / when_no_match / default → 201",
        "short": "注文の作成も、専用通路（VPC リンク V2）を通って ALB へそのまま渡します。",
        "detail": "GET /orders（C-10〜C-19）とほぼ同じで、httpMethod が POST、統合レスポンスの既定ステータスが 201、requestParameters"
                  "（X-Client-Id の書き写し）がありません。",
        "principle": "C-10〜C-19 と同じ仕組みです。",
        "image": "新規注文も、同じ関係者専用通路で厨房へ届けます。",
        "history": "C-10〜C-14 と同じです。",
        "caution": "POST には X-Client-Id のマッピングがありません。バックエンドで依頼元を記録する必要（監査ログなど）があるなら、GET と同じように"
                   "追加を検討してください。",
        "jmeter": "使用しません。",
    },

    {"group": "E. OPTIONS /orders（CORS のプリフライト）"},
    {
        "no": "E-1", "path": PO + ["summary"], "kind": STD,
        "short": "ブラウザが「この API を使っていいですか？」と事前に確かめるための窓口（CORS プリフライト）です。",
        "detail": "summary は「CORSプリフライト」です。認可（security）は無く、統合は mock（E-3）です。",
        "principle": "ブラウザは、別のドメインの API に独自ヘッダ（Authorization など）付きでリクエストするとき、先に OPTIONS メソッドで"
                     "「どのオリジン・メソッド・ヘッダなら許可されるか」を問い合わせます（プリフライト）。許可の返事が来てから本番のリクエストを送ります。",
        "image": "よその会社の人が入る前に、受付へ「こういう用事で入ってもいいですか？」と電話で確認するイメージです。",
        "history": "ブラウザの同一オリジンポリシー（よそのサイトのデータを勝手に読めない仕組み）を安全に緩めるため、CORS（Cross-Origin Resource "
                   "Sharing）が標準化されました（2014年に W3C 勧告、現在は WHATWG の Fetch 標準）。API Gateway は 2015年11月3日に CORS の有効化機能を追加しています。",
        "caution": "プリフライトは認証情報を付けずに送られるため、OPTIONS に認可を付けてはいけません（この定義は正しく付けていません）。"
                   "社内のシステム間（M2M）専用の API ならブラウザは使わないため、CORS 自体が不要な可能性があります。",
        "jmeter": "サンプラー「03 OPTIONS /orders」を生成します（ボディなし・期待 200）。",
    },
    {
        "no": "E-2", "path": PO + ["responses", "200"], "kind": STD,
        "short": "確認への返事に「許可するサイト・方法・ヘッダ」の3つを載せる、という約束です。",
        "detail": "Access-Control-Allow-Origin（許可するオリジン）・Access-Control-Allow-Methods（許可するメソッド）・"
                  "Access-Control-Allow-Headers（許可するリクエストヘッダ）の3つのヘッダを返し、本文（content）は空と定義しています。",
        "principle": "API Gateway ではメソッドレスポンスのヘッダとして登録され、E-5 の統合レスポンスで実際の値が入ります。非プロキシ（mock）統合では、"
                     "ここでヘッダを宣言しておかないと値を設定できません。",
        "image": "返事の用紙に「入ってよい会社名」「用事の種類」「持ち込んでよい物」の3つの欄を用意するイメージです。",
        "history": "CORS の標準のヘッダです。",
        "caution": "Access-Control-Max-Age（確認結果をブラウザが覚えておく秒数）を加えると、プリフライトの回数を減らせます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "E-3", "path": PO + ["x-amazon-apigateway-integration", "type"], "kind": AWS,
        "short": "厨房には聞かず、受付係がその場で返事をする方式です。",
        "detail": "mock 統合は、バックエンドを呼ばずに API Gateway の中で応答を作ります。",
        "principle": "requestTemplates（E-4）で決めた statusCode をもとに統合レスポンス（E-5・E-6）が選ばれ、ヘッダと本文が作られます。"
                     "バックエンドの負荷や遅延がありません。",
        "image": "「営業時間を教えて」という質問に、厨房に聞かず受付係がすぐに答えるイメージです。",
        "history": "2015年9月1日に追加されました。バックエンドを作る前の試作や、CORS の定型の応答によく使われます。",
        "caution": "mock でも API Gateway のリクエスト料金はかかります。",
        "jmeter": "サンプラーのコメントに「API Gateway 統合: type=mock」と記載します。localhost:8080 のバックエンドを直接呼ぶ場合、OPTIONS の結果は"
                  "バックエンドの実装しだいで変わります。",
    },
    {
        "no": "E-4", "path": PO + ["x-amazon-apigateway-integration", "requestTemplates"], "kind": AWS,
        "short": "受付係に「返事は 200 番にして」と指示するメモです。",
        "detail": "Content-Type が application/json のとき（Content-Type が無い場合も application/json とみなされます）に使うテンプレートで、"
                  '{"statusCode": 200} を作ります。',
        "principle": "mock 統合では、このテンプレートの statusCode が「統合レスポンスのどれを使うか」を選ぶ鍵になります。200 なので default"
                     "（statusCode 200）の設定が使われます。",
        "image": "受付係の手元のメモ「この質問には 200 番の定型の返事」です。",
        "history": "mock 統合の標準的な書き方で、API Gateway コンソールで CORS を有効にすると同じ設定が自動で作られます。",
        "caution": "プリフライトには Content-Type が付かないことが多いですが、その場合も application/json とみなされるため、このテンプレートが使われます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "E-5", "path": PO + ["x-amazon-apigateway-integration", "responses", "default", "responseParameters"], "kind": AWS,
        "cover": [PO + ["x-amazon-apigateway-integration", "responses", "default", "statusCode"],
                  PO + ["x-amazon-apigateway-integration", "responses", "default", "responseParameters"]],
        "short": "返事に載せる実際の値：許可するサイトは https://app.example.com、方法は GET・POST・OPTIONS、ヘッダは Content-Type と Authorization です。",
        "detail": "statusCode 200 の統合レスポンスで、Access-Control-Allow-Origin に 'https://app.example.com'、…-Methods に 'GET,POST,OPTIONS'、"
                  "…-Headers に 'Content-Type,Authorization' を固定値（シングルクォート）で設定しています。",
        "principle": "ブラウザは、自分のページのオリジン（https://app.example.com）が Allow-Origin と一致し、使いたいメソッドとヘッダが許可の一覧に"
                     "入っていれば、本番のリクエストを送ります。",
        "image": "「入ってよいのは app.example.com 社の人だけ」「用事は見る・注文・確認の3つ」「持ち込めるのは Content-Type と Authorization だけ」という返事です。",
        "history": "CORS の標準的な設定値です。",
        "caution": "【確認事項】許可するヘッダに X-Api-Key が入っていません。ブラウザから X-API-KEY ヘッダを付けて呼ぶと、プリフライトで拒否されます。"
                   "また CORS ヘッダは OPTIONS にしか付かないため、本番の GET・POST の応答にはバックエンドが Access-Control-Allow-Origin を付ける"
                   "必要があり、401・403 などのゲートウェイレスポンスにも付けないと、ブラウザはエラーの内容を読めません。",
        "jmeter": "使用しません（JMeter はブラウザではないため CORS の制約を受けません）。",
    },
    {
        "no": "E-6", "path": PO + ["x-amazon-apigateway-integration", "responses", "default", "responseTemplates"], "kind": AWS,
        "short": "返事の本文は空の JSON（{}）にする、という指定です。",
        "detail": "application/json の本文のテンプレートとして {} を返します。",
        "principle": "プリフライトでブラウザが見るのはヘッダだけなので、本文は空で十分です。",
        "image": "返事の用紙の本文欄は空欄で、欄外（ヘッダ）の記入だけで用が足りるイメージです。",
        "history": "E-4 と同じく、コンソールで CORS を有効にしたときに作られる標準の形です。",
        "caution": "特にありません。",
        "jmeter": "使用しません。",
    },

    {"group": "F. GET /orders/{orderId}（注文1件の取得：getOrder）"},
    {
        "no": "F-1", "path": PG + ["parameters", 0], "kind": STD,
        "short": "「どの注文か」を URL の中（/orders/ の後ろ）で指定する、必須の注文 ID（orderId）です。",
        "detail": "パスレベル（このパスの全メソッドに共通）のパラメータで、in: path、required: true、型は string です。{orderId} の部分に実際の ID が入ります。",
        "principle": "API Gateway では /orders の下の子リソース {orderId}（パス変数）になり、method.request.path.orderId として参照できます。"
                     "パスパラメータは OpenAPI の決まりで必ず required: true です。",
        "image": "「注文番号〇〇番について」の〇〇を URL に書き込む欄です。",
        "history": "パスの一部を変数にする書き方は、REST で「1つ1つのもの（リソース）」を指すための基本の形です。",
        "caution": "型が string だけで形式（pattern）の指定が無いため、どんな文字列でも受け付けます。注文 ID の形式が決まっているなら "
                   "pattern を書くと、検証とテストデータの生成に役立ちます。",
        "jmeter": "英数字 8〜16 文字の乱数を URL エンコードしてパスに埋め込みます（例：/orders/Xk29aB0q）。実在しない ID なので、実データで確認する"
                  "場合は値を書き換えてください。",
    },
    {
        "no": "F-2", "path": PG + ["get"], "kind": STD, "value": "tags: [Orders] / operationId: getOrder / security: orders.read / 200: Order / 404: 見つからない",
        "cover": [PG + ["get", "tags"], PG + ["get", "operationId"], PG + ["get", "security"], PG + ["get", "responses"]],
        "short": "注文を1件だけ取得する操作です。",
        "detail": "tags は Orders、operationId は getOrder、必要なスコープは orders.read、応答は 200（Order スキーマ）と 404（見つからない）です。"
                  "summary はありません。",
        "principle": "C-7 と同じ認可と、B-8 のバリデーター（必須のパスパラメータの存在確認）が適用されます。",
        "image": "「注文番号〇〇番の中身を見せて」という窓口です。",
        "history": "一覧（GET /orders）と個別（GET /orders/{id}）を分けるのは、REST の典型的な設計です。",
        "caution": "summary が無いため、ドキュメントの表示が不親切になります（C-4 を参照）。",
        "jmeter": "サンプラー「04 GET /orders/{orderId} [getOrder]」を生成し、期待コード 200 のアサーションと Accept: application/json を付けます。",
    },
    {
        "no": "F-3", "path": PG + ["get", "x-amazon-apigateway-integration"], "kind": AWS, "value": "http_proxy / GET / VPC_LINK / uri: …/orders/{orderId} / path.orderId ← method.request.path.orderId / default → 200",
        "short": "注文1件の取得も、専用通路を通って ALB の /orders/{orderId} へ渡します。",
        "detail": "uri の {orderId} には、requestParameters の integration.request.path.orderId ← method.request.path.orderId というマッピングで、"
                  "クライアントが指定した ID が入ります。timeoutInMillis と passthroughBehavior は書かれていません。",
        "principle": "パス変数のマッピングで、クライアントの /orders/ABC がバックエンドの /orders/ABC になります。書かれていない項目は既定値"
                     "（タイムアウト 29000 ミリ秒、passthroughBehavior は WHEN_NO_MATCH）になります。",
        "image": "伝票の「注文番号」欄を、そのまま厨房向けの伝票に書き写すイメージです。",
        "history": "C-10〜C-16 と同じです。",
        "caution": "ほかのメソッドと書き方をそろえるため、timeoutInMillis と passthroughBehavior も明記しておくと、設定漏れや既定値の変化に強くなります。",
        "jmeter": "使用しません。",
    },

    {"group": "G. /{proxy+}（その他すべてのパスを受け止めるプロキシ）"},
    {
        "no": "G-1", "path": PX, "kind": STD + "＋AWS の貪欲パス", "container": True, "value": "x-amazon-apigateway-any-method のみ",
        "short": "ほかのどのパスにも当てはまらないリクエストを、すべて受け止める「なんでも受付」のパスです。",
        "detail": "{proxy+} は「貪欲な（greedy）パス変数」で、/ 以下の何階層ものパス（例：/a/b/c）をまとめて1つの変数 proxy として受け取ります。",
        "principle": "API Gateway は、より具体的に定義されたパス（/orders、/orders/{orderId}）を優先し、どれにも当てはまらないパスを /{proxy+} で"
                     "受け付けます。受けたパスは G-6 のマッピングでバックエンドの同じパスへ転送されます。",
        "image": "「その他のご用件はこちら」と書かれた総合窓口です。専門の窓口が無い用事は、全部ここに来ます。",
        "history": "2016年9月20日に、ANY メソッドとプロキシ統合と一緒に追加されました。パスを1つずつ定義する手間がなくなり、既存の Web アプリを"
                   "まるごと API Gateway の後ろに置けるようになりました。",
        "caution": "便利な反面、意図しないパス（管理画面や内部用の API など）までバックエンドへ通してしまう危険があります（06_レビュー所見を参照）。",
        "jmeter": "サンプラー「05 ANY(GET) /{proxy+} [proxyAll]」を生成し、proxy に英数字の乱数を入れます（例：/Z9vQ3k34）。",
    },
    {
        "no": "G-2", "path": PXA + ["operationId"], "kind": AWS + "（ANY メソッド）",
        "short": "「どの HTTP メソッド（GET・POST・PUT・DELETE…）でも受け付ける」という指定です（操作名は proxyAll）。",
        "detail": "OpenAPI の標準には「すべてのメソッド」を表す書き方が無いため、AWS 独自の拡張キー x-amazon-apigateway-any-method で ANY メソッドを"
                  "定義しています。",
        "principle": "API Gateway の ANY メソッドとして登録され、GET・POST・PUT・PATCH・DELETE・HEAD・OPTIONS のすべてが同じ設定（認可・統合）で処理されます。",
        "image": "総合窓口では「見る」「頼む」「変える」「取り消す」のどの用事でも受け付けるイメージです。",
        "history": "G-1 と同じく 2016年9月20日に追加されました。",
        "caution": "同じパスに具体的なメソッド（例：OPTIONS）を別に定義すると、そちらが優先されます。",
        "jmeter": "ANY は実際の HTTP メソッドではないため、既定では GET を代表として送ります（生成時に --any-method／-AnyMethod で変更可。"
                  "DELETE のような影響の大きいメソッドは既定にしていません）。",
    },
    {
        "no": "G-3", "path": PXA + ["parameters", 0], "kind": STD,
        "short": "総合窓口で受け取った「残りのパス全部」を入れる変数 proxy の定義です。",
        "detail": "in: path、required: true、型は string です。{proxy+} の + は変数名に含まれず、変数名は proxy です。",
        "principle": "例えば /reports/2026/09 というリクエストなら、proxy = reports/2026/09 になります。",
        "image": "総合窓口の受付票の「ご用件の宛先」欄です。",
        "history": "G-1 と同じです。",
        "caution": "値に / が含まれる点が、普通のパス変数と違います。",
        "jmeter": "英数字の乱数を入れます（/ を含むパスで試したい場合は、サンプラーのパスを書き換えてください）。",
    },
    {
        "no": "G-4", "path": PXA + ["security"], "kind": STD + "（AWS の Cognito と連動）",
        "short": "総合窓口も、orders.read の許可があれば使える、という指定です。",
        "detail": "ANY メソッドなので、GET だけでなく POST・PUT・DELETE も orders.read のトークンで通ります。",
        "principle": "認可は「メソッドごと」に設定されるため、ANY に付けたスコープがすべてのメソッドに適用されます。",
        "image": "閲覧室の入館証だけで、総合窓口からは記入や取り消しの用事まで頼めてしまうイメージです。",
        "history": "C-7 と同じです。",
        "caution": "【要確認】読み取りの権限だけで、書き込み系の操作がバックエンドに届く設計です。バックエンド側で書き込みを拒否しているか、"
                   "プロキシで受ける必要がある操作だけに絞れないかを確認してください（06_レビュー所見を参照）。",
        "jmeter": "C-7 と同じです。",
    },
    {
        "no": "G-5", "path": PXA + ["responses"], "kind": STD,
        "short": "総合窓口の成功の返事は 200 番、という最小限の約束です。",
        "detail": "200 の説明（成功）だけで、本文の形は定義していません。",
        "principle": "プロキシ統合なので、実際にはバックエンドが返したステータスと本文がそのまま返ります。",
        "image": "「なんでも窓口」なので、返事の形は用件しだいです。",
        "history": "OpenAPI 3.0.3 では responses に少なくとも1つの応答コードを書く決まりがあるため、書かれています。",
        "caution": "実際には 201・204・404 なども返ることがあります。",
        "jmeter": "「ステータスコード検証（200）」を付けます。localhost:8080 のバックエンドにそのパスが無ければ 404 になり、NG として検出されます"
                  "（ランダムなパスなので、実在するパスに書き換えて確認してください）。",
    },
    {
        "no": "G-6", "path": PXA + ["x-amazon-apigateway-integration"], "kind": AWS, "value": "http_proxy / ANY / VPC_LINK / uri: https://backend.internal.example.com:443/{proxy} / path.proxy ← method.request.path.proxy / when_no_match / default → 200",
        "short": "総合窓口の用件は、同じメソッド・同じパスのまま ALB へ転送します。",
        "detail": "httpMethod は ANY（クライアントのメソッドをそのまま使う）、uri は https://backend.internal.example.com:443/{proxy}、requestParameters で "
                  "integration.request.path.proxy ← method.request.path.proxy をマッピングしています。",
        "principle": "ANY と {proxy+} と http_proxy の組み合わせは、API Gateway を「リバースプロキシ（中継役）」として使う定番の構成です。",
        "image": "総合窓口に来た用件を、宛先を書き換えずにそのまま厨房へ回すイメージです。",
        "history": "G-1 と同じです。",
        "caution": "C-15 と同じ注意（証明書・ステージ名を含むパス）があります。timeoutInMillis が書かれていないので、既定の 29 秒になります。",
        "jmeter": "使用しません。",
    },

    {"group": "H. components › securitySchemes › CognitoM2M（認可の方式）"},
    {
        "no": "H-1", "path": CS, "kind": STD + "＋AWS の書き方", "value": "type: apiKey / name: Authorization / in: header",
        "cover": [CS + ["type"], CS + ["name"], CS + ["in"]],
        "short": "入館証（トークン）を Authorization ヘッダに入れて持ってくる、という決まりです。",
        "detail": "securitySchemes で認可の方式を定義しています。type: apiKey・name: Authorization・in: header は「Authorization という名前の"
                  "ヘッダで値を送る」という意味です。",
        "principle": "API Gateway の Cognito オーソライザーは、OpenAPI 上は type: apiKey（ヘッダで送る値）として書き、実体を AWS 拡張（H-2・H-3）で"
                     "定義するのが AWS の決まった書き方です。API Gateway は Authorization ヘッダのトークンを取り出して検証します。",
        "image": "「入館証はカードケース（Authorization）に入れて見せてください」という決まりです。",
        "history": "OpenAPI 2.0 の時代から API Gateway はこの書き方を使っており、3.0 でも同じ形です（OpenAPI 標準の type: oauth2 や http bearer は、"
                   "HTTP API の JWT オーソライザーなどで使われます）。",
        "caution": "OpenAPI の type: apiKey という名前ですが、API Gateway の「API キー（B-5）」とは関係ありません。名前が紛らわしいので注意してください。",
        "jmeter": "認可の方式が定義されているため、無効化した Authorization ヘッダ（値は ${AUTH_TOKEN}＝-JauthToken で指定）を生成します。",
    },
    {
        "no": "H-2", "path": CS + ["x-amazon-apigateway-authtype"], "kind": AWS,
        "short": "認可の種類が「Cognito ユーザープール」であることを示す印です。",
        "detail": "API Gateway 用の拡張で、オーソライザーの種類（authType）を表します。",
        "principle": "CreateAuthorizer API の説明では、authType は「OpenAPI のインポート・エクスポートで使われる任意の項目で、動作には影響しない」と"
                     "されています。実際の種類は H-3 の type で決まります。",
        "image": "入館証の種類を示すラベル「Cognito 発行」です。",
        "history": "API Gateway の OpenAPI 拡張として初期からあります。",
        "caution": "H-3 の type と値をそろえてください。",
        "jmeter": "使用しません。",
    },
    {
        "no": "H-3", "path": AU + ["type"], "kind": AWS,
        "short": "入館証の確認を Amazon Cognito（ユーザープール）に任せる、という指定です。",
        "detail": "x-amazon-apigateway-authorizer がオーソライザーの実体で、type に cognito_user_pools を指定しています"
                  "（ほかに token・request＝Lambda オーソライザーがあります）。",
        "principle": "API Gateway は、Cognito ユーザープールの公開鍵でトークン（JWT）の署名・有効期限・発行元などを検証します。Lambda のプログラムを"
                     "書かずに認証・認可を実現できます。",
        "image": "入館証が本物かどうかを、発行元の Cognito 事務所の印鑑（署名）と照らし合わせて確かめるイメージです。",
        "history": "Cognito ユーザープールによるメソッドの認可は 2016年7月28日に追加され、2018年4月2日には別アカウントのユーザープールも使えるようになりました。",
        "caution": "1つの COGNITO_USER_POOLS オーソライザーには、最大 1,000 個のユーザープールを登録できます。",
        "jmeter": "使用しません。",
    },
    {
        "no": "H-4", "path": AU + ["providerARNs"], "kind": AWS,
        "short": "入館証を発行している Cognito ユーザープールの「住所（ARN）」です。",
        "detail": "検証に使うユーザープールを ARN で指定します（ap-northeast-1_ABC123 は説明用の例です）。",
        "principle": "API Gateway は、ここに書かれたユーザープールが発行したトークンだけを受け入れます。",
        "image": "「この事務所（ユーザープール）が発行した入館証だけ有効」という指定です。",
        "history": "H-3 と同じです。",
        "caution": "ユーザープールはステージ変数でも指定できます（…:userpool/${stageVariables.MyUserPool}）。環境ごとにプールが違う場合に便利です。",
        "jmeter": "使用しません。",
    },
    {
        "no": "H-5", "path": AU + ["identitySource"], "kind": AWS,
        "short": "入館証を「リクエストの Authorization ヘッダ」から取り出す、という指定です。",
        "detail": "トークンの取り出し元を method.request.header.{ヘッダ名} の形で指定します。",
        "principle": "CreateAuthorizer API の説明では、COGNITO_USER_POOLS オーソライザーでは必須で、トークンを入れるヘッダを表すとされています。"
                     "一方、OpenAPI 拡張の説明では identitySource は request・jwt 型向けとされ、Cognito ではセキュリティスキームの name（H-1 の "
                     "Authorization）が使われます。どちらも Authorization なので矛盾はありません。",
        "image": "「入館証はカードケース（Authorization）から取り出して確認する」という手順です。",
        "history": "H-3 と同じです。",
        "caution": "H-1 の name と必ず一致させてください。",
        "jmeter": "使用しません（生成する Authorization ヘッダはこのヘッダ名に合わせています）。",
    },
    {
        "no": "H-6", "path": AU + ["authorizerResultTtlInSeconds"], "kind": AWS,
        "short": "入館証の確認結果を 300 秒（5分）覚えておく、という設定です。",
        "detail": "オーソライザーの結果をキャッシュする秒数です。API の仕様では、既定 300 秒・最大 3600 秒（1時間）・0 でキャッシュ無効です。",
        "principle": "キャッシュが有効だと、同じトークンで続けて呼ばれたときに検証結果を使い回し、処理を速くできます。",
        "image": "一度確認した入館証の人は、5分間は顔パスで通すイメージです。",
        "history": "オーソライザーの結果のキャッシュは、Lambda オーソライザー（2016年2月11日追加）の呼び出し回数と遅延を減らすために取り入れられた仕組みです。",
        "caution": "API Gateway の拡張リファレンスでも CreateAuthorizer の説明でも Cognito 型への適用は否定されていませんが、コンソールの Cognito"
                   "オーソライザーの画面にはキャッシュの設定が表示されません。トークンを取り消した直後の動きが重要な場合は、実際の環境で確認してください。",
        "jmeter": "使用しません。",
    },

    {"group": "I. components › schemas（データの形＝注文票の書式）"},
    {
        "no": "I-1", "path": SC + ["Order"], "kind": JS, "value": "type: object / required: orderId, customerId, status, items",
        "cover": [SC + ["Order", "type"], SC + ["Order", "required"]],
        "short": "「注文」データの形（書式）の定義です。",
        "detail": "type: object（項目の集まり）で、orderId・customerId・status・items の4つが必須（required）です。totalAmount と createdAt は任意です。",
        "principle": "components.schemas は、データの形に名前を付けて定義し、$ref（例：#/components/schemas/Order）で何度でも参照できるようにする場所です。"
                     "API Gateway にインポートすると「モデル」（JSON Schema draft-04 形式）として登録され、検証（B-6）とドキュメントに使われます。",
        "image": "「注文カード」の書式見本です。必ず書く欄（注文番号・お客様番号・状態・品目）と、書かなくてもよい欄（合計金額・作成日時）があります。",
        "history": "OpenAPI 3.0 で、2.0 の definitions から components.schemas に移りました。スキーマの書き方は JSON Schema を土台にした OpenAPI 独自の"
                   "部分集合で、3.1 以降は JSON Schema 2020-12 と完全に互換になりました。",
        "caution": "Order は応答（GET の結果、POST の結果）で使われる形です。additionalProperties の指定が無いため、定義外の項目が付いていても許されます。",
        "jmeter": "応答用のスキーマなので、リクエストデータの生成には使いません（応答の中身の検証も行いません）。",
    },
    {
        "no": "I-2", "path": SC + ["Order", "properties", "orderId"], "kind": JS,
        "short": "注文番号（文字列）です。",
        "detail": "type: string（文字列）で、形式の指定はありません。",
        "principle": "F-1 のパスパラメータ orderId と同じ意味の値です。",
        "image": "注文カードの「注文番号」欄です。",
        "history": "JSON Schema の基本の書き方です。",
        "caution": "形式（桁数・文字の種類）を pattern で決めておくと、パスパラメータの検証やテストデータの生成に役立ちます。",
        "jmeter": "使用しません（応答用）。",
    },
    {
        "no": "I-3", "path": SC + ["Order", "properties", "customerId"], "kind": JS,
        "short": "お客様番号です。「C」の後に数字が8つ（例：C12345678）という形が決まっています。",
        "detail": "type: string、pattern: ^C[0-9]{8}$ です。^ は先頭、$ は末尾、[0-9]{8} は「数字がちょうど8個」を表す正規表現です。",
        "principle": "検証ツールや API Gateway のモデル検証は、この形に合わない値（例：C123、X12345678）を不正と判断します。OpenAPI の pattern は"
                     "ECMA-262（JavaScript）の正規表現の書き方です。",
        "image": "「お客様番号は C で始まり、その後ろに数字を8つ書く」という書き方のルールです。",
        "history": "正規表現による文字列の形のチェックは、JSON Schema の初期からあります。",
        "caution": "pattern は「一部に一致すればよい」で評価されるため、完全に一致させたい場合はこの例のように ^ と $ を付けます。",
        "jmeter": "（CreateOrderRequest の同じ pattern を使って）C＋数字8桁の値を自動で作ります（例：C05558498）。",
    },
    {
        "no": "I-4", "path": SC + ["Order", "properties", "status"], "kind": JS,
        "short": "注文の状態です。NEW・PAID・SHIPPED・CANCELLED の4つのどれかです。",
        "detail": "type: string、enum: [NEW, PAID, SHIPPED, CANCELLED]。この4つ以外は不正です。",
        "principle": "enum は「選択肢」を固定する仕組みで、検証・コード生成（列挙型）・ドキュメントの選択肢表示に使われます。",
        "image": "状態の欄は「新規・支払済・発送済・取消」の4つから選んで丸を付ける形式です。",
        "history": "JSON Schema の基本のキーワードです。",
        "caution": "あとから選択肢を増やすと、古いクライアントが知らない値を受け取って困ることがあります（互換性に注意）。",
        "jmeter": "使用しません（応答用）。リクエスト側に enum があれば、その中からランダムに選びます。",
    },
    {
        "no": "I-5", "path": SC + ["Order", "properties", "totalAmount"], "kind": JS,
        "short": "合計金額です。0以上で、0.01刻み（小数第2位まで）の数です。",
        "detail": "type: number（小数を含む数）、minimum: 0（0以上）、multipleOf: 0.01（0.01の倍数）です。",
        "principle": "multipleOf は「その数で割り切れること」を求めるキーワードで、0.01 なら小数第2位までに制限できます。",
        "image": "金額欄は「0円以上、1銭単位まで」という書き方のルールです。",
        "history": "JSON Schema の数値の制約キーワードです。",
        "caution": "小数の multipleOf は、コンピューターの2進数の小数の誤差のせいで、正しい値でも一部の検証ツールが「不合格」と判定してしまうことが"
                   "あります。金額を整数（円・銭などの最小単位）で持つ設計も検討してください。",
        "jmeter": "使用しません（応答用）。リクエスト側の数値は、本ツールが10進数で正確に計算するため、誤差なく multipleOf を満たします。",
    },
    {
        "no": "I-6", "path": SC + ["Order", "properties", "items"], "kind": JS,
        "short": "注文の品目リストです。1件1件の形は OrderItem（I-8）で決まっています。",
        "detail": "type: array（並び）で、items は $ref: #/components/schemas/OrderItem です。",
        "principle": "$ref は「別の場所の定義を参照する」仕組みで、同じ形を何度も書かずに済みます。API Gateway にインポートすると、モデル同士の参照に変換されます。",
        "image": "注文カードの「品目」欄は、品目カード（OrderItem）を何枚も綴じる形式です。",
        "history": "$ref は JSON Reference（IETF の草案）に由来し、Swagger の初期から使われています。",
        "caution": "件数の下限（minItems）が無いため、空の配列（品目 0 件の注文）も形としては正しくなります。",
        "jmeter": "使用しません（応答用）。",
    },
    {
        "no": "I-7", "path": SC + ["Order", "properties", "createdAt"], "kind": JS,
        "short": "注文を作った日時です。「2026-09-26T10:30:00Z」のような決まった形で書きます。",
        "detail": "type: string、format: date-time（RFC 3339 の日時の形式）です。",
        "principle": "format は値の意味（日時・メール・UUID など）を表す注釈です。JSON Schema では format の検査は任意（実装しだい）とされています。",
        "image": "作成日時の欄は「年-月-日T時:分:秒＋時差」で書くルールです。",
        "history": "RFC 3339（2002年）は、インターネットで日時をやりとりするための形式です。",
        "caution": "時差（Z は協定世界時、+09:00 は日本時間）を必ず付ける運用にすると、時刻のずれを防げます。",
        "jmeter": "使用しません（応答用）。リクエスト側の date-time は、2025〜2026年のランダムな UTC 日時（例：2026-03-14T08:21:45Z）を作ります。",
    },
    {
        "no": "I-8", "path": SC + ["OrderItem"], "kind": JS, "value": "type: object / additionalProperties: false / required: sku, qty",
        "cover": [SC + ["OrderItem", "type"], SC + ["OrderItem", "additionalProperties"], SC + ["OrderItem", "required"]],
        "short": "品目1件の形です。品番（sku）と数量（qty）が必須で、決められた項目以外は書けません。",
        "detail": "type: object、required: [sku, qty]、additionalProperties: false（定義に無い項目は禁止）です。",
        "principle": 'additionalProperties: false のため、例えば {"sku":"A1","qty":1,"memo":"x"} は memo があるので不正になります。ボディ検証（B-6）が'
                     "有効なので、API Gateway が 400 で止めます。",
        "image": "品目カードには「品番・数量・単価」以外の欄が無く、余白に書き込むと受け付けてもらえないイメージです。",
        "history": "送り手の打ち間違い（qtty など）に早く気付けるよう、厳しい検査を選べるキーワードとして使われています。",
        "caution": "厳しい検査は安全ですが、クライアントが新しい項目を送れるようにしたいとき（前方互換）に困ります。API のバージョン管理の方針と"
                   "あわせて決めてください。",
        "jmeter": "定義された項目（sku・qty・unitPrice）だけを作り、余計な項目は付けません。",
    },
    {
        "no": "I-9", "path": SC + ["OrderItem", "properties", "sku"], "kind": JS,
        "short": "品番です。32文字までの文字列です。",
        "detail": "type: string、maxLength: 32 です。",
        "principle": "JSON Schema では文字数を Unicode の文字（コードポイント）単位で数えます。",
        "image": "品番の欄は32マスまで、という書き方のルールです。",
        "history": "JSON Schema の基本のキーワードです。",
        "caution": '下限（minLength）が無いので、空の文字列（""）も形としては正しくなります。必要なら minLength: 1 を付けます。',
        "jmeter": "8〜16文字（32 を超えない範囲）の英数字をランダムに作ります。",
    },
    {
        "no": "I-10", "path": SC + ["OrderItem", "properties", "qty"], "kind": JS,
        "short": "数量です。1以上999以下の整数です。",
        "detail": "type: integer、minimum: 1、maximum: 999 です。",
        "principle": "integer は小数点を含まない数です。範囲外（0 や 1000）はボディ検証で 400 になります。",
        "image": "数量の欄は「1個〜999個」まで、という書き方のルールです。",
        "history": "JSON Schema の基本のキーワードです。",
        "caution": "format（int32 など）の指定はありませんが、範囲が決まっているので問題ありません。",
        "jmeter": "1〜999 の範囲でランダムな整数を作ります（例：355）。",
    },
    {
        "no": "I-11", "path": SC + ["OrderItem", "properties", "unitPrice"], "kind": JS,
        "short": "単価です。0以上の数です（書かなくてもよい項目）。",
        "detail": "type: number、minimum: 0 です。小数の桁数の指定はありません。",
        "principle": "必須ではないので、省略しても正しい品目です。",
        "image": "単価の欄は書かなくてもよく、書くなら0円以上です。",
        "history": "JSON Schema の基本のキーワードです。",
        "caution": "totalAmount（I-5）と違って multipleOf が無いため、0.001 のような値も形としては正しくなります。金額の桁のルールは統一すると安全です。",
        "jmeter": "小数第2位までの数を、0.00〜99.00 の範囲でランダムに作ります（上限の指定が無い数値の既定の範囲）。",
    },
    {
        "no": "I-12", "path": SC + ["OrderList"], "kind": JS, "value": "type: object / required: items / items: Order の配列 / nextCursor: string",
        "short": "注文一覧の返事の形です。注文（Order）の並びと、続きを取るための目印（nextCursor）が入ります。",
        "detail": "type: object、required: [items]、items は Order の配列、nextCursor は任意の文字列です。",
        "principle": "クライアントは nextCursor があれば次の要求の cursor（C-6）に渡して続きを取り、無ければ最後のページと判断します。",
        "image": "一覧表の最後に「続きは しおり〇〇 から」と書かれているイメージです。",
        "history": "C-6 と同じく、カーソル方式のページングの定番の形です。",
        "caution": "特にありません。",
        "jmeter": "使用しません（応答用）。",
    },
    {
        "no": "I-13", "path": SC + ["CreateOrderRequest"], "kind": JS, "value": "type: object / additionalProperties: false / required: customerId, items / customerId: ^C[0-9]{8}$ / items: OrderItem の配列",
        "short": "注文を作るときに送る注文票の形です。お客様番号と品目リストが必須で、それ以外は書けません。",
        "detail": "type: object、additionalProperties: false、required: [customerId, items] です。customerId は pattern ^C[0-9]{8}$、items は OrderItem の配列です。",
        "principle": "POST /orders の requestBody（D-3）から参照され、API Gateway ではリクエストのモデルとして登録されます。ボディ検証（B-6）で、"
                     "必須項目の抜け・形の間違い・余計な項目を 400 で止めます。",
        "image": "新規注文用の注文票の見本です。「お客様番号（C＋8桁）」と「品目カード」を必ず付けて、ほかには何も書かないルールです。",
        "history": "リクエスト用とレスポンス用のスキーマを分ける（orderId や status はサーバーが決めるので送らせない）のは、API 設計の定石です。",
        "caution": 'items に minItems が無いため、品目 0 件（"items": []）でも検証を通ります。業務上1件以上が必要なら minItems: 1 を付けてください。',
        "jmeter": "この形に従い、customerId（C＋数字8桁）と品目1件（sku・qty・unitPrice）のランダムな JSON を作ります。作ったデータがこの定義を"
                  "満たすことは、模擬サーバーで受信したボディを検証して確認済みです。",
    },
]
