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
| First-boot LAN/WAN and Wi-Fi **static generation paths** | [Run 37873707260](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37873707260): real SquashFS contains board_detect, config_generate, NR3053 LAN1–3/WAN board mapping and `/sbin/wifi config` before kmodloader | PASS (static only) |
| First-boot 2.4/5 GHz Wi-Fi and network on physical NR3053 | Dynamic UCI config generation **not executed on the router**; actual management reachability and both bands still unverified | BLOCK |
| Wiflow Setup, local captive portal, remote WP API integration | Not yet implemented in the public base image | BLOCK |
| Recovery from failed boot/flash with Wi-Fi-only access | Not demonstrated | BLOCK |
| Public source / binary / credential leak prevention | [Run 37874211552](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37874211552) — 12 Python tests plus tracked-file scan; private ZIP/ITB, secrets and device media are rejected | PASS |
| Uploaded Wiflow WP/IPK baseline provenance + protocol metadata | User-uploaded 2026-10-05 baseline verified locally: WP/IPK hashes match manifest; both use generation 4, API v1, snapshot schema 2 | PASS (inspection) |
| Private IPK-to-APK source port | NR3053 identity/model corrected in private staging; shell syntax passed, but package not compiled and no live router test | WARN (pre-build source only) |
| Wiflow revision-media immutability and legacy gate fallback | Existing WP media downloads use mutable media table; historical fallback authentication requires redesign before production | BLOCK |
| Public protocol and source-leak checks | [Run 37875222828](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37875222828) — 18 regressions including protocol consistency and source-leak checks | PASS |
| Firmware release / permission to flash | **Not approved** | **BLOCK** |

The base build uses a pinned public ImmortalWrt source commit `e39aded8420d454804a376e63400aff73da66247`, targets the NR3053 only, and removes four unreviewed automatic Wi-Fi calibration writers. It does **not** change the reference device's factory EEPROM, NAND partition declarations or bootloader.

Rootfs audit observed `lib/modules/6.12.94/mt_wifi.ko`, MT7981 firmware blobs, `dnsmasq-full`, `firewall4`, `uhttpd`, `rpcd`, `luci`, and the **APK package database** (ImmortalWrt 25.12). [Read-only first-boot audit](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37873707260) additionally confirms boot-time UCI configuration scripts and correct NR3053 interface mapping are present, explaining the missing pre-populated `network`/`wireless` configs. The latest audit also executed **four host regression tests** for real boot command ordering and comment/reversed-order rejection, all passing. This is source/firmware **static evidence only**; it does not prove live 2.4/5 GHz Wi-Fi, first-boot success, guest isolation, management recovery or Captive Portal on a real device.

## Work remaining — source-of-truth boundaries

1. **Hardware/network gate:** verify first-boot networking and both Wi-Fi radios without altering calibration or losing management access. Determine a real device recovery path before approving any flash.
2. **Wiflow runtime:** integrate local Captive Portal (Website / Image / Video), per-account full replacement media sync with verification and atomic activation, and authenticated Internet authorization.
3. **Management endpoints:** integrate gated Wiflow Setup and gated LuCI, pairing and device token with WordPress remote control at `https://projify.io.vn/wiflow/wp-json`, plus persistent configuration and per-device identity.
4. **Guest security/network:** guest isolation with firewall4, DHCP/DNS and pre-authorization Private DNS/bootstrap support without general Internet bypass; allow WordPress to change the guest SSID for 2.4/5 GHz when uplink is Ethernet.
5. **Compatibility and evidence:** preserve current analytics schema, verify runtime/UI/media parity using a reviewed Wiflow baseline, test reboot, pairing, portal display, guest authorization and rollback on a real target; release only when recovery is proven.

The earlier Wiflow WordPress/PWA package is **not** present in this public-source build. It must be supplied and reviewed before claiming feature parity; private materials must not be made public by default. A fresh `Wiflow-BASELINE-2026-10-05-PWA-HISTORY-BACK-FULL(8).zip` was explicitly uploaded and **read locally** on 2026-10-09. Its WordPress package and router IPK hashes matched the bundled manifest. Audited WP and IPK both declare data generation **4**, API version **1**, and Portal snapshot schema **2**. The router IPK source still targeted **CR6609** in device identity and pairing model and used legacy **opkg** packaging. A **private local conversion staging** replaced those NR3053 device identity/model literals and prepared an APK-native OpenWrt package skeleton; 25 shell scripts passed syntax checks. This staging has **not been compiled** and is **not in this public repository**. See [non-sensitive protocol contract](reference/wiflow-nr3053-contract.json). The public repository MUST NOT absorb private Wiflow application source, media, or raw baseline archives by default.

## Source and inspection files

- `scripts/build-nr3053-base.sh` — clean public-source base compilation, not a Wiflow installer.
- `.github/workflows/build-nr3053-base.yml` — no-cost GitHub-hosted base build.
- `reference/nr3053-golden.json` — user-stable firmware fingerprint and reference.
- `tools/check_nr3053_fit_reference.py` — FIT / DTB / device compatibility check.
- `tools/audit_nr3053_rootfs.py` — actual SquashFS and MTWiFi inventory.
- `.github/workflows/rootfs-audit.yml` — audit of a successful build image.
- `.github/workflows/postbuild-reference-audit.yml` — compare new images to golden reference.

**NO FLASH:** all artifact/report success statuses explicitly preserve `flash_authorization=BLOCK`. The repository does not provide a tested recovery procedure or final firmware.
