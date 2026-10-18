#!/bin/bash
# Prepares the ImmortalWrt source tree for the Wiflow NR3053 firmware:
#   upstream quytttb/immortalwrt-mt798x-rebase pinned to v2.3.6 (the stable
#   firmware), feeds pinned to the commits that firmware was built from,
#   the Wiflow package, the lean config. Then resolves and checks the config.
# Usage: scripts/prepare.sh [source dir, default ./openwrt]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/openwrt}"
OUT="$ROOT/out"
UPSTREAM_URL=https://github.com/quytttb/immortalwrt-mt798x-rebase.git
UPSTREAM_COMMIT=495af17576e227358630e003428497b0fdb4feae   # tag v2.3.6
FEED_PACKAGES=4e8d525f20f4958cf0cf5159a661046825ea5d5f     # immortalwrt/packages openwrt-25.12, 2026-08-17
FEED_LUCI=287f6c898985638f597f7a5770f52abb540c1b95         # immortalwrt/luci openwrt-25.12 (LuCI 26.223.24507~287f6c8 in v2.3.6)

mkdir -p "$OUT"
if [ ! -d "$SRC/.git" ]; then
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$UPSTREAM_URL"
fi
git -C "$SRC" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$SRC" checkout -q --force --detach FETCH_HEAD
[ "$(git -C "$SRC" rev-parse HEAD)" = "$UPSTREAM_COMMIT" ] || { echo "upstream is not v2.3.6" >&2; exit 1; }
echo "upstream: $UPSTREAM_COMMIT (v2.3.6)"

cd "$SRC"
cat > feeds.conf <<EOT
src-git packages https://github.com/immortalwrt/packages.git^$FEED_PACKAGES
src-git luci https://github.com/immortalwrt/luci.git^$FEED_LUCI
EOT
./scripts/feeds update -a
./scripts/feeds install -a
for f in packages luci; do echo "feed $f: $(git -C feeds/$f rev-parse HEAD)"; done
[ "$(git -C feeds/packages rev-parse HEAD)" = "$FEED_PACKAGES" ] && [ "$(git -C feeds/luci rev-parse HEAD)" = "$FEED_LUCI" ] || { echo "feeds not pinned" >&2; exit 1; }

rm -rf package/wiflow-setup
cp -a "$ROOT/package/wiflow-setup" package/wiflow-setup

# Reference: the stable firmware's own config, resolved the same way.
cp defconfig/viettel-only.config .config
make defconfig >/dev/null
cp .config "$OUT/upstream-v2.3.6.config"

cp "$ROOT/config/nr3053.config" .config
make defconfig >/dev/null
cp .config "$OUT/nr3053.config"
bash "$ROOT/scripts/check-config.sh" "$OUT/nr3053.config" "$OUT/upstream-v2.3.6.config" | tee "$OUT/config-check.txt"
