import AppKit

/// Следит за системным буфером обмена. macOS не присылает уведомлений
/// об изменении буфера, поэтому, как и все аналоги, опрашиваем changeCount.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onCapture: (CapturedClip) -> Void

    init(onCapture: @escaping (CapturedClip) -> Void) {
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Пропустить текущее содержимое (когда в буфер пишем мы сами).
    func skipCurrent() {
        lastChangeCount = pasteboard.changeCount
    }

    private func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let prefs = Preferences.shared
        guard !prefs.isPaused else { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if prefs.skipConcealed && !types.isDisjoint(with: PasteboardTypes.privateMarkers) { return }

        let front = NSWorkspace.shared.frontmostApplication
        if let bundle = front?.bundleIdentifier, prefs.ignoredApps.contains(bundle) { return }

        guard let pbItems = pasteboard.pasteboardItems, !pbItems.isEmpty else { return }
        var payload: ClipPayload = []
        for item in pbItems.prefix(500) {
            var entries: [PasteboardEntry] = []
            for type in item.types {
                guard let data = item.data(forType: type),
                      PasteboardTypes.shouldStore(type: type.rawValue, size: data.count) else { continue }
                entries.append(PasteboardEntry(type: type.rawValue, data: data))
            }
            if !entries.isEmpty { payload.append(entries) }
        }
        guard !payload.isEmpty else { return }

        if let clip = ClipClassifier.make(payload: payload,
                                          sourceBundle: front?.bundleIdentifier,
                                          sourceName: front?.localizedName) {
            onCapture(clip)
        }
    }
}
