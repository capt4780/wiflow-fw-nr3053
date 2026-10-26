#!/bin/bash
# Builds what the bench and the package build need, into $PFX (default /opt/pfx):
# libubox, uci, ubus (ubusd), rpcd with ucode plugins, ucode (same commit as
# the router) with fs/uci/ubus/uloop, and apk-tools 3.0.5 (the router's apk).
# needs: cmake, gcc, make, pkg-config, libjson-c-dev, libssl-dev, zlib1g-dev
set -euo pipefail
PFX="${PFX:-/opt/pfx}"
SRC="${SRC:-/tmp/wfdeps}"
UCODE_COMMIT="${UCODE_COMMIT:-85922056}"
APK_TOOLS_TAG="${APK_TOOLS_TAG:-v3.0.5}"
mkdir -p "$PFX/lib" "$PFX/include" "$SRC"
J="-j$(nproc)"
FLAGS=(-DCMAKE_INSTALL_PREFIX="$PFX" -DCMAKE_PREFIX_PATH="$PFX"
	-DCMAKE_C_FLAGS="-I$PFX/include"
	-DCMAKE_EXE_LINKER_FLAGS="-L$PFX/lib -Wl,-rpath,$PFX/lib"
	-DCMAKE_SHARED_LINKER_FLAGS="-L$PFX/lib -Wl,-rpath,$PFX/lib")

get(){ [ -d "$SRC/$1" ] || git clone -q "$2" "$SRC/$1"; [ -z "${3:-}" ] || git -C "$SRC/$1" checkout -q "$3"; }

get libubox https://github.com/openwrt/libubox.git
cmake -S "$SRC/libubox" -B "$SRC/libubox/b" "${FLAGS[@]}" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF > /dev/null
make -C "$SRC/libubox/b" $J install > /dev/null

get uci https://github.com/openwrt/uci.git
cmake -S "$SRC/uci" -B "$SRC/uci/b" "${FLAGS[@]}" -DBUILD_LUA=OFF > /dev/null
make -C "$SRC/uci/b" $J install > /dev/null

get ubus https://github.com/openwrt/ubus.git
cmake -S "$SRC/ubus" -B "$SRC/ubus/b" "${FLAGS[@]}" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF > /dev/null
make -C "$SRC/ubus/b" $J install > /dev/null

get ucode https://github.com/jow-/ucode.git "$UCODE_COMMIT"
cmake -S "$SRC/ucode" -B "$SRC/ucode/b" "${FLAGS[@]}" -DCMAKE_INSTALL_PREFIX=/usr/local \
	-DUCI_SUPPORT=ON -DUBUS_SUPPORT=ON -DULOOP_SUPPORT=ON -DFS_SUPPORT=ON -DMATH_SUPPORT=ON -DLOG_SUPPORT=ON \
	-DRTNL_SUPPORT=OFF -DNL80211_SUPPORT=OFF -DDIGEST_SUPPORT=OFF -DSOCKET_SUPPORT=OFF -DZLIB_SUPPORT=OFF -DDEBUG_SUPPORT=OFF > /dev/null
make -C "$SRC/ucode/b" $J > /dev/null
mkdir -p "$PFX/ucode" "$PFX/include/ucode"
cp "$SRC/ucode/b/ucode" "$SRC/ucode/b"/*.so* "$PFX/ucode/"
cp "$SRC/ucode/b"/libucode.so* "$PFX/lib/"
cp "$SRC/ucode/include/ucode"/*.h "$PFX/include/ucode/"

get rpcd https://github.com/openwrt/rpcd.git
cmake -S "$SRC/rpcd" -B "$SRC/rpcd/b" "${FLAGS[@]}" -DFILE_SUPPORT=OFF -DIWINFO_SUPPORT=OFF -DRPCSYS_SUPPORT=OFF -DUCODE_SUPPORT=ON > /dev/null
make -C "$SRC/rpcd/b" $J install > /dev/null

get apk-tools https://github.com/alpinelinux/apk-tools.git "$APK_TOOLS_TAG"
make -C "$SRC/apk-tools" $J LUA=no ZSTD=no > /dev/null
cp "$SRC/apk-tools/src/apk" "$PFX/bin/apk"
cp "$SRC/apk-tools/src"/libapk.so* "$PFX/lib/"

echo "deps in $PFX:"; ls "$PFX/bin" "$PFX/sbin" "$PFX/ucode"
LD_LIBRARY_PATH="$PFX/lib" "$PFX/bin/apk" --version
