# Wiflow firmware — Viettel NR3053

This is the public source and engineering-build repository for NR3053. **Not a flash-ready Wiflow release.** Original Wiflow NR3053 source and test/build glue are provided under the [MIT License](LICENSE), subject to separate third-party upstream licenses. Never commit account data, API/device tokens, private media or application baseline archives. The openly documented fixed emergency Gate `WIFDIDNR3053` is a deliberate project requirement, **not a secret or substitute for account authentication**.

## Verified evidence — 2026-10-09

| Gate | Actual evidence | Status |
| --- | --- | --- |
| Free runner | [Run 37825407301](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825407301) — 4 vCPU, 15 GiB RAM, ~87 GB available | PASS |
| Public upstream firmware compilation | [Run 37825631862](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825631862) — a nonempty NR3053 sysupgrade FIT artifact produced | PASS |
| Device FIT structure and stable-image comparison | [Run 37831729897](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37831729897) — no structural errors, expected new-image SHA difference | WARN |
| Original stable NR3053 reference | [Golden manifest](reference/nr3053-golden.json) — metadata and hashes from the user's stable 3.2.6 firmware; original binary **not** published | REFERENCE |
| Actual built SquashFS / init / radio | [Run 37872278328](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37872278328) — inspected extracted rootfs and driver | PASS |
| First-boot LAN/WAN and Wi-Fi **static generation paths** | [Run 37873707260](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37873707260): real SquashFS contains board_detect, config_generate, NR3053 LAN1–3/WAN board mapping and `/sbin/wifi config` before kmodloader | PASS (static only) |
| Guest-IP management Gate routing (source) | [Run 37880482701](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37880482701) validates guest firewall4 ACCEPT to `10.0.0.1:80` and `10.0.0.2:80`, captive redirect exceptions, guarded LuCI `:8081`, and executable 6-digit device PIN from guest subnet. Real packet flow not verified | PASS (source only) |
| First-boot 2.4/5 GHz Wi-Fi and network on physical NR3053 | Dynamic UCI config generation **not executed on the router**; actual management reachability and both bands still unverified | BLOCK |
| Wiflow Setup, local captive portal, remote WP API integration | NR3053 experimental source staged and Kconfig-selected ([experimental build](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37876660880)); no final integrated image or device-runtime verification yet | BLOCK (runtime) |
| Recovery from failed boot/flash with Wi-Fi-only access | Not demonstrated | BLOCK |
| Public source / binary / credential leak prevention | [Run 37874211552](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37874211552) — 12 Python tests plus tracked-file scan; private ZIP/ITB, secrets and device media are rejected | PASS |
| Uploaded Wiflow WP/IPK baseline provenance + protocol metadata | User-uploaded 2026-10-05 baseline verified locally: WP/IPK hashes match manifest; both use generation 4, API v1, snapshot schema 2 | PASS (inspection) |
| Public IPK-to-APK source port | 43 package text/config files imported, 1 status metadata record; NR3053 ID/model and package selection verified; [source tests](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37878145010) passed | PASS (source only) |
| Wiflow revision-media immutability and shared emergency Gate | WP media for historical revisions still require immutable snapshots. The permanently enabled public string `WIFDIDNR3053` is implemented in both management Gates but hardware network isolation and downstream account safety remain unverified | BLOCK (release) |
| Public protocol and source-leak checks | [Latest baseline contract run](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37878981111) covers permanent Gate, source leak checks, DoT preauth, atomic media activation, and dual-band guest SSID source invariants | PASS (source) |
| Firmware release / permission to flash | **Not approved** | **BLOCK** |

The base build uses a pinned public ImmortalWrt source commit `e39aded8420d454804a376e63400aff73da66247`, targets the NR3053 only, and removes four unreviewed automatic Wi-Fi calibration writers. It does **not** change the reference device's factory EEPROM, NAND partition declarations or bootloader.

