import XCTest
@testable import Blether

final class MicrophoneTests: XCTestCase {
    private let builtIn = AudioInputDevice(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    private let headset = AudioInputDevice(id: "USB-1234", name: "Headset")

    func testNilOrEmptyIDMeansSystemDefault() {
        XCTAssertEqual(Microphone.resolve(deviceID: nil, in: [builtIn]), .systemDefault)
        XCTAssertEqual(Microphone.resolve(deviceID: "", in: [builtIn]), .systemDefault)
    }

    func testKnownIDPicksThatDevice() {
        XCTAssertEqual(Microphone.resolve(deviceID: "USB-1234", in: [builtIn, headset]), .device(headset))
    }

    func testUnknownIDFallsBackToDefaultAndSaysWhich() {
        let choice = Microphone.resolve(deviceID: "USB-1234", in: [builtIn])
        XCTAssertEqual(choice, .fallback(missingID: "USB-1234"))
        XCTAssertEqual(Microphone.describe(choice), "microphone USB-1234 not connected, using the system default")
    }

    func testChunkerCarriesRemainderBetweenCalls() {
        var chunker = SampleChunker(size: 4)
        XCTAssertEqual(chunker.append([1, 2, 3]), [])
        XCTAssertEqual(chunker.append([4, 5, 6, 7, 8, 9]), [[1, 2, 3, 4], [5, 6, 7, 8]])
        XCTAssertEqual(chunker.append([10, 11, 12]), [[9, 10, 11, 12]])
    }

    func testDeviceListDoesNotCrashAndHasUniqueIDs() {
        let devices = AudioInputDevice.all()
        XCTAssertEqual(Set(devices.map(\.id)).count, devices.count)
        for device in devices { XCTAssertFalse(device.name.isEmpty) }
    }

    func testUnknownUIDTranslatesToNil() {
        XCTAssertNil(AudioInputDevice.deviceID(forUID: "blether-no-such-device-\(UUID().uuidString)"))
    }
}
