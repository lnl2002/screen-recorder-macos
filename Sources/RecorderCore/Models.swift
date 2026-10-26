import Foundation

public enum ZoomMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, follow, off
    public var id: String { rawValue }
    public var title: String {
        switch self { case .auto: return "Auto zoom"; case .follow: return "Follow mouse"; case .off: return "Full screen" }
    }
}

public struct CameraSettings: Codable, Equatable, Sendable {
    public var mode: ZoomMode = .auto
    public var zoom: Double = 1.8
    public var response: Double = 0.45
    public var hold: Double = 1.5
    public var lead: Double = 0.25
    public var deadZone: Double = 0.15
    public init() {}
    public var sanitized: Self {
        var s = self
        s.zoom = finiteClamp(zoom, 1, 3, fallback: 1.8)
        s.response = finiteClamp(response, 0.15, 1.2, fallback: 0.45)
        s.hold = finiteClamp(hold, 0.3, 5, fallback: 1.5)
        s.lead = finiteClamp(lead, 0, 1, fallback: 0.25)
        s.deadZone = finiteClamp(deadZone, 0, 0.4, fallback: 0.15)
        return s
    }
}

public struct PointerSample: Codable, Sendable {
    public let time: Double
    public let x: Double
    public let y: Double // normalized, top-left origin
    public let buttons: UInt64
    public let inside: Bool
    public init(time: Double, x: Double, y: Double, buttons: UInt64 = 0, inside: Bool = true) {
        self.time = time; self.x = x; self.y = y; self.buttons = buttons; self.inside = inside
    }
}

public struct SessionManifest: Codable, Sendable {
    public var version = 1
    public var createdAt = Date()
    public var width: Int
    public var height: Int
    public var fps: Int
    public var duration: Double
    public var displayID: UInt32
    public var captureBounds: [Double]
    public var hostEpoch: Double
    public var systemAudio: Bool
    public var videoFrames: Int
    public var droppedVideoFrames: Int
    public var droppedAudioBuffers: Int
    public var settings: CameraSettings
    public init(width: Int, height: Int, fps: Int, duration: Double, displayID: UInt32,
                captureBounds: [Double], hostEpoch: Double, systemAudio: Bool,
                videoFrames: Int, droppedVideoFrames: Int, droppedAudioBuffers: Int,
                settings: CameraSettings) {
        self.width = width; self.height = height; self.fps = fps; self.duration = duration
        self.displayID = displayID; self.captureBounds = captureBounds; self.hostEpoch = hostEpoch
        self.systemAudio = systemAudio; self.videoFrames = videoFrames
        self.droppedVideoFrames = droppedVideoFrames; self.droppedAudioBuffers = droppedAudioBuffers
        self.settings = settings
    }
}

public func finiteClamp(_ value: Double, _ lower: Double, _ upper: Double, fallback: Double) -> Double {
    value.isFinite ? min(upper, max(lower, value)) : fallback
}
