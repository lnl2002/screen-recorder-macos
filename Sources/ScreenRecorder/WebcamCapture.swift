import AVFoundation

@MainActor
final class WebcamCapture: NSObject, AVCaptureFileOutputRecordingDelegate {
    private(set) var session: AVCaptureSession?
    private var output: AVCaptureMovieFileOutput?
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private(set) var startedAt: Double = 0

    func start(to url: URL) async throws {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized else { throw RecorderError.message("Allow Camera access in System Settings to record your face.") }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw RecorderError.message("No camera is available.")
        }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureMovieFileOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.message("The camera could not be configured.")
        }
        session.addInput(input); session.addOutput(output)
        self.session = session; self.output = output
        await Task.detached { session.startRunning() }.value
        startedAt = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stop() async {
        guard let output, output.isRecording else { stopSession(); return }
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
            output.stopRecording()
        }
        stopSession()
    }

    func abort() {
        if output?.isRecording == true { output?.stopRecording() }
        stopSession()
    }

    private func stopSession() {
        let old = session
        session = nil; output = nil
        Task.detached { old?.stopRunning() }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.stopContinuation?.resume()
            self.stopContinuation = nil
        }
    }
}
