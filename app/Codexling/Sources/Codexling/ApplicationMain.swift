import AppKit

@main
enum CodexlingMain {
    // NSApplication.delegate is weak; keep a strong reference for app lifetime.
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
