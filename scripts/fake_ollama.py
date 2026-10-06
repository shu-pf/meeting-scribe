"""check_ollama_reconnect.swift 用の疑似Ollama。

起動を遅らせて再起動直後の未起動状態を再現し、最初の数回の生成では
応答せずに接続を切って、生成中のOllama異常終了を再現する。
受けたリクエストは標準出力に記録する。
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1])
startup_delay = float(sys.argv[2])
drops_remaining = int(sys.argv[3])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        print(f"GET {self.path}", flush=True)
        self._json({"models": [{"name": "fake-model"}]})

    def do_POST(self):
        global drops_remaining
        length = int(self.headers.get("Content-Length", 0))
        request = json.loads(self.rfile.read(length) or b"{}")
        if self.path == "/api/show":
            print("POST /api/show", flush=True)
            self._json({"model_info": {"fake.context_length": 131072}})
            return
        num_ctx = request.get("options", {}).get("num_ctx")
        if drops_remaining > 0:
            drops_remaining -= 1
            print(f"POST /api/generate num_ctx={num_ctx} -> drop", flush=True)
            self.close_connection = True
            self.connection.close()
            return
        print(f"POST /api/generate num_ctx={num_ctx} -> ok", flush=True)
        self._json({
            "response": "定例日程の確認\n\n次回の定例は木曜に行うと話した。",
            "done_reason": "stop",
            "prompt_eval_count": 10,
            "eval_count": 10,
        })


time.sleep(startup_delay)
print(f"listening on {port}", flush=True)
ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
