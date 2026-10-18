# Wiflow firmware — Viettel NR3053

Firmware thương mại Wiflow cho router Viettel NR3053 (MediaTek MT7981B, 512 MB RAM, 128 MB NAND).

- **Nền:** ImmortalWrt bản v2.3.6 đang chạy ổn định ([quytttb/immortalwrt-mt798x-rebase](https://github.com/quytttb/immortalwrt-mt798x-rebase) `495af17`).
  - Feed `packages` và `luci` khoá đúng commit của bản đó.
- **Giữ nguyên v2.3.6:**
  - Kernel và cấu hình kernel.
  - Driver WiFi mt_wifi, firmware WiFi, file cấu hình sóng.
  - Device tree, phân vùng NAND.
  - Firmware không chứa và không ghi bootloader, preloader, dữ liệu hiệu chỉnh.
- **Có trong ROM:** Wiflow (cổng bảo mật, quản trị, captive portal, đồng bộ app), LuCI tối giản, công cụ WiFi MediaTek.
  - Reset router không mất Wiflow.
- **Đã bỏ:** IPv6, PPPoE, VPN, chặn quảng cáo, UPnP, DDNS, tăng tốc phần cứng (HNAT), giao diện Aurora, tiếng Trung, công cụ dòng lệnh dư.

Nạp và cứu router: [docs/HUONG-DAN-NAP.md](docs/HUONG-DAN-NAP.md). File firmware ở **Releases**.

## Cấu trúc

| Đường dẫn | Nội dung |
|---|---|
| `package/wiflow-setup/` | Gói Wiflow (sinh từ mã nguồn Wiflow, cùng mã với CR6609) và phần riêng của ROM NR3053 |
| `config/nr3053.config` | Cấu hình build tối giản |
| `scripts/prepare.sh` | Lấy nguồn v2.3.6, khoá feed, thêm Wiflow, tạo và kiểm tra cấu hình |
| `scripts/check-config.sh` | Kiểm tra cấu hình: chỉ NR3053, đủ gói cần, không còn gói đã bỏ, driver và kernel giống v2.3.6 |
| `scripts/audit-image.sh` | Kiểm tra file `.itb` đã build: device tree, file WiFi so với v2.3.6, file Wiflow, gói đã bỏ |
| `tools/nr3053-golden.json` | Mã băm từ bản v2.3.6 dùng để so sánh |
| `.github/workflows/build.yml` | Build trên GitHub Actions, kiểm tra image, phát hành |

## Build

Tự chạy khi đẩy thay đổi lên `main`, hoặc chạy tay ở **Actions → Build NR3053 firmware → Run workflow**.

Build trên máy Ubuntu 24.04:

```sh
bash scripts/prepare.sh openwrt
cd openwrt && make download -j8 && make -j"$(nproc)"
bash ../scripts/audit-image.sh bin/targets/mediatek/filogic/*nr3053*sysupgrade.itb ../out/audit
```

Không đưa vào repo: dữ liệu tài khoản, token API/thiết bị, file firmware, bản sao lưu.
