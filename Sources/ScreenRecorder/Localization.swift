import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, vi
    var id: String { rawValue }
    var name: String { self == .en ? "English" : "Tiếng Việt" }
}

enum L10n {
    private static let vi: [String: String] = [
        "Language": "Ngôn ngữ", "Record once. Find your focus.": "Quay một lần. Tập trung đúng chỗ.",
        "Live preview": "Xem trước trực tiếp", "Recording": "Đang quay", "Waiting for screen preview…": "Đang chờ hình xem trước…",
        "Screen Recording permission": "Quyền quay màn hình", "Allow access so this app can record your selected screen.": "Cho phép ứng dụng quay màn hình bạn đã chọn.",
        "Allow screen recording": "Cho phép quay màn hình", "System Settings": "Cài đặt hệ thống", "Refresh": "Làm mới",
        "Capture": "Ghi hình", "Refresh screens": "Làm mới màn hình", "Screen": "Màn hình", "No screen selected": "Chưa chọn màn hình",
        "Main display": "Màn hình chính", "Display": "Màn hình", "Record system audio": "Ghi âm thanh hệ thống",
        "System audio": "Âm thanh", "Webcam": "Webcam", "Webcam size": "Cỡ webcam",
        "Show camera bubble": "Hiện camera hình tròn", "Export": "Xuất video",
        "Original resolution · best detail": "Độ phân giải gốc · rõ nhất", "1080p · smaller file": "1080p · tệp nhỏ hơn", "720p · compact": "720p · gọn nhẹ",
        "The recorder controls are excluded. Original pixels are retained up to 4K. MP4 export renders every frame at 60 fps.": "Cửa sổ điều khiển không xuất hiện trong video. Hình gốc được giữ tối đa 4K và MP4 được xuất ở 60 fps.",
        "Camera style": "Kiểu chuyển động", "Smooth preset": "Thiết lập mượt", "Auto zoom": "Tự động zoom", "Follow mouse": "Theo con trỏ", "Full screen": "Toàn màn hình",
        "Zoom around clicks, follow the action, then ease back to the full screen.": "Zoom quanh vị trí nhấp chuột, theo hành động rồi từ từ trở về toàn màn hình.",
        "Stay zoomed in. The camera gently follows your mouse across the screen.": "Giữ mức zoom và nhẹ nhàng di chuyển theo con trỏ.",
        "Keep the full screen in view, with no camera movement.": "Giữ nguyên toàn màn hình, không di chuyển khung hình.",
        "Zoom": "Độ zoom", "Glide duration": "Thời gian lướt", "Hold after click": "Giữ sau khi nhấp", "Fine tune": "Tinh chỉnh", "Quiet zone": "Vùng tĩnh", "Lead-in": "Đón trước",
        "Stop & export": "Dừng và xuất", "Cancel export": "Hủy xuất", "Record": "Bắt đầu quay", "Export again": "Xuất lại", "Session folder": "Thư mục phiên", "Show MP4": "Hiện tệp MP4",
        "Open an existing recording session": "Mở một phiên quay đã có", "Originals are saved in Movies / Screen Recorder.": "Video gốc được lưu trong Movies / Screen Recorder.",
        "Camera size": "Kích thước camera", "Drag the circle to place it. The camera is mirrored like a selfie and saved into the exported MP4.": "Kéo hình tròn để đổi vị trí. Camera được lật như ảnh selfie và ghép vào MP4 khi xuất.",
        "Choose a screen and a camera style.": "Chọn màn hình và kiểu chuyển động.", "No screens available.": "Không có màn hình khả dụng.", "Ready to record. Your original video stays saved.": "Sẵn sàng quay. Video gốc sẽ luôn được giữ lại.",
        "Allow Screen Recording in System Settings, then refresh screens. You may need to reopen the app.": "Hãy cấp quyền Quay màn hình trong Cài đặt hệ thống, sau đó làm mới danh sách. Bạn có thể cần mở lại ứng dụng.",
        "Starting screen capture…": "Đang bắt đầu quay màn hình…", "Recording. Stop from this window or the menu bar.": "Đang quay. Bạn có thể dừng tại cửa sổ này hoặc thanh menu.",
        "Get ready…": "Chuẩn bị…", "Camera permission is required for webcam preview.": "Cần cấp quyền Camera để xem trước webcam.",
        "Recording. Drag the camera bubble to move it, or resize it from an edge.": "Đang quay. Kéo camera tròn để di chuyển hoặc kéo cạnh để đổi kích thước.",
        "Could not start recording.": "Không thể bắt đầu quay.", "Saving the original recording…": "Đang lưu video gốc…", "Recording stopped with an error.": "Đã dừng quay do có lỗi.",
        "Rendering camera movement and exporting MP4…": "Đang dựng chuyển động và xuất MP4…", "MP4 ready. Change the camera style to export another version.": "MP4 đã sẵn sàng. Bạn có thể đổi kiểu chuyển động và xuất phiên bản khác.",
        "Export cancelled. Your original recording is safe.": "Đã hủy xuất. Video gốc vẫn an toàn.", "Export failed. Your original recording is safe; you can retry.": "Xuất video thất bại. Video gốc vẫn an toàn; bạn có thể thử lại.",
        "Cancelling export… Your original recording is safe.": "Đang hủy xuất… Video gốc vẫn an toàn.", "Session opened. Choose a camera style and export.": "Đã mở phiên quay. Chọn kiểu chuyển động rồi xuất video.",
        "Choose a recording folder containing manifest.json and screen.mov.": "Chọn thư mục phiên quay có manifest.json và screen.mov.",
        "Show recorder": "Hiện trình quay", "Start recording": "Bắt đầu quay", "Quit Screen Recorder": "Thoát Screen Recorder", "About Screen Recorder": "Giới thiệu Screen Recorder",
        "Finish your recording first": "Hãy hoàn tất phiên quay", "Stop the recording or cancel the export before quitting. Your original recording will be kept.": "Dừng quay hoặc hủy xuất trước khi thoát. Video gốc của bạn vẫn được giữ lại.", "Keep recorder open": "Tiếp tục mở ứng dụng"
    ]

    static func text(_ english: String, _ language: AppLanguage) -> String {
        language == .vi ? (vi[english] ?? english) : english
    }
}
