import AVFoundation
@preconcurrency import CoreImage
import RecorderCore

@MainActor
final class VideoExporter {
    private var active: AVAssetExportSession?
    private var preparing = false
    private var cancelRequested = false
    var progress: Double { Double(active?.progress ?? 0) }
    func cancel() { cancelRequested = true; active?.cancelExport() }

    func export(_ session: RecordingSession, settings: CameraSettings) async throws -> URL {
        guard active == nil, !preparing else { throw RecorderError.message("An export is already running.") }
        preparing = true; cancelRequested = false
        defer { preparing = false }
        let samples = try await Task.detached { try session.loadPointer() }.value
        if cancelRequested { throw CancellationError() }
        let asset = AVURLAsset(url: session.source)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw RecorderError.message("The recording has no video track.") }
        let naturalSize = try await track.load(.naturalSize)
        guard naturalSize.width > 0, naturalSize.height > 0, duration.seconds.isFinite,
              duration.seconds > 0, duration.seconds <= 86400 else {
            throw RecorderError.message("The source video has invalid dimensions or duration.")
        }
        let path = await Task.detached {
            CameraPath(samples: samples, duration: duration.seconds, settings: settings)
        }.value
        if cancelRequested { throw CancellationError() }
        let ratio = min(1, min(1920 / naturalSize.width, 1080 / naturalSize.height))
        let size = CGSize(width: max(2, floor(naturalSize.width * ratio / 2) * 2),
                          height: max(2, floor(naturalSize.height * ratio / 2) * 2))
        let context = CIContext(options: [.cacheIntermediates: false])
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let frame = path.frame(at: request.compositionTime.seconds)
            let extent = request.sourceImage.extent
            let normalized = frame.crop
            // Pointer coordinates use a top-left origin; Core Image uses bottom-left.
            let crop = CGRect(x: extent.minX + normalized.minX * extent.width,
                              y: extent.minY + (1 - normalized.maxY) * extent.height,
                              width: normalized.width * extent.width,
                              height: normalized.height * extent.height)
            let image = request.sourceImage.clampedToExtent().cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
                .cropped(to: CGRect(origin: .zero, size: size))
            request.finish(with: image, context: context)
        }
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: 60)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw RecorderError.message("The MP4 exporter is unavailable.")
        }
        let stem = "export-\(settings.mode.rawValue)-\(UUID().uuidString.prefix(8))"
        let output = session.directory.appendingPathComponent(stem + ".mp4")
        let temporary = session.directory.appendingPathComponent(".\(stem).partial.mp4")
        exporter.outputURL = temporary; exporter.outputFileType = .mp4
        exporter.videoComposition = composition; exporter.shouldOptimizeForNetworkUse = true
        active = exporter
        defer { active = nil; try? FileManager.default.removeItem(at: temporary) }
        await exporter.export()
        if exporter.status == .cancelled { throw CancellationError() }
        guard exporter.status == .completed else {
            throw exporter.error ?? RecorderError.message("The export did not finish. The original recording is safe.")
        }
        try FileManager.default.moveItem(at: temporary, to: output)
        try RecordingSession.writeJSON(settings.sanitized, to: session.directory.appendingPathComponent(stem + ".json"))
        return output
    }
}
