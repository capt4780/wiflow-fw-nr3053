#!/usr/bin/env python3
"""Mock WordPress device API (Wiflow plugin 4.2 contract, data generation 4)."""
import json, os, re, secrets, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
REST = 'http://127.0.0.1:%d/wp-json' % PORT
D = '/tmp/mock/wp'
os.makedirs(D, exist_ok=True)
SF = D + '/state.json'

def load():
    if os.path.exists(SF):
        return json.load(open(SF))
    return {'codes': {'ABCD1234EFGH': {'account': 'WIFUID482913'}}, 'devices': {}, 'revoked': [], 'commands': [], 'results': {}}

def save(s):
    json.dump(s, open(SF + '.tmp', 'w'), indent=1); os.replace(SF + '.tmp', SF)

def log(name, obj):
    with open('%s/%s.jsonl' % (D, name), 'a') as f:
        f.write(json.dumps(obj, ensure_ascii=False) + '\n')

def perr(code, msg, status=400):
    return {'ok': False, 'code': code, 'message': msg, 'retryable': False, 'data_generation': '4', 'http_status': status}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def reply(self, obj, status=200):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def auth(self, s):
        hw = (self.headers.get('X-Wiflow-Device-ID') or '').upper().strip()
        tok = (self.headers.get('X-Wiflow-Device-Token') or '').strip()
        if not re.match(r'^WIFDID-[A-Z0-9-]{6,80}$', hw) or len(tok) < 40:
            return None, perr('DEVICE_AUTH_MISSING', 'Thiếu thông tin xác thực thiết bị.', 401)
        d = s['devices'].get(hw)
        if d and d['token'] == tok:
            return d, None
        if [hw, tok] in s['revoked']:
            return None, perr('DEVICE_UNPAIRED', 'Thiết bị đã được gỡ khỏi tài khoản Wiflow.', 401)
        return None, perr('DEVICE_AUTH_INVALID', 'Thông tin xác thực thiết bị không hợp lệ.', 401)

    def do_GET(self):
        if self.path.startswith('/wp-json/devices/health'):
            if os.path.exists(D + '/down'):
                return self.reply({'code': 'rest_no_route'}, 503)
            return self.reply({'ok': True, 'service': 'wiflow-devices', 'api_version': 1, 'data_generation': '4', 'wp_home': 'x', 'rest_root': REST})
        self.reply({'code': 'rest_no_route'}, 404)

    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        try:
            b = json.loads(self.rfile.read(n) or b'{}')
        except Exception:
            b = {}
        s = load()
        p = self.path.replace('/wp-json/devices/', '')
        if os.path.exists(D + '/down'):
            return self.reply({'code': 'down'}, 503)
        if p == 'pair':
            log('pair', b)
            code = re.sub('[^A-Z0-9]', '', str(b.get('pairing_code', '')).upper())
            hw = str(b.get('device_id', '')).upper()
            if str(b.get('data_generation')) != '4': return self.reply(perr('PAIR_GENERATION_MISMATCH', 'WP và thiết bị không cùng generation dữ liệu.', 409))
            if not re.match(r'^[A-Z0-9]{12}$', code): return self.reply(perr('PAIR_CODE_FORMAT', 'Mã kết nối không đúng định dạng.'))
            if not re.match(r'^WIFDID-[A-Z0-9-]{6,80}$', hw): return self.reply(perr('PAIR_DEVICE_ID_INVALID', 'ID thiết bị không hợp lệ.'))
            t = s['codes'].get(code)
            if not t: return self.reply(perr('PAIR_CODE_NOT_FOUND', 'Mã kết nối không tồn tại.'))
            if t.get('used'): return self.reply(perr('PAIR_CODE_ALREADY_USED', 'Mã kết nối đã được dùng.'))
            t['used'] = True
            tok = secrets.token_urlsafe(36)
            s['devices'][hw] = {'token': tok, 'account': t['account'], 'agent': b.get('agent_version'), 'model': b.get('model')}
            save(s)
            return self.reply({'ok': True, 'device_token': tok, 'account_public_id': t['account'], 'desired_portal_revision': 0, 'portal_enabled': False, 'data_generation': '4'})
        d, e = self.auth(s)
        if e:
            log('denied', {'path': p, 'code': e['code']})
            return self.reply(e)
        hw = self.headers.get('X-Wiflow-Device-ID').upper()
        if p == 'heartbeat':
            log('heartbeat', b)
            if str(b.get('data_generation')) != '4': return self.reply(perr('DEVICE_GENERATION_MISMATCH', 'x', 409))
            cr = b.get('command_result')
            if isinstance(cr, dict) and cr.get('id'):
                s['results'][cr['id']] = cr
            cmd = None
            for c in s['commands']:
                r = s['results'].get(c['id'])
                if not r or r.get('status') not in ('success', 'failed', 'rebooting', 'running'):
                    cmd = c; break
            save(s)
            return self.reply({'ok': True, 'command': cmd, 'desired_portal_revision': 0, 'account_public_id': d['account'], 'data_generation': '4', 'server_time': int(time.time())})
        if p == 'unpair':
            s['revoked'].append([hw, d['token']]); del s['devices'][hw]; save(s)
            return self.reply({'ok': True, 'data_generation': '4'})
        if p == 'diag':
            log('diag', b)
            return self.reply({'ok': True, 'data_generation': '4'})
        self.reply({'code': 'rest_no_route'}, 404)

ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
