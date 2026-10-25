# Wiflow Setup trên Viettel NR3053

Wiflow Setup là gói `.apk` cài lên Wiflow OS. Giao diện giống Wiflow Setup trên CR6609, gồm bốn trang: **Trạng thái**, **Internet**, **WiFi khách** và **Hệ thống**. Wiflow Setup mở ở `http://10.0.0.1/wiflow/` và dùng chung phiên đăng nhập với LuCI. Sau khi đăng nhập, router mở thẳng Wiflow Setup. Nút **Nâng cao (LuCI)** mở trang quản trị LuCI (tiếng Anh).

## Cài đặt

1. Nạp Wiflow OS mới nhất ở mục Releases (`nr3053-os-v1.0.0-…`). Bản này nhận gói tải lên mà không đòi chữ ký của kho ImmortalWrt, và khi cài không còn hiện các dòng "Errors" do router tìm kho gói trên mạng.
2. Tải file `wiflow-setup-<phiên bản>.apk` ở mục Releases của repo.
3. Mở `http://10.0.0.1`, nhập Gate rồi đăng nhập (`wiflow` / `wiflow` hoặc `root` / `1234`).
4. Vào **System → Software**, bấm **Upload Package…**, chọn file `.apk`, rồi bấm **Install**.
5. Tải lại trang, bấm **Wiflow Setup** ở đầu thanh bên. Lúc này WiFi của router chưa thay đổi. Trang cài đặt hiện 4 bước:
   1. **WiFi khách**: đặt tên rồi bấm **Bật Wiflow**. WiFi `Wiflow 2.4G` / `Wiflow 5G` đổi thành WiFi khách (mở) trên mạng `10.10.10.x`, mỗi băng một kênh cố định ít nhiễu. Nếu bạn đang dùng WiFi của router, sau khoảng 30 giây hãy kết nối vào WiFi khách rồi mở lại `http://10.0.0.1`.
   2. **Internet nguồn**: chọn **Dây LAN** (bấm Kiểm tra dây LAN) hoặc **WiFi của modem** (chọn mạng, nhập mật khẩu).
   3. **Liên kết tài khoản**: nhập mã 12 ký tự từ app Wiflow, hoặc bấm Để sau.
   4. **Hoàn tất**.

Bản 1.2.x đã bật Wiflow thì bỏ qua bước 1.

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
- 6 số cuối của mã thiết bị (`WIFDID-NR3053-xxxxxx`), xem ở trang Hệ thống.

## Internet

Thẻ xanh ở đầu trang Internet chọn cách router lấy Internet và vẽ đường đang dùng (dây LAN hay WiFi nguồn), điểm chất lượng, độ trễ, dao động và mất gói. Bên dưới là thẻ **Dây LAN** (địa chỉ, cổng mặc định, DNS, tốc độ cổng) và thẻ **WiFi nguồn** (danh sách mạng quét được).

- **Tự động**: dùng cáp WAN trước, WiFi nguồn làm dự phòng. Khi cáp vẫn cắm nhưng modem phía trước mất Internet, router chuyển sang WiFi nguồn. Khi cáp có Internet trở lại, router tự quay về cáp.
- **Chỉ dây**: tắt WiFi nguồn (cấu hình vẫn giữ).
- **Chỉ WiFi**: tắt cổng WAN.

Cách bắt WiFi nguồn: chạm một mạng trong thẻ **WiFi nguồn**, nhập mật khẩu, rồi bấm **Kết nối**. Router quét 5 GHz trước (khoảng 15 giây) rồi 2.4 GHz. Khi kết nối, trang hiện từng bước: Chuẩn bị, Kết nối WiFi nguồn, Nhận địa chỉ mạng, Kiểm tra Internet.

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

## WiFi khách

Đổi tên WiFi khách, xem mã QR và số khách đang dùng. Giới hạn tốc độ, thời gian mỗi lượt, số khách tối đa và giờ phục vụ cần trang chào Wiflow: các thẻ này hiện mờ, sẽ dùng được ở bản cập nhật sau.

## Hệ thống

- Mã thiết bị, bộ nhớ flash, RAM 24 giờ.
- **Cập nhật Wiflow**: kéo thả file `.apk` mới, router cài ngay và giữ cấu hình.
- **Ghép nối**: nhập mã 12 ký tự lấy trong app Wiflow (**Thiết bị → Thêm thiết bị**), hoặc **Rời tài khoản**.
- **Khởi động lại** (bấm giữ 2 giây), **Gửi chẩn đoán**, **Tải báo cáo**, **Nâng cao (LuCI)**, **Đổi mật khẩu**, **Reset Wiflow**, **Đăng xuất**.
- Nhật ký hệ thống.

Báo cáo chẩn đoán là file văn bản gồm trạng thái sóng, kênh, kết nối, lần quét WiFi gần nhất, ghi chép của driver khi bắt WiFi nguồn lỗi và nhật ký. Báo cáo không có mật khẩu.

**Reset Wiflow** xoá WiFi nguồn và ghép nối, đưa WiFi khách về tên "Wiflow", Internet về tự động, tài khoản Wiflow Setup về `wiflow` / `wiflow`. Gói vẫn giữ.

## Kết nối Wiflow

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
