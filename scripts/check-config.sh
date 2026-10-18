#!/bin/bash
# Checks the resolved firmware config: NR3053 only, Wiflow and the WiFi stack
# in, the removed features out, MediaTek driver and kernel options exactly as in
# the stable v2.3.6 firmware.
# Usage: scripts/check-config.sh <resolved .config> <resolved upstream v2.3.6 .config>
set -euo pipefail
C="$1"; U="$2"; bad=0
y(){ grep -qx "CONFIG_PACKAGE_$1=y" "$C"; }
need(){ for p in "$@"; do y "$p" || { echo "MISSING $p"; bad=1; }; done; }
deny(){ for p in "$@"; do y "$p" && { echo "NOT ALLOWED $p"; bad=1; }; done; return 0; }

devs="$(grep -E '^CONFIG_TARGET_(DEVICE_)?mediatek_filogic_DEVICE_[a-z0-9_]+=y$' "$C" | sed 's/.*DEVICE_//; s/=y//' | sort -u | tr '\n' ' ')"
[ "$devs" = "viettel_nr3053 " ] || { echo "DEVICES: $devs (want viettel_nr3053 only)"; bad=1; }

need wiflow-setup kmod-mt_wifi kmod-warp kmod-conninfra wifi-dats mtwifi-cfg-ucode datconf ucode-mod-datconf \
     ucode-mod-l1parser l1util wireless-tools rpcd-mod-iwinfo libiwinfo luci-base luci-mod-admin-full \
     luci-app-firewall luci-app-mtwifi-cfg luci-i18n-base-vi uhttpd uhttpd-mod-ubus dnsmasq-full firewall4 \
     dropbear fitblk uboot-envtools jsonfilter uclient-fetch ca-bundle
deny luci luci-light luci-app-package-manager luci-proto-ipv6 luci-proto-ppp default-settings default-settings-chn \
     default-settings-vn luci-theme-aurora luci-app-aurora-config luci-app-turboacc-mtk luci-app-upnp miniupnpd \
     miniupnpd-nftables luci-app-ddns ddns-scripts wireguard-tools luci-proto-wireguard kmod-wireguard luci-app-adblock \
     adblock blockd tailscale luci-app-tailscale-community block-mount odhcp6c odhcpd odhcpd-ipv6only ppp \
     ppp-mod-pppoe kmod-ppp hnat-detect wpad-openssl wpad-basic-mbedtls luci-app-eqos-mtk mtkhqos_util zram-swap \
     kmod-zram htop nano tcpdump curl coreutils ipset kmod-usb3 kmod-tun
zh="$(grep -E '^CONFIG_PACKAGE_[^=]*zh[-_]c[nh][^=]*=y$' "$C" || true)"; [ -z "$zh" ] || { echo "NOT ALLOWED (Chinese): $zh"; bad=1; }
ipt="$(grep -E '^CONFIG_PACKAGE_(iptables|ip6tables)[^=]*=y$' "$C" || true)"; [ -z "$ipt" ] || { echo "NOT ALLOWED (iptables): $ipt"; bad=1; }

# MediaTek WiFi driver / WED / kernel options: identical to v2.3.6.
sym='^CONFIG_(MTK_|WARP_|WED_|CONNINFRA_|first_card|KERNEL_|TARGET_(BOARD|SUBTARGET|ARCH|mediatek)|LINUX_|ARCH=|CPU_TYPE|TARGET_OPTIMIZATION|GCC_|BINUTILS_|LIBC_|LIBC=)'
d="$(diff <(grep -E "$sym" "$U" | grep -v DEVICE | sort) <(grep -E "$sym" "$C" | grep -v DEVICE | sort) || true)"
if [ -n "$d" ]; then echo "DRIVER/KERNEL OPTIONS DIFFER FROM v2.3.6:"; echo "$d"; bad=1; else echo "driver, kernel and toolchain options: identical to v2.3.6"; fi
# Kernel modules: same set built (y or m) as v2.3.6, so the kernel is configured the same.
km(){ grep -E '^CONFIG_PACKAGE_kmod-[^=]+=(y|m)$' "$1" | sed 's/=.*//' | sort; }
extra="$(comm -13 <(km "$U") <(km "$C") | sed 's/CONFIG_PACKAGE_//' | tr '\n' ' ')"
miss="$(comm -23 <(km "$U") <(km "$C") | sed 's/CONFIG_PACKAGE_//' | tr '\n' ' ')"
echo "kernel modules vs v2.3.6: extra [${extra}] missing [${miss}]"
echo "firmware packages: $(grep -c '^CONFIG_PACKAGE_.*=y$' "$C") (v2.3.6: $(grep -c '^CONFIG_PACKAGE_.*=y$' "$U"))"
[ "$bad" = 0 ] && echo "CONFIG OK" || { echo "CONFIG CHECK FAILED"; exit 1; }
