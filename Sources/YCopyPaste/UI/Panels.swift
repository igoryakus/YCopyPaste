import AppKit
import SwiftUI

/// Панель без рамки, которая может принимать ввод с клавиатуры,
/// не активируя приложение (как Spotlight). Фокус остаётся у текущего приложения,
/// поэтому вставка уходит туда, где работал пользователь.
final class KeyablePanel: NSPanel {
    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Расположить у курсора мыши или по центру экрана с курсором.
    func position(_ mode: PopupPosition) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { center(); return }
        let size = frame.size
        var origin: NSPoint
        switch mode {
        case .saved:
            if let saved = Preferences.shared.popupOrigin,
               let target = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: saved, size: size)) }) {
                // Не даём окну уехать за край экрана (например, после отключения монитора).
                let v = target.visibleFrame
                let x = min(max(saved.x, v.minX), v.maxX - size.width)
                let y = min(max(saved.y, v.minY), v.maxY - size.height)
                setFrameOrigin(NSPoint(x: x, y: y))
                return
            }
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1)
        case .cursor:
            origin = NSPoint(x: mouse.x + 8, y: mouse.y - size.height - 8)
        case .center:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(origin)
    }
}

/// Область, за которую можно перетаскивать окно без рамки.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Полупрозрачный фон как у системных меню.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Иконки приложений-источников (кэш).
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[bundleID] = img
        return img
    }
}

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .full
        return f
    }()

    static func relativeString(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 5 { return "только что" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
