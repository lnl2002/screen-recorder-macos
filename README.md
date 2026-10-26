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
3. Chọn **Auto zoom**, **Follow mouse**, hoặc **Full screen**. Chỉnh mức zoom, glide duration, thời gian giữ zoom, quiet zone và lead-in.
4. Bấm **Record**. Khi xong, bấm **Stop & export** ở cửa sổ app hoặc menu bar.
5. Bấm **Show MP4** để mở vị trí video. Đổi preset và bấm **Export again** để xuất bản khác từ cùng video gốc.

`⌘⇧R` bắt đầu/dừng khi cửa sổ app đang active; đây không phải global hotkey. Menu bar luôn có nút dừng. Các cửa sổ của app được loại khỏi màn hình đang quay.

## Camera

- **Auto zoom:** zoom trước click theo lead-in, giữ theo hold, gộp các cụm click gần nhau, rồi trở lại toàn cảnh.
- **Follow mouse:** giữ mức zoom đã chọn và pan theo chuột.
- **Full screen:** xuất toàn cảnh.
- **Glide duration:** số lớn làm camera chuyển động chậm hơn.
- **Quiet zone:** chuột di chuyển trong vùng giữa mà camera chưa cần pan.

Camera dùng spring critically damped, tính trước ở bước thời gian cố định. Crop được giới hạn trong màn hình. Con trỏ thật được giữ trong video gốc; app làm mượt camera, chưa vẽ lại/làm mượt con trỏ riêng.

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

## Phạm vi bản 0.1

- Quay một màn hình mỗi lần; source giữ tỷ lệ, tối đa nằm trong 3840×2160, yêu cầu 60 fps. Tốc độ thực phụ thuộc thiết bị/tải hệ thống.
- MP4 H.264 tối đa nằm trong 1920×1080, giữ tỷ lệ màn hình, render 60 fps. Màn hình dọc được xuất với tỷ lệ dọc.
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

Unit tests kiểm tra crop ở biên, click/lead-in, trở lại toàn cảnh, input không hợp lệ và render không phụ thuộc thứ tự frame. Smoke test tạo video gradient + audio tổng hợp, chạy encoder/exporter thật, decode toàn bộ MP4 và kiểm tra thời lượng, codec, audio track, vị trí crop và re-export toàn cảnh. Fixture nằm trong thư mục tạm được in ra cuối lệnh. Test này không quay màn hình hay xác nhận quyền ScreenCaptureKit.

Xem [kiến trúc](docs/architecture.md) và [checklist thử quay thật](docs/manual-validation.md).

**Trạng thái kiểm thử ban đầu:** build release và smoke test video/audio mẫu đã qua. Chưa xác nhận quay màn hình thật trong phiên phát triển vì ScreenCaptureKit trả về danh sách màn hình rỗng. Cần chạy checklist capture thực tế trên máy có màn hình khả dụng trước khi coi bản 0.1 là bản đã nghiệm thu.
