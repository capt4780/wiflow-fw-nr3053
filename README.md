# Wiflow OS — Viettel NR3053

Firmware nền cho router Wiflow trên Viettel NR3053 (MediaTek MT7981B, 512 MB RAM, 128 MB NAND).

Wiflow OS là bản ImmortalWrt v2.3.6 đang chạy ổn định, được **đóng gói lại** chứ không biên dịch lại:
- **Giữ nguyên từng byte v2.3.6:** kernel, device tree, driver WiFi mt_wifi, firmware WiFi, file cấu hình sóng, script nâng cấp. Bootloader và dữ liệu hiệu chỉnh không bị đụng tới.
- **Rootfs làm gọn:** chỉ giữ gói Wiflow cần (`tools/lean-keep.txt` cùng các gói phụ thuộc), gỡ hết phần còn lại.
- **Thương hiệu Wiflow:** theme LuCI Wiflow (duy nhất), logo và favicon từ ảnh gốc (`rom/brand`, `tools/make-brand.py`), tên máy, banner.
- **Mặc định:** `10.0.0.1`, `root` / `1234`, WiFi mở `Wiflow 2.4G` / `Wiflow 5G`, HNAT tắt.

Ứng dụng Wiflow (Setup, portal, kết nối WordPress) là gói `.apk` riêng, cài sau qua LuCI → System → Software.

Nạp và cứu router: [docs/HUONG-DAN-NAP.md](docs/HUONG-DAN-NAP.md). File firmware ở **Releases**.

## Cấu trúc

| Đường dẫn | Nội dung |
|---|---|
| `base/` | Bản v2.3.6 gốc (`.itb`), SHA-256 khớp `tools/nr3053-golden.json` |
| `tools/lean-keep.txt` | Danh sách gói giữ lại |
| `tools/lean-rootfs.py` | Tính gói cần giữ theo phụ thuộc trong cơ sở dữ liệu apk, gỡ phần còn lại (file, liên kết, bản ghi apk) |
| `rom/overlay/` | File thêm vào rootfs: theme LuCI Wiflow, cài đặt lần đầu `98-wiflow-base`, tắt HNAT, banner |
| `rom/VERSION` | Phiên bản Wiflow OS |
| `scripts/repack.sh` | Giải nén → làm gọn → thêm Wiflow → kiểm tra → đóng gói `.itb` |
| `tools/rom-check.py` | Kiểm tra rootfs: WiFi giống v2.3.6, đủ thư viện, đủ module kernel, liên kết, mặc định, gói đã bỏ |
| `tools/fit-rootfs.py` | Thay rootfs trong file FIT, giữ nguyên kernel và device tree |
| `.github/workflows/repack.yml` | Build trên GitHub Actions (vài phút), phát hành khi đẩy lên `main` |
| `package/`, `config/`, `scripts/prepare.sh`, `build.yml` | Bản build từ mã nguồn trước đây (1.0.x), chỉ để tham khảo |

## Build

Tự chạy khi đẩy thay đổi; chạy tay ở **Actions → Wiflow OS NR3053 → Run workflow**.

Trên Ubuntu (cần `squashfs-tools`, `fwtool`, `python3`, `openssl`):

```sh
sudo bash scripts/repack.sh dist
```

Không đưa vào repo: dữ liệu tài khoản, token API/thiết bị, file firmware đã build, bản sao lưu.
