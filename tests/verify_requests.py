#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成した JMX が送ったリクエストを OpenAPI 定義と突き合わせて検証します（Python 3.6 以降・標準ライブラリのみ）。

mock_api_server.py が記録した requests.jsonl を読み、次を確認します。
  1. OpenAPI に定義された全オペレーションが呼ばれたか（網羅性）
  2. X-API-KEY ヘッダが期待値どおり付いているか
  3. パス / クエリ / ヘッダ パラメータが定義の型・制約を満たすか（必須の有無を含む）
  4. リクエストボディが Content-Type どおりで、スキーマ（型・required・pattern・
     enum・最小/最大・桁・additionalProperties・format など）を満たすか
  5. Accept ヘッダが定義の応答メディアタイプと一致するか

使い方:
  python3 verify_requests.py --spec openapi.json --requests requests.jsonl [--api-key XXXXXXXXXXXX]
終了コード: 0=すべて合格 / 1=不合格あり / 2=入力エラー
"""
import argparse
import json
import re
import sys
from collections import OrderedDict
from decimal import Decimal

METHODS = ('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
ANY_KEY = 'x-amazon-apigateway-any-method'


def load_json_text(text):
    return json.loads(text, object_pairs_hook=OrderedDict, parse_float=Decimal)


def resolve(doc, obj, depth=0):
    """ローカル $ref を辿る。解決できない参照は None（＝検査対象外）を返す"""
    while isinstance(obj, dict) and '$ref' in obj and depth < 50:
        ref = obj['$ref']
        if not isinstance(ref, str) or not ref.startswith('#/'):
            return None
        cur = doc
        for tok in ref[2:].split('/'):
            tok = tok.replace('~1', '/').replace('~0', '~')
            if not isinstance(cur, dict) or tok not in cur:
                return None
            cur = cur[tok]
        obj = cur
        depth += 1
    return obj


def is_int_value(v):
    if isinstance(v, bool):
        return False
    if isinstance(v, int):
        return True
    return isinstance(v, Decimal) and v == v.to_integral_value()


def is_num_value(v):
    return (isinstance(v, (int, Decimal))) and not isinstance(v, bool)


FORMAT_RE = {
    'date-time': r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$',
    'date': r'^\d{4}-\d{2}-\d{2}$',
    'uuid': r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    'email': r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    'ipv4': r'^(\d{1,3}\.){3}\d{1,3}$',
}


def validate(doc, schema, value, where, errors, for_request=True):
    schema = resolve(doc, schema)
    if schema is None or schema is True or not isinstance(schema, dict):
        return
    if 'allOf' in schema:
        for s in schema['allOf']:
            validate(doc, s, value, where, errors, for_request)
    for key in ('oneOf', 'anyOf'):
        if key in schema:
            ok = False
            for s in schema[key]:
                tmp = []
                validate(doc, s, value, where, tmp, for_request)
                if not tmp:
                    ok = True
                    break
            if not ok:
                errors.append('%s: %s のいずれにも一致しません' % (where, key))
    if value is None:
        if schema.get('nullable') is True or schema.get('type') == 'null':
            return
        errors.append('%s: null は許可されていません' % where)
        return
    if 'enum' in schema:
        if value not in schema['enum']:
            errors.append('%s: %r は enum %r に含まれません' % (where, value, list(schema['enum'])))
    t = schema.get('type')
    if t is None:
        if 'properties' in schema:
            t = 'object'
        elif 'items' in schema:
            t = 'array'
    if t == 'object':
        if not isinstance(value, dict):
            errors.append('%s: object ではありません' % where)
            return
        props = schema.get('properties') or {}
        for r in schema.get('required') or []:
            ps = resolve(doc, props.get(r)) if r in props else None
            if r not in value and not (isinstance(ps, dict) and ps.get('readOnly') is True):
                errors.append('%s: 必須プロパティ %s がありません' % (where, r))
        addl = schema.get('additionalProperties')
        for k, v in value.items():
            if k in props:
                ps = resolve(doc, props[k])
                if for_request and isinstance(ps, dict) and ps.get('readOnly') is True:
                    errors.append('%s.%s: readOnly プロパティがリクエストに含まれています' % (where, k))
                validate(doc, props[k], v, where + '.' + k, errors, for_request)
            elif addl is False:
                errors.append('%s: 定義外のプロパティ %s があります（additionalProperties: false）' % (where, k))
            elif isinstance(addl, dict):
                validate(doc, addl, v, where + '.' + k, errors, for_request)
    elif t == 'array':
        if not isinstance(value, list):
            errors.append('%s: array ではありません' % where)
            return
        if 'minItems' in schema and len(value) < schema['minItems']:
            errors.append('%s: 要素数 %d < minItems %s' % (where, len(value), schema['minItems']))
        if 'maxItems' in schema and len(value) > schema['maxItems']:
            errors.append('%s: 要素数 %d > maxItems %s' % (where, len(value), schema['maxItems']))
        for i, it in enumerate(value):
            validate(doc, schema.get('items') or {}, it, '%s[%d]' % (where, i), errors, for_request)
    elif t == 'string':
        if not isinstance(value, str):
            errors.append('%s: string ではありません（%r）' % (where, value))
            return
        if 'minLength' in schema and len(value) < schema['minLength']:
            errors.append('%s: 長さ %d < minLength %s' % (where, len(value), schema['minLength']))
        if 'maxLength' in schema and len(value) > schema['maxLength']:
            errors.append('%s: 長さ %d > maxLength %s' % (where, len(value), schema['maxLength']))
        if 'pattern' in schema:
            try:
                rx = re.compile(schema['pattern'])
            except re.error:
                rx = None   # Python の re で解釈できない pattern（\p{L} など）は検査対象外
            if rx is not None and rx.search(value) is None:
                errors.append('%s: %r は pattern %s に一致しません' % (where, value, schema['pattern']))
        fmt = schema.get('format')
        if fmt in FORMAT_RE and re.match(FORMAT_RE[fmt], value) is None:
            errors.append('%s: %r は format %s ではありません' % (where, value, fmt))
    elif t in ('integer', 'number'):
        if t == 'integer' and not is_int_value(value):
            errors.append('%s: integer ではありません（%r）' % (where, value))
            return
        if t == 'number' and not is_num_value(value):
            errors.append('%s: number ではありません（%r）' % (where, value))
            return
        d = Decimal(value)
        if 'minimum' in schema:
            mn = Decimal(schema['minimum'])
            if d < mn or (schema.get('exclusiveMinimum') is True and d == mn):
                errors.append('%s: %s は minimum %s 未満です' % (where, value, schema['minimum']))
        if 'maximum' in schema:
            mx = Decimal(schema['maximum'])
            if d > mx or (schema.get('exclusiveMaximum') is True and d == mx):
                errors.append('%s: %s は maximum %s を超えています' % (where, value, schema['maximum']))
        if 'multipleOf' in schema:
            m = Decimal(schema['multipleOf'])
            if m > 0 and d % m != 0:
                errors.append('%s: %s は multipleOf %s の倍数ではありません' % (where, value, schema['multipleOf']))
    elif t == 'boolean':
        if not isinstance(value, bool):
            errors.append('%s: boolean ではありません' % where)


def coerce_param(schema, raw):
    """パラメータ文字列をスキーマの型に合わせて変換（検証用）"""
    t = schema.get('type') if isinstance(schema, dict) else None
    if t == 'integer':
        return int(raw) if re.match(r'^-?\d+$', raw) else raw
    if t == 'number':
        try:
            return Decimal(raw)
        except Exception:
            return raw
    if t == 'boolean':
        return {'true': True, 'false': False}.get(raw, raw)
    return raw


def coerce_array(doc, schema, raw_values, style, explode):
    """配列パラメータを style / explode に従って要素へ分解し、要素の型へ変換する"""
    items_schema = resolve(doc, schema.get('items') or {}) or {}
    if explode and style == 'form':
        parts = list(raw_values)
    else:
        sep = {'spaceDelimited': ' ', 'pipeDelimited': '|'}.get(style, ',')
        parts = []
        for v in raw_values:
            parts.extend(v.split(sep))
    return [coerce_param(items_schema, p) for p in parts]


def template_regex(path):
    out = '^'
    pos = 0
    names = []
    for m in re.finditer(r'\{([^{}]+)\}', path):
        out += re.escape(path[pos:m.start()])
        name = m.group(1)
        if name.endswith('+'):
            names.append(name[:-1])
            out += '(.+)'
        else:
            names.append(name)
            out += '([^/]+)'
        pos = m.end()
    out += re.escape(path[pos:]) + '$'
    return re.compile(out), names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', required=True)
    ap.add_argument('--requests', required=True)
    ap.add_argument('--api-key', default='XXXXXXXXXXXX')
    ap.add_argument('--base-path', default='')
    a = ap.parse_args()

    with open(a.spec, 'rb') as f:
        raw = f.read()
    if raw[:3] == b'\xef\xbb\xbf':
        raw = raw[3:]
    doc = load_json_text(raw.decode('utf-8'))
    ops = []
    for path, item in doc['paths'].items():
        item = resolve(doc, item)
        rx, names = template_regex(path)
        greedy = '+}' in path
        for key, op in item.items():
            k = key.lower()
            if k in METHODS or k == ANY_KEY:
                ops.append({'path': path, 'key': k, 'method': None if k == ANY_KEY else k.upper(), 'op': op,
                            'item': item, 'rx': rx, 'names': names, 'greedy': greedy, 'hits': 0})
    # 具体的なパスを優先（貪欲パス {x+} や ANY は後回し）
    ops_sorted = sorted(ops, key=lambda o: (o['greedy'], o['method'] is None))

    records = []
    with open(a.requests, encoding='utf-8') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))

    total_errors = 0
    for idx, rec in enumerate(records, 1):
        errors = []
        path = rec['path']
        if a.base_path and path.startswith(a.base_path):
            path = path[len(a.base_path):]
        match = None
        for o in ops_sorted:
            if o['method'] is not None and o['method'] != rec['method']:
                continue
            m = o['rx'].match(path)
            if m:
                match = (o, m)
                break
        headers = {}
        for k, v in rec['headers']:
            headers[k.lower()] = v
        label = '%s %s' % (rec['method'], rec['path'] + ('?' + rec['query'] if rec['query'] else ''))
        if match is None:
            print('[NG] #%d %s : 定義に一致するオペレーションがありません' % (idx, label))
            total_errors += 1
            continue
        o, m = match
        o['hits'] += 1
        op = o['op']
        # X-API-KEY
        if headers.get('x-api-key') != a.api_key:
            errors.append('X-API-KEY ヘッダが期待値（%s）ではありません: %r' % (a.api_key, headers.get('x-api-key')))
        # パラメータ
        params = OrderedDict()
        for src in (o['item'].get('parameters'), op.get('parameters')):
            for p in src or []:
                p = resolve(doc, p)
                params[(p['in'], p['name'])] = p
        from urllib.parse import unquote
        path_values = dict(zip(o['names'], [unquote(g) for g in m.groups()]))
        for (loc, name), p in params.items():
            schema = resolve(doc, p.get('schema') or {}) or {}
            if loc == 'path':
                if name not in path_values:
                    errors.append('パスパラメータ %s が URL にありません' % name)
                else:
                    validate(doc, schema, coerce_param(schema, path_values[name]), 'path.' + name, errors)
            elif loc == 'query':
                style = p.get('style') or 'form'
                explode = p.get('explode') if isinstance(p.get('explode'), bool) else (style == 'form')
                if style == 'deepObject' and schema.get('type') == 'object':
                    obj = OrderedDict()
                    props = schema.get('properties') or {}
                    for qk, qv in rec['query_params'].items():
                        if qk.startswith(name + '[') and qk.endswith(']'):
                            pk = qk[len(name) + 1:-1]
                            obj[pk] = coerce_param(resolve(doc, props.get(pk) or {}), qv[0])
                    if not obj:
                        if p.get('required') is True:
                            errors.append('必須クエリ %s がありません' % name)
                        continue
                    validate(doc, schema, obj, 'query.' + name, errors)
                    continue
                vals = rec['query_params'].get(name)
                if not vals:
                    if p.get('required') is True:
                        errors.append('必須クエリ %s がありません' % name)
                    continue
                if schema.get('type') == 'array':
                    validate(doc, schema, coerce_array(doc, schema, vals, style, explode), 'query.' + name, errors)
                else:
                    for v in vals:
                        validate(doc, schema, coerce_param(schema, v), 'query.' + name, errors)
            elif loc == 'header':
                if name.lower() in ('accept', 'content-type', 'authorization', 'x-api-key'):
                    continue
                v = headers.get(name.lower())
                if v is None:
                    if p.get('required') is True:
                        errors.append('必須ヘッダ %s がありません' % name)
                    continue
                if schema.get('type') == 'array':
                    validate(doc, schema, coerce_array(doc, schema, [v], 'simple', False), 'header.' + name, errors)
                else:
                    validate(doc, schema, coerce_param(schema, v), 'header.' + name, errors)
            elif loc == 'cookie':
                cookie_header = headers.get('cookie', '')
                cookies = {}
                for part in cookie_header.split(';'):
                    if '=' in part:
                        ck, cv = part.strip().split('=', 1)
                        cookies[ck] = unquote(cv)
                if name not in cookies:
                    if p.get('required') is True:
                        errors.append('必須クッキー %s がありません' % name)
                    continue
                validate(doc, schema, coerce_param(schema, cookies[name]), 'cookie.' + name, errors)
        # ボディ
        rb = resolve(doc, op.get('requestBody')) if 'requestBody' in op else None
        if isinstance(rb, dict) and rb.get('content'):
            content = rb['content']
            mt = next((k for k in content if k.split(';')[0].strip().lower() == 'application/json'), list(content)[0])
            ct = headers.get('content-type', '')
            if ct.split(';')[0].strip().lower() != mt.split(';')[0].strip().lower():
                errors.append('Content-Type が %r（期待 %r）' % (ct, mt))
            if 'json' in mt:
                try:
                    body = load_json_text(rec['body'])
                except ValueError as e:
                    errors.append('ボディが JSON ではありません: %s' % e)
                    body = None
                if body is not None:
                    validate(doc, content[mt].get('schema') or {}, body, 'body', errors)
            if rb.get('required') is True and rec['body_length'] == 0:
                errors.append('必須のリクエストボディがありません')
        # Accept
        exp_accept = None
        for code, resp in (op.get('responses') or {}).items():
            if re.match(r'^2\d\d$', str(code)):
                resp = resolve(doc, resp)
                c = (resp or {}).get('content') or {}
                if c:
                    exp_accept = list(c)[0]
                    break
        if exp_accept and headers.get('accept') != exp_accept:
            errors.append('Accept が %r（期待 %r）' % (headers.get('accept'), exp_accept))

        body_note = (' body=' + rec['body'].replace('\n', ' ')) if rec['body'] else ''
        if errors:
            total_errors += len(errors)
            print('[NG] #%d %s ← %s %s' % (idx, label, o['key'], o['path']))
            for e in errors:
                print('       - ' + e)
        else:
            print('[OK] #%d %s ← %s %s%s' % (idx, label, o['key'], o['path'], body_note))

    for o in ops:
        if o['hits'] == 0:
            print('[NG] 未呼び出し: %s %s' % (o['key'], o['path']))
            total_errors += 1
    print('----')
    print('検証結果: リクエスト %d 件 / 定義オペレーション %d 件 / 不合格 %d 件' % (len(records), len(ops), total_errors))
    return 0 if total_errors == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
