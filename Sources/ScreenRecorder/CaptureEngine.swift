import AppKit
import AVFoundation
import ScreenCaptureKit
import RecorderCore

/// Every writer, pointer file and timer mutation lives on one serial queue.
final class CaptureSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "recorder.capture", qos: .userInitiated)
    let directory: URL
    let bounds: CGRect
    let writer: AVAssetWriter
    let video: AVAssetWriterInput
    let audio: AVAssetWriterInput?
    let pointer: FileHandle
    private var timer: DispatchSourceTimer?
    private var epoch: CMTime?
    private var lastVideo: CMSampleBuffer?
    private var lastPTS: CMTime?
    private var stopped = false
    private var failure: Error?
    private var frames = 0, dropped = 0, droppedAudio = 0
    var onFailure: ((Error) -> Void)?

    init(directory: URL, bounds: CGRect, width: Int, height: Int, fps: Int, systemAudio: Bool) throws {
        self.directory = directory; self.bounds = bounds
        writer = try AVAssetWriter(outputURL: directory.appendingPathComponent("screen.mov"), fileType: .mov)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(100_000_000, width * height * 16),
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoExpectedSourceFrameRateKey: fps,
                                              AVVideoMaxKeyFrameIntervalKey: fps * 2]
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecorderError.message("Video encoder is unavailable.") }
        writer.add(video)
        if systemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecorderError.message("Audio encoder is unavailable.") }
            writer.add(input); audio = input
        } else { audio = nil }
        let pointerURL = directory.appendingPathComponent("pointer.jsonl")
        guard FileManager.default.createFile(atPath: pointerURL.path, contents: nil) else {
            throw RecorderError.message("Could not create the pointer recording.")
        }
        pointer = try FileHandle(forWritingTo: pointerURL)
        super.init()
        guard writer.startWriting() else { throw writer.error ?? RecorderError.message("Could not start the video writer.") }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, failure == nil, sample.isValid else { return }
        let pts = sample.presentationTimeStamp
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  status == SCFrameStatus.complete.rawValue, sample.imageBuffer != nil else { return }
            if epoch == nil {
                epoch = pts
                writer.startSession(atSourceTime: pts)
                startPointerTimer()
            }
            if let lastPTS, CMTimeCompare(pts, lastPTS) <= 0 { return }
            guard video.isReadyForMoreMediaData else { dropped += 1; return }
            if video.append(sample) {
                frames += 1; lastVideo = sample; lastPTS = pts
            } else { fail(writer.error ?? RecorderError.message("Video writing failed.")) }
        } else if type == .audio, let audio, let epoch, CMTimeCompare(pts, epoch) >= 0 {
            guard audio.isReadyForMoreMediaData else { droppedAudio += 1; return }
            if !audio.append(sample) { fail(writer.error ?? RecorderError.message("Audio writing failed.")) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.fail(error) }
    }

    private func fail(_ error: Error) {
        guard failure == nil, !stopped else { return }
        failure = error
        onFailure?(error)
    }

    private func startPointerTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .microseconds(8333), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.samplePointer() }
        self.timer = timer; timer.resume()
    }

    private func samplePointer() {
        guard let epoch, !stopped else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard let location = CGEvent(source: nil)?.location else { return }
        var buttons: UInt64 = 0
        for index in 0..<3 {
            if let button = CGMouseButton(rawValue: UInt32(index)), CGEventSource.buttonState(.combinedSessionState, button: button) {
                buttons |= 1 << index
            }
        }
        let sample = PointerSample(time: max(0, CMTimeGetSeconds(now - epoch)),
                                   x: (location.x - bounds.minX) / bounds.width,
                                   y: (location.y - bounds.minY) / bounds.height,
                                   buttons: buttons, inside: bounds.contains(location))
        do {
            var data = try JSONEncoder().encode(sample); data.append(10)
            try pointer.write(contentsOf: data)
        } catch { fail(error) }
    }

    func finish(at end: CMTime) async throws -> (Double, Double, Int, Int, Int) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.timer?.cancel(); self.timer = nil
                self.samplePointer(); self.stopped = true
                do { try self.pointer.synchronize(); try self.pointer.close() }
                catch { self.failure = self.failure ?? error }
                guard let epoch = self.epoch, self.frames > 0 else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: self.failure ?? RecorderError.message("No screen frames arrived. Check Screen Recording permission and try again."))
                    return
                }
                // Hold the final frame through the user's stop time, even for a static desktop.
                let end = CMTimeMaximum(end, (self.lastPTS ?? epoch) + CMTime(value: 1, timescale: 60))
                if let sample = self.lastVideo, self.video.isReadyForMoreMediaData {
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                                                   presentationTimeStamp: end, decodeTimeStamp: .invalid)
                    var copy: CMSampleBuffer?
                    if CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                                                            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                                            sampleBufferOut: &copy) == noErr, let copy {
                        if !self.video.append(copy) { self.failure = self.writer.error }
                    }
                }
                self.writer.endSession(atSourceTime: end)
                self.video.markAsFinished(); self.audio?.markAsFinished()
                self.writer.finishWriting {
                    if let error = self.failure ?? self.writer.error {
                        continuation.resume(throwing: error)
                    } else if self.writer.status != .completed {
                        continuation.resume(throwing: RecorderError.message("Recording could not be finalized."))
                    } else {
                        continuation.resume(returning: (CMTimeGetSeconds(end - epoch), CMTimeGetSeconds(epoch),
                                                        self.frames, self.dropped, self.droppedAudio))
                    }
                }
            }
        }
    }

    func abort() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopped = true; self.timer?.cancel(); self.timer = nil
                self.writer.cancelWriting(); try? self.pointer.close()
                continuation.resume()
            }
        }
    }
}

