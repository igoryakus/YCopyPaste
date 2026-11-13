import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon RegisterEventHotKey.
/// Не требует разрешений и работает в любом приложении.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Registration {
        var combo: KeyCombo
        var handler: () -> Void
        var ref: EventHotKeyRef?
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private var suspended = false
    private let signature: OSType = 0x434C_4E53 // 'CLNS'

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &eventHandler)
    }

    @discardableResult
    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        registrations[id] = Registration(combo: combo, handler: handler, ref: nil)
        return suspended ? true : activate(id: id)
    }

    func unregister(id: UInt32) {
        if let ref = registrations[id]?.ref { UnregisterEventHotKey(ref) }
        registrations[id] = nil
    }

    /// Временно отключить (например, пока пользователь записывает новое сочетание).
    func suspend() {
        guard !suspended else { return }
        suspended = true
        for (id, reg) in registrations {
            if let ref = reg.ref { UnregisterEventHotKey(ref) }
            registrations[id]?.ref = nil
        }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for id in registrations.keys { activate(id: id) }
    }

    @discardableResult
    private func activate(id: UInt32) -> Bool {
        guard let reg = registrations[id] else { return false }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(reg.combo.keyCode, reg.combo.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("YCopyPaste: не удалось зарегистрировать \(reg.combo.displayString): \(status)")
            return false
        }
        registrations[id]?.ref = ref
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }
}

/// C-обработчик событий Carbon (глобальная функция, чтобы не захватывать контекст).
private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in HotKeyManager.shared.fire(id) }
    return noErr
}
