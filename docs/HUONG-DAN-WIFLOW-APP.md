# Wiflow App trên Viettel NR3053

Wiflow App nằm sẵn trong firmware (mục đầu tiên của thanh bên, không cài gói riêng). Nó chỉ làm hai việc: **liên kết router với tài khoản Wiflow** (WordPress) và **hiển thị tình trạng router**. Cổng, nội dung portal, khách và cập nhật được quản lý trên WordPress.

WiFi và mạng (WiFi nguồn, tên và mật khẩu WiFi, địa chỉ LAN) cài thẳng trong LuCI.

## Cài WiFi nguồn

1. **Network → Wireless**, ở radio muốn bắt nguồn bấm **Scan**.
2. Chọn mạng, bấm **Join Network**, nhập mật khẩu, bấm **Submit**, rồi **Save & Apply**.

## Liên kết tài khoản

1. Trong app Wiflow vào **Devices → Add device** lấy mã 12 ký tự.
2. Ở router mở **Wiflow App**, nhập mã, bấm **Link account**.
3. Sau khi liên kết, trang hiện: Internet, thiết bị đang kết nối và trong ngày, uptime, biểu đồ 24 giờ (thiết bị, độ trễ), tài khoản, các mạng WiFi đang phát, nguồn Internet, tình trạng router (CPU, bộ nhớ, lưu trữ, nhiệt độ) và nhật ký.

Số liệu được router lưu trong RAM, mất khi khởi động lại (biểu đồ bắt đầu lại từ lúc bật máy). **Unlink account** gỡ liên kết.

## Đăng nhập

- Gate: `WIFDIDNR3053` (dùng chung) hoặc 6 số cuối của mã thiết bị `WIFDID-NR3053-xxxxxx`.
- LuCI: `wiflow` / `wiflow` hoặc `root` / `1234`.

## Menu LuCI

Wiflow App · Status (Overview, System Log) · System (System, Administration, Software, Backup / Flash Firmware, Reboot) · Network (Interfaces, Wireless, DHCP and DNS) · Log out. Các mục khác đã gỡ khỏi firmware.

## Nâng từ Wiflow Setup 1.x

Nạp firmware mới và bỏ chọn Keep settings. Nếu giữ cấu hình, lần chạy đầu Wiflow App dọn mạng khách của bản 1.x (WiFi khách quay về mạng LAN, WiFi nguồn đang kết nối được giữ nguyên).
