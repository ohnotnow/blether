import XCTest
@testable import Blether

final class ModelStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ModelStore!
    private let expected = 3_000_000

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("blether-models-\(UUID().uuidString)")
        store = ModelStore(directory: directory, session: URLProtocolStub.makeSession(), size: expected)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        try? FileManager.default.removeItem(at: directory)
    }

    private func serve(_ data: Data, status: Int = 200) -> Requests {
        let requests = Requests()
        URLProtocolStub.install { request in
            requests.record(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        return requests
    }

    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func record(_ request: URLRequest) { lock.withLock { urls.append(request.url!) } }
        var count: Int { lock.withLock { urls.count } }
    }

    func testPresentFileOfTheRightSizeIsReturnedWithoutARequest() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: store.modelURL.path, contents: Data(count: expected))
        let requests = serve(Data())
        let url = try await store.ensureModel { _ in XCTFail("no progress expected") }
        XCTAssertEqual(url, store.modelURL)
        XCTAssertEqual(requests.count, 0)
        XCTAssertTrue(store.isPresent)
    }

    func testMissingFileIsDownloadedWithProgressAndLandsAtThePath() async throws {
        let requests = serve(Data(repeating: 7, count: expected))
        let lines = Lines()
        let url = try await store.ensureModel { lines.add($0) }
        XCTAssertEqual(url, store.modelURL)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, expected)
        XCTAssertEqual(lines.all, ["Downloading the ears (3 MB)"])
    }

    func testWrongSizeDownloadThrowsAndLeavesNoFile() async throws {
        _ = serve(Data(repeating: 7, count: 1000))
        do {
            _ = try await store.ensureModel { _ in }
            XCTFail("expected a size error")
        } catch let error as ModelStoreError {
            XCTAssertEqual(error, .wrongSize(got: 1000, expected: expected))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelURL.path))
    }

    func testBadStatusThrows() async {
        _ = serve(Data(), status: 503)
        do {
            _ = try await store.ensureModel { _ in }
            XCTFail("expected a status error")
        } catch let error as ModelStoreError {
            XCTAssertEqual(error, .badStatus(503))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAFileOfTheWrongSizeCountsAsMissing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: store.modelURL.path, contents: Data(count: 10))
        XCTAssertFalse(store.isPresent)
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var _all: [String] = []
        func add(_ line: String) { lock.withLock { _all.append(line) } }
        var all: [String] { lock.withLock { _all } }
    }
}
