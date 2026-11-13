import AppKit
import Combine

/// Иконка в строке меню и её меню.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private unowned let app: AppController
    private var bag = Set<AnyCancellable>()

    init(app: AppController) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        Preferences.shared.$isPaused
            .sink { [weak self] paused in self?.updateIcon(paused: paused) }
            .store(in: &bag)
    }

    private func updateIcon(paused: Bool) {
        let name = paused ? "pause.circle" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "YCopyPaste")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = paused ? "YCopyPaste — запись приостановлена" : "YCopyPaste"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = Preferences.shared

        add("Открыть историю  \(prefs.popupHotKey.displayString)", #selector(openHistory))

        let recent = app.store.items.prefix(max(0, prefs.menuRecentCount))
        if !recent.isEmpty {
            menu.addItem(.separator())
            for (i, item) in recent.enumerated() {
                var title = item.displayTitle
                if title.count > 60 { title = String(title.prefix(60)) + "…" }
                let mi = NSMenuItem(title: title, action: #selector(pasteRecent(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
                mi.keyEquivalentModifierMask = []
                mi.target = self
                mi.representedObject = NSNumber(value: item.id)
                mi.image = NSImage(systemSymbolName: item.pinned ? "pin" : item.kind.symbolName, accessibilityDescription: nil)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let pause = add(prefs.isPaused ? "Возобновить запись" : "Приостановить запись", #selector(togglePause))
        pause.state = prefs.isPaused ? .on : .off
        add("Очистить историю…", #selector(clearHistory))
        menu.addItem(.separator())
        if !Accessibility.isTrusted {
            add("⚠︎ Разрешить автовставку…", #selector(grantAccessibility))
        }
        add("Настройки…", #selector(openSettings), key: ",")
        add("Выйти из YCopyPaste", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    @objc private func openHistory() {
        // Даём меню закрыться, иначе панель сразу потеряет фокус.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.app.popup.show()
        }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.int64Value,
              let item = app.store.items.first(where: { $0.id == id }) else { return }
        app.paste(item, mode: .normal)
    }

    @objc private func togglePause() { Preferences.shared.isPaused.toggle() }
    @objc private func clearHistory() { app.confirmClearHistory() }
    @objc private func grantAccessibility() { app.requestAccessibility() }
    @objc private func openSettings() { app.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
