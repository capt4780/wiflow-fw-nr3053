#!/usr/bin/env python3
"""Mock speed server for the bench (the Cloudflare /__down and /__up endpoints):
about 4 MB per request, paced to roughly 0.8 s, so the measured rate is stable and non-zero."""
import sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHUNK = 100_000

class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *a): pass
    def do_GET(self):
        if not self.path.startswith('/__down'):
            self.send_response(404); self.send_header('Content-Length', '0'); self.end_headers(); return
        self.send_response(200); self.send_header('Content-Length', str(CHUNK * 40)); self.end_headers()
        for _ in range(40):
            self.wfile.write(b'0' * CHUNK); time.sleep(0.02)
    def do_POST(self):
        n = int(self.headers.get('Content-Length', '0')); got = 0
        while got < n:
            d = self.rfile.read(min(65536, n - got))
            if not d: break
            got += len(d); time.sleep(0.003)
        self.send_response(200); self.send_header('Content-Length', '2'); self.end_headers(); self.wfile.write(b'ok')

ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
