import Foundation
import CoreGraphics

public struct CameraFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let zoom: Double
    public init(x: Double, y: Double, zoom: Double) {
        self.x = x; self.y = y; self.zoom = zoom
    }
    public var crop: CGRect {
        CGRect(x: x - 0.5 / zoom, y: y - 0.5 / zoom, width: 1 / zoom, height: 1 / zoom)
    }
}

/// Immutable, precomputed at 120 Hz: export order cannot change the camera path.
public struct CameraPath: Sendable {
    private let frames: [CameraFrame]
    private let hz = 120.0

    public init(samples: [PointerSample], duration: Double, settings: CameraSettings) {
        let s = settings.sanitized
        let samples = samples.filter { $0.time.isFinite && $0.time >= 0 && $0.x.isFinite && $0.y.isFinite }
            .sorted { $0.time < $1.time }
        let duration = finiteClamp(duration, 0, 86400, fallback: 0)
        let count = Int(ceil(duration * 120)) + 1
        var windows: [(Double, Double)] = []
        var previousButtons: UInt64 = 0
        for p in samples {
            if p.buttons & ~previousButtons != 0 && p.inside {
                let start = max(0, p.time - s.lead)
                let end = p.time + s.hold
                if let last = windows.last, start <= last.1 + 0.8 {
                    windows[windows.count - 1].1 = max(last.1, end)
                } else { windows.append((start, end)) }
            }
            previousButtons = p.buttons
        }
        var output: [CameraFrame] = []
        output.reserveCapacity(count)
        var index = 0, windowIndex = 0
        var x = 0.5, y = 0.5, z = 1.0, vx = 0.0, vy = 0.0, vz = 0.0
        var targetX = 0.5, targetY = 0.5
        let dt = 1.0 / 120
        let omega = 4.6 / s.response
        for i in 0..<count {
            let time = Double(i) * dt
            while index + 1 < samples.count && samples[index + 1].time <= time { index += 1 }
            while windowIndex < windows.count && windows[windowIndex].1 < time { windowIndex += 1 }
            let active = s.mode == .follow || (s.mode == .auto && windowIndex < windows.count && windows[windowIndex].0 <= time)
            let desiredZoom = active ? s.zoom : 1
            if active, !samples.isEmpty, samples[index].time <= time, samples[index].inside {
                let p = samples[index]
                let dead = s.deadZone / desiredZoom
                if abs(p.x - targetX) > dead { targetX = p.x - copysign(dead, p.x - targetX) }
                if abs(p.y - targetY) > dead { targetY = p.y - copysign(dead, p.y - targetY) }
            } else if !active { targetX = 0.5; targetY = 0.5 }
            Self.step(&z, &vz, target: desiredZoom, omega: omega, dt: dt)
            z = min(s.zoom, max(1, z))
            let half = 0.5 / z
            let tx = min(1 - half, max(half, targetX))
            let ty = min(1 - half, max(half, targetY))
            Self.step(&x, &vx, target: tx, omega: omega, dt: dt)
            Self.step(&y, &vy, target: ty, omega: omega, dt: dt)
            let cx = min(1 - half, max(half, x)), cy = min(1 - half, max(half, y))
            if cx != x { vx = 0 }; if cy != y { vy = 0 }
            x = cx; y = cy
            output.append(CameraFrame(x: x, y: y, zoom: z))
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
        // Exact critically damped spring for a constant target over this step.
        let delta = value - target, c = velocity + omega * delta, decay = exp(-omega * dt)
        value = target + (delta + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
    }
}
