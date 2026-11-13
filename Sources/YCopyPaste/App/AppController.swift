import AppKit
import Combine
import SwiftUI

/// Связывает все части приложения.
@MainActor
final class AppController {
    let store: HistoryStore
    private(set) var monitor: ClipboardMonitor!
    private(set) var popup: PopupController!
    private(set) var cycle: CycleController!
    private var statusBar: StatusBarController!
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    /// Последнее активное приложение, кроме нашего — туда и вставляем.
    private var lastExternalApp: NSRunningApplication?

    private enum HotKeyID: UInt32 { case popup = 1, cycle = 2 }

    init(store: HistoryStore) {
        self.store = store
        monitor = ClipboardMonitor { [weak self] clip in self?.store.add(clip) }
        popup = PopupController(store: store,
                                onPick: { [weak self] item, mode in self?.paste(item, mode: mode) },
                                onOpenSettings: { [weak self] in self?.openSettings() })
        cycle = CycleController(store: store) { [weak self] item in self?.paste(item, mode: .normal) }
        statusBar = StatusBarController(app: self)
    }

    func start() {
        monitor.start()
        trackFrontmostApp()

        let prefs = Preferences.shared
        prefs.$popupHotKey.combineLatest(prefs.$cycleHotKey)
            .sink { [weak self] popupCombo, cycleCombo in
                self?.registerHotKeys(popup: popupCombo, cycle: cycleCombo)
            }
            .store(in: &bag)

        prefs.$maxItems.combineLatest(prefs.$maxDays)
            .dropFirst()
            .sink { [weak self] _, _ in
                Task { @MainActor in self?.store.prune() }
            }
            .store(in: &bag)

        if !prefs.onboardingDone {
            prefs.onboardingDone = true
            showWelcome()
        }
    }

    private func registerHotKeys(popup popupCombo: KeyCombo, cycle cycleCombo: KeyCombo) {
        let hk = HotKeyManager.shared
        hk.register(id: HotKeyID.popup.rawValue, combo: popupCombo) { [weak self] in
            self?.popup.toggle()
        }
        hk.register(id: HotKeyID.cycle.rawValue, combo: cycleCombo) { [weak self] in
            self?.cycle.hotKeyPressed(cycleCombo)
        }
    }

    private func trackFrontmostApp() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.processIdentifier != ownPID }
            .sink { [weak self] app in self?.lastExternalApp = app }
            .store(in: &bag)
    }

    // MARK: - Вставка

    func paste(_ item: ClipItem, mode: PasteMode) {
        let prefs = Preferences.shared
        var plain = false
        switch mode {
        case .plain: plain = !prefs.plainByDefault
        case .normal, .copyOnly: plain = prefs.plainByDefault
        }
        Paster.write(item, payload: store.payload(for: item.id), plain: plain)
        monitor.skipCurrent()
        if prefs.moveToTopOnPaste { store.touch(item.id) }

        guard mode != .copyOnly, prefs.autoPaste else { return }
        guard Accessibility.isTrusted else {
            Accessibility.prompt()
            return
        }
        if NSApp.isActive {
            // Наше окно (например, настройки) было активным — вернём фокус.
            lastExternalApp?.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.postCommandV()
        }
    }

    // MARK: - Действия

    func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(app: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Настройки YCopyPaste"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func confirmClearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Очистить историю?"
        alert.informativeText = "Будут удалены все элементы, кроме закреплённых. Это нельзя отменить."
        alert.addButton(withTitle: "Очистить")
        alert.addButton(withTitle: "Отмена")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: true)
        }
    }

    func requestAccessibility() {
        if !Accessibility.prompt() {
            Accessibility.openSettings()
        }
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "YCopyPaste запущен"
        alert.informativeText = """
        Иконка приложения — в строке меню вверху экрана.

        • \(Preferences.shared.popupHotKey.displayString) — открыть историю буфера
        • \(Preferences.shared.cycleHotKey.displayString) — листать историю: держите ⌃⌘ и нажимайте V, отпустите клавиши, и элемент вставится

        Чтобы выбранный элемент вставлялся сам, разрешите YCopyPaste «Универсальный доступ» \
        (Системные настройки → Конфиденциальность и безопасность → Универсальный доступ).
        """
        alert.addButton(withTitle: "Разрешить доступ")
        alert.addButton(withTitle: "Позже")
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibility()
        }
    }
}
