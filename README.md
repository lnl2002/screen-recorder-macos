# Screen Recorder for macOS

Quay màn hình với zoom/pan mượt theo chuột, rồi tự xuất MP4. App native Swift, không có timeline editor, không cần cài Screen Studio và không có dependency bên ngoài.

## Chạy app

Yêu cầu macOS 14 trở lên và Xcode Command Line Tools với Swift 5.9+.

```sh
git clone https://github.com/lnl2002/screen-recorder-macos.git
cd screen-recorder-macos
./scripts/build-app.sh
open "dist/Screen Recorder.app"
```

Có thể chép app trong `dist` sang Applications trước khi cấp quyền. Bản build dùng chữ ký ad hoc để chạy local; chưa có Developer ID/notarization để phát hành rộng rãi. GitHub Actions build app và lưu ZIP trong artifacts của mỗi lần chạy thành công.

1. Bấm **Allow screen recording**, bật quyền trong System Settings → Privacy & Security → Screen & System Audio Recording. Mở lại app nếu macOS yêu cầu, rồi bấm Refresh.
2. Chọn màn hình và bật system audio nếu cần.
3. Chọn **Auto zoom**, **Follow mouse**, hoặc **Full screen**. Bấm **Smooth preset** nếu muốn chuyển động chậm và mềm hơn; vẫn có thể chỉnh từng thông số. Chọn Original resolution / 1080p / 720p ở mục Export.
4. Bấm **Record**. Khi xong, bấm **Stop & export** ở cửa sổ app hoặc menu bar.
5. Bấm **Show MP4** để mở vị trí video. Đổi preset và bấm **Export again** để xuất bản khác từ cùng video gốc.

`⌘⇧R` bắt đầu/dừng khi cửa sổ app đang active; đây không phải global hotkey. Menu bar luôn có nút dừng. Các cửa sổ của app được loại khỏi màn hình đang quay.

## Camera

- **Auto zoom:** zoom trước click theo lead-in, giữ theo hold, gộp các cụm click gần nhau, rồi trở lại toàn cảnh.
- **Follow mouse:** giữ mức zoom đã chọn và pan theo chuột.
- **Full screen:** xuất toàn cảnh.
- **Glide duration:** số lớn làm camera chuyển động chậm hơn.
- **Quiet zone:** chuột di chuyển trong vùng giữa mà camera chưa cần pan.

Camera dùng đường chuột nội suy và lọc hai chiều, chuẩn bị hướng nhìn về click sắp tới, rồi tính spring cho pan và zoom riêng ở bước thời gian cố định. Vị trí crop được tính trong khoảng di chuyển hợp lệ để không phải cắt vận tốc đột ngột ở mép màn hình. Con trỏ thật được giữ trong video gốc; app làm mượt camera, chưa vẽ lại/làm mượt con trỏ riêng.

## File lưu ở đâu?

Mỗi lần quay tạo một thư mục riêng trong `~/Movies/Screen Recorder/`:

```text
screen.mov                     # video gốc, kèm audio nếu bật
pointer.jsonl                  # tọa độ, trạng thái nút chuột, thời gian
manifest.json                  # kích thước, clock, cấu hình và số frame bị drop
export-follow-xxxxxxxx.mp4     # mỗi lần export tạo một file mới
export-follow-xxxxxxxx.json    # preset dùng để xuất file tương ứng
```

Nút folder mở lại một thư mục session để xuất tiếp sau khi khởi động lại app. File đang export được ghi tạm và chỉ đổi tên khi hoàn tất. Hủy export giữ nguyên video gốc. Không upload video, telemetry hay dữ liệu chuột lên mạng.

## Phạm vi bản 0.2

- Quay một màn hình mỗi lần; source giữ tỷ lệ, tối đa nằm trong 3840×2160, yêu cầu 60 fps. Tốc độ thực phụ thuộc thiết bị/tải hệ thống.
- MP4 H.264 có lựa chọn giữ độ phân giải gốc (mặc định), giới hạn 1080p hoặc 720p; giữ tỷ lệ màn hình. Render đủ frame theo timestamp 60 fps, kể cả khi source thưa frame. Source frame gần nhất được giữ lại giữa các mốc; camera vẫn chạy mỗi frame, nhưng app không tự tạo thêm chuyển động màn hình bị thiếu trong source.
- Decode pixel gốc → crop → resize Lanczos một lần → encode với bitrate mục tiêu cao hơn. Bitrate thực phụ thuộc nội dung. Nguồn 1080p zoom 2× chỉ còn 960×540 pixel chi tiết: export 4K hoặc tăng bitrate không thể khôi phục phần thiếu. Muốn chữ rõ ở mức zoom lớn, cần nguồn quay nhiều pixel hơn hoặc giảm zoom.
- Có tùy chọn system audio; chưa có microphone, webcam, chọn window/region, pause/resume hoặc manual zoom markers.
- Vị trí và trạng thái ba nút chuột được lấy mẫu khoảng 120 Hz, không ghi bàn phím. Click cực ngắn giữa hai lần lấy mẫu có thể bị bỏ lỡ; độ trễ thực cần đo với capture trên máy đích.
- Bản hiện tại tải pointer log và camera path vào RAM khi export; ưu tiên clip demo ngắn. Chưa tối ưu cho bản quay nhiều giờ.
- Nếu đổi cấu hình màn hình/rút monitor lúc quay, dừng và bắt đầu session mới. Không tự remap màn hình trong một session.
- Một recording lỗi/đĩa đầy có thể để lại session chưa hoàn tất; thông báo lỗi chỉ vị trí file để kiểm tra. Không cam kết phục hồi video chưa được finalize.

## Kiểm tra

```sh
swift run CameraTests
swift run ScreenRecorder --smoke-test
```

Chín unit tests kiểm tra crop ở biên, click/lead-in, chuẩn bị hướng camera trước click, chống rung nhỏ, độ phân giải và render không phụ thuộc thứ tự frame. Smoke test tạo nguồn gradient 15 fps + audio tổng hợp, xác minh đủ 240 frame cách đều ở output 60 fps trong 4 giây, decode audio, kiểm tra crop, re-export, hủy export và bảo toàn vạch 2 pixel khi crop nguồn 2560×1440 xuống 720p ở zoom 2×. Fixture nằm trong thư mục tạm được in ra cuối lệnh. Test này không quay màn hình hay xác nhận quyền ScreenCaptureKit.

Xem [kiến trúc](docs/architecture.md) và [checklist thử quay thật](docs/manual-validation.md).

**Trạng thái kiểm thử ban đầu:** build release và smoke test video/audio mẫu đã qua. Chưa xác nhận quay màn hình thật trong phiên phát triển vì ScreenCaptureKit trả về danh sách màn hình rỗng. Cần chạy checklist capture thực tế trên máy có màn hình khả dụng trước khi coi bản 0.1 là bản đã nghiệm thu.


## Nâng cấp từ 0.1

Quit app cũ rồi mở app mới. Settings cũ được giữ nguyên; bấm **Smooth preset** để dùng thông số mới. Có thể build song song mà không ghi đè app cũ:

```sh
./scripts/build-app.sh 'Screen Recorder 0.2'
open 'dist/Screen Recorder 0.2.app'
```

Để xuất lại một session mà không mở UI:

```sh
"dist/Screen Recorder 0.2.app/Contents/MacOS/ScreenRecorder" --reexport '/path/to/session' --smooth
# Thêm --720p nếu muốn output nhỏ hơn.
```

Các video cũ không bị sửa. Export receipt JSON phiên bản 2 lưu camera settings cùng kích thước output, fps, chất lượng và bitrate mục tiêu.