Rootfs audit observed `lib/modules/6.12.94/mt_wifi.ko`, MT7981 firmware blobs, `dnsmasq-full`, `firewall4`, `uhttpd`, `rpcd`, `luci`, and the **APK package database** (ImmortalWrt 25.12). [Read-only first-boot audit](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37873707260) additionally confirms boot-time UCI configuration scripts and correct NR3053 interface mapping are present, explaining the missing pre-populated `network`/`wireless` configs. The latest audit also executed **four host regression tests** for real boot command ordering and comment/reversed-order rejection, all passing. This is source/firmware **static evidence only**; it does not prove live 2.4/5 GHz Wi-Fi, first-boot success, guest isolation, management recovery or Captive Portal on a real device.

## Management access and no-Ethernet installation limitation

The source currently **disables stock radio APs**, creates an **unencrypted Wiflow guest SSID**, leases client addresses in `10.10.10.0/24`, and explicitly allows those guest clients to reach the Gate pages at `10.0.0.1:80` and `10.0.0.2:80`. By contrast, the hardcoded emergency Gate `WIFDIDNR3053` is currently accepted only for requests whose source address is `10.0.0.x`.

**BLOCK — wireless-only first enrollment:** A user connected solely to the Wiflow guest SSID receives `10.10.10.x` and therefore cannot use the emergency Gate, even though the Gate page can load. This is not solved by an otherwise successful firmware build; it requires an explicit safe decision about management-network access or physically authorized initial enrollment. Do not broaden root/LuCI access from the open guest SSID by accident. The ordinary six-digit device PIN remains enabled, but the device ID is not displayed before login. The default LuCI root credential and true hardware recovery path also require verification.

## Work remaining — source-of-truth boundaries

1. **Hardware/network gate:** verify first-boot networking and both Wi-Fi radios without altering calibration or losing management access. Determine a real device recovery path before approving any flash.
2. **Wiflow runtime:** integrate local Captive Portal (Website / Image / Video), per-account full replacement media sync with verification and atomic activation, and authenticated Internet authorization.
3. **Management endpoints:** integrate gated Wiflow Setup and gated LuCI, pairing and device token with WordPress remote control at `https://projify.io.vn/wiflow/wp-json`, plus persistent configuration and per-device identity.
4. **Guest security/network:** guest isolation with firewall4, DHCP/DNS and pre-authorization Private DNS/bootstrap support without general Internet bypass; allow WordPress to change the guest SSID for 2.4/5 GHz when uplink is Ethernet.
5. **Compatibility and evidence:** preserve current analytics schema, verify runtime/UI/media parity using a reviewed Wiflow baseline, test reboot, pairing, portal display, guest authorization and rollback on a real target; release only when recovery is proven.

The earlier Wiflow WordPress/PWA package is **not** present in this public-source build. It must be supplied and reviewed before claiming feature parity; private materials must not be made public by default. A fresh `Wiflow-BASELINE-2026-10-05-PWA-HISTORY-BACK-FULL(8).zip` was explicitly uploaded and **read locally** on 2026-10-09. Its WordPress package and router IPK hashes matched the bundled manifest. Audited WP and IPK both declare data generation **4**, API version **1**, and Portal snapshot schema **2**. The router IPK source still targeted **CR6609** in device identity and pairing model and used legacy **opkg** packaging. With the repository owner's explicit approval, a sanitized **source-only Wiflow device port** was committed to [`package/wiflow-setup/`](package/wiflow-setup/) at commit [`5b1aec9`](https://github.com/capt4780/wiflow-fw-nr3053/commit/5b1aec9277033cd6b7cf7a6f38fae00aa4c8af93). It comprises 44 text files (43 package sources and one status record), preserving generation 4 / API 1 / snapshot schema 2 and targeting NR3053. The original WP baseline, original IPK, media, logo and fonts were **not** published. The compiled APK-native package and device runtime are **not yet verified**; the experimental build is [GitHub Actions #37876660880](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37876660880). See [non-sensitive protocol contract](reference/wiflow-nr3053-contract.json). The public repository MUST NOT absorb private Wiflow application source, media, or raw baseline archives by default.

## Guest-client access to management Gates — canonical routing requirement

