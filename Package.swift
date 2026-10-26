// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenRecorder",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ScreenRecorder", targets: ["ScreenRecorder"])],
    targets: [
        .target(name: "RecorderCore"),
        .executableTarget(name: "ScreenRecorder", dependencies: ["RecorderCore"]),
        .executableTarget(name: "CameraTests", dependencies: ["RecorderCore"], path: "Tests/RecorderCoreTests")
    ]
)
