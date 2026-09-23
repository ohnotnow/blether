import Synchronization
import XCTest
@testable import Blether

/// What the provider reads from Settings, changeable mid-test from any thread.
private final class DesignsBox: Sendable {
    private let value = Mutex<[VoiceDesign]>(VoiceDesign.defaults)
    func set(designs: [VoiceDesign]) { value.withLock { $0 = designs } }
    var read: @Sendable () -> [VoiceDesign] { { self.value.withLock { $0 } } }
}

/// Drives BreezeProvider with the fake helper, so no uv or Breeze is needed here.
final class BreezeProviderTests: XCTestCase {
    private let box = DesignsBox()
    private var provider: BreezeProvider!

    private func makeProvider(executable: String = "/usr/bin/python3") throws -> BreezeProvider {
        BreezeProvider(
            executable: URL(filePath: executable),
            arguments: [try HelperProcessTests.fakeScript().path],
            settings: box.read,
            requestTimeout: .seconds(5)
        ) { _ in }
    }

    override func tearDown() {
        provider?.stop()
    }

    private func sent(_ key: String, for clip: AudioClip) throws -> String {
        try String(contentsOfFile: clip.url.path + "." + key, encoding: .utf8)
    }

    private func remove(_ clip: AudioClip) {
        for ext in ["", ".instruct", ".cfg"] { try? FileManager.default.removeItem(atPath: clip.url.path + ext) }
    }

    func testVoicesAreTheDesignsAndDoNotStartTheHelper() async throws {
        provider = try makeProvider(executable: "/nonexistent/python3")
        let voices = try await provider.voices()
        XCTAssertEqual(voices.map(\.id), ["servalan", "marvin", "danish-detective", "the-guide"])
        XCTAssertEqual(voices.map(\.name), ["Servalan", "Marvin", "Danish Detective", "The Guide"])
    }

    func testSynthesiseStartsTheHelperAndSendsTheDesignAndQuality() async throws {
        provider = try makeProvider()
        let clip = try await provider.synthesise("Hello", voice: "marvin", language: "French", tone: .sarcasm)
        defer { remove(clip) }
        XCTAssertEqual(try sent("instruct", for: clip), VoiceDesign.marvin.description)
        XCTAssertEqual(try sent("cfg", for: clip), "4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.url.path + ".lang"), "Breeze sends no language")
    }

    func testEditsInSettingsReachTheNextClip() async throws {
        provider = try makeProvider()
        let first = try await provider.synthesise("One", voice: "servalan", language: nil, tone: nil)
        defer { remove(first) }
        box.set(designs: [VoiceDesign(id: "servalan", name: "Servalan", description: "Deeper still.", quality: .faster)])
        let second = try await provider.synthesise("Two", voice: "servalan", language: nil, tone: nil)
        defer { remove(second) }
        XCTAssertEqual(try sent("instruct", for: second), "Deeper still.")
        XCTAssertEqual(try sent("cfg", for: second), "1")
    }

    func testEachDesignSendsItsOwnQuality() async throws {
        box.set(designs: [VoiceDesign(id: "quick", name: "Quick", description: "Brisk.", quality: .faster), VoiceDesign.marvin])
        provider = try makeProvider()
        let quick = try await provider.synthesise("One", voice: "quick", language: nil, tone: nil)
        defer { remove(quick) }
        let marvin = try await provider.synthesise("Two", voice: "marvin", language: nil, tone: nil)
        defer { remove(marvin) }
        XCTAssertEqual(try sent("cfg", for: quick), "1")
        XCTAssertEqual(try sent("cfg", for: marvin), "4")
    }

    func testAnUnknownDesignSpeaksAsTheFirst() async throws {
        provider = try makeProvider()
        let clip = try await provider.synthesise("Hello", voice: "deleted-one", language: nil, tone: nil)
        defer { remove(clip) }
        XCTAssertEqual(try sent("instruct", for: clip), VoiceDesign.servalan.description)
    }

    func testNoDesignsAtAllThrows() async throws {
        box.set(designs: [])
        provider = try makeProvider()
        do {
            _ = try await provider.synthesise("Hello", voice: "servalan", language: nil, tone: nil)
            XCTFail("expected a throw")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .other("no Breeze voice designs"))
        }
    }

    func testProviderCapIsEightHundredAndItIsNamed() throws {
        let provider = try makeProvider()
        XCTAssertEqual(provider.maxMainCharacters, 800)
        XCTAssertEqual(provider.name, "breeze")
        XCTAssertEqual(ProviderRegistry.displayName(id: "breeze"), "Breeze")
    }
}
