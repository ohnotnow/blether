import Foundation

enum AppRuntime {
    /// True when the app is launched as the host for the XCTest bundle.
    /// Used to keep the app body inert during `make test`.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
