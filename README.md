# Wiflow firmware — Viettel NR3053

This is the public source and engineering-build repository for NR3053. **Not a flash-ready Wiflow release.** Original Wiflow NR3053 source and test/build glue are provided under the [MIT License](LICENSE), subject to separate third-party upstream licenses. Never commit account data, API/device tokens, private media or application baseline archives. The openly documented fixed emergency Gate `WIFDIDNR3053` is a deliberate project requirement, **not a secret or substitute for account authentication**.

## Canonical state — 2026-10-10 (verified live)

- **Latest source baseline:** `main=ab3632d6624a8d34ed01476ba1ceacbc8cf52bcb` (S5 read-only acceptance tools; no device package changes).
- **Latest exact engineering firmware FIT:** source commit `acae341c52cdadfdef4ff60e08afae218638b08c`, [hosted build #38011329173](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38011329173), [artifact #11655088477](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38011329173/artifacts/11655088477), ITB SHA-256 `630a5dda0a00470c9beae98b803c423bf7dc5745644dbca0605ca936748403c4`. Exact built image audit: `static_gate=PASS`, 23/23 required Wiflow files, `root_shadow_gate=PASS`, 279 observed packages. **Engineering only, NOT FOR FLASHING.**
- **S4 merged and host tested:** Gate device/emergency parity for management and guest subnets; LuCI root credential provisioning (`root/1234`, publicly weak development default); captive authorization only after a valid POST; WordPress Portal ACK retry; atomic media replacement and captive firewall heartbeat idempotence. Tests and static image audit do **not** prove runtime client flows.
- **S5 collection tools available:** [read-only field diagnostic](tools/nr3053-s5-readonly.sh), [independent S5 acceptance plan](reference/NR3053-S5-READONLY-ACCEPTANCE.md), merged via [PR #24](https://github.com/capt4780/wiflow-fw-nr3053/pull/24). [Public Source Safety](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38017354021) PASS; 113/113 PR host tests. **No physical NR3053 test or proven UART/bootloader recovery. S5 NOT VERIFIED, S6 BLOCK, NO FLASH.**
- Historic entries below are evidence from **2026-10-09**, retained for provenance, not the latest project status. Current evidence is tracked in [Issue #5](https://github.com/capt4780/wiflow-fw-nr3053/issues/5).

## Historical engineering evidence — 2026-10-09

| Gate | Actual evidence | Status |
| --- | --- | --- |
| Free runner | [Run 37825407301](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825407301) — 4 vCPU, 15 GiB RAM, ~87 GB available | PASS |
| Public upstream firmware compilation | [Run 37825631862](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37825631862) — a nonempty NR3053 sysupgrade FIT artifact produced | PASS |
| Device FIT structure and stable-image comparison | [Run 37831729897](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37831729897) — no structural errors, expected new-image SHA difference | WARN |
| Original stable NR3053 reference | [Golden manifest](reference/nr3053-golden.json) — metadata and hashes from the user's stable 3.2.6 firmware; original binary **not** published | REFERENCE |
| Actual built SquashFS / init / radio | [Run 37872278328](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37872278328) — inspected extracted rootfs and driver | PASS |
| First-boot LAN/WAN and Wi-Fi **static generation paths** | [Run 37873707260](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37873707260): real SquashFS contains board_detect, config_generate, NR3053 LAN1–3/WAN board mapping and `/sbin/wifi config` before kmodloader | PASS (static only) |
| Guest-IP management Gate and Setup enrollment (source) | [Run 37880903682](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/37880903682): **43/43** source regressions PASS, including guest Gate entrypoints, nftables LuCI backend guard, executed client-IP allowlist and mandatory Gate cookie/same-origin check before Setup first-owner enrollment. Real device packet flow not verified | PASS (source only) |
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

The source currently **disables stock radio APs**, creates an **unencrypted Wiflow guest SSID**, leases client addresses in `10.10.10.0/24`, and explicitly allows those guest clients to reach the Gate pages at `10.0.0.1:80` and `10.0.0.2:80`. The canonical verifier now permits the permanent emergency Gate code from management `10.0.0.x` **and** guest `10.10.10.x` sources. Gate entry is distinct from Wiflow Setup owner authentication and LuCI root login; physical guest reachability is not yet verified.

**BLOCK — wireless-only installation / first-owner security / recovery not tested:** Code now accepts both the normal six-digit device PIN and the permanent emergency code from `10.10.10.x` guest IPs, but that does not prove guest Gate reachability or that a new owner can safely commission the router. The account login behind each Gate remains separate. Production use of the known weak development LuCI password `root/1234` requires a reviewed rotation/onboarding policy. Do not flash on a Wi-Fi-only device without a verified independent physical recovery path.

## Work remaining — source-of-truth boundaries

1. **Hardware/network gate:** verify first-boot networking and both Wi-Fi radios without altering calibration or losing management access. Determine a real device recovery path before approving any flash.
2. **Wiflow runtime:** implemented and image-static-audited local Website / Image / Video Portal, per-account full-replacement atomic media sync and explicit local Internet authorization; run end-to-end Page 6/guest packet tests on real NR3053 hardware.
3. **Management endpoints:** confirm gated Wiflow Setup/LuCI, actual credential login, pairing and remote WordPress heartbeat/ACK/media behaviour on a powered lab unit; the implementation is source-integrated but runtime not verified.
4. **Guest security/network:** guest isolation with firewall4, DHCP/DNS and pre-authorization Private DNS/bootstrap support without general Internet bypass; allow WordPress to change the guest SSID for 2.4/5 GHz when uplink is Ethernet.
5. **Compatibility and evidence:** preserve current analytics schema, verify runtime/UI/media parity using a reviewed Wiflow baseline, test reboot, pairing, portal display, guest authorization and rollback on a real target; release only when recovery is proven.

The earlier Wiflow WordPress/PWA package is **not** present in this public-source build. It must be supplied and reviewed before claiming feature parity; private materials must not be made public by default. A fresh `Wiflow-BASELINE-2026-10-05-PWA-HISTORY-BACK-FULL(8).zip` was explicitly uploaded and **read locally** on 2026-10-09. Its WordPress package and router IPK hashes matched the bundled manifest. Audited WP and IPK both declare data generation **4**, API version **1**, and Portal snapshot schema **2**. The router IPK source still targeted **CR6609** in device identity and pairing model and used legacy **opkg** packaging. With the repository owner's explicit approval, a sanitized **source-only Wiflow device port** was committed to [`package/wiflow-setup/`](package/wiflow-setup/) at commit [`5b1aec9`](https://github.com/capt4780/wiflow-fw-nr3053/commit/5b1aec9277033cd6b7cf7a6f38fae00aa4c8af93). It comprises 44 text files (43 package sources and one status record), preserving generation 4 / API 1 / snapshot schema 2 and targeting NR3053. The original WP baseline, original IPK, media, logo and fonts were **not** published. The APK-native package and required files **are verified in the exact built FIT** from [GitHub Actions #38011329173](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38011329173); live device runtime and WP end-to-end feature parity remain unverified. See [non-sensitive protocol contract](reference/wiflow-nr3053-contract.json). The public repository MUST NOT absorb private Wiflow application source, media, or raw baseline archives by default.

## Guest Internet fail-closed before Portal readiness

The Wiflow guest zone must never inherit an unconditional `guest -> WAN` forwarding rule from network initialization. `portal-firewall` alone owns that forwarding: it activates the UCI forwarding rule together with captive nftables rules **only when an active local `portal.json` snapshot exists**, and removes forwarding when Captive Portal is disabled or its local snapshot disappears. This preserves pre-auth local DNS, Private DNS on TCP/853, and IP-guest access to **both management Gate pages** without permitting general Internet before Portal confirmation. Static source/firmware checks cover this lifecycle; **hardware validation remains BLOCK**.

## Guest-client access to management Gates — canonical routing requirement

- A client assigned `10.10.10.x` must be able to load Wiflow Setup Gate at `http://10.0.0.1/` and LuCI Gate at `http://10.0.0.2/` even **before Captive Portal Internet authorization**. Captive HTTP interception must exempt both addresses.
- **Fixed missing guest enrollment path:** `www-wiflow/cgi-bin/enroll` now permits `10.10.10.*` after the same Gate session and strict `Origin: http://10.0.0.1` checks already used on the management LAN; other subnets remain denied. Note that guest first-owner enrollment is sensitive while a brand-new router has no Setup password; provision the first owner on a trusted connection and check physical access policy.
- Only the gate entrypoints (TCP 80) are unconditionally reachable from the guest zone. `10.0.0.2:8081` remains denied by the fw4 nftables input gate unless LuCI Gate has granted that client a temporary entry; LuCI login still follows it.
- Guest addresses can pass both Gate handlers with the normal **last six digits of device ID**. The permanent `WIFDIDNR3053` emergency Gate string now has **source-level parity** for `10.0.0.x` and `10.10.10.x` clients. It only opens a Gate, not the Setup/LuCI account; E5 must still verify guest reachability and backend isolation.
- A PASS from source tests does not demonstrate firewall4/netfilter connectivity on physical hardware. E5 guest-Gate checks, direct-port denial, session expiry, guest source spoofing, and firmware recovery remain release **BLOCK**.

## Public device-source port and active experimental build (not for flashing)

- **Public component owner:** `package/wiflow-setup/` (OpenWrt package source, build via APK on ImmortalWrt 25.12); WordPress remains remote manager and is **not** in public source.
- **Permanent alternate Gate code (source only):** Both Wiflow Setup (`10.0.0.1`) and LuCI Gate (`10.0.0.2`) accept either the final six numeric digits of the router's device ID **or** the permanently enabled `WIFDIDNR3053` string. The shared verifier lives in `package/wiflow-setup/files/usr/lib/wiflow/gate-code.sh`. The emergency Gate code is accepted for management `10.0.0.x` or guest `10.10.10.x` source addresses; the normal device PIN keeps its existing behaviour. This is source-only until real-client testing. The alternate Gate works before and after enrollment and before device ID initialization. Existing five-failures/60-second throttling, Setup login and LuCI root login remain unchanged. **SECURITY WARNING:** this shared string is hardcoded in a public repository and is not secret; it reduces the Gate's security to reachability controls and the password authentication behind it. Especially with a default LuCI root password, the firmware is NOT approved for unattended/production deployment. No physical recovery method has been tested.
- **Assets:** the user-specific branding logo and Inter binary fonts are excluded, replaced with Wiflow text/system-font fallback; exact visual parity with original Portal is therefore **NOT verified**.
- **Offline source evidence:** public CI now includes 113/113 host regressions plus public-source leak checks; the latest exact FIT was audited separately. Neither is proof of hardware Wi-Fi, real guest authorization, on-device WordPress sync, or recovery from a failed boot.
- **Build owner:** [Experimental source build workflow](.github/workflows/build-nr3053-wiflow.yml) sets `WIFLOW_SOURCE_BUILD=1` and stages this device package into a pinned ImmortalWrt source tree; it must produce a real sysupgrade FIT plus both golden and rootfs audit reports before claiming a successful engineering image.
- **Strict BLOCK:** Wiflow Setup/Portal on the actual NR3053, both Wi-Fi bands, first-boot management reachability, true emergency recovery, Private DNS guest firewall proof, revision-immutable WP media and E5 end-to-end pairing/authorization are not validated. **DO NOT FLASH engineering images.**

## Source and inspection files

- `scripts/build-nr3053-base.sh` — pinned public NR3053 source compilation; optional experimental Wiflow source selection via `WIFLOW_SOURCE_BUILD=1`.
- `.github/workflows/build-nr3053-base.yml` — no-cost GitHub-hosted base build.
- `reference/nr3053-golden.json` — user-stable firmware fingerprint and reference.
- `tools/check_nr3053_fit_reference.py` — FIT / DTB / device compatibility check.
- `tools/audit_nr3053_rootfs.py` — actual SquashFS and MTWiFi inventory.
- `tools/nr3053-s5-readonly.sh` — safe read-only field report on an already-running lab device; always keeps flash authorization BLOCK.
- `reference/NR3053-S5-READONLY-ACCEPTANCE.md` — full physical/radio/Gate/Portal/WP/recovery evidence plan.
- `.github/workflows/rootfs-audit.yml` — audit of a successful build image.
- `.github/workflows/postbuild-reference-audit.yml` — compare new images to golden reference.

**NO FLASH:** all artifact/report success statuses explicitly preserve `flash_authorization=BLOCK`. The repository does not provide a tested recovery procedure or final firmware.
