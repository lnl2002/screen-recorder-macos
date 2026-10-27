import AVFoundation
@preconcurrency import CoreImage
import RecorderCore

/// Cross-thread cancellation/progress; encoder objects remain owned by the export task.
private final class ExportState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private var cancelled = false
    var progress: Double { lock.lock(); defer { lock.unlock() }; return value }
    func update(_ progress: Double) { lock.lock(); value = progress; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        try Task.checkCancellation()
        lock.lock(); let cancelled = cancelled; lock.unlock()
        if cancelled { throw CancellationError() }
    }
}

@MainActor
final class VideoExporter {
    private var active: ExportState?
    var isExporting: Bool { active != nil }
    var progress: Double { active?.progress ?? 0 }
    func cancel() { active?.cancel() }

    func export(_ session: RecordingSession, settings: CameraSettings, quality: ExportQuality = .source) async throws -> URL {
        guard active == nil else { throw RecorderError.message("An export is already running.") }
        let state = ExportState(); active = state
        defer { active = nil }
        return try await Task.detached(priority: .userInitiated) {
            try await Self.render(session, settings: settings.sanitized, quality: quality, state: state)
        }.value
    }

    /// Decode original pixels, crop first, resample once, then encode every output timestamp.
    /// A composition's frameDuration alone does not turn sparse capture samples into CFR.
    nonisolated private static func render(_ session: RecordingSession, settings: CameraSettings,
                                           quality: ExportQuality, state: ExportState) async throws -> URL {
        try state.check()
        let samples = try session.loadPointer()
        let asset = AVURLAsset(url: session.source)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw RecorderError.message("The recording has no video track.") }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        // Sessions produced by this recorder are upright. Reject unsupported imported transforms explicitly.
        guard transform == .identity, naturalSize.width > 0, naturalSize.height > 0,
              duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 86400 else {
            throw RecorderError.message("The recording has unsupported geometry or duration.")
        }
        let path = CameraPath(samples: samples, duration: duration.seconds, settings: settings)
        let size = quality.size(for: naturalSize)
        let width = Int(size.width), height = Int(size.height)
        let fps = 60
        let count = max(1, Int(ceil(duration.seconds * Double(fps) - 0.00001)))
        let videoReader = try AVAssetReader(asset: asset)
        // No width/height keys here: always decode the original source resolution.
        let videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOutput.alwaysCopiesSampleData = false
        videoReader.add(videoOutput)

