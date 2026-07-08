import AppKit

@main
enum CodexLightMain {
    // NSApplication.delegate is weak; keep a strong reference for app lifetime.
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let delegate = AppDelegate()
        appDelegate = delegate
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
