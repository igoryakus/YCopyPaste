import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Запись элемента в буфер и имитация ⌘V.
enum Paster {
    @MainActor
    static func write(_ item: ClipItem, payload: ClipPayload?, plain: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if plain || payload == nil {
            pb.setString(item.text, forType: .string)
            return
        }
        let objects: [NSPasteboardItem] = payload!.map { entries in
            let pbItem = NSPasteboardItem()
            for entry in entries {
                pbItem.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
            }
            return pbItem
        }
        if !pb.writeObjects(objects) {
            pb.clearContents()
            pb.setString(item.text, forType: .string)
        }
    }

    /// Нажать ⌘V в активном приложении. Требует разрешения «Универсальный доступ».
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Не даём зажатым пользователем клавишам (⌥, ⇧) примешаться к нашему ⌘V.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Показать системный запрос на доступ (появляется один раз).
    @discardableResult
    static func prompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
