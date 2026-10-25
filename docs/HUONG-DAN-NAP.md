# Nạp Wiflow OS cho Viettel NR3053

Dùng cho router **đang chạy ImmortalWrt v2.3.6** (bản `immortalwrt-…-viettel_nr3053-squashfs-sysupgrade.itb` ổn định).

Wiflow OS là chính bản v2.3.6 được làm gọn:
- Kernel, device tree, driver và firmware WiFi MediaTek giống v2.3.6 từng byte.
- Bootloader, phân vùng NAND, dữ liệu hiệu chỉnh sóng không bị đụng tới.

Ứng dụng Wiflow (Setup, portal, kết nối WordPress) là gói `.apk` riêng, cài sau.

## Chuẩn bị

- Ở trang **Releases**, tải file `wiflow-os-<phiên bản>-viettel-nr3053-squashfs-sysupgrade.itb` và `SHA256SUMS`.
- Giữ lại file v2.3.6 để quay về khi cần.
- Nối máy tính (hoặc điện thoại có hub USB-LAN) vào **cổng LAN** bằng cáp. Không nạp qua WiFi.

## Nạp

1. Vào LuCI của router đang chạy, mở **Hệ thống → Sao lưu / Nạp firmware** (System → Backup / Flash Firmware).
2. Chọn file `.itb` của Wiflow OS.
3. **Bỏ chọn "Giữ cấu hình" (Keep settings).**
4. Bấm **Nạp** và chờ router tự khởi động lại, khoảng 3 phút. Không rút điện trong lúc này.

## Sau khi nạp

| | |
|---|---|
| Địa chỉ router | `http://10.0.0.1`, máy nối LAN hoặc WiFi nhận IP `10.0.0.x` |
| Đăng nhập LuCI | `root` / `1234` |
| WiFi | `Wiflow 2.4 GHz` và `Wiflow 5 GHz`, mở, không mật khẩu |
| SSH | `root@10.0.0.1`, mật khẩu `1234` |

- Internet nguồn: cắm cáp vào cổng **WAN** (DHCP), hoặc cài ở LuCI → **Mạng → Giao diện**.
- Cài ứng dụng Wiflow: LuCI → **Hệ thống → Phần mềm → Tải lên gói…**, chọn file `.apk` Wiflow.

## Reset

Giữ nút **Reset** khoảng 10 giây khi router đang chạy. Router về mặc định của Wiflow OS: `10.0.0.1`, `root` / `1234`, WiFi `Wiflow 2.4 GHz` / `Wiflow 5 GHz`.

## Quay về v2.3.6 / cứu router

- **Router vẫn vào được LuCI:** nạp file v2.3.6 như trên, **bỏ chọn Giữ cấu hình**.
- **Router không vào được:** dùng **Web Failsafe** của bootloader.
  1. Đặt IP máy `192.168.1.254`, mask `255.255.255.0`, cắm cáp vào cổng LAN.
  2. Vào Web Failsafe:
     - Bootloader tự mở Web Failsafe khi không khởi động được hệ điều hành.
     - Hoặc giữ nút Reset trong lúc cắm nguồn khoảng 5–10 giây, rồi thả ra.
  3. Mở `http://192.168.1.1`, tải lên file `…-squashfs-sysupgrade.itb` (v2.3.6 hoặc Wiflow OS).
- Cách vào Web Failsafe bằng nút Reset tùy bản bootloader. Hãy thử trước một lần khi router còn chạy tốt.

## Có gì trong Wiflow OS

| | |
|---|---|
| Nền | ImmortalWrt v2.3.6 (quytttb/immortalwrt-mt798x-rebase `495af17`), kernel 6.12.94, driver WiFi MediaTek mt_wifi 7.6.7.3 |
| Giữ | Mạng lõi, tường lửa nftables, DHCP/DNS, PPPoE, driver và công cụ WiFi MediaTek, curl/HTTPS, LuCI tiếng Việt (Trạng thái, Mạng, WiFi, Tường lửa, Hệ thống, Phần mềm), SSH, apk |
| Giao diện | Theme LuCI Wiflow, theme duy nhất, không đổi được |
| Đã bỏ | Tailscale, WireGuard, chặn quảng cáo, DDNS, UPnP, TurboACC, EQoS, IPv6 (DHCPv6/RA), zram, iptables cũ, htop/nano/tcpdump, theme Aurora/Bootstrap, tiếng Trung |
| Tăng tốc phần cứng | HNAT tắt, để mọi gói tin đi qua tường lửa |