@MainActor
final class CaptureEngine {
    private var stream: SCStream?
    private var sink: CaptureSink?
    private var displayID: CGDirectDisplayID = 0
    private var dimensions = (0, 0)
    private var hasAudio = false
    private let fps = 60
    var onFailure: ((Error) -> Void)?

    func start(display: SCDisplay, systemAudio: Bool) async throws -> URL {
        guard stream == nil else { throw RecorderError.message("A recording is already running.") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let bounds = CGDisplayBounds(display.displayID)
        // ScreenCaptureKit's point-to-pixel scale is authoritative for Retina capture.
        let nativeWidth = max(2, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        let nativeHeight = max(2, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        let scale = min(1, min(3840.0 / Double(nativeWidth), 2160.0 / Double(nativeHeight)))
        let width = max(2, Int(Double(nativeWidth) * scale) / 2 * 2)
        let height = max(2, Int(Double(nativeHeight) * scale) / 2 * 2)
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        config.queueDepth = 6; config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.capturesAudio = systemAudio; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        let directory = try RecordingSession.createDirectory()
        let sink = try CaptureSink(directory: directory, bounds: bounds, width: width, height: height, fps: fps, systemAudio: systemAudio)
        sink.onFailure = { [weak self] error in Task { @MainActor in self?.onFailure?(error) } }
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if systemAudio { try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue) }
            self.sink = sink; self.stream = stream
            self.displayID = display.displayID; self.dimensions = (width, height); self.hasAudio = systemAudio
            try await stream.startCapture()
        } catch {
            self.stream = nil; self.sink = nil
            await sink.abort()
            throw error
        }
        return directory
    }

    func stop(settings: CameraSettings) async throws -> RecordingSession {
        guard let stream, let sink else { throw RecorderError.message("No recording is running.") }
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        // A stream that already failed may reject stopCapture; still finalize its writer.
        try? await stream.stopCapture()
        defer { self.stream = nil; self.sink = nil }
        let (duration, epoch, frames, dropped, droppedAudio) = try await sink.finish(at: stopTime)
        let bounds = sink.bounds
        let manifest = SessionManifest(width: dimensions.0, height: dimensions.1, fps: fps, duration: duration,
                                       displayID: displayID, captureBounds: [bounds.minX, bounds.minY, bounds.width, bounds.height],
                                       hostEpoch: epoch, systemAudio: hasAudio, videoFrames: frames,
                                       droppedVideoFrames: dropped, droppedAudioBuffers: droppedAudio, settings: settings)
        try RecordingSession.writeJSON(manifest, to: sink.directory.appendingPathComponent("manifest.json"))
        return RecordingSession(directory: sink.directory, manifest: manifest)
    }
}
