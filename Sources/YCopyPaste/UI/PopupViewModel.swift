import AppKit
import Combine

@MainActor
final class PopupViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, pinned
        var id: String { rawValue }
        var title: String { self == .all ? "Все" : "Закреплённые" }
    }

    @Published var query = ""
    @Published var filter: Filter = .all
    @Published var selection = 0
    @Published private(set) var results: [ClipItem] = []
    @Published var focusTrigger = 0
    @Published var notice: String?

    let store: HistoryStore
    private var bag = Set<AnyCancellable>()
    private let maxResults = 2000

    init(store: HistoryStore) {
        self.store = store
        Publishers.CombineLatest3(store.$items, $query.removeDuplicates(), $filter.removeDuplicates())
            .sink { [weak self] items, query, filter in
                self?.recompute(items: items, query: query, filter: filter)
            }
            .store(in: &bag)
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func prepareForShow() {
        query = ""
        filter = .all
        selection = 0
        notice = Accessibility.isTrusted || !Preferences.shared.autoPaste ? nil
            : "Нет доступа «Универсальный доступ»: элемент будет только скопирован. Откройте Настройки → Основные."
        focusTrigger += 1
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    func toggleFilter() {
        filter = filter == .all ? .pinned : .all
    }

    private func recompute(items: [ClipItem], query: String, filter: Filter) {
        let previousID = selectedItem?.id
        let base = filter == .pinned ? items.filter(\.pinned) : items
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            results = Array(base.prefix(maxResults))
        } else {
            let scored: [(ClipItem, Int, Int)] = base.enumerated().compactMap { index, item in
                guard let s = FuzzyMatcher.score(query: q, text: item.text) else { return nil }
                return (item, s, index)
            }
            results = scored
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
                .prefix(maxResults)
                .map(\.0)
        }
        if let previousID, q == self.query, filter == self.filter,
           let idx = results.firstIndex(where: { $0.id == previousID }) {
            selection = idx
        } else {
            selection = 0
        }
    }
}
