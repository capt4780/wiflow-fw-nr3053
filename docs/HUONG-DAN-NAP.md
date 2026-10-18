# Nạp firmware Wiflow cho Viettel NR3053

Dùng cho router **đang chạy ImmortalWrt v2.3.6** (bản `immortalwrt-…-viettel_nr3053-squashfs-sysupgrade.itb` ổn định).
Firmware Wiflow giữ nguyên bootloader, phân vùng NAND và dữ liệu hiệu chỉnh sóng WiFi.

## Chuẩn bị

- File firmware `wiflow-<phiên bản>-viettel-nr3053-squashfs-sysupgrade.itb` và `SHA256SUMS` ở trang **Releases**.
- File v2.3.6 đang chạy ổn định: giữ lại để quay về khi cần.
- Máy tính nối **cổng LAN** của router bằng cáp. Không nạp qua WiFi.
- Kiểm tra file: SHA-256 của file `.itb` phải trùng dòng trong `SHA256SUMS`.

## Nạp

1. Vào LuCI của router (`http://192.168.1.1`), mở **System → Backup / Flash Firmware**.
2. Ở **Flash new firmware image**, chọn file `.itb` của Wiflow.
3. **Bỏ chọn "Keep settings"**. Cấu hình cũ (IPv6, UPnP, …) không dùng cho Wiflow.
4. Bấm **Flash**. Router tự khởi động lại, khoảng 3–4 phút. Không rút điện trong lúc này.

## Sau khi nạp

1. Máy tính nhận địa chỉ `10.0.0.x`. Mở `http://10.0.0.1`.
2. **Cổng bảo mật:** nhập 6 số cuối ID thiết bị hoặc `WIFDIDNR3053`.
3. **Đăng nhập:** `wiflow` / `wiflow`.
4. Làm 3 bước: **Internet nguồn** → **Liên kết tài khoản** → **Hoàn tất**.
- WiFi khách tên `Wiflow` phát ở 2.4 GHz và 5 GHz.
- **Nâng cao (LuCI)** trong Wiflow mở LuCI, tự đăng nhập `root` / `1234`.
- SSH: `root@10.0.0.1`, mật khẩu `1234`.

## Reset

Giữ nút **Reset** khoảng 10 giây khi router đang chạy: router về mặc định của firmware Wiflow (Wiflow vẫn còn, phải ghép nối lại tài khoản).

## Cập nhật bản Wiflow mới

LuCI → **System → Backup / Flash Firmware**, chọn file mới:
- Giữ **Keep settings**: giữ ghép nối tài khoản, Internet nguồn, mật khẩu.
- Bỏ **Keep settings**: như router mới.

## Quay về v2.3.6 / cứu router

- **Router vẫn vào được LuCI:** nạp file v2.3.6 như trên, **bỏ chọn Keep settings**.
- **Router không khởi động được:** dùng trang **Web Failsafe** của bootloader.
  1. Đặt IP máy tính `192.168.1.254`, mask `255.255.255.0`, cắm cáp vào cổng LAN.
  2. Vào Web Failsafe:
     - Bootloader tự mở Web Failsafe khi không khởi động được hệ điều hành.
     - Hoặc giữ nút Reset trong lúc cắm nguồn khoảng 5–10 giây, rồi thả ra.
     - Hoặc qua UART (115200): nhấn phím khi thấy `Hit any key to stop autoboot`, gõ `bootmenu`.
  3. Mở `http://192.168.1.1`, tải lên file `…-squashfs-sysupgrade.itb`: v2.3.6 hoặc Wiflow.
- Cách vào Web Failsafe bằng nút Reset tuỳ bản bootloader. Hãy thử trước một lần, khi router còn chạy tốt.

## Thông số

| | |
|---|---|
| Nền | ImmortalWrt v2.3.6 (quytttb/immortalwrt-mt798x-rebase `495af17`), kernel 6.12.94, driver WiFi MediaTek mt_wifi 7.6.7.3 |
| Quản trị | `10.0.0.1`: cổng bảo mật → Wiflow → LuCI |
| WiFi khách | `10.10.10.0/24`, captive portal |
| Đã bỏ | IPv6, PPPoE, VPN (WireGuard, Tailscale), chặn quảng cáo, UPnP, DDNS, tăng tốc phần cứng (HNAT), giao diện Aurora, tiếng Trung |
