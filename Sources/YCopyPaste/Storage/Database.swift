import Foundation
import SQLite3

/// Минимальная обёртка над SQLite3 без внешних зависимостей.
enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

struct DatabaseError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Optional where Wrapped == String {
    var sqlValue: SQLValue {
        switch self {
        case .some(let s): return .text(s)
        case .none: return .null
        }
    }
}

final class Statement {
    let handle: OpaquePointer

    init(db: OpaquePointer, sql: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let prepared = stmt else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(db)))
        }
        handle = prepared
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ values: [SQLValue]) {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let idx = Int32(offset + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(handle, idx, v)
            case .double(let v): sqlite3_bind_double(handle, idx, v)
            case .text(let v): sqlite3_bind_text(handle, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                if v.isEmpty {
                    sqlite3_bind_zeroblob(handle, idx, 0)
                } else {
                    _ = v.withUnsafeBytes { buf in
                        sqlite3_bind_blob(handle, idx, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
                    }
                }
            case .null: sqlite3_bind_null(handle, idx)
            }
        }
    }

    /// Возвращает true, если получена очередная строка.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw DatabaseError(message: "sqlite3_step failed: \(rc)")
    }

    func run(_ values: [SQLValue] = []) throws {
        bind(values)
        _ = try step()
    }

    func int64(_ col: Int32) -> Int64 { sqlite3_column_int64(handle, col) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(handle, col) }
    func isNull(_ col: Int32) -> Bool { sqlite3_column_type(handle, col) == SQLITE_NULL }

    func text(_ col: Int32) -> String? {
        guard let ptr = sqlite3_column_text(handle, col) else { return nil }
        return String(cString: ptr)
    }

    func blob(_ col: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(handle, col))
        guard count > 0, let ptr = sqlite3_column_blob(handle, col) else { return Data() }
        return Data(bytes: ptr, count: count)
    }
}

final class Database {
    private var db: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError(message: "Не удалось открыть базу: \(msg)")
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError(message: msg)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        guard let db else { throw DatabaseError(message: "База закрыта") }
        return try Statement(db: db, sql: sql)
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(db) }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '',
            hash TEXT NOT NULL UNIQUE,
            source_bundle TEXT,
            source_name TEXT,
            created REAL NOT NULL,
            used REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            copy_count INTEGER NOT NULL DEFAULT 1,
            byte_size INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS item_data(
            item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            idx INTEGER NOT NULL,
            type TEXT NOT NULL,
            data BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_item_data_item ON item_data(item_id);
        CREATE INDEX IF NOT EXISTS idx_items_used ON items(used);
        """)
    }
}
