#!/bin/sh
# Build the Wiflow Setup package for Wiflow OS (apk v3, noarch).
#   APK=/path/to/apk (apk-tools 3.x)  OUT=dir  sh apk/wiflow/build.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
APK=${APK:-apk}
OUT=${OUT:-$HERE/../../out}
NAME=wiflow-setup
VERSION=$(sed -n "s/^export const VERSION = '\(.*\)';/\1/p" "$HERE/files/usr/share/ucode/wiflow/setup.uc")
REL=${REL:-1}
mkdir -p "$OUT"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a "$HERE/files/." "$STAGE/"
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE"/usr/libexec/wiflow/* "$STAGE"/etc/init.d/wiflow "$STAGE"/etc/hotplug.d/ntp/20-wiflow
"$APK" mkpkg \
	--info "name:$NAME" \
	--info "version:$VERSION-r$REL" \
	--info "description:Wiflow Setup for Wiflow OS (Viettel NR3053): source Internet, guest WiFi, Wiflow account" \
	--info "arch:noarch" \
	--info "license:Proprietary" \
	--info "origin:wiflow" \
	--info "url:https://wiflow.projifylab.com" \
	--info "maintainer:Wiflow" \
	--info "depends:ucode ucode-mod-fs ucode-mod-uci ucode-mod-ubus rpcd rpcd-mod-ucode luci-base curl wireless-tools" \
	--script "post-install:$HERE/scripts/post-install" \
	--script "post-upgrade:$HERE/scripts/post-upgrade" \
	--script "pre-deinstall:$HERE/scripts/pre-deinstall" \
	--script "post-deinstall:$HERE/scripts/post-deinstall" \
	--files "$STAGE" \
	--output "$OUT/$NAME-$VERSION-r$REL.apk"
echo "$OUT/$NAME-$VERSION-r$REL.apk"
