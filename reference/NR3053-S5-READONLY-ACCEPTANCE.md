# NR3053 S5 — read-only field acceptance (NO FLASH)

Status: **engineering evidence only**. This procedure does NOT provision, upgrade,
flash, configure, restart services, authorize guest Internet, or recover hardware.
Its automated report always ends with **e5_complete=BLOCK** and
**flash_authorization=BLOCK** until independent lab acceptance is documented.

## Preconditions

1. Confirm exact hardware ID, PCB/bootloader revisions and radio/calibration map on
   the *actual* Viettel NR3053. A successful hosted FIT build is NOT evidence that
   the bootloader can recover from incompatible images.
2. Do not flash a Wi-Fi-only device. Before any future flash, obtain a separately
   verified physical/UART recovery, powered serial console, working backup strategy,
   verified firmware restore procedure, and a second management path.
3. Use only a router already running a **known lab Wiflow candidate** for this
   script. On original stock firmware, missing Wiflow files are normal and will
   produce BLOCK; do not use that result as a reason to flash.

## Device-side evidence collection — no changes

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

As of 2026-10-10, current source baseline was commit
`acae341c52cdadfdef4ff60e08afae218638b08c`.
The exact hosted engineering image was built in
[GitHub Actions #38011329173](https://github.com/capt4780/wiflow-fw-nr3053/actions/runs/38011329173);
it is explicitly **NOT FOR FLASHING**. Firmware static audit is not a device test.
Never substitute an earlier run's SHA256 or rootfs report for a newer image.

S5 remains **NOT VERIFIED** and S6 **BLOCK** unless all real-device tests above
are completed with independent recovery evidence. Do not silently convert host
fixtures, source tests, or this checklist into release certification.
