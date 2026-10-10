# NR3053 S5 — read-only field acceptance (NO FLASH)

Status: **engineering evidence only**. This procedure does NOT provision, upgrade,
flash, configure, restart services, authorize guest Internet, or recover hardware.
Its automated report always ends with **e5_complete=BLOCK** and
**flash_authorization=BLOCK** until independent lab acceptance is documented.

## Single-router risk gate (ProjifyLab v5)

The owner has **only one NR3053**. Passing the host/source CI does not justify
testing its only bootable NAND image. In particular:

1. Preserve the owner's previously supplied `nr3053-source-fingerprint.txt`
   (2026-10-07) as **observed device evidence** for board, device tree, MTD
   partition names/sizes, UBI `fit` and `rootfs_data`, and the Factory
   *hash*. Do **not** repeatedly ask to recapture those known facts.
   A Factory hash does **not** constitute an off-device calibration backup.
2. A software snapshot in `/etc/wiflow/stock` is taken after booting the
   **new** firmware and only helps reverse its own startup UCI changes.
   This is not an image of the previous operating system, bootloader,
   Factory partition or EEPROM. Depending on sysupgrade's *keep settings*
   choice, it may also lack the previous router's private configuration.
3. P46 management-bootstrap recovery is a **best-effort** OS-level mechanism:
   failure can leave different management IPs active, the rollback service
   restart can itself fail, and no shell script runs if kernel/rootfs fails
   before procd. Do not equate P46 host tests with a guaranteed recovery.
4. **Before LuCI upload/upgrade**: an independently stored and independently
   validated backup of device-specific partitions, a privately documented
   UART/bootloader or equivalent hardware recovery and a tested original
   firmware restore procedure are required. Only authorized personnel should
   handle raw Factory/calibration data. Keep them out of public GitHub/chat.
5. Verify the exact candidate digest and source revision, stock-firmware
   `sysupgrade -T` image acceptance without writing flash, the FIT/UBI
   upgrade method, and one reviewed `keep settings` policy. Never override
   compatibility rejection with `-F`/Force Flash.
6. If any recovery evidence is missing, first-flash authorization is
   **BLOCK**, regardless of a new successful image build or 100% host CI.
   With one router and no proven physical rescue, use a second identical lab
   unit instead of risking the only unit.

A successful P46 source patch is not a waiver of any of these conditions.

## Actual starting state — S5-A before the first Wiflow flash

**As confirmed by the owner on 2026-10-10: no NR3053 has Wiflow installed or running.** The current devices are on their existing/stock firmware. It is **incorrect** to ask the owner to run `nr3053-s5-readonly.sh` against a device already running Wiflow; no such device exists. A hosted Wiflow FIT build cannot establish device-runtime E5 PASS.

**S5-A** starts on the original existing firmware. The separate read-only [stock inventory tool](../tools/nr3053-stock-preflight-readonly.sh) does not depend on Wiflow:

~~~sh
# Only if your existing stock firmware already offers authorized SSH access.
# Replace the literal account/address placeholder using your known stock access.
ssh 'ACCOUNT@STOCK_ROUTER_IP' 'sh -s' < tools/nr3053-stock-preflight-readonly.sh > nr3053-stock-preflight-report.txt
~~~

This reads the runtime board identifier and device-tree compatibility (NR3053 board **and MT7981 SoC**) when available, existing OS metadata, the *presence* of an MTD partition table and a calibration-name hint, and optional live IP/radio observations. A readable device-tree that explicitly lacks **either** pinned Golden identifier (`viettel,nr3053` or `mediatek,mt7981`) is **BLOCK** even when a board-name file claims NR3053; unavailable device-tree is **WARN**, never PASS. The script separately reports `dt_compatible` and `soc_compatible` without exposing raw strings. It also compares only the names and declared **sizes** of the five required MTD entries against the pinned Golden reference (`BL2`, `u-boot-env`, `Factory`, `FIP`, `ubi`). `golden_partition_sizes` reports `PASS` for observed matching entries, `WARN` for incomplete/unavailable inventory, and `BLOCK` for an observed required size mismatch or duplicate required name. The check ignores unrelated additional partitions, does not read any partition bytes and **cannot establish physical partition offsets, calibration validity, backup completeness or recovery capability**. It deliberately prints no partition contents, MAC/SSID, serial, secret, login or raw MTD layout. It never changes stock firmware and ends with `first_flash_approval|BLOCK`, `bootloader_recovery|NOT_VERIFIED` and `wiflow_s5_runtime|NOT_TESTED`.

