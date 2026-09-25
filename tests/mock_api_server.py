#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
検証用の模擬 API サーバー（Python 3.6 以降・標準ライブラリのみ）

JMeter から送られてきたリクエストを 1 件 1 行の JSON（JSON Lines）で記録し、
メソッドに応じたステータスコードで JSON を返します。生成した JMX が
「正しいメソッド・パス・クエリ・ヘッダ・ボディで API を呼べているか」を
実際の通信で確かめるために使います。

使い方:
  python3 mock_api_server.py --port 8080 --log requests.jsonl
  python3 mock_api_server.py --port 8080 --status POST=201,DELETE=204 --max-requests 5

  --status        メソッドごとの応答コード（既定: POST=201、その他=200）
  --max-requests  指定件数を受け付けたら自動終了（自動テスト用）
  --timeout       指定秒数が経過したら自動終了（自動テスト用。0 は無制限）
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlsplit


class _Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class _State(object):
    def __init__(self, log_path, status_map, max_requests):
        self.log_path = log_path
        self.status_map = status_map
        self.max_requests = max_requests
        self.count = 0
        self.lock = threading.Lock()
        self.done = threading.Event()


def _read_body(handler):
    te = (handler.headers.get('Transfer-Encoding') or '').lower()
    if 'chunked' in te:
        chunks = []
        while True:
            size_line = handler.rfile.readline().strip()
            size = int(size_line.split(b';', 1)[0] or b'0', 16)
            if size == 0:
                handler.rfile.readline()
                break
            chunks.append(handler.rfile.read(size))
            handler.rfile.readline()
        return b''.join(chunks)
    length = int(handler.headers.get('Content-Length') or 0)
    return handler.rfile.read(length) if length > 0 else b''


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        server_version = 'MockApiServer/1.0'

        def log_message(self, fmt, *args):
            sys.stderr.write('[mock] %s - %s\n' % (self.address_string(), fmt % args))

        def _handle(self):
            body = _read_body(self)
            parts = urlsplit(self.path)
            body_text = body.decode('utf-8', errors='replace')
            try:
                json.loads(body_text)
                body_is_json = True
            except ValueError:
                body_is_json = False
            record = {
                'method': self.command,
                'path': parts.path,
                'query': parts.query,
                'query_params': parse_qs(parts.query, keep_blank_values=True),
                'headers': [[k, v] for k, v in self.headers.items()],
                'body': body_text,
                'body_length': len(body),
                'body_is_json': body_is_json,
            }
            status = state.status_map.get(self.command, 200)
            with state.lock:
                state.count += 1
                seq = state.count
                with open(state.log_path, 'a', encoding='utf-8') as f:
                    f.write(json.dumps(record, ensure_ascii=False) + '\n')
            payload = b''
            if status != 204 and self.command != 'HEAD':
                payload = json.dumps({'mock': True, 'seq': seq, 'method': self.command,
                                      'path': parts.path}, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=UTF-8')
            self.send_header('X-Request-Id', 'mock-%d' % seq)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            if payload:
                self.wfile.write(payload)
            if state.max_requests and seq >= state.max_requests:
                state.done.set()

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _handle
        do_OPTIONS = do_HEAD = do_TRACE = _handle

    return Handler


def main():
    ap = argparse.ArgumentParser(description='検証用の模擬 API サーバー')
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=8080)
    ap.add_argument('--log', default='requests.jsonl')
    ap.add_argument('--status', default='POST=201')
    ap.add_argument('--max-requests', type=int, default=0)
    ap.add_argument('--timeout', type=float, default=0)
    a = ap.parse_args()
    status_map = {}
    for item in [x for x in a.status.split(',') if x.strip()]:
        k, v = item.split('=', 1)
        status_map[k.strip().upper()] = int(v)
    open(a.log, 'w', encoding='utf-8').close()
    state = _State(a.log, status_map, a.max_requests)
    server = _Server((a.host, a.port), make_handler(state))
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    sys.stderr.write('[mock] listening on http://%s:%d/ (log=%s)\n' % (a.host, a.port, a.log))
    sys.stderr.flush()
    started = time.time()
    try:
        while not state.done.is_set():
            if a.timeout and time.time() - started > a.timeout:
                break
            time.sleep(0.1)
        time.sleep(0.3)
    except KeyboardInterrupt:
        pass
    server.shutdown()
    sys.stderr.write('[mock] stopped after %d request(s)\n' % state.count)


if __name__ == '__main__':
    main()
