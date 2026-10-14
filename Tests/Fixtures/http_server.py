#!/usr/bin/env python3
"""Loopback-only response fixtures. No provider tokens, private files or transcript content."""
import http.server
import sys
import time

mode = sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_):
        pass
    def end_headers(self):
        self.send_header('Connection', 'close')
        self.close_connection = True
        super().end_headers()
    def do_GET(self):
        try:
            if self.path == '/redirect-target':
                body = b'followed'
                self.send_response(200); self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body); return
            if mode == 'redirect':
                self.send_response(302); self.send_header('Location', '/redirect-target')
                self.send_header('Content-Length', '0'); self.end_headers(); return
            if mode == 'auth-error':
                self.send_response(401); self.send_header('Content-Length', '256')
                self.end_headers(); self.wfile.write(b'x' * 256); return
            self.send_response(200)
            if mode in {'stream-limit', 'cancel'}:
                self.send_header('Transfer-Encoding', 'chunked'); self.end_headers()
                if mode == 'cancel':
                    self.wfile.write(b'1\r\nx\r\n'); self.wfile.flush()
                    print('body-started', flush=True); time.sleep(3)
                else:
                    for _ in range(8):
                        self.wfile.write(b'20\r\n' + b'x' * 32 + b'\r\n'); self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n'); return
            body = b'x' * 256 if mode == 'declared-limit' else b'x' * 64 if mode == 'exact-limit' else b'{"ok":true}'
            length = 256 if mode == 'declared-limit' else len(body)
            self.send_header('Content-Length', str(length)); self.end_headers(); self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the client cancels a rejected body.

server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.timeout = 5
server.handle_request()
server.server_close()
