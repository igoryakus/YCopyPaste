import AppKit

@main
enum YCopyPasteMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try HistoryStore()
            let controller = AppController(store: store)
            controller.start()
            self.controller = controller
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть историю"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Повторный запуск из Finder/Launchpad открывает настройки.
        controller?.openSettings()
        return true
    }
}
