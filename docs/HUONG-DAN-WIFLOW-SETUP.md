# Wiflow Setup trên Viettel NR3053

Wiflow Setup là gói `.apk` cài lên Wiflow OS. Gói thêm nhóm **Wiflow** ở đầu thanh bên của trang quản trị, gồm bốn trang: Tổng quan, Internet nguồn, WiFi khách và Kết nối Wiflow. Các trang Wiflow viết bằng tiếng Việt; phần còn lại của LuCI giữ tiếng Anh.

## Cài đặt

1. Router cần chạy Wiflow OS **1.0.0 build 15** trở lên. Từ build này, router nhận gói tải lên mà không đòi chữ ký của kho ImmortalWrt.
2. Tải file `wiflow-setup-<phiên bản>.apk` ở mục Releases của repo.
3. Mở `http://10.0.0.1`, nhập Gate rồi đăng nhập (`wiflow` / `wiflow` hoặc `root` / `1234`).
4. Vào **System → Software**, bấm **Upload Package…**, chọn file `.apk`, rồi bấm **Install**.
5. Vài giây sau khi cài, router tự cấu hình. WiFi `Wiflow 2.4G` / `Wiflow 5G` đổi thành WiFi khách **Wiflow** (mở) trên mạng `10.10.10.x`. Kết nối lại vào WiFi **Wiflow** rồi mở `http://10.0.0.1`.

Nếu router đang chạy bản cũ hơn build 15, cài qua SSH:

```
scp wiflow-setup-*.apk root@10.0.0.1:/tmp/
ssh root@10.0.0.1 apk add --allow-untrusted /tmp/wiflow-setup-*.apk
```

## Mạng sau khi cài

| | Địa chỉ | Ghi chú |
|---|---|---|
| Quản trị (cổng LAN 1–3) | `10.0.0.1/24` | Như firmware gốc |
| WiFi khách **Wiflow** | `10.10.10.1/24` | Mở. Khách không thấy nhau và không vào được mạng quản trị; riêng `http://10.0.0.1` vẫn mở được |
| Internet nguồn | cổng WAN và/hoặc WiFi nguồn | Xem bên dưới |

Mã Gate của router có hai dạng:

- `WIFDIDNR3053`, dùng chung cho mọi router NR3053;
- 6 số cuối của mã thiết bị (`WIFDID-NR3053-xxxxxx`), xem ở trang Tổng quan.

## Internet nguồn

- **Tự động**: dùng cáp WAN trước, WiFi nguồn làm dự phòng. Khi cáp vẫn cắm nhưng modem phía trước mất Internet, router chuyển sang WiFi nguồn. Khi cáp có Internet trở lại, router tự quay về cáp.
- **Chỉ cáp WAN**: tắt WiFi nguồn.
- **Chỉ WiFi nguồn**: tắt cổng WAN.

Cách bắt WiFi nguồn: bấm **Quét WiFi**, chọn mạng, nhập mật khẩu, rồi bấm **Kết nối**.

- Router chỉ lưu cấu hình mới khi đã ra được Internet qua mạng vừa chọn.
- Nếu sai mật khẩu, không thấy mạng, hoặc modem nguồn dùng dải `10.0.0.x` / `10.10.10.x`, router quay về cấu hình cũ và báo lý do.

WiFi khách luôn phát ở cả 2 băng. Băng đang bắt WiFi nguồn sẽ phát theo kênh của WiFi nguồn.

## Kết nối Wiflow

1. Trong ứng dụng Wiflow, vào **Thiết bị → Thêm thiết bị** để lấy mã kết nối 12 ký tự.
2. Nhập mã ở trang **Kết nối Wiflow**.

Sau khi kết nối, router liên lạc máy chủ Wiflow khoảng 20 giây một lần. Router nhận các lệnh sau từ ứng dụng:

- khởi động lại, kết nối Internet lại;
- đổi WiFi nguồn, đổi chế độ Internet;
- đổi tên WiFi khách;
- đổi tài khoản đăng nhập Wiflow Setup;
- gửi báo cáo chẩn đoán.

Router cũng gửi sự kiện khách kết nối và rời đi. Địa chỉ MAC của khách được mã hóa ngay trên router, không gửi đi nguyên dạng.

Lệnh cài giới hạn tốc độ, thời gian truy cập và giờ mở cửa cho khách thuộc phần cổng chào, sẽ có ở bản cập nhật sau. Hiện tại router trả lời ứng dụng là chưa hỗ trợ.

## Gỡ cài đặt

Vào **System → Software**, gỡ gói `wiflow-setup`. Router trở lại như trước khi cài:

- WiFi `Wiflow 2.4G` / `Wiflow 5G` trên mạng quản trị;
- không còn mạng khách và WiFi nguồn;
- cổng WAN bật lại.

Mã thiết bị được giữ lại. Khi cài lại, router vẫn dùng mã cũ.
