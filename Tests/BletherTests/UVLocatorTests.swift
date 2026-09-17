import XCTest
@testable import Blether

final class UVLocatorTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blether-uv-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func file(_ name: String, executable: Bool) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    func testExecutableOverrideWins() throws {
        let override = try file("mine", executable: true)
        let candidate = try file("uv", executable: true)
        XCTAssertEqual(UVLocator.find(override: override.path, candidates: [candidate])?.path, override.path)
    }

    func testEmptyOrNonExecutableOverrideFallsThrough() throws {
        let dud = try file("dud", executable: false)
        let candidate = try file("uv", executable: true)
        XCTAssertEqual(UVLocator.find(override: "", candidates: [candidate])?.path, candidate.path)
        XCTAssertEqual(UVLocator.find(override: dud.path, candidates: [candidate])?.path, candidate.path)
    }

    func testNothingExecutableReturnsNil() throws {
        let dud = try file("uv", executable: false)
        XCTAssertNil(UVLocator.find(override: nil, candidates: [dud, dir.appendingPathComponent("missing")]))
    }
}
