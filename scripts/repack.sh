#!/bin/bash
# Builds the lean Wiflow ROM for Viettel NR3053 by repacking the stable stock
# image (base/, ImmortalWrt v2.3.6) instead of compiling:
#   - kernel, device tree and the FIT layout stay byte-identical to v2.3.6
#   - rootfs: packages Wiflow does not need are removed (tools/lean-keep.txt),
#     Wiflow branding + base settings added (rom/overlay), defaults patched
#   - sysupgrade metadata (viettel,nr3053) carried over from the stock image
#
# usage: scripts/repack.sh <out dir>
# needs: unsquashfs, mksquashfs, fwtool, python3, openssl (run as root so
#        ownership and device nodes are kept; override tool paths with
#        UNSQUASHFS= MKSQUASHFS= FWTOOL=)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
UNSQUASHFS="${UNSQUASHFS:-unsquashfs}"
MKSQUASHFS="${MKSQUASHFS:-mksquashfs}"
FWTOOL="${FWTOOL:-fwtool}"
VERSION="$(tr -d ' \n' < "$ROOT/rom/VERSION")"
BASE="$ROOT/base/immortalwrt-v2.3.6-viettel_nr3053-squashfs-sysupgrade.itb"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
step(){ echo; echo "== $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }

step "stock image"
want="$(python3 -c "import json;print(json.load(open('$ROOT/tools/nr3053-golden.json'))['itb_sha256'])")"
got="$(sha256sum "$BASE" | cut -d' ' -f1)"
[ "$got" = "$want" ] || die "base image is not the stock v2.3.6 ($got)"
echo "v2.3.6 $got"

cp "$BASE" "$W/stock.itb"
"$FWTOOL" -q -t -i "$W/meta.json" "$W/stock.itb" || die "no sysupgrade metadata in stock image"
python3 "$ROOT/tools/fitx.py" "$W/stock.itb" "$W/fit" > /dev/null
"$UNSQUASHFS" -q -no-progress -d "$W/root" "$W/fit/_images_rootfs-1.bin" > /dev/null
F="$W/root"

step "remove packages Wiflow does not need"
python3 "$ROOT/tools/lean-rootfs.py" "$F" "$ROOT/tools/lean-keep.txt" "$OUT/report"
# first-boot scripts of the stock build for removed features (no package owns them)
rm -f "$F/etc/uci-defaults/99-viettel-custom-defaults" "$F/etc/uci-defaults/99-viettel-services-defaults"

step "Wiflow files and defaults"
cp -a "$ROOT/rom/overlay/." "$F/"
chmod 0755 "$F/etc/init.d/wiflow-hnat-off" "$F/etc/uci-defaults/98-wiflow-base"
ln -sf ../init.d/wiflow-hnat-off "$F/etc/rc.d/S21wiflow-hnat-off"
sed -i "s/@VERSION@/$VERSION/" "$F/etc/banner"
echo "$VERSION" > "$F/etc/wiflow_release"

# LAN 10.0.0.1 also for configs generated after a reset
grep -q 'ipad=${ipaddr:-"192.168.1.1"}' "$F/bin/config_generate" || die "config_generate: LAN default not found"
sed -i 's/ipad=${ipaddr:-"192.168.1.1"}/ipad=${ipaddr:-"10.0.0.1"}/' "$F/bin/config_generate"

# Status overview: no DHCPv6 lease table (IPv6 DHCP/RA is off in Wiflow OS)
D="$F/www/luci-static/resources/view/status/include/40_dhcp.js"
grep -qF "table,E('h3',_('Active DHCPv6 Leases')),table6]" "$D" || die "40_dhcp.js: DHCPv6 lease table not found"
sed -i "s/table,E('h3',_('Active DHCPv6 Leases')),table6\]/table]/" "$D"

# root password 1234
hash="$(openssl passwd -1 1234)"
sed -i "s|^root:[^:]*:|root:$hash:|" "$F/etc/shadow"

# display names only. DISTRIB_ID/DISTRIB_RELEASE and os-release VERSION stay
# as v2.3.6: the stock WiFi first-boot fixes (99-hack-wifi-scripts,
# 99-replace-iwinfo) only run when DISTRIB_RELEASE >= 25.12.
sed -i -e "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='Wiflow OS $VERSION'/" "$F/etc/openwrt_release"
sed -i -e 's/^NAME=.*/NAME="Wiflow OS"/' \
       -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Wiflow OS $VERSION\"/" \
       -e 's/^OPENWRT_DEVICE_MANUFACTURER=.*/OPENWRT_DEVICE_MANUFACTURER="Wiflow"/' \
       -e 's|^OPENWRT_DEVICE_MANUFACTURER_URL=.*|OPENWRT_DEVICE_MANUFACTURER_URL="https://wiflow.projifylab.com/"|' \
       -e "s/^OPENWRT_RELEASE=.*/OPENWRT_RELEASE=\"Wiflow OS $VERSION (ImmortalWrt 25.12 r0-495af17)\"/" \
       "$F/usr/lib/os-release"
sed -i -e "s/^DEVICE_MANUFACTURER=.*/DEVICE_MANUFACTURER='Wiflow'/" \
       -e "s|^DEVICE_MANUFACTURER_URL=.*|DEVICE_MANUFACTURER_URL='https://wiflow.projifylab.com/'|" \
       -e "s/^DEVICE_PRODUCT=.*/DEVICE_PRODUCT='NR3053'/" "$F/etc/device_info"
# hostname for configs generated after a reset
grep -q "hostname='ImmortalWrt'" "$F/bin/config_generate" || die "config_generate: hostname default not found"
sed -i "s/hostname='ImmortalWrt'/hostname='Wiflow'/" "$F/bin/config_generate"

step "check rootfs"
python3 "$ROOT/tools/rom-check.py" "$F" "$W/fit/_images_rootfs-1.bin" "$UNSQUASHFS" | tee "$OUT/report/rom-check.txt"

[ -n "${SAVE_ROOT:-}" ] && { rm -rf "$SAVE_ROOT"; cp -a "$F" "$SAVE_ROOT"; }

step "squashfs"
"$MKSQUASHFS" "$F" "$W/rootfs.sqfs" -comp xz -b 256k -no-xattrs -all-root -noappend -quiet -no-progress > /dev/null
size="$(stat -c %s "$W/rootfs.sqfs")"
pad=$(( (4096 - size % 4096) % 4096 ))
[ "$pad" = 0 ] || head -c "$pad" /dev/zero >> "$W/rootfs.sqfs"
echo "rootfs $(stat -c %s "$W/rootfs.sqfs") bytes (v2.3.6: $(stat -c %s "$W/fit/_images_rootfs-1.bin"))"

step "sysupgrade image"
NAME="wiflow-os-$VERSION-viettel-nr3053-squashfs-sysupgrade.itb"
python3 "$ROOT/tools/fit-rootfs.py" "$W/stock.itb" "$W/rootfs.sqfs" "$OUT/$NAME"
"$FWTOOL" -I "$W/meta.json" "$OUT/$NAME"
cp "$W/meta.json" "$OUT/report/metadata.json"
(cd "$OUT" && sha256sum "$NAME" > SHA256SUMS && cat SHA256SUMS)
