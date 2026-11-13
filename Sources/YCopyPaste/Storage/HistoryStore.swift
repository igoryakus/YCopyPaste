import AppKit
import Combine

/// Хранилище истории: SQLite на диске + список метаданных в памяти.
@MainActor
final class HistoryStore: ObservableObject {
    /// Отсортировано по времени последнего использования (новые сверху).
    @Published private(set) var items: [ClipItem] = []

    private let db: Database
    private let imageCache = NSCache<NSNumber, NSImage>()

    static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YCopyPaste", isDirectory: true)
    }

    init() throws {
        let dir = Self.storageDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        db = try Database(url: dir.appendingPathComponent("history.sqlite"))
        imageCache.countLimit = 200
        reload()
        prune()
    }

    // MARK: - Чтение

    func reload() {
        do {
            let st = try db.prepare("""
                SELECT id, kind, text, hash, source_bundle, source_name, created, used, pinned, copy_count, byte_size
                FROM items ORDER BY used DESC
                """)
            st.bind([])
            var result: [ClipItem] = []
            while try st.step() {
                result.append(ClipItem(
                    id: st.int64(0),
                    kind: ClipKind(rawValue: st.text(1) ?? "") ?? .text,
                    text: st.text(2) ?? "",
                    hash: st.text(3) ?? "",
                    sourceBundle: st.text(4),
                    sourceName: st.text(5),
                    created: Date(timeIntervalSince1970: st.double(6)),
                    used: Date(timeIntervalSince1970: st.double(7)),
                    pinned: st.int64(8) != 0,
                    copyCount: Int(st.int64(9)),
                    byteSize: Int(st.int64(10))
                ))
            }
            items = result
        } catch {
            NSLog("YCopyPaste: reload failed: \(error)")
        }
    }

    func payload(for id: Int64) -> ClipPayload? {
        do {
            let st = try db.prepare("SELECT idx, type, data FROM item_data WHERE item_id = ? ORDER BY idx, rowid")
            st.bind([.int(id)])
            var groups: [Int: [PasteboardEntry]] = [:]
            while try st.step() {
                let idx = Int(st.int64(0))
                groups[idx, default: []].append(PasteboardEntry(type: st.text(1) ?? "", data: st.blob(2)))
            }
            if groups.isEmpty { return nil }
            return groups.keys.sorted().compactMap { groups[$0] }
        } catch {
            NSLog("YCopyPaste: payload failed: \(error)")
            return nil
        }
    }

    func image(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let payload = payload(for: item.id), let first = payload.first else { return nil }
        for type in PasteboardTypes.imageTypes {
            if let entry = first.first(where: { $0.type == type }), let img = NSImage(data: entry.data) {
                imageCache.setObject(img, forKey: key)
                return img
            }
        }
        return nil
    }

    // MARK: - Запись

    func add(_ clip: CapturedClip) {
        let now = Date()
        do {
            if let existing = items.firstIndex(where: { $0.hash == clip.hash }) {
                var item = items[existing]
                item.used = now
                item.copyCount += 1
                item.sourceBundle = clip.sourceBundle ?? item.sourceBundle
                item.sourceName = clip.sourceName ?? item.sourceName
                try db.prepare("UPDATE items SET used = ?, copy_count = copy_count + 1, source_bundle = ?, source_name = ? WHERE id = ?")
                    .run([.double(now.timeIntervalSince1970), item.sourceBundle.sqlValue,
                          item.sourceName.sqlValue, .int(item.id)])
                items.remove(at: existing)
                items.insert(item, at: 0)
            } else {
                var newID: Int64 = 0
                try db.transaction {
                    try db.prepare("""
                        INSERT INTO items(kind, text, hash, source_bundle, source_name, created, used, pinned, copy_count, byte_size)
                        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?)
                        """).run([
                            .text(clip.kind.rawValue), .text(clip.text), .text(clip.hash),
                            clip.sourceBundle.sqlValue,
                            clip.sourceName.sqlValue,
                            .double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970),
                            .int(Int64(clip.byteSize)),
                        ])
                    newID = db.lastInsertID
                    let ins = try db.prepare("INSERT INTO item_data(item_id, idx, type, data) VALUES (?, ?, ?, ?)")
                    for (idx, entries) in clip.payload.enumerated() {
                        for entry in entries {
                            try ins.run([.int(newID), .int(Int64(idx)), .text(entry.type), .blob(entry.data)])
                        }
                    }
                }
                let item = ClipItem(id: newID, kind: clip.kind, text: clip.text, hash: clip.hash,
                                    sourceBundle: clip.sourceBundle, sourceName: clip.sourceName,
                                    created: now, used: now, pinned: false, copyCount: 1, byteSize: clip.byteSize)
                items.insert(item, at: 0)
            }
            prune()
        } catch {
            NSLog("YCopyPaste: add failed: \(error)")
        }
    }

    /// Поднять элемент наверх (после вставки).
    func touch(_ id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        try? db.prepare("UPDATE items SET used = ? WHERE id = ?").run([.double(now.timeIntervalSince1970), .int(id)])
        var item = items.remove(at: idx)
        item.used = now
        items.insert(item, at: 0)
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        try? db.prepare("UPDATE items SET pinned = ? WHERE id = ?").run([.int(pinned ? 1 : 0), .int(id)])
        items[idx].pinned = pinned
    }

    func delete(_ id: Int64) {
        delete(ids: [id])
    }

    func clear(keepPinned: Bool = true) {
        let ids = items.filter { !keepPinned || !$0.pinned }.map(\.id)
        delete(ids: ids)
        try? db.exec("VACUUM;")
    }

    private func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        do {
            try db.transaction {
                let st = try db.prepare("DELETE FROM items WHERE id = ?")
                for id in ids { try st.run([.int(id)]) }
            }
            let set = Set(ids)
            items.removeAll { set.contains($0.id) }
            for id in ids { imageCache.removeObject(forKey: NSNumber(value: id)) }
        } catch {
            NSLog("YCopyPaste: delete failed: \(error)")
        }
    }

    /// Применить ограничения по количеству и сроку хранения (закреплённые не трогаем).
    func prune() {
        let prefs = Preferences.shared
        var toDelete = Set<Int64>()
        if prefs.maxDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(prefs.maxDays) * 86_400)
            for item in items where !item.pinned && item.used < cutoff { toDelete.insert(item.id) }
        }
        if prefs.maxItems > 0 {
            let unpinned = items.filter { !$0.pinned }
            if unpinned.count > prefs.maxItems {
                for item in unpinned[prefs.maxItems...] { toDelete.insert(item.id) }
            }
        }
        if !toDelete.isEmpty { delete(ids: Array(toDelete)) }
    }
}
