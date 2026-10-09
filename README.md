# Wiflow firmware — Viettel NR3053

This is the single, clean PUBLIC engineering repository for NR3053. **Not a flash-ready Wiflow release.** Public upstream and open build/test glue only. Do not commit account data, API/device tokens, private media, private application baselines, or hardcoded recovery credentials.

## Verified evidence — 2026-10-09

| Gate | Actual evidence | Status |
| --- | --- | --- |
| Free runner | [Run 37825407301](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825407301) — 4 vCPU, 15 GiB RAM, ~87 GB available | PASS |
| Public upstream firmware compilation | [Run 37825631862](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825631862) — a nonempty NR3053 sysupgrade FIT artifact produced | PASS |
| Device FIT structure and stable-image comparison | [Run 37831729897](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37831729897) — no structural errors, expected new-image SHA difference | WARN |
| Original stable NR3053 reference | [Golden manifest](reference/nr3053-golden.json) — metadata and hashes from the user's stable 3.2.6 firmware; original binary **not** published | REFERENCE |
| Actual built SquashFS / init / radio | [Run 37872278328](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37872278328) — inspected extracted rootfs and driver | PASS |
| First-boot network and Wi-Fi provisioning | No on-device test. `/etc/config/network` and `/etc/config/wireless` not pre-populated in built rootfs. Their generation still needs verification | BLOCK |
| Wiflow Setup, local captive portal, remote WP API integration | Not yet implemented in the public base image | BLOCK |
| Recovery from failed boot/flash with Wi-Fi-only access | Not demonstrated | BLOCK |
| Firmware release / permission to flash | **Not approved** | **BLOCK** |

The base build uses a pinned public ImmortalWrt source commit `e39aded8420d454804a376e63400aff73da66247`, targets the NR3053 only, and removes four unreviewed automatic Wi-Fi calibration writers. It does **not** change the reference device's factory EEPROM, NAND partition declarations or bootloader.

Rootfs audit observed `lib/modules/6.12.94/mt_wifi.ko`, MT7981 firmware blobs, `dnsmasq-full`, `firewall4`, `uhttpd`, `rpcd`, `luci`, and the **APK package database** (ImmortalWrt 25.12). The evidence covers the built image only; it does not demonstrate 2.4 GHz / 5 GHz client connectivity or captive-portal operation on an NR3053.

## Work remaining — source-of-truth boundaries

1. **Hardware/network gate:** verify first-boot networking and both Wi-Fi radios without altering calibration or losing management access. Determine a real device recovery path before approving any flash.
2. **Wiflow runtime:** integrate local Captive Portal (Website / Image / Video), per-account full replacement media sync with verification and atomic activation, and authenticated Internet authorization.
3. **Management endpoints:** integrate gated Wiflow Setup and gated LuCI, pairing and device token with WordPress remote control at `https://projify.io.vn/wiflow/wp-json`, plus persistent configuration and per-device identity.
4. **Guest security/network:** guest isolation with firewall4, DHCP/DNS and pre-authorization Private DNS/bootstrap support without general Internet bypass; allow WordPress to change the guest SSID for 2.4/5 GHz when uplink is Ethernet.
5. **Compatibility and evidence:** preserve current analytics schema, verify runtime/UI/media parity using a reviewed Wiflow baseline, test reboot, pairing, portal display, guest authorization and rollback on a real target; release only when recovery is proven.

The earlier Wiflow WordPress/PWA package is **not** present in this public-source build. It must be supplied and reviewed before claiming feature parity; private materials must not be made public by default.

## Source and inspection files

- `scripts/build-nr3053-base.sh` — clean public-source base compilation, not a Wiflow installer.
- `.github/workflows/build-nr3053-base.yml` — no-cost GitHub-hosted base build.
- `reference/nr3053-golden.json` — user-stable firmware fingerprint and reference.
- `tools/check_nr3053_fit_reference.py` — FIT / DTB / device compatibility check.
- `tools/audit_nr3053_rootfs.py` — actual SquashFS and MTWiFi inventory.
- `.github/workflows/rootfs-audit.yml` — audit of a successful build image.
- `.github/workflows/postbuild-reference-audit.yml` — compare new images to golden reference.

**NO FLASH:** all artifact/report success statuses explicitly preserve `flash_authorization=BLOCK`. The repository does not provide a tested recovery procedure or final firmware.
