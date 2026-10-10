# NR3053 P49 — Evidence-led bootloader rescue with RAM-only rehearsal

**STATUS: Source capability observed; installed bootloader NOT VERIFIED; first flash BLOCK.**

This is a **single-router** safety document, not a request to flash anything.
The existing October 7 device fingerprint already confirms NR3053/MT7981,
MTD names/sizes, current Golden reference and a Factory *hash*. Do not
repeat collection of those observations. The hash alone is not a backup.

## What the exact pinned upstream source actually provides

ImmortalWrt source commit
`e39aded8420d454804a376e63400aff73da66247` includes
`package/boot/uboot-mediatek/patches/504-add-viettel-nr3053.patch` and
`target/linux/mediatek/dts-ext/mt7981b-viettel-nr3053.dts`.

The *source* defines `bootmenu_1=Boot system via TFTP.` mapping to
`run boot_tftp`, whose `tftpboot ... && bootm ...` path is a RAM image
boot rather than a NAND write. The DTS specifies
`stdout-path = "serial0:115200n8"` (UART `ttyS0`).

The same source explicitly differentiates dangerous operations:

| Upstream menu | Classification | Owner policy |
|---|---|---|
| 1 — Boot system via TFTP | Possible boot in RAM only | Technician may assess only after confirming installed menu and matching recovery image |
| 2 — Boot production system from NAND | Boot existing production volume | Observation only, not a recovery proof |
| 3 — Boot recovery system from NAND | Reads recovery volume if present | Do not assume a recovery volume exists on this router |
| 0 — Initialize environment | May initialize/save boot variables | DO NOT SELECT |
| 4/5 — TFTP then write production/recovery to NAND | NAND mutation | DO NOT SELECT |
| 6/7 — Write FIP/BL2 via TFTP | Bootloader NAND mutation; high-risk | DO NOT SELECT |
| 9 — Reset all settings to factory defaults | Environment/config reset | DO NOT SELECT |

**Critical:** These strings are from an *upstream source patch*, not an
authenticated copy of the U-Boot binary on the owner's actual device. The
physical device's existing UBI inventory did not establish a populated
recovery volume. Upstream also bundles a
`docs/uart_payloads/bl2-viettel-nr3053-ram.bin` file, but its presence
**does not** establish that UART rescue is installed or working. It must
not be used to rewrite BL2/FIP.

## Owner-safe lab sequence before any first LuCI flash

The following requires an **authorized technician**, not a remote
unattended experiment:

1. Privately locate and electrically verify the router's UART pads and
   voltage levels using the exact PCB variant. Source documentation does
   not establish their positions. If the interface is verified as 3.3V
   TTL, connect *only* matching GND/TX/RX as appropriate. **Never connect
   USB-TTL 5V or VCC to unknown router pins.** Do not open/alter the board
   without owner permission.
2. Observe the original boot log at the verified `115200n8` settings
   over a local, trusted serial console, without writing to NAND or
   U-Boot environment. Record bootloader build/version and whether
   the actual menu matches the source. Keep raw logs and hardware labels
   private: boot logs can contain identifying data.
3. With the original firmware still intact, determine whether the
   currently installed bootloader supports *RAM-only* boot over TFTP.
   Use a reviewed, matching **initramfs recovery ITB**, never a
   `sysupgrade.itb` in place of an initramfs image. Verify its FIT
   integrity and exact digest. Check actual memory limits, boot address,
   UART speed, and network topology with the technician first.
4. If the installed menu, recovery ITB and connection are validated,
   a technician may separately perform and document an approved
   **non-writing RAM boot**. Successful console output, kernel start
   and management Ethernet access are necessary observations; do not
   assume the firmware can flash/restore unless separately demonstrated.
5. Independently verify complete backups of device-specific partitions
   privately (including Factory/calibration) and that a matching Golden
   firmware can be restored using a validated recovery route. On a single
   unit, a destructive restore demonstration itself has risk; prefer
   an identical spare unit and an expert-reviewed method.
6. Only after independent recovery evidence and approved P46/P47/P48
   firmware gates can first-flash permission be reconsidered; real
   captive, Wi-Fi and network tests after flash remain separate E5.

If the bootloader menu is inaccessible, differs unexpectedly or the
physical electrical interface cannot be verified, **stop and retain the
working firmware**; buy/borrow a lab unit instead of gambling the only
router.

## Local-only transcript classification (P49)

A sanitized, privately stored UART transcript can be checked on an offline
computer, *without connecting to the router*:

```sh
python3 tools/nr3053-uart-bootmenu-evidence-offline.py \
  --uart-transcript /PRIVATE/observed-uart-boot-menu.txt
```

The tool distinguishes the source's non-writing RAM/boot options from
write-to-NAND menu options, rejects linked/oversized files and emits only
nonsensitive `PASS`/`BLOCK` verdict codes. A fabricated text file
could match. Even a textual PASS is **not hardware authentication**,
TFTP RAM boot evidence, NAND restore evidence, or first-flash approval.

**No UART logs, Factory dumps or private device identifiers belong in
public GitHub, WordPress or CI artifacts. The release gate remains BLOCK.**
