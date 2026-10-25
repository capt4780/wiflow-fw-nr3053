# Wiflow Setup trên Viettel NR3053

Wiflow Setup là gói `.apk` cài lên Wiflow OS. Gói thêm nhóm **Wiflow** ở đầu thanh bên của trang quản trị, gồm bốn trang: Tổng quan, Internet nguồn, WiFi khách và Kết nối Wiflow. Các trang Wiflow viết bằng tiếng Việt; phần còn lại của LuCI giữ tiếng Anh.

## Cài đặt

1. Nạp Wiflow OS mới nhất ở mục Releases (`nr3053-os-v1.0.0-…`). Bản này nhận gói tải lên mà không đòi chữ ký của kho ImmortalWrt, và khi cài không còn hiện các dòng "Errors" do router tìm kho gói trên mạng.
2. Tải file `wiflow-setup-<phiên bản>.apk` ở mục Releases của repo.
3. Mở `http://10.0.0.1`, nhập Gate rồi đăng nhập (`wiflow` / `wiflow` hoặc `root` / `1234`).
4. Vào **System → Software**, bấm **Upload Package…**, chọn file `.apk`, rồi bấm **Install**.
5. Tải lại trang. Menu **Wiflow** hiện ở đầu thanh bên. Lúc này WiFi của router chưa thay đổi.
6. Vào **Wiflow → Tổng quan**, bấm **Bật Wiflow**. WiFi `Wiflow 2.4G` / `Wiflow 5G` đổi thành WiFi khách **Wiflow** (mở) trên mạng `10.10.10.x`, mỗi băng một kênh cố định ít nhiễu. Nếu bạn đang dùng WiFi của router, sau khoảng 30 giây hãy kết nối vào WiFi **Wiflow** rồi mở lại `http://10.0.0.1`.

Nếu router đang chạy bản cũ (trước build 15), cài qua SSH:

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

### Cách router bắt và phát WiFi

Router dùng chế độ repeater của chip MediaTek: bắt WiFi nguồn và phát WiFi khách trên cùng một băng. WiFi khách luôn phát ở cả 2 băng.

- Băng đang bắt WiFi nguồn phát WiFi khách theo kênh của WiFi nguồn. Tốc độ tối đa ở băng này còn khoảng một nửa vì sóng được dùng chung; khách vẫn dùng bình thường.
- Băng còn lại giữ kênh cố định (chọn lúc bật Wiflow), khách ở băng này đủ tốc độ.
- Router không bao giờ tắt phát ở băng đang bắt nguồn (kiểu "bắt băng này, phát băng kia" dễ lỗi trên chip MediaTek).
- Khi đổi sang WiFi nguồn khác cùng băng, router đổi ngay trong driver, không khởi động lại WiFi, khách không bị rớt.
- Khi mất WiFi nguồn, router chỉ yêu cầu phần bắt sóng tìm lại nguồn. Chỉ khi mất quá 10 phút router mới khởi động lại WiFi, tối đa 1 lần mỗi 30 phút.

Danh sách WiFi nguồn có nhãn:

- **Nên dùng**: băng ổn định hơn cho mạng đó. Router ưu tiên 5G kênh thường (36–48, 149–165) có sóng tốt, nếu không thì 2.4G.
- **Kênh DFS** (5G kênh 52–144): router có thể phải chờ 1 phút hoặc đổi kênh khi gặp radar, WiFi khách băng 5G ngắt theo. Router hỏi lại trước khi kết nối.
- **Sóng yếu** (dưới −75 dBm): dễ chập chờn. Nên đặt router gần nguồn hơn, từ −65 dBm trở lên là tốt.

## Chẩn đoán

Ở trang Tổng quan, thẻ **Chẩn đoán**:

- **Tải báo cáo**: tải file văn bản gồm trạng thái sóng, kênh, kết nối và nhật ký (không có mật khẩu) để gửi cho kỹ thuật.
- **Gửi cho Wiflow**: gửi báo cáo lên máy chủ Wiflow khi router đã kết nối tài khoản.

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
