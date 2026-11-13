import AppKit
import SwiftUI

/// Режим Flycut: держите модификаторы и нажимайте клавишу, чтобы листать историю.
/// Отпустите модификаторы — выбранный элемент вставится.
@MainActor
final class FlycutModel: ObservableObject {
    @Published var item: ClipItem?
    @Published var index = 0
    @Published var total = 0
}

@MainActor
final class FlycutController: NSObject {
    private let store: HistoryStore
    private let model: FlycutModel
    private let panel: KeyablePanel
    private var timer: Timer?
    private var keyMonitor: Any?
    private var requiredModifiers: NSEvent.ModifierFlags = []
    private var index = 0
    private let onCommit: (ClipItem) -> Void

    init(store: HistoryStore, onCommit: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onCommit = onCommit
        model = FlycutModel()
        panel = KeyablePanel(size: NSSize(width: 440, height: 280))
        super.init()
        let hosting = NSHostingView(rootView: FlycutBezelView(model: model, store: store))
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 280)
        panel.contentView = hosting
    }

    func hotKeyPressed(_ combo: KeyCombo) {
        guard !store.items.isEmpty else { NSSound.beep(); return }
        if panel.isVisible {
            step(1)
        } else {
            requiredModifiers = combo.nsModifiers
            index = 0
            update()
            panel.position(.center)
            panel.makeKeyAndOrderFront(nil)
            startWatching()
        }
    }

    private func step(_ delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
        update()
    }

    private func update() {
        let items = store.items
        model.total = items.count
        model.index = index
        model.item = items.indices.contains(index) ? items[index] : nil
    }

    private func startWatching() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkModifiers() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 53: self.finish(commit: false)          // Esc — отмена
            case 125, 124: self.step(1)                  // ↓ →
            case 126, 123: self.step(-1)                 // ↑ ←
            case 51: self.deleteCurrent()                // ⌫ — удалить из истории
            default: break
            }
            return nil
        }
    }

    private func checkModifiers() {
        guard panel.isVisible else { return }
        if requiredModifiers.isEmpty || !NSEvent.modifierFlags.contains(requiredModifiers) {
            finish(commit: true)
        }
    }

    private func deleteCurrent() {
        guard let item = model.item else { return }
        store.delete(item.id)
        if store.items.isEmpty { finish(commit: false); return }
        index = min(index, store.items.count - 1)
        update()
    }

    private func finish(commit: Bool) {
        timer?.invalidate()
        timer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        let item = model.item
        panel.orderOut(nil)
        if commit, let item { onCommit(item) }
    }
}

@MainActor
struct FlycutBezelView: View {
    @ObservedObject var model: FlycutModel
    let store: HistoryStore

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(model.index + 1) из \(model.total)").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let item = model.item {
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(item.sourceName ?? item.kind.title)
                    Text("· " + Formatters.relativeString(item.used))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Group {
                if let item = model.item {
                    if item.kind == .image, let img = store.image(for: item) {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        Text(String(item.text.prefix(1500)))
                            .font(.system(size: 13, design: .monospaced))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Text("Отпустите клавиши — вставить  ·  ↑↓ листать  ·  ⌫ удалить  ·  ⎋ отмена")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 440, height: 280)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
