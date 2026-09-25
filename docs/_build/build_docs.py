# -*- coding: utf-8 -*-
"""
OpenAPI 定義の解説資料（Excel: Meiryo UI・モノトーン / Markdown）を生成します。

  python docs/_build/build_docs.py

・04_項目別詳細解説 の「設定値」は OpenAPI 定義ファイルから自動で読み取ります。
・定義ファイルのすべての設定（末端の値）が、いずれかの解説項目で説明されているかを検査し、
  説明漏れ・存在しないパスがあればエラーで終了します（書き漏れ防止）。
"""
import hashlib
import json
import os
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import content_items  # noqa: E402
import content_misc  # noqa: E402
import render_docs  # noqa: E402

SPEC = os.path.join(ROOT, "openapi", "orders-api.openapi.json")
SOURCE = r"C:\Users\taka_\Claude\APIGateway_OpenAPI_List\03_sample_openapi_3.0.3_restapi.json"
OUT_DIR = os.path.join(ROOT, "docs")
BASENAME = "OrdersApi_OpenAPI定義_完全解説"
BOOK_TITLE = "OrdersApi OpenAPI 3.0.3 定義ファイル 完全解説 ― API Gateway の設定を動作原理・歴史から小学生にもわかるように"
SUBJECT = "対象: openapi/orders-api.openapi.json（OpenAPI 3.0.3 / Amazon API Gateway REST API）｜情報の基準日: 2026年9月26日｜JMeter 5.6.3 シナリオ自動生成ツールとの対応付き"


def path_text(path):
    out = []
    for p in path:
        out.append("[{}]".format(p) if isinstance(p, int) else str(p))
    return " › ".join(out)


def get_at(doc, path):
    cur = doc
    for p in path:
        if isinstance(p, int):
            if not isinstance(cur, list) or p >= len(cur):
                raise KeyError(path_text(path))
            cur = cur[p]
        else:
            if not isinstance(cur, dict) or p not in cur:
                raise KeyError(path_text(path))
            cur = cur[p]
    return cur


def value_text(v, limit=600):
    if isinstance(v, (dict, list)):
        s = json.dumps(v, ensure_ascii=False, separators=(", ", ": "))
    else:
        s = json.dumps(v, ensure_ascii=False)
    return s if len(s) <= limit else s[:limit] + " …（以下略）"


def leaves(node, prefix=()):
    """末端（値・空のオブジェクト・空の配列）のパスを列挙"""
    if isinstance(node, dict):
        if not node:
            yield prefix
        for k, v in node.items():
            yield from leaves(v, prefix + (k,))
    elif isinstance(node, list):
        if not node:
            yield prefix
        for i, v in enumerate(node):
            yield from leaves(v, prefix + (i,))
    else:
        yield prefix


