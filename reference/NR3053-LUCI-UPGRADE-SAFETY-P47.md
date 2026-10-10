# NR3053 P47 — LuCI/sysupgrade first-flash compatibility and single-device gate

**Status: ENGINEERING ONLY / NO FLASH.**

This document is an audit and optional non-flashing validation procedure for the
owner's **single** real Viettel NR3053 running existing ImmortalWrt firmware.
The evidence package `nr3053-source-fingerprint.txt` supplied on 2026-10-07
already records actual device/SoC, MTD names/sizes, UBI volumes and a Factory
partition SHA-256. **Do not recollect those facts without a material reason.**
A Factory hash is not an independent backup, and /proc/mtd does not prove
physical recovery or calibration authenticity.

## Exact upstream path (source-based, not on-device execution)

Source: pinned ImmortalWrt commit
`e39aded8420d454804a376e63400aff73da66247`.

1. `target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh`
   routes `viettel,nr3053` to `fit_check_image` for validation and
   `fit_do_upgrade` for the actual upgrade.
2. `package/utils/fitblk/files/fit.sh` uses `fit_check_sign`, resolves
   the boot device from device tree, then dispatches `fit_do_upgrade`
   to UBI/NAND, block or raw-MTD methods as observed at execution.
3. `package/base-files/files/sbin/sysupgrade` accepts
   **`sysupgrade -T -n /tmp/<reviewed-image>.itb`**. The `-T` validation
   exits after image checks, before `ubus call system sysupgrade`.
   It may write temporary state in volatile /tmp. It does not write NAND
   or permanently change configuration.
4. A passing test only establishes acceptance by the *running*
   firmware validation code. It cannot prove success of subsequent
   FIT/UBI writes, the next boot, Wiflow Gate/LuCI, radios, or rollback.

## Non-flashing P47 tool

`tools/nr3053-sysupgrade-test-readonly.sh` accepts **exactly**:

```sh
sh tools/nr3053-sysupgrade-test-readonly.sh \
  /tmp/REVIEWED_NR3053_CANDIDATE.itb \
  EXPECTED_EXACT_64_CHARACTER_SHA256
```

Only an authorized technician should stage the public candidate image and
run this on the existing router via a trusted shell. Do not run on a Wi-Fi-only
management path, and do not proceed if a required management connection is
unavailable. No command in this tool writes MTD, restarts service, commits UCI
or invokes a real upgrade. It checks board ID, both NR3053 + MT7981 DT IDs,
the **five required partition names and sizes** (not offsets), regular
volatile image file, exact SHA256, and actual `sysupgrade -T -n` acceptance.
Results contain only sanitized PASS/BLOCK codes.

The optional host-fixture mode is clearly marked
`HOST_FIXTURE_NOT_DEVICE`; host tests cannot replace an on-router result.
Every successful result intentionally ends in `first_flash_approval|BLOCK`
because the bootloader/Factory/restore gate is independent.

**Stop** if `sysupgrade` rejects the candidate; do **not** use LuCI
"Force Flash", `-F`, or `--ignore-minor-compat-version` to override
the rejection. Recheck the source, board and exact image; use only the
matching engineering artifact. Do not use an older P45 digest for P46 or
subsequent builds.

## Configuration policy — not yet approved for use

For a first transition from the existing ImmortalWrt to Wiflow:

- **Keep settings enabled** could carry incompatible `/etc/config/network`,
  `wireless`, `uhttpd`, firewall and DHCP state into the new image.
- **Keep settings disabled** is preferable *in design* to avoid that conflict,
  **but is NOT yet approved** because firstboot default network and account
  access must be verified end to end (physical/E5), and the owner only has
  one device.
- P46's `/etc/wiflow/stock` snapshot is captured after booting the new
  firmware. It does **not** preserve original stock firmware/Factory and cannot
  rescue kernel/rootfs or bootloader failures.
- The owner must never guess between the two LuCI choices during first flash.
  The final release must provide one independently validated policy.

## Physical release blockers

Even with a PASS from the read-only test:

1. Independently obtained off-device Factory/calibration and required
   bootloader/firmware recovery backups must be validated and held privately.
2. Independent bootloader/UART (or equivalent hardware) recovery must be
   **demonstrated**, including the ability to restore the original image.
3. A rebuilt exact-commit candidate must pass image-structure, rootfs,
   Wiflow source and first-boot static audits; all relevant host tests pass.
4. Management firstboot and both radio bands require target evidence. Guest
   isolation and Page 6 authorization require independent packet-level E5.
5. Controlled first-flash approval must be explicit and recorded.

**Status after P47 host CI or `-T` success: NO FLASH / S5-A recovery BLOCK.**
