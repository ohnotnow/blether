import Foundation

enum ModelStoreError: Error, Equatable {
    case badStatus(Int)
    case wrongSize(got: Int, expected: Int)
}

/// Where the speech-to-text model lives and how it gets there. One file, fetched on the first listen,
/// checked by size on every start so a half-written download is never trusted.
struct ModelStore: Sendable {
    /// canary-180m-flash, Q8_0, as published by the transcribe.cpp authors. Size and URL checked 2026-09-19.
    static let url = URL(string: "https://huggingface.co/handy-computer/canary-180m-flash-gguf/resolve/main/canary-180m-flash-Q8_0.gguf")!
    static let expectedSize = 218_447_552
    static let fileName = "canary-180m-flash-Q8_0.gguf"

    let directory: URL
    let session: URLSession
    /// Injectable so tests download a few kilobytes, not 218 MB.
    let size: Int

    /// ~/Library/Application Support/blether/models by default.
    init(directory: URL? = nil, session: URLSession = .shared, size: Int = ModelStore.expectedSize) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("blether/models", isDirectory: true)
        self.session = session
        self.size = size
    }

    var modelURL: URL { directory.appendingPathComponent(Self.fileName) }

    var isPresent: Bool {
        (try? FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? Int) == size
    }

    /// Returns the model's path, downloading it first if it is missing or the wrong size. `progress`
    /// gets one human line when the download starts; URLSession writes the file itself, so there is no
    /// percentage (a per-byte loop for one cost seconds of CPU and made the test suite four times slower).
    func ensureModel(progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        if isPresent { return modelURL }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        progress("Downloading the ears (\(size / 1_000_000) MB)")
        let (downloaded, response) = try await session.download(from: Self.url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: downloaded)
            throw ModelStoreError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let got = (try? FileManager.default.attributesOfItem(atPath: downloaded.path)[.size] as? Int) ?? 0
        guard got == size else {
            try? FileManager.default.removeItem(at: downloaded)
            throw ModelStoreError.wrongSize(got: got, expected: size)
        }
        try? FileManager.default.removeItem(at: modelURL)
        try FileManager.default.moveItem(at: downloaded, to: modelURL)
        Log.log("ears: model downloaded to \(modelURL.path)")
        return modelURL
    }
}