def main():
    with open(SPEC, "rb") as f:
        raw = f.read()
    doc = json.loads(raw.decode("utf-8"), object_pairs_hook=OrderedDict)
    sha = hashlib.sha256(raw).hexdigest()

    # ---- 解説項目の組み立てと検査
    rows = []
    errors = []
    covers = []
    for it in content_items.ITEMS:
        if "group" in it:
            rows.append({"group": it["group"]})
            continue
        try:
            v = get_at(doc, it["path"])
        except KeyError as e:
            errors.append("存在しないパス: {} ({})".format(it["no"], e))
            continue
        r = dict(it)
        r["path"] = path_text(it["path"])
        r["value"] = it.get("value") or value_text(v)
        rows.append(r)
        if not it.get("container"):
            for c in it.get("cover", [it["path"]]):
                try:
                    get_at(doc, c)
                except KeyError as e:
                    errors.append("存在しない cover パス: {} ({})".format(it["no"], e))
                covers.append(tuple(c))
    uncovered = []
    for lf in leaves(doc):
        if not any(lf[:len(c)] == c for c in covers):
            uncovered.append(path_text(list(lf)))
    if uncovered:
        errors.append("説明されていない設定があります:\n  " + "\n  ".join(uncovered))
    if errors:
        for e in errors:
            print("[ERROR] " + e)
        return 1

    n_items = sum(1 for r in rows if "group" not in r)
    n_leaves = sum(1 for _ in leaves(doc))

    # ---- API 一覧（全体像シート）
    ops_rows = [
        ["01", "GET", "/orders", "listOrders", "注文の一覧を取得する（limit・cursor で件数と続きを指定）",
         "orders.read", "http_proxy（VPC リンク V2 → ALB）", "200"],
        ["02", "POST", "/orders", "createOrder", "注文を作成する（本文 CreateOrderRequest）", "orders.write",
         "http_proxy（VPC リンク V2 → ALB）", "201"],
        ["03", "OPTIONS", "/orders", "（なし）", "CORS のプリフライト（ブラウザの事前確認）", "なし",
         "mock（API Gateway がその場で応答）", "200"],
        ["04", "GET", "/orders/{orderId}", "getOrder", "注文を1件取得する", "orders.read",
         "http_proxy（VPC リンク V2 → ALB）", "200"],
        ["05", "ANY", "/{proxy+}", "proxyAll", "上記以外のすべてのパス・メソッドをバックエンドへ転送", "orders.read",
         "http_proxy（ANY・VPC リンク V2 → ALB）", "200"],
    ]
    info = {
        "file_name": os.path.basename(SPEC),
        "file_path": "openapi/" + os.path.basename(SPEC) + "（このリポジトリ内）",
        "source_path": SOURCE + "（同一内容のコピー）",
        "sha256": sha,
        "size": "{:,} バイト".format(len(raw)),
        "openapi": doc["openapi"],
        "title": doc["info"]["title"],
        "version": doc["info"]["version"],
        "op_summary": "5 つ（GET /orders、POST /orders、OPTIONS /orders、GET /orders/{orderId}、ANY /{proxy+}）",
        "item_count": "{} 項目（ファイル内の末端の設定 {} 個をすべて網羅していることを自動で検査済み）".format(n_items, n_leaves),
    }

    item_cols = ["No.", "区分", "JSON パス", "設定値", "ひとことで（小学生向け）", "詳しい意味", "動作原理（中で何が起きるか）",
                 "動作イメージ（たとえ話）", "登場の歴史・背景・必要になった経緯", "注意点・最新情報（2026年9月時点）", "JMeter シナリオでの扱い"]
    item_keys = ["no", "kind", "path", "value", "short", "detail", "principle", "image", "history", "caution", "jmeter"]
    sheets = [
        content_misc.sheet_intro(info),
        content_misc.sheet_overview(ops_rows),
        content_misc.sheet_history(),
        {
            "name": "04_項目別詳細解説", "title": "項目別詳細解説（ファイル内のすべての設定を1つずつ）",
            "widths": [7, 16, 30, 28, 30, 44, 48, 36, 44, 46, 36],
            "zoom": 90, "paper": 8,
            "blocks": [("items", item_cols, rows, item_keys)],
        },
        content_misc.sheet_flow(),
        content_misc.sheet_review(),
        content_misc.sheet_jmeter(),
        content_misc.sheet_glossary(),
        content_misc.sheet_refs(),
    ]
    xlsx = render_docs.build_xlsx(sheets, os.path.join(OUT_DIR, BASENAME + ".xlsx"), BOOK_TITLE, SUBJECT)
    lead = "> " + SUBJECT
    md = render_docs.build_md(sheets, os.path.join(OUT_DIR, BASENAME + ".md"), BOOK_TITLE, lead)
    print("[INFO] 解説項目 {} 件 / 末端の設定 {} 個をすべて網羅".format(n_items, n_leaves))
    print("[INFO] 出力: " + xlsx)
    print("[INFO] 出力: " + md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
