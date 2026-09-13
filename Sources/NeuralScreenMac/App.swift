import AppKit
import SwiftUI
import CoreFoundation

@main
struct DLSSApplication {
    @MainActor static func main() {
        // Keep AppKit panels and framework messages in the app's only language.
        // This preference is scoped to this application, not to macOS.
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        if CommandLine.arguments.contains("--video-test") || CommandLine.arguments.contains("--process-video") || CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--benchmark") || CommandLine.arguments.contains("--capture-test") || CommandLine.arguments.contains("--ui-snapshot") {
            Task {
                do { try await Diagnostics.run(); exit(0) }
                catch { fputs("ERROR: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            CFRunLoopRun()
            return
        }
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}
