import AppKit
import SwiftUI

/// The Restart button: a fresh copy of this bundle, then quit. The new instance is asked for
/// explicitly (createsNewApplicationInstance), since `open` on a running bundle only activates it.
/// The new one is launched first and quits us from its completion. The new instance binds 8765 and
/// 8766 at launch, so if it ever comes up before this process has let go of them it will show a bind
/// error in its menu; if that is seen, terminate first and launch through a detached `open -n`.
enum Relaunch {
    @MainActor
    static func now() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { Log.log("restart failed: \(error)") }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

/// The row a "takes effect after a restart" footnote points at.
struct RestartButton: View {
    var body: some View {
        Button("Restart blether") { Relaunch.now() }
    }
}
