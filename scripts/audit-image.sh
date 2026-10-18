#!/bin/bash
# Audits the built sysupgrade image itself (not the build tree):
#  - FIT: kernel, device tree, rootfs; metadata for viettel,nr3053 only
#  - device tree byte-identical to the stable v2.3.6 firmware (same partitions,
#    same hardware description); kernel compared for information
#  - WiFi firmware, calibration-related profiles and driver scripts identical
#    to v2.3.6
#  - Wiflow files present, removed features absent, package list
# Usage: scripts/audit-image.sh <sysupgrade.itb> <report dir>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ITB="$1"; OUT="$2"; G="$ROOT/tools/nr3053-golden.json"
rm -rf "$OUT"; mkdir -p "$OUT"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
bad=0; R="$OUT/audit.txt"; : > "$R"
say(){ echo "$*" | tee -a "$R"; }
ok(){ say "PASS $*"; }
no(){ say "FAIL $*"; bad=1; }
gj(){ python3 -c "import json,sys;print(json.load(open('$G'))$1)"; }

say "image: $(basename "$ITB")  $(stat -c %s "$ITB") bytes  sha256 $(sha256sum "$ITB" | cut -d' ' -f1)"
python3 "$ROOT/tools/fitx.py" "$ITB" "$W/fit" > "$OUT/fit.txt"
for p in kernel-1 fdt-1 rootfs-1; do [ -s "$W/fit/_images_$p.bin" ] && ok "FIT has $p" || no "FIT has no $p"; done
meta="$(tail -c 4096 "$ITB" | strings | grep -o '{.*supported_devices.*}' | tail -n1 || true)"
echo "$meta" > "$OUT/metadata.json"
echo "$meta" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d["supported_devices"]==["viettel,nr3053"] else 1)' \
  && ok "sysupgrade metadata: supported_devices = viettel,nr3053 only" || no "sysupgrade metadata: $meta"

fdt="$(sha256sum "$W/fit/_images_fdt-1.bin" | cut -d' ' -f1)"
[ "$fdt" = "$(gj "['fdt_sha256']")" ] && ok "device tree identical to v2.3.6 (partitions, hardware)" || no "device tree differs from v2.3.6 ($fdt)"
k="$(sha256sum "$W/fit/_images_kernel-1.bin" | cut -d' ' -f1)"
[ "$k" = "$(gj "['kernel_sha256']")" ] && say "INFO kernel identical to v2.3.6" || say "INFO kernel rebuilt: $(stat -c %s "$W/fit/_images_kernel-1.bin") bytes (v2.3.6: $(gj "['kernel_bytes']"))"
say "INFO rootfs $(stat -c %s "$W/fit/_images_rootfs-1.bin") bytes (v2.3.6: $(gj "['rootfs_bytes']"))"

unsquashfs -q -no-progress -d "$W/root" "$W/fit/_images_rootfs-1.bin" >/dev/null 2>&1 || unsquashfs -d "$W/root" "$W/fit/_images_rootfs-1.bin" >/dev/null
F="$W/root"
python3 - "$G" "$F" > "$W/drv.txt" <<'PY' || bad=1
import hashlib, json, os, sys
g = json.load(open(sys.argv[1])); F = sys.argv[2]; bad = 0
h = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
for p, want in g['must_match'].items():
    f = F + p
    if not os.path.isfile(f): print('FAIL missing (in v2.3.6):', p); bad = 1
    elif h(f) != want: print('FAIL differs from v2.3.6:', p); bad = 1
print('PASS' if not bad else 'FAIL', 'WiFi firmware, profiles, driver scripts, board files: %d files identical to v2.3.6' % len(g['must_match']))
for p, want in g['info'].items():
    import glob
    fs = glob.glob(F + p.replace('6.12.94', '*'))
    print('INFO', p, 'identical' if fs and h(fs[0]) == want else ('rebuilt' if fs else 'MISSING'))
sys.exit(bad)
PY
tee -a "$R" < "$W/drv.txt"

