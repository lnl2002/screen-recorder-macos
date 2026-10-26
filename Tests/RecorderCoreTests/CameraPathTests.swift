import Foundation
import RecorderCore

final class CameraPathTests {
    func testOffNeverMoves() {
        var settings = CameraSettings(); settings.mode = .off
        let path = CameraPath(samples: [PointerSample(time: 0, x: 0, y: 1, buttons: 1)], duration: 3, settings: settings)
        for t in stride(from: 0.0, through: 3, by: 0.013) {
            expectEqual(path.frame(at: t), CameraFrame(x: 0.5, y: 0.5, zoom: 1))
        }
    }

    func testEdgesAndFastTravelNeverRevealOutsideSource() {
        var settings = CameraSettings(); settings.mode = .follow; settings.zoom = 3; settings.response = 0.15
        let samples: [PointerSample] = (0..<20).map { index in
            let x: Double = index % 2 == 0 ? 0 : 1
            let y: Double = index % 3 == 0 ? 1 : 0
            return PointerSample(time: Double(index) / 4.0, x: x, y: y)
        }
        let path = CameraPath(samples: samples, duration: 5, settings: settings)
        for t in stride(from: 0.0, through: 5, by: 0.007) {
            let crop = path.frame(at: t).crop
            expectAtLeast(crop.minX, -1e-10); expectAtLeast(crop.minY, -1e-10)
            expectAtMost(crop.maxX, 1 + 1e-10); expectAtMost(crop.maxY, 1 + 1e-10)
        }
    }

    func testAutoLeadsClickAndReturnsToOverview() {
        let samples = [PointerSample(time: 0, x: 0.7, y: 0.3), PointerSample(time: 1, x: 0.7, y: 0.3, buttons: 1),
                       PointerSample(time: 1.1, x: 0.7, y: 0.3)]
        let path = CameraPath(samples: samples, duration: 5, settings: CameraSettings())
        expectEqual(path.frame(at: 0.5).zoom, 1)
        expectGreater(path.frame(at: 0.95).zoom, 1.1)
        expectGreater(path.frame(at: 2).zoom, 1.7)
        expectEqual(path.frame(at: 5).zoom, 1, accuracy: 0.001)
    }

    func testOutOfBoundsClickDoesNotTriggerZoom() {
        let samples = [PointerSample(time: 1, x: 2, y: 0.5, buttons: 1, inside: false)]
        let path = CameraPath(samples: samples, duration: 3, settings: CameraSettings())
        expectEqual(path.frame(at: 2).zoom, 1)
    }

    func testSamplingIsIndependentOfRenderOrder() {
        var settings = CameraSettings(); settings.mode = .follow
        let samples = [PointerSample(time: 0, x: 0.9, y: 0.1)]
        let first = CameraPath(samples: samples, duration: 3, settings: settings)
        let second = CameraPath(samples: samples, duration: 3, settings: settings)
        let end = first.frame(at: 2.8)
        _ = first.frame(at: 0.1)
        expectEqual(end, first.frame(at: 2.8)); expectEqual(end, second.frame(at: 2.8))
    }

    func testEmptyAndInvalidInputIsSafe() {
        var settings = CameraSettings(); settings.zoom = .nan; settings.response = -.infinity
        let path = CameraPath(samples: [PointerSample(time: .nan, x: 1, y: 1)], duration: 0, settings: settings)
        expectEqual(path.frame(at: .infinity), CameraFrame(x: 0.5, y: 0.5, zoom: 1))
    }
}


private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "Expected \(a) == \(b)", file: file, line: line)
}
private func expectEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(a - b) <= accuracy, "Expected \(a) ≈ \(b)", file: file, line: line)
}
private func expectAtLeast(_ a: Double, _ b: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(a >= b, "Expected \(a) >= \(b)", file: file, line: line)
}
private func expectAtMost(_ a: Double, _ b: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(a <= b, "Expected \(a) <= \(b)", file: file, line: line)
}
private func expectGreater(_ a: Double, _ b: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(a > b, "Expected \(a) > \(b)", file: file, line: line)
}

@main struct CameraTestRunner {
    static func main() {
        let tests = CameraPathTests()
        tests.testOffNeverMoves()
        tests.testEdgesAndFastTravelNeverRevealOutsideSource()
        tests.testAutoLeadsClickAndReturnsToOverview()
        tests.testOutOfBoundsClickDoesNotTriggerZoom()
        tests.testSamplingIsIndependentOfRenderOrder()
        tests.testEmptyAndInvalidInputIsSafe()
        print("PASS: 6 camera planning tests (including per-frame boundary checks).")
    }
}