If stock firmware does **not** provide an authorized shell/SSH (or access is Wi-Fi only), **do not force SSH, install packages, change bootloader settings or flash merely to run a test**. Collect the available non-sensitive board/revision and firmware-version details from the original UI and hardware label privately. An authorized technician may document the PCB/bootloader and a physically recoverable connection. This step cannot certify a recovery procedure.

### P48: offline verification against the already supplied 2026-10-07 fingerprint

The owner's existing **nr3053-source-fingerprint.txt** includes a direct read
of \`/dev/mtd2\` Factory SHA-256 and the actual \`/proc/mtd\` partition
inventory. **Do not request those observations again.** A checksum is **not**
a calibration backup and does not certify a physical rescue method.

After an authorized technician has obtained two private/offline Factory
backup copies through an independently approved procedure, optionally bind
the existing local fingerprint document to the consistency check:

~~~sh
python3 tools/nr3053-s5a-verify-factory-backup.py \
  --factory-a /PRIVATE/COPY-1.bin \
  --factory-b /PRIVATE/COPY-2.bin \
  --observed-fingerprint /PRIVATE/nr3053-source-fingerprint.txt
~~~

The checker validates full Factory size, distinct backup files, nonblank
contents, identical backup bytes and agreement with the pre-existing
on-device Factory digest. All raw inputs remain private: **never commit or
upload** the fingerprint text or Factory dumps to GitHub, public chat,
CI artifacts or third-party services. The script prints only verdict codes
without the sensitive digest.

A matching digest reduces the risk that the two backups come from a different
state or unrelated device, but cannot rule out a forged fingerprint,
read errors during the original capture, missing radio calibration validity,
incomplete NAND backup or an unavailable restore path.

Regardless of PASS here, **physical device origin** and **UART/bootloader
restore test** remain **NOT_VERIFIED**; first flash and release remain
**BLOCK** until independently evidenced. The script never writes the device.

### Optional S5-A offline Factory backup-copy consistency check

**Only after an authorized technician has privately obtained Factory backup copies
from the real stock NR3053 through a separately approved extraction procedure.**
Run this on an offline/trusted workstation, from the reviewed repository clone:

~~~sh
python3 tools/nr3053-s5a-verify-factory-backup.py \
  --factory-a /LOCAL/PRIVATE/FACTORY-COPY-A \
  --factory-b /LOCAL/PRIVATE/FACTORY-COPY-B
~~~

The tool reads only the two supplied local regular files and the public pinned
Golden metadata. It checks the expected Factory length (2 MiB), refuses
symlinks/same-inode hardlinks, rejects all-0xFF (erased) or all-0x00 (zeroed)
copies, checks SHA-256 equivalence of distinct local files, and detects basic
file mutations while reading. It prints **only status
codes** (never file paths, backup contents, individual hashes or device IDs).
There are no router commands, network calls, uploads, or device writes.
Exit code 0 means **copy-level local byte consistency only**.

Two matching files may still be copies of the same damaged, fake, wrong-board,
or incomplete source. This tool **does not validate** provenance, NAND
read errors, physical offsets, every partition, independently acquired dumps,
Factory calibration validity, bootloader usability, or ability to restore.
The required backup_device_origin and backup_restore_test always remain
NOT_VERIFIED; first_flash_approval always remains BLOCK. Keep private
backup files and any device details outside this public repository and chat.

**Gate between S5-A and S5-B (not yet met):** match the exact stock hardware variant to Golden, determine and independently validate an offline backup of calibration and partitions, confirm bootloader/UART recovery with a second management path on dedicated lab hardware, and approve a *separate* controlled first-flash plan. Do not treat GitHub Actions green tests, a readable MTD table, or two matching backup files as any of those proofs.

**S5-B** begins *only if* a designated lab NR3053 has actually booted a reviewed Wiflow candidate through an approved, recoverable process. The remainder of this runbook, including `nr3053-s5-readonly.sh`, applies to S5-B and **cannot be run as a Wiflow acceptance test on stock firmware**.

## Preconditions — S5-B only

1. Confirm exact hardware ID, PCB/bootloader revisions and radio/calibration map on
   the *actual* Viettel NR3053. A successful hosted FIT build is NOT evidence that
   the bootloader can recover from incompatible images.
2. Do not flash a Wi-Fi-only device. Before any future flash, obtain a separately
   verified physical/UART recovery, powered serial console, working backup strategy,
   verified firmware restore procedure, and a second management path.
3. Use only a router already running a **known lab Wiflow candidate** for this
   script. On original stock firmware, missing Wiflow files are normal and will
   produce BLOCK; do not use that result as a reason to flash.

## S5-B Wiflow device-side evidence collection — no changes

From a trusted management workstation with a reviewed copy of the script in this
repository, and only when the device is already reachable over a safe management
path:

~~~sh
ssh root@10.0.0.1 'sh -s' < tools/nr3053-s5-readonly.sh > nr3053-s5-readonly-report.txt
~~~

The script queries runtime board name, LAN and guest interface addresses,
existence of local CGI handlers, active Portal snapshot schema/generation,
firewall nft chain/set presence, and observed 2.4/5 GHz radio channels.
It **does not** enumerate connected devices or output the Wi-Fi SSID, MACs,
tokens, root hashes, pairing codes or device identity.

The report format is one sanitized line per assertion:

~~~text
target_board|PASS|exact_nr3053_board
portal_snapshot|PASS|active_symlink_valid_schema_generation
guest_pre_post_authorization|NOT_TESTED|independent_guest_packet_trace_required
physical_recovery|NOT_VERIFIED|uart_bootloader_and_restore_plan_required
e5_complete|BLOCK|physical_acceptance_incomplete
flash_authorization|BLOCK|no_device_recovery_evidence
~~~

PASS from this script is **a local observation only**, NOT full hardware E5 PASS.
WARN means a fact was not observed; BLOCK means a required condition failed or is
not yet evidenced. A dummy host fixture explicitly identifies itself as
HOST_FIXTURE_NOT_DEVICE and can never approve flash. Do not publish unreviewed raw
UART logs, serial numbers, device-specific IDs, accounts or WP tokens.

## Independent S5 manual/packet acceptance

Record actual test time, NR3053 board revision, expected GitHub commit/artifact
digest, tester and independent rollback evidence *privately*. For each item
below, record PASS/FAIL, minimal redacted evidence, and environment:

1. Boot stable with no boot loop; inspect partition/calibration validity and
   both radios. Associate real guest clients on 2.4 GHz and 5 GHz.
2. Guest is assigned a 10.10.10.x address and can open the TWO first Gate
   entrypoints (10.0.0.1 and 10.0.0.2) while the WAN is otherwise denied.
   Check direct backend 10.0.0.2:8081 fails before Gate permission.
3. Both normal six-digit device PIN and permanent emergency Gate code work as
   configured; opening either Gate does not by itself bypass separate Setup
   or LuCI account authentication. Test invalid PIN and lockout/expiry.
4. Before Page 6 confirmation, independently verify ordinary external HTTP/HTTPS
   and IPv6 do not bypass policy. Confirm only intended Private DNS/bootstrap
   exceptions work. After the deliberate Page 6 confirm, verify the specific
   IP/MAC pair receives Internet immediately, and another client stays blocked.
   Test revoked session, captive DNS, reconnection and VPN after authorization.
5. Verify WordPress pairing, heartbeat, active revision ACK, failed ACK retry,
   and full media-snapshot replacement. A new snapshot must be hash-validated,
   activated atomically, and old media removed only after successful swap.
   Verify WP outage / API generation mismatch retains a valid local Portal.
6. Restart and test whether local Portal persists, both Gate pages remain
   reachable, client authorization is correct, and the device returns to
   working management access without rescue intervention.
7. Independently exercise/verify the exact bootloader/UART recovery and rollback
   path on **dedicated lab hardware** before approving any further flash.

## Evidence and current source baseline

The specific source commit, hosted image run, engineering artifact ID, and
independently checked SHA256 must be resolved for **each** acceptance attempt
from [live Issue #5](https://github.com/capt4780/wiflow-fw-nr3053/issues/5)
and the exact matching GitHub Actions run. Historical checkpoints (including
the 2026-10-10 S4-P36 image run
[#38033834092](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38033834092))
do not certify the currently running source or hardware.
All engineering images remain **NOT FOR FLASHING** until separately approved.
Never substitute an older run's SHA256, rootfs audit, or success status for a newer image.

S5 remains **NOT VERIFIED** and S6 **BLOCK** unless all real-device tests above
are completed with independent recovery evidence. Do not silently convert host
fixtures, source tests, or this checklist into release certification.