need=(/usr/lib/wiflow/bootstrap /usr/lib/wiflow/common.sh /usr/lib/wiflow/apply-uplink /usr/lib/wiflow/scan-wifi
      /usr/lib/wiflow/radio-policy /usr/share/wiflow/luci-sso.uc /www-wiflow/index.html /www-wiflow/setup.html
      /www-wiflow/cgi-bin/gate /www-wiflow/cgi-bin/api /www-wiflow-portal/cgi-bin/portal /etc/init.d/wiflow-setup
      /etc/init.d/wiflow-rom /etc/uci-defaults/95-wiflow-rom /etc/config/wiflow /etc/config/wireless
      /etc/sysctl.d/90-wiflow-ipv4.conf /lib/upgrade/keep.d/wiflow-setup
      /usr/share/ucode/luci/template/themes/wiflow/header.ut /www/luci-static/wiflow/wiflow.css
      /usr/share/ucode/luci/uhttpd.uc /usr/sbin/uhttpd /usr/sbin/iwpriv /usr/lib/rpcd/iwinfo.so
      /usr/sbin/dnsmasq /sbin/fw4 /usr/sbin/dropbear /etc/wireless/l1profile.dat)
m=0; for p in "${need[@]}"; do [ -e "$F$p" ] || { no "missing $p"; m=1; }; done
[ "$m" = 0 ] && ok "Wiflow, LuCI, WiFi tools: ${#need[@]} required files present"
[ -n "$(ls "$F"/lib/modules/*/mt_wifi.ko 2>/dev/null)" ] && ok "mt_wifi driver present" || no "mt_wifi.ko missing"
grep -q "WIFLOW_AGENT_VERSION='" "$F/usr/lib/wiflow/common.sh" 2>/dev/null && say "INFO Wiflow $(sed -n "s/^WIFLOW_AGENT_VERSION='\(.*\)'/\1/p" "$F/usr/lib/wiflow/common.sh")"
grep -q "MT7981_1_1" "$F/etc/config/wireless" 2>/dev/null && grep -q "MT7981_1_2" "$F/etc/config/wireless" && ok "WiFi config for MT7981_1_1 / MT7981_1_2 in ROM" || no "ROM wireless config"
ls "$F"/etc/rc.d/ | grep -q 'wiflow-setup$' && ok "Wiflow service enabled at boot" || no "Wiflow service not enabled"

deny=(/usr/sbin/odhcpd /usr/sbin/odhcp6c /usr/sbin/pppd /usr/sbin/tailscaled /usr/bin/wg /etc/init.d/adblock
      /etc/init.d/turboacc /etc/init.d/miniupnpd /etc/init.d/ddns /www/luci-static/aurora /usr/sbin/hostapd
      /usr/sbin/wpa_supplicant /etc/init.d/zram /usr/sbin/tcpdump /usr/bin/htop /usr/bin/nano /usr/bin/curl
      /etc/hotplug.d/iface/99-hnat-detect /usr/sbin/iptables-legacy)
m=0; for p in "${deny[@]}"; do [ -e "$F$p" ] && { no "removed feature still present: $p"; m=1; }; done
zh="$(find "$F/usr/lib/lua/luci/i18n" "$F/usr/share/luci" "$F/usr/share/ucode/luci" -name '*zh*' 2>/dev/null | head -3 || true)"; [ -z "$zh" ] || { no "Chinese translations present: $zh"; m=1; }
[ "$m" = 0 ] && ok "removed features absent (IPv6 DHCP/RA, PPP, VPN, ad block, UPnP, DDNS, hardware NAT tools, Chinese UI)"

db="$F/lib/apk/db/installed"
if [ -f "$db" ]; then
    python3 - "$db" > "$OUT/packages.txt" <<'PY'
import sys
for blk in open(sys.argv[1], encoding='utf8', errors='replace').read().split('\n\n'):
    f = {l[0]: l[2:] for l in blk.splitlines() if len(l) > 2 and l[1] == ':'}
    if 'P' in f: print(f['P'], f.get('V', ''))
PY
    say "INFO packages: $(wc -l < "$OUT/packages.txt") (v2.3.6: 342)"
    grep -q '^wiflow-setup ' "$OUT/packages.txt" && ok "package wiflow-setup installed" || no "wiflow-setup not in package database"
fi
sed -n 's/^DISTRIB_DESCRIPTION=//p' "$F/etc/openwrt_release" | tr -d "'" | sed 's/^/INFO release: /' | tee -a "$R"
[ "$bad" = 0 ] && say "AUDIT PASSED" || say "AUDIT FAILED"
if [ -n "${GITHUB_ACTIONS:-}" ]; then   # readable from the checks API
    grep '^FAIL' "$R" | head -n 10 | while read -r l; do echo "::error title=audit::$l"; done
    echo "::notice title=audit report::$(sed ':a;N;$!ba;s/%/%25/g;s/\n/%0A/g' "$R")"
fi
[ "$bad" = 0 ] || exit 1
