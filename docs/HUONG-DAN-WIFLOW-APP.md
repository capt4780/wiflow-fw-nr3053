# Wiflow App trên Viettel NR3053

Wiflow App nằm sẵn trong firmware (mục đầu tiên của thanh bên, không cài gói riêng). Nó **liên kết router với tài khoản Wiflow** (WordPress) và **hiển thị tình trạng router**. Nội dung portal, tốc độ, giờ mở cửa và số khách tối đa được đặt trên WordPress.

WiFi và mạng (WiFi nguồn, tên và mật khẩu WiFi, địa chỉ LAN) cài thẳng trong LuCI.

## Cài WiFi nguồn

1. **Network → Wireless**, ở radio muốn bắt nguồn bấm **Scan**.
2. Chọn mạng, bấm **Join Network**, nhập mật khẩu, bấm **Submit**, rồi **Save & Apply**.

## Liên kết tài khoản

1. Trong app Wiflow vào **Devices → Add device** lấy mã 12 ký tự.
2. Ở router mở **Wiflow App**, nhập mã, bấm **Link account**.
3. Sau khi liên kết, trang hiện: Internet, thiết bị đang kết nối và trong ngày, uptime, biểu đồ 24 giờ (thiết bị, độ trễ), tài khoản, các mạng WiFi đang phát, nguồn Internet, tình trạng router (CPU, bộ nhớ, lưu trữ, nhiệt độ) và nhật ký.

Số liệu được router lưu trong RAM, mất khi khởi động lại (biểu đồ bắt đầu lại từ lúc bật máy). **Unlink account** gỡ liên kết.

## Portal cho khách

- WiFi `Wiflow` (cả hai băng tần) là mạng khách (`10.10.10.0/24`), tách khỏi cáp LAN `10.0.0.1` dùng để quản lý. Khách vào được `10.0.0.1` và Internet.
- Router không thu thập dữ liệu khách (không số điện thoại, Zalo, email). Chỉ đếm lượt xem và xác nhận.
- Mạng khách được kiểm tra mỗi lần Wiflow App khởi động: thiếu thì tạo lại, WiFi `Wiflow` còn nằm trên LAN được chuyển sang một lần. Trang Wiflow App hiện trạng thái portal và WiFi đang ở mạng nào.
- Chưa có nội dung từ WordPress thì portal tắt và khách có Internet bình thường. Khi WordPress công bố nội dung (website, hình hoặc video), router tải về, kiểm tra sha256, dùng tối đa 80% bộ nhớ và xoá nội dung cũ trước khi tải bản mới.
- Khách mở WiFi sẽ thấy portal, bấm xác nhận để có Internet. Băng thông chia đều; giới hạn tốc độ chỉ có khi WordPress đặt (mặc định 0 = không giới hạn).
- Lỗi portal nhiều lần: chế độ an toàn tự tắt portal 10 phút để khách vẫn có Internet.
- Gỡ liên kết tài khoản xoá nội dung và phiên khách.

## Đăng nhập

- Gate: `WIFDIDNR3053` (dùng chung) hoặc 6 số cuối của mã thiết bị `WIFDID-NR3053-xxxxxx`.
- LuCI: `wiflow` / `wiflow` hoặc `root` / `1234`.

## Menu LuCI

Tổng quan (Overview) · WiFi · Hệ thống (System) · Đăng xuất. Thanh bên gập lại: chỉ nhóm đang chọn được mở. Các mục khác đã gỡ khỏi firmware.
