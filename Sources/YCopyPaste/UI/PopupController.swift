import AppKit
import SwiftUI

/// Всплывающее окно истории (⇧⌘V).
@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    let vm: PopupViewModel
    private let panel: KeyablePanel
    private var keyMonitor: Any?
    private var isPositioning = false
    private let onPick: (ClipItem, PasteMode) -> Void
    private let onOpenSettings: () -> Void

    var isVisible: Bool { panel.isVisible }

    init(store: HistoryStore, onPick: @escaping (ClipItem, PasteMode) -> Void, onOpenSettings: @escaping () -> Void) {
        vm = PopupViewModel(store: store)
        self.onPick = onPick
        self.onOpenSettings = onOpenSettings
        panel = KeyablePanel(size: NSSize(width: 780, height: 470))
        super.init()
        panel.delegate = self
        let root = PopupView(vm: vm) { [weak self] item, mode in self?.pick(item, mode) }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 470)
        panel.contentView = hosting
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        vm.prepareForShow()
        isPositioning = true
        panel.position(Preferences.shared.popupPosition)
        isPositioning = false
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Пользователь перетащил окно — запоминаем место.
    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, panel.isVisible else { return }
        Preferences.shared.popupOrigin = panel.frame.origin
        if Preferences.shared.popupPosition != .saved {
            Preferences.shared.popupPosition = .saved
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func pick(_ item: ClipItem, _ mode: PasteMode) {
        hide()
        onPick(item, mode)
    }

    // MARK: - Клавиатура

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Esc
            if !vm.query.isEmpty { vm.query = "" } else { hide() }
            return nil
        case 125: vm.move(1); return nil          // ↓
        case 126: vm.move(-1); return nil         // ↑
        case 121: vm.move(10); return nil         // Page Down
        case 116: vm.move(-10); return nil        // Page Up
        case 48: vm.toggleFilter(); return nil    // Tab
        case 36, 76:                              // Return / Enter
            if let item = vm.selectedItem {
                let mode: PasteMode = flags.contains(.command) ? .copyOnly
                    : (flags.contains(.option) ? .plain : .normal)
                pick(item, mode)
            }
            return nil
        default:
            break
        }

        if flags.contains(.command) {
            if let n = Self.digitKeyCodes[event.keyCode] {
                if vm.results.indices.contains(n - 1) {
                    pick(vm.results[n - 1], flags.contains(.option) ? .plain : .normal)
                }
                return nil
            }
            switch event.keyCode {
            case 35: // ⌘P
                if let item = vm.selectedItem { vm.store.setPinned(item.id, !item.pinned) }
                return nil
            case 51: // ⌘⌫
                if let item = vm.selectedItem { vm.store.delete(item.id) }
                return nil
            case 43: // ⌘,
                hide()
                onOpenSettings()
                return nil
            case 13: // ⌘W
                hide()
                return nil
            default:
                break
            }
        }
        return event
    }
}
