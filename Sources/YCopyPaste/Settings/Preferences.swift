import Foundation
import Combine

enum PopupPosition: String, CaseIterable, Identifiable {
    case saved, center, cursor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .saved: return "Там, куда перетащили"
        case .center: return "По центру экрана"
        case .cursor: return "У курсора мыши"
        }
    }
}

/// Настройки приложения (UserDefaults).
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    private enum K {
        static let popupHotKey = "popupHotKey"
        static let cycleHotKey = "cycleHotKey"
        static let autoPaste = "autoPaste"
        static let plainByDefault = "plainByDefault"
        static let moveToTop = "moveToTopOnPaste"
        static let maxItems = "maxItems"
        static let maxDays = "maxDays"
        static let isPaused = "isPaused"
        static let skipConcealed = "skipConcealed"
        static let ignoredApps = "ignoredApps"
        static let popupPosition = "popupPosition"
        static let menuRecentCount = "menuRecentCount"
        static let onboardingDone = "onboardingDone"
        static let popupOrigin = "popupOrigin"
    }

    @Published var popupHotKey: KeyCombo { didSet { saveCombo(popupHotKey, K.popupHotKey) } }
    @Published var cycleHotKey: KeyCombo { didSet { saveCombo(cycleHotKey, K.cycleHotKey) } }
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: K.autoPaste) } }
    @Published var plainByDefault: Bool { didSet { d.set(plainByDefault, forKey: K.plainByDefault) } }
    @Published var moveToTopOnPaste: Bool { didSet { d.set(moveToTopOnPaste, forKey: K.moveToTop) } }
    /// 0 — без ограничения.
    @Published var maxItems: Int { didSet { d.set(maxItems, forKey: K.maxItems) } }
    /// 0 — хранить всегда.
    @Published var maxDays: Int { didSet { d.set(maxDays, forKey: K.maxDays) } }
    @Published var isPaused: Bool { didSet { d.set(isPaused, forKey: K.isPaused) } }
    @Published var skipConcealed: Bool { didSet { d.set(skipConcealed, forKey: K.skipConcealed) } }
    @Published var ignoredApps: [String] { didSet { d.set(ignoredApps, forKey: K.ignoredApps) } }
    @Published var popupPosition: PopupPosition { didSet { d.set(popupPosition.rawValue, forKey: K.popupPosition) } }
    @Published var menuRecentCount: Int { didSet { d.set(menuRecentCount, forKey: K.menuRecentCount) } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: K.onboardingDone) } }

    private init() {
        d.register(defaults: [
            K.autoPaste: true,
            K.plainByDefault: false,
            K.moveToTop: true,
            K.maxItems: 1000,
            K.maxDays: 0,
            K.isPaused: false,
            K.skipConcealed: true,
            K.ignoredApps: PasteboardTypes.defaultIgnoredApps,
            K.popupPosition: PopupPosition.saved.rawValue,
            K.menuRecentCount: 10,
            K.onboardingDone: false,
        ])
        popupHotKey = Self.loadCombo(d, K.popupHotKey) ?? .defaultPopup
        cycleHotKey = Self.loadCombo(d, K.cycleHotKey) ?? .defaultCycle
        autoPaste = d.bool(forKey: K.autoPaste)
        plainByDefault = d.bool(forKey: K.plainByDefault)
        moveToTopOnPaste = d.bool(forKey: K.moveToTop)
        maxItems = d.integer(forKey: K.maxItems)
        maxDays = d.integer(forKey: K.maxDays)
        isPaused = d.bool(forKey: K.isPaused)
        skipConcealed = d.bool(forKey: K.skipConcealed)
        ignoredApps = d.stringArray(forKey: K.ignoredApps) ?? PasteboardTypes.defaultIgnoredApps
        popupPosition = PopupPosition(rawValue: d.string(forKey: K.popupPosition) ?? "") ?? .saved
        menuRecentCount = d.integer(forKey: K.menuRecentCount)
        onboardingDone = d.bool(forKey: K.onboardingDone)
    }

    /// Последнее положение окна истории (левый нижний угол), если его перетаскивали.
    var popupOrigin: CGPoint? {
        get {
            guard let arr = d.array(forKey: K.popupOrigin) as? [Double], arr.count == 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }
        set {
            if let p = newValue { d.set([Double(p.x), Double(p.y)], forKey: K.popupOrigin) }
            else { d.removeObject(forKey: K.popupOrigin) }
        }
    }

    private func saveCombo(_ combo: KeyCombo, _ key: String) {
        if let data = try? JSONEncoder().encode(combo) { d.set(data, forKey: key) }
    }

    private static func loadCombo(_ d: UserDefaults, _ key: String) -> KeyCombo? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}
