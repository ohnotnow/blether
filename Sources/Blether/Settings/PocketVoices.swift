import Foundation

/// The Pocket voices a person added themselves: one saved state per `.safetensors` file, named by
/// the file. Helpers/pocket.py lists them after the bundled ones; an added voice with a bundled or
/// catalogue voice's id takes its place (blether-xhLum).
struct PocketVoices {
    /// ~/Library/Application Support/blether/pocket-voices, beside the samples and the speech model.
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("blether/pocket-voices", isDirectory: true)

    let directory: URL

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// The same rule as pocket.py and training/pocket_clone.py: lower case, runs of anything else become one hyphen.
    static func id(for name: String) -> String {
        name.lowercased()
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .joined(separator: "-")
    }

    /// How pocket.py names a voice in the pickers.
    static func displayName(id: String) -> String {
        id.split(separator: "-").map(\.capitalized).joined(separator: " ")
    }

    /// Ids, sorted. None when the folder does not exist yet.
    var ids: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "safetensors" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// Copies `file` in under `name`, replacing a voice of the same id. Returns the id.
    @discardableResult
    func add(_ file: URL, name: String) throws -> String {
        let id = Self.id(for: name)
        guard !id.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: id)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: file, to: destination)
        return id
    }

    func remove(id: String) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    /// When the file last changed, or nil for a voice that is not an added one. The sample cache keys on
    /// it, so replacing a voice under the same name plays a fresh sample.
    func stamp(id: String) -> String? {
        let date = (try? FileManager.default.attributesOfItem(atPath: url(for: id).path))?[.modificationDate] as? Date
        return date.map { String($0.timeIntervalSince1970) }
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("safetensors")
    }
}
