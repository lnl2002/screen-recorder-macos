import Foundation
import CoreGraphics

public struct CameraFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let zoom: Double
    public init(x: Double, y: Double, zoom: Double) { self.x = x; self.y = y; self.zoom = zoom }
    public var crop: CGRect {
        CGRect(x: x - 0.5 / zoom, y: y - 0.5 / zoom, width: 1 / zoom, height: 1 / zoom)
    }
}

/// Immutable fixed-step path. Crop position and zoom are independent; the final crop
/// is expressed inside its legal travel range, so edge clamping never resets velocity.
public struct CameraPath: Sendable {
    private let frames: [CameraFrame]
    private let hz = 120.0
    private struct Point { var x: Double; var y: Double; var inside: Bool }
    private struct Window { var start: Double; var end: Double; let click: PointerSample }

    public init(samples: [PointerSample], duration: Double, settings: CameraSettings) {
        let s = settings.sanitized
        let samples = samples.filter { $0.time.isFinite && $0.time >= 0 && $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.time < $1.time }
        let duration = finiteClamp(duration, 0, 86400, fallback: 0)
        let count = Int(ceil(duration * 120)) + 1
        let dt = 1.0 / 120
        var windows: [Window] = []
        var previousButtons: UInt64 = 0
        for p in samples {
            if p.buttons & ~previousButtons != 0 && p.inside {
                let start = max(0, p.time - s.lead), end = p.time + s.hold
                if let last = windows.last, start <= last.end + 0.8 {
                    windows[windows.count - 1].end = max(last.end, end)
                } else { windows.append(Window(start: start, end: end, click: p)) }
            }
            previousButtons = p.buttons
        }
        // Interpolate uneven samples, then smooth forward/backward to remove small
        // pointer jitter without introducing the lag of a one-way filter.
        var points = [Point](repeating: Point(x: 0.5, y: 0.5, inside: false), count: count)
        var index = 0
        for i in 0..<count where !samples.isEmpty {
            let time = Double(i) * dt
            while index + 1 < samples.count && samples[index + 1].time <= time { index += 1 }
            let a = samples[index]
            guard a.time <= time else { continue }
            var x = a.x, y = a.y
            if index + 1 < samples.count {
                let b = samples[index + 1], gap = b.time - a.time
                // Never invent a path across an absent interval or a monitor boundary.
                if a.inside && b.inside && gap > 0 && gap < 0.1 {
                    let f = min(1, max(0, (time - a.time) / gap))
                    x += (b.x - x) * f; y += (b.y - y) * f
                }
            }
            points[i] = Point(x: min(1, max(0, x)), y: min(1, max(0, y)), inside: a.inside)
        }
        let alpha = 1 - exp(-dt / 0.06)
        if count > 1 {
            for i in 1..<count where points[i].inside && points[i - 1].inside {
                points[i].x = points[i - 1].x + alpha * (points[i].x - points[i - 1].x)
                points[i].y = points[i - 1].y + alpha * (points[i].y - points[i - 1].y)
            }
            for i in stride(from: count - 2, through: 0, by: -1) where points[i].inside && points[i + 1].inside {
                points[i].x = points[i + 1].x + alpha * (points[i].x - points[i + 1].x)
                points[i].y = points[i + 1].y + alpha * (points[i].y - points[i + 1].y)
            }
        }
        var output: [CameraFrame] = []; output.reserveCapacity(count)
        var windowIndex = 0
        var panX = 0.5, panY = 0.5, z = 1.0, vx = 0.0, vy = 0.0, vz = 0.0
        var focusX = 0.5, focusY = 0.5
        let omega = 4.6 / s.response, panOmega = omega / 1.25
        let leadFrames = Int(min(0.18, s.response * 0.2) * 120)
        let halfAtZoom = 0.5 / s.zoom, travelAtZoom = 1 - 1 / s.zoom
        for i in 0..<count {
            let time = Double(i) * dt
            while windowIndex < windows.count && windows[windowIndex].end < time { windowIndex += 1 }
            let window = windowIndex < windows.count ? windows[windowIndex] : nil
            let active = s.mode == .follow || (s.mode == .auto && window.map { $0.start <= time } == true)
            let preparing = s.mode == .auto && window.map { time >= $0.start - s.response && time < $0.click.time } == true
            if preparing, let click = window?.click {
                // Aim at the impending click while still at overview, instead of
                // zooming toward the old cursor position and chasing it afterward.
                focusX = click.x; focusY = click.y
            } else if active {
                let p = points[min(count - 1, i + leadFrames)]
                if p.inside {
                    let dead = s.deadZone / s.zoom
                    if abs(p.x - focusX) > dead { focusX = p.x - copysign(dead, p.x - focusX) }
                    if abs(p.y - focusY) > dead { focusY = p.y - copysign(dead, p.y - focusY) }
                }
            }
            let tx = travelAtZoom > 0 ? min(1, max(0, (focusX - halfAtZoom) / travelAtZoom)) : 0.5
            let ty = travelAtZoom > 0 ? min(1, max(0, (focusY - halfAtZoom) / travelAtZoom)) : 0.5
            Self.step(&panX, &vx, target: tx, omega: panOmega, dt: dt)
            Self.step(&panY, &vy, target: ty, omega: panOmega, dt: dt)
            Self.step(&z, &vz, target: active ? s.zoom : 1, omega: omega, dt: dt)
            z = min(s.zoom, max(1, z))
            let half = 0.5 / z, travel = 1 - 1 / z
            output.append(CameraFrame(x: half + travel * min(1, max(0, panX)),
                                      y: half + travel * min(1, max(0, panY)), zoom: z))
        }
        frames = output
    }

    public func frame(at time: Double) -> CameraFrame {
        let safeTime = time.isFinite ? max(0, time) : 0
        let pos = min(Double(frames.count - 1), safeTime * hz)
        let i = Int(pos), j = min(i + 1, frames.count - 1), f = pos - Double(i)
        let a = frames[i], b = frames[j]
        let z = a.zoom + (b.zoom - a.zoom) * f, half = 0.5 / z
        return CameraFrame(x: min(1 - half, max(half, a.x + (b.x - a.x) * f)),
                           y: min(1 - half, max(half, a.y + (b.y - a.y) * f)), zoom: z)
    }

    private static func step(_ value: inout Double, _ velocity: inout Double, target: Double, omega: Double, dt: Double) {
        let delta = value - target, c = velocity + omega * delta, decay = exp(-omega * dt)
        value = target + (delta + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
    }
}