        var webcamReader: AVAssetReader?
        var webcamOutput: AVAssetReaderTrackOutput?
        var webcamCurrent: CMSampleBuffer?
        var webcamNext: CMSampleBuffer?
        let webcamSettings = session.manifest.webcam?.sanitized
        if webcamSettings?.enabled == true, session.manifest.webcamBakedIn != true,
           FileManager.default.fileExists(atPath: session.webcamFile.path) {
            let webcamAsset = AVURLAsset(url: session.webcamFile)
            if let webcamTrack = try await webcamAsset.loadTracks(withMediaType: .video).first {
                let reader = try AVAssetReader(asset: webcamAsset)
                let output = AVAssetReaderTrackOutput(track: webcamTrack, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
                output.alwaysCopiesSampleData = false
                reader.add(output); webcamReader = reader; webcamOutput = output
            }
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = audioTracks.first {
            let reader = try AVAssetReader(asset: asset)
            // Decode to PCM and encode to AAC so both recorder sessions and imported smoke fixtures work.
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            output.alwaysCopiesSampleData = false
            reader.add(output); audioReader = reader; audioOutput = output
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
            ])
        }
        let stem = "export-\(settings.mode.rawValue)-\(UUID().uuidString.prefix(8))"
        let outputURL = session.directory.appendingPathComponent(stem + ".mp4")
        let temporary = session.directory.appendingPathComponent(".\(stem).partial.mp4")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let bitrate = min(100_000_000, max(8_000_000, width * height * 16))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                                              AVVideoExpectedSourceFrameRateKey: fps,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: fps * 2,
                                              AVVideoAllowFrameReorderingKey: false]
        ])
        guard writer.canAdd(videoInput) else { throw RecorderError.message("The video encoder cannot handle this output size.") }
        writer.add(videoInput)
        if let audioInput {
            guard writer.canAdd(audioInput) else { throw RecorderError.message("The audio encoder is unavailable.") }
            writer.add(audioInput)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        var completed = false
        defer {
            videoReader.cancelReading(); audioReader?.cancelReading(); webcamReader?.cancelReading()
            if !completed { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: temporary)
        }
        try state.check()
        guard videoReader.startReading(), writer.startWriting() else {
            throw videoReader.error ?? writer.error ?? RecorderError.message("Could not start export.")
        }
        if let audioReader, !audioReader.startReading() { throw audioReader.error ?? RecorderError.message("Cannot decode audio.") }
        if let webcamReader {
            guard webcamReader.startReading() else { throw webcamReader.error ?? RecorderError.message("Cannot decode camera video.") }
            webcamCurrent = webcamOutput?.copyNextSampleBuffer()
            webcamNext = webcamOutput?.copyNextSampleBuffer()
        }
        writer.startSession(atSourceTime: .zero)
        guard var current = videoOutput.copyNextSampleBuffer() else {
            throw videoReader.error ?? RecorderError.message("The recording has no decodable frames.")
        }
        var next = videoOutput.copyNextSampleBuffer()
        // Independent producers are required: the muxer may pause video while
        // waiting for more audio (or vice versa). Never block one behind the other.
        let audioSource = audioOutput, audioDestination = audioInput, audioDecoder = audioReader
        async let audioWork: Void = writeAudio(audioSource, reader: audioDecoder, input: audioDestination,
                                              writer: writer, duration: duration.seconds, state: state)
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        for index in 0..<count {
            try state.check()
            let time = CMTime(value: Int64(index), timescale: Int32(fps))
            while let candidate = next, CMTimeCompare(candidate.presentationTimeStamp, time) <= 0 {
                current = candidate; next = videoOutput.copyNextSampleBuffer()
            }
            if videoReader.status == .failed { throw videoReader.error ?? RecorderError.message("Video decoding failed.") }
            try await waitUntilReady(videoInput, writer: writer, state: state)
            try autoreleasepool {
                guard let source = current.imageBuffer, let pool = adaptor.pixelBufferPool else {
                    throw RecorderError.message("A video frame or encoder pixel pool is missing.")
                }
                var target: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &target) == kCVReturnSuccess,
                      let target else { throw RecorderError.message("Could not allocate an export frame.") }
                let image = CIImage(cvPixelBuffer: source)
                let normalized = path.frame(at: time.seconds).crop
                let crop = CGRect(x: normalized.minX * image.extent.width,
                                  y: (1 - normalized.maxY) * image.extent.height,
                                  width: normalized.width * image.extent.width,
                                  height: normalized.height * image.extent.height)
                let cropped = image.clampedToExtent().cropped(to: crop)
                    .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                // Lanczos resamples the original crop once; there is no pre-zoom 1080p resize.
                let scaled = cropped.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: size.height / crop.height,
                    kCIInputAspectRatioKey: (size.width / crop.width) / (size.height / crop.height)
                ])
                var composed = scaled
                if let webcamSettings, var cameraSample = webcamCurrent, let cameraBuffer = cameraSample.imageBuffer {
                    let cameraTime = max(0, time.seconds + (session.manifest.webcamTimeOffset ?? 0))
                    while let candidate = webcamNext, candidate.presentationTimeStamp.seconds <= cameraTime {
                        cameraSample = candidate; webcamCurrent = candidate
                        webcamNext = webcamOutput?.copyNextSampleBuffer()
                    }
                    if let buffer = cameraSample.imageBuffer {
                        composed = addWebcam(CIImage(cvPixelBuffer: buffer), to: scaled, outputSize: size,
                                             settings: webcamSettings)
                    } else { _ = cameraBuffer }
                }
                context.render(composed, to: target, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
                guard adaptor.append(target, withPresentationTime: time) else {
                    throw writer.error ?? RecorderError.message("Video writing failed.")
                }
            }
            state.update(Double(index + 1) / Double(count) * 0.98)
        }
        videoInput.markAsFinished()
        try await audioWork
        writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: Int32(fps)))
        await writer.finishWriting()
        try state.check()
        guard writer.status == .completed else { throw writer.error ?? RecorderError.message("Export could not be finalized.") }
        try FileManager.default.moveItem(at: temporary, to: outputURL)
        let receipt = ExportReceipt(camera: settings, quality: quality, width: width, height: height, fps: fps, bitrate: bitrate)
        try RecordingSession.writeJSON(receipt, to: session.directory.appendingPathComponent(stem + ".json"))
        completed = true; state.update(1)
        return outputURL
    }

    nonisolated private static func addWebcam(_ webcam: CIImage, to background: CIImage, outputSize: CGSize,
                                               settings: WebcamSettings) -> CIImage {
        let diameter = settings.size * min(outputSize.width, outputSize.height)
        let origin = CGPoint(x: settings.x * outputSize.width - diameter / 2,
                             y: (1 - settings.y) * outputSize.height - diameter / 2)
        let destination = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        let source = webcam.extent
        let side = min(source.width, source.height)
        let square = CGRect(x: source.midX - side / 2, y: source.midY - side / 2, width: side, height: side)
        let face = webcam.cropped(to: square)
            .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -side, y: 0))
            .transformed(by: CGAffineTransform(scaleX: diameter / side, y: diameter / side))
            .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
        let mask = CIImage(color: .white).cropped(to: destination)
            .applyingFilter("CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: destination.midX, y: destination.midY),
                "inputRadius0": diameter / 2 - 1,
                "inputRadius1": diameter / 2 + 1,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.clear
            ]).cropped(to: destination)
        return face.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ]).cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    nonisolated private static func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter, state: ExportState) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        while !input.isReadyForMoreMediaData {
            try state.check()
            guard writer.status == .writing else { throw writer.error ?? RecorderError.message("The encoder stopped unexpectedly.") }
            if ProcessInfo.processInfo.systemUptime - started > 30 { throw RecorderError.message("The encoder stalled. Your original recording is safe.") }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    nonisolated private static func writeAudio(_ output: AVAssetReaderTrackOutput?, reader: AVAssetReader?,
                                               input: AVAssetWriterInput?, writer: AVAssetWriter,
                                               duration: Double, state: ExportState) async throws {
        guard let output, let reader, let input else { return }
        defer { input.markAsFinished() }
        while let sample = output.copyNextSampleBuffer() {
            try state.check()
            if sample.presentationTimeStamp.seconds >= duration { break }
            try await waitUntilReady(input, writer: writer, state: state)
            guard input.append(sample) else { throw writer.error ?? RecorderError.message("Audio writing failed.") }
        }
        if reader.status == .failed { throw reader.error ?? RecorderError.message("Audio decoding failed.") }
    }
}

private struct ExportReceipt: Codable {
    var version = 2
    let camera: CameraSettings
    let quality: ExportQuality
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int
}
