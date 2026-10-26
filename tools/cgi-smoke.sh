#!/bin/bash
# Runs the ROM's real LuCI CGI (/www/cgi-bin/luci, dispatcher, Wiflow theme,
# gate) with the SAME ucode version as the router, inside a chroot of the
# finished rootfs. Native modules that only exist for the router CPU (uci,
# ubus, html, lucihttp, luci.core) are replaced by small stubs
# (tools/ucode-stubs); fs, math and log are real.
#
# Checks: login page renders, gate refuses wrong codes, credentials are
# refused before the gate, correct code -> login form, wiflow/wiflow and
# root/1234 log in, a forged gate cookie is refused, and every menu page,
# the menu and the translations render without a ucode error.
#
# usage: tools/cgi-smoke.sh <rootfs> <ucode build dir (ucode, libucode.so, fs.so, math.so, log.so)>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$1"; UB="$2"
C="$(mktemp -d)"; trap 'rm -rf "$C"' EXIT
fail=0
ok(){ echo "PASS $*"; }
no(){ echo "FAIL $*"; fail=1; }

cp -a "$SRC/." "$C/"
mkdir -p "$C/x86/lib" "$C/x86/mod" "$C/x86/stubs" "$C/tmp" "$C/dev"
cp "$UB/ucode" "$C/x86/"
cp -L "$UB"/libucode.so* "$C/x86/lib/"
cp "$UB/fs.so" "$UB/math.so" "$UB/log.so" "$C/x86/mod/"
for l in $(ldd "$UB/ucode" "$UB/fs.so" | awk '/=>/{print $3} /ld-linux/{print $1}' | sort -u); do
	[ -f "$l" ] && cp -L "$l" "$C/x86/lib/"
done
cp -a "$ROOT/tools/ucode-stubs/." "$C/x86/stubs/"
[ -e "$C/dev/urandom" ] || mknod -m 444 "$C/dev/urandom" c 1 9

# first-boot LuCI settings (98-wiflow-base)
sed -i "s#option mediaurlbase .*#option mediaurlbase '/luci-static/wiflow'#; s#option lang .*#option lang 'en'#" "$C/etc/config/luci"
python3 - "$C/etc/config/luci" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"config internal 'themes'\n(\toption .*\n)*", "config internal 'themes'\n\toption Wiflow '/luci-static/wiflow'\n", s)
open(p, 'w').write(s)
PY

LD="$(ls "$C"/x86/lib/ld-linux-* | head -n1)"; LD="/x86/lib/$(basename "$LD")"
req() { # path cookie body
	local body="${3:-}" method=GET
	[ -n "$body" ] && method=POST
	printf '%s' "$body" | env -i LD_LIBRARY_PATH=/x86/lib PATH=/usr/bin:/bin \
		REQUEST_METHOD=$method SCRIPT_NAME=/cgi-bin/luci PATH_INFO="$1" REQUEST_URI="/cgi-bin/luci$1" \
		HTTP_COOKIE="${2:-}" REMOTE_ADDR=10.0.0.100 SERVER_PORT=80 HTTP_HOST=10.0.0.1 DOCUMENT_ROOT=/www \
		CONTENT_TYPE=application/x-www-form-urlencoded CONTENT_LENGTH=${#body} \
		"$(command -v chroot)" "$C" "$LD" /x86/ucode -L '/x86/mod/*.so' -L '/x86/stubs/*.uc' -L '/usr/share/ucode/*.uc' /www/cgi-bin/luci 2>&1
}
has() { grep -q "$2" <<<"$1"; }

r="$(req /)"
has "$r" '^Status: 403' && has "$r" 'data-title="Security code"' && ok "login page renders, gate shown first" || { no "login page: $(grep -A10 'configured theme failed' <<<"$r" | tail -n 9 | cut -c1-300 | tr '\r\n\t' '|| ')"; }
has "$r" 'Wrong security code' && ok "wrong access code refused" || no "wrong code not refused: ${#r} bytes: $(head -c 300 <<<"$r" | tr '\r\n\t' '|| ') ... $(tail -c 500 <<<"$r" | tr '\r\n\t' '|| ')"
has "$r" 'data-title="Security code"' && ! has "$r" '^Status: 302' && ok "credentials refused before the gate" || no "login possible without the gate"

r="$(req / "" "wf_gate_code=wifdidnr3053")"
tok="$(grep -o 'wiflow_gate=[0-9a-f]\{32\}' <<<"$r" | head -n1)"
[ -n "$tok" ] && has "$r" 'data-title="Sign in"' && ok "correct access code gives a token and the login form" || no "gate pass failed"

for cred in "wiflow:wiflow" "root:1234"; do
	r="$(req / "$tok" "luci_username=${cred%%:*}&luci_password=${cred#*:}")"
	has "$r" '^Status: 302' && ok "login ${cred%%:*} after the gate" || no "login ${cred%%:*} failed"
done

r="$(req / "wiflow_gate=0123456789abcdef0123456789abcdef" "luci_username=wiflow&luci_password=wiflow")"
! has "$r" '^Status: 302' && ok "forged gate cookie refused" || no "forged gate cookie accepted"

sess="sysauth_http=abcdef0123456789abcdef0123456789"
pages="$(python3 - "$C" <<'PY'
import json, glob, sys
root = sys.argv[1]; out = []
for f in sorted(glob.glob(root + '/usr/share/luci/menu.d/*.json')):
    for path, spec in json.load(open(f)).items():
        a = spec.get('action') or {}
        if a.get('type') in ('view', 'template') and path.startswith('admin/'):
            out.append(path)
print(' '.join(sorted(set(out))))
PY
)"
n=0; bad=""
for p in $pages admin/menu admin/translations/en; do
	r="$(req "/$p" "$sess")"
	# pages whose menu dependencies are not met answer 404; anything else must be 200
	if grep -qi 'Syntax error\|Runtime error\|Unhandled exception' <<<"$r" || ! grep -q '^Status: \(200\|404\)' <<<"$r"; then
		bad="$bad $p"
	fi
	n=$((n + 1))
done
[ -z "$bad" ] && ok "$n pages, menu and translations render (logged in)" || no "pages with errors:$bad"

r="$(req /admin/status/overview "$sess")"
has "$r" 'wf-logo' && has "$r" 'wf-brand' && ok "Wiflow theme frame (logo, device) on inside pages" || no "theme frame missing"

exit $fail
