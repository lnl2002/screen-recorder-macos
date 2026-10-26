import AVFoundation
import RecorderCore
import ScreenCaptureKit

/// Runs the real encoder and camera exporter against a generated, non-private fixture.
enum SmokeTest {
    @MainActor static func capture() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw RecorderError.message("Capture test needs Screen Recording permission for the packaged app. Open it, grant permission, then run --capture-test again.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw RecorderError.message("No display available for the capture test.")
        }
        let engine = CaptureEngine()
        _ = try await engine.start(display: display, systemAudio: false)
        try await Task.sleep(for: .seconds(3))
        var settings = CameraSettings(); settings.mode = .follow
        let session = try await engine.stop(settings: settings)
        let output = try await VideoExporter().export(session, settings: settings)
        let asset = AVURLAsset(url: output)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(decoded)
        guard reader.startReading() else { throw reader.error! }
        var count = 0
        while decoded.copyNextSampleBuffer() != nil { count += 1 }
        guard reader.status == .completed, count >= 120, !(try session.loadPointer()).isEmpty else {
            throw RecorderError.message("Capture test produced incomplete video or pointer data.")
        }
        print("PASS: real ScreenCaptureKit capture → pointer log → follow export → full decode (\(count) frames).")
        print("Private local test recording: \(session.directory.path)")
    }

    @MainActor static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("screen-recorder-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("screen.mov")
        print("Smoke: creating video at \(directory.path)")
        try await makeVideo(at: source)
        print("Smoke: adding audio")
        try await addAudio(to: source)
        let samples = (0..<480).map { i in
            PointerSample(time: Double(i) / 120, x: 0.8, y: 0.2, buttons: i == 120 ? 1 : 0)
        }
        var pointer = Data()
        for sample in samples { pointer.append(try JSONEncoder().encode(sample)); pointer.append(10) }
        try pointer.write(to: directory.appendingPathComponent("pointer.jsonl"))
        var settings = CameraSettings(); settings.mode = .follow; settings.zoom = 2; settings.deadZone = 0
        let manifest = SessionManifest(width: 640, height: 360, fps: 60, duration: 4,
                                       displayID: 0, captureBounds: [0, 0, 640, 360], hostEpoch: 0,
                                       systemAudio: true, videoFrames: 60, droppedVideoFrames: 0,
                                       droppedAudioBuffers: 0, settings: settings)
        try RecordingSession.writeJSON(manifest, to: directory.appendingPathComponent("manifest.json"))
        let session = try RecordingSession.open(directory)
        let exporter = VideoExporter()
        print("Smoke: exporting follow mode")
        let follow = try await exporter.export(session, settings: settings)
        let path = CameraPath(samples: samples, duration: 4, settings: settings)
        let expected = path.frame(at: 2)
        try await validate(follow, expectedX: expected.x, expectedY: expected.y)
        settings.mode = .off
        print("Smoke: exporting full-screen mode")
        let full = try await exporter.export(session, settings: settings)
        try await validate(full, expectedX: 0.5, expectedY: 0.5)
        let cancelledExporter = VideoExporter()
        let cancelledTask = Task { try await cancelledExporter.export(session, settings: settings) }
        while !cancelledExporter.isExporting { await Task.yield() }
        cancelledExporter.cancel()
        do {
            _ = try await cancelledTask.value
            throw RecorderError.message("Cancelled export unexpectedly succeeded.")
        } catch is CancellationError {
            guard FileManager.default.fileExists(atPath: source.path) else { throw RecorderError.message("Cancellation removed the original.") }
        }
        print("PASS: sparse source → 240 evenly spaced output frames, H.264/MP4, audio decode, crop geometry, and re-export.")
        print("PASS: export cancellation preserves the original.")
        try await testNativeDetail(in: directory)
        print("Fixtures and MP4s: \(directory.path)")
    }

    private static func makeVideo(at url: URL, width: Int = 640, height: Int = 360, stripes: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                      AVVideoWidthKey: width, AVVideoHeightKey: height,
                                      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 16]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { throw RecorderError.message("Fixture pixel allocation failed.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base.advanced(by: y * rowBytes + x * 4)
                if stripes {
                    let value: UInt8 = (x / 2) % 2 == 0 ? 16 : 235
                    p[0] = value; p[1] = value; p[2] = value
                } else {
                    p[0] = 60; p[1] = UInt8(y * 255 / (height - 1)); p[2] = UInt8(x * 255 / (width - 1))
                }
                p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // Reuse an immutable fixture image at sparse source timestamps (15 fps).
        for frame in stride(from: 0, to: 240, by: 4) {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? RecorderError.message("Fixture writer stopped.") }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 60)) else { throw writer.error! }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 4, preferredTimescale: 600))
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
    }

    @MainActor private static func testNativeDetail(in parent: URL) async throws {
        let directory = parent.appendingPathComponent("native-detail")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await makeVideo(at: directory.appendingPathComponent("screen.mov"), width: 2560, height: 1440, stripes: true)
        let pointer = PointerSample(time: 0, x: 0.5, y: 0.5)
        try JSONEncoder().encode(pointer).write(to: directory.appendingPathComponent("pointer.jsonl"))
        var settings = CameraSettings(); settings.mode = .follow; settings.zoom = 2; settings.response = 0.15
        let manifest = SessionManifest(width: 2560, height: 1440, fps: 60, duration: 4,
                                       displayID: 0, captureBounds: [0, 0, 2560, 1440], hostEpoch: 0,
                                       systemAudio: false, videoFrames: 60, droppedVideoFrames: 0,
                                       droppedAudioBuffers: 0, settings: settings)
        try RecordingSession.writeJSON(manifest, to: directory.appendingPathComponent("manifest.json"))
        let session = try RecordingSession.open(directory)
        let output = try await VideoExporter().export(session, settings: settings, quality: .compact)
        let asset = AVURLAsset(url: output)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        guard size == CGSize(width: 1280, height: 720) else { throw RecorderError.message("Wrong compact output size.") }
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(decoded)
        guard reader.startReading() else { throw reader.error! }
        defer { reader.cancelReading() }
        while let sample = decoded.copyNextSampleBuffer() {
            if sample.presentationTimeStamp.seconds < 2 { continue }
            guard let buffer = sample.imageBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let pixels = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            var totalError = 0.0
            for x in 576..<704 {
                let actual = Double(pixels[360 * rowBytes + x * 4 + 2])
                let expected = ((x + 640) / 2) % 2 == 0 ? 16.0 : 235.0
                totalError += abs(actual - expected)
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            guard totalError / 128 < 20 else {
                throw RecorderError.message("Native detail was lost before zoom: stripe MAE \(totalError / 128)")
            }
            print("PASS: original 2560×1440 crop → 1280×720 at 2× preserves two-pixel stripe detail.")
            return
        }
        throw RecorderError.message("No detail verification frame decoded.")
    }

    private static func addAudio(to source: URL) async throws {
        let audioURL = source.deletingLastPathComponent().appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 192000)!
            buffer.frameLength = 192000
            for i in 0..<192000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000) * 0.1) }
            try file.write(from: buffer)
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: source), audioAsset = AVURLAsset(url: audioURL)
        let video = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audio = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 4, preferredTimescale: 600))
        print("Smoke: inserting fixture video/audio tracks")
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: video, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: audio, at: .zero)
        let output = source.deletingLastPathComponent().appendingPathComponent("with-audio.mov")
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        export.outputURL = output; export.outputFileType = .mov
        print("Smoke: exporting fixture with audio")
        await export.export()
        guard export.status == .completed else { throw export.error! }
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: output, to: source)
    }

    private static func validate(_ url: URL, expectedX: Double, expectedY: Double) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard abs(duration - 4) < 0.08 else { throw RecorderError.message("Wrong export duration: \(duration)") }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count == 1 else { throw RecorderError.message("Audio was lost during export.") }
        let video = try await asset.loadTracks(withMediaType: .video)[0]
        let descriptions = try await video.load(.formatDescriptions)
        guard descriptions.first.map({ CMFormatDescriptionGetMediaSubType($0) }) == kCMVideoCodecType_H264 else {
            throw RecorderError.message("Export codec is not H.264.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error! }
        var count = 0, checkedCenter = false
        while let sample = output.copyNextSampleBuffer() {
            let expectedPTS = Double(count) / 60
            guard abs(sample.presentationTimeStamp.seconds - expectedPTS) < 0.0001 else {
                throw RecorderError.message("Nonuniform frame cadence at frame \(count): \(sample.presentationTimeStamp.seconds)")
            }
            count += 1
            if !checkedCenter, sample.presentationTimeStamp.seconds >= 2, let buffer = sample.imageBuffer {
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                    .advanced(by: (height / 2) * CVPixelBufferGetBytesPerRow(buffer) + (width / 2) * 4)
                let r = Double(p[2]) / 255, g = Double(p[1]) / 255
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                guard abs(r - expectedX) < 0.08, abs(g - expectedY) < 0.08 else {
                    throw RecorderError.message("Crop mismatch: got (\(r), \(g)), expected (\(expectedX), \(expectedY)).")
                }
                checkedCenter = true
            }
        }
        guard reader.status == .completed, count == 240, checkedCenter else {
            throw reader.error ?? RecorderError.message("Incomplete export: \(count) frames.")
        }
        let audioReader = try AVAssetReader(asset: asset)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTracks[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        audioReader.add(audioOutput)
        guard audioReader.startReading() else { throw audioReader.error! }
        var audioFrames = 0
        while let sample = audioOutput.copyNextSampleBuffer() { audioFrames += sample.numSamples }
        guard audioReader.status == .completed, audioFrames > 180000 else {
            throw RecorderError.message("Audio decode incomplete: \(audioFrames) samples")
        }
    }
}
