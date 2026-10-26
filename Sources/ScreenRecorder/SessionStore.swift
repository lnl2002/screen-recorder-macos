import Foundation
import RecorderCore

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct RecordingSession {
    let directory: URL
    let manifest: SessionManifest
    var source: URL { directory.appendingPathComponent("screen.mov") }
    var pointerFile: URL { directory.appendingPathComponent("pointer.jsonl") }

    static var root: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screen Recorder", isDirectory: true)
    }

    static func createDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = root.appendingPathComponent("\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func open(_ directory: URL) throws -> Self {
        let manifest = try JSONDecoder().decode(SessionManifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.version == 1, manifest.width > 0, manifest.height > 0,
              manifest.duration.isFinite, manifest.duration > 0, manifest.duration <= 86400 else {
            throw RecorderError.message("This recording has an unsupported or invalid manifest.")
        }
        let session = Self(directory: directory, manifest: manifest)
        guard FileManager.default.fileExists(atPath: session.source.path) else {
            throw RecorderError.message("The original screen.mov is missing from this session.")
        }
        return session
    }

    func loadPointer() throws -> [PointerSample] {
        let data = try Data(contentsOf: pointerFile)
        let decoder = JSONDecoder()
        return try data.split(separator: 10).map { try decoder.decode(PointerSample.self, from: Data($0)) }
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