- A client assigned `10.10.10.x` must be able to load Wiflow Setup Gate at `http://10.0.0.1/` and LuCI Gate at `http://10.0.0.2/` even **before Captive Portal Internet authorization**. Captive HTTP interception must exempt both addresses.
- Only the gate entrypoints (TCP 80) are unconditionally reachable from the guest zone. `10.0.0.2:8081` remains denied by the fw4 nftables input gate unless LuCI Gate has granted that client a temporary entry; LuCI login still follows it.
- Guest addresses can pass both Gate handlers with the normal **last six digits of device ID**. The persistent shared `WIFDIDNR3053` emergency code is **currently limited to client IPs `10.0.0.x`**, not guest IPs; extending that shared public-code authorization to untrusted clients has not been approved in the source. This is an explicit remaining requirement mismatch; DO NOT claim guest emergency-code parity.
- A PASS from source tests does not demonstrate firewall4/netfilter connectivity on physical hardware. E5 guest-Gate checks, direct-port denial, session expiry, guest source spoofing, and firmware recovery remain release **BLOCK**.

## Public device-source port and active experimental build (not for flashing)

- **Public component owner:** `package/wiflow-setup/` (OpenWrt package source, build via APK on ImmortalWrt 25.12); WordPress remains remote manager and is **not** in public source.
- **Permanent alternate Gate code (source only):** Both Wiflow Setup (`10.0.0.1`) and LuCI Gate (`10.0.0.2`) accept either the final six numeric digits of the router's device ID **or** the permanently enabled `WIFDIDNR3053` string. The shared verifier lives in `package/wiflow-setup/files/usr/lib/wiflow/gate-code.sh`. The emergency code is accepted only when the client is on management subnet `10.0.0.x`; the normal device PIN keeps its existing behavior. The alternate Gate works before and after enrollment and before device ID initialization. Existing five-failures/60-second throttling, Setup login and LuCI root login remain unchanged. **SECURITY WARNING:** this shared string is hardcoded in a public repository and is not secret; it reduces the Gate's security to reachability controls and the password authentication behind it. Especially with a default LuCI root password, the firmware is NOT approved for unattended/production deployment. No physical recovery method has been tested.
- **Assets:** the user-specific branding logo and Inter binary fonts are excluded, replaced with Wiflow text/system-font fallback; exact visual parity with original Portal is therefore **NOT verified**.
- **Offline source evidence:** device shell syntax checked (26 shell scripts), and public CI host tests cover protocol, device ID, onboarding guard and credential/binary exclusion. None of this is proof that the router will display the Portal or recover from a failed boot.
- **Build owner:** [Experimental source build workflow](.github/workflows/build-nr3053-wiflow.yml) sets `WIFLOW_SOURCE_BUILD=1` and stages this device package into a pinned ImmortalWrt source tree; it must produce a real sysupgrade FIT plus both golden and rootfs audit reports before claiming a successful engineering image.
- **Strict BLOCK:** Wiflow Setup/Portal on the actual NR3053, both Wi-Fi bands, first-boot management reachability, true emergency recovery, Private DNS guest firewall proof, revision-immutable WP media and E5 end-to-end pairing/authorization are not validated. **DO NOT FLASH engineering images.**

## Source and inspection files

- `scripts/build-nr3053-base.sh` — pinned public NR3053 source compilation; optional experimental Wiflow source selection via `WIFLOW_SOURCE_BUILD=1`.
- `.github/workflows/build-nr3053-base.yml` — no-cost GitHub-hosted base build.
- `reference/nr3053-golden.json` — user-stable firmware fingerprint and reference.
- `tools/check_nr3053_fit_reference.py` — FIT / DTB / device compatibility check.
- `tools/audit_nr3053_rootfs.py` — actual SquashFS and MTWiFi inventory.
- `.github/workflows/rootfs-audit.yml` — audit of a successful build image.
- `.github/workflows/postbuild-reference-audit.yml` — compare new images to golden reference.

**NO FLASH:** all artifact/report success statuses explicitly preserve `flash_authorization=BLOCK`. The repository does not provide a tested recovery procedure or final firmware.
