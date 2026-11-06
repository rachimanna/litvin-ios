import Foundation
import SQLite3

public final class LitvinEditHistoryStore {
    private let db: OpaquePointer?

    public init(path: String) {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            self.db = nil
            return
        }
        self.db = handle
        self.exec("""
            CREATE TABLE IF NOT EXISTS edits(
                message_id INTEGER NOT NULL,
                peer_id INTEGER NOT NULL,
                version INTEGER NOT NULL,
                ts INTEGER NOT NULL,
                text TEXT,
                attributes_blob BLOB,
                PRIMARY KEY(message_id, peer_id, version)
            );
        """)
    }

    deinit { if let db = db { sqlite3_close(db) } }

    public func record(messageId: Int64, peerId: Int64, version: Int32, ts: Int32, text: String?, attributesBlob: Data?) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO edits(message_id, peer_id, version, ts, text, attributes_blob) VALUES (?,?,?,?,?,?);"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, messageId)
        sqlite3_bind_int64(stmt, 2, peerId)
        sqlite3_bind_int(stmt, 3, version)
        sqlite3_bind_int(stmt, 4, ts)
        if let t = text { sqlite3_bind_text(stmt, 5, t, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } else { sqlite3_bind_null(stmt, 5) }
        if let b = attributesBlob { b.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(b.count), nil) } } else { sqlite3_bind_null(stmt, 6) }
        _ = sqlite3_step(stmt)
    }

    public func history(messageId: Int64, peerId: Int64) -> [(version: Int32, ts: Int32, text: String?)] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT version, ts, text FROM edits WHERE message_id = ? AND peer_id = ? ORDER BY version ASC;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, messageId)
        sqlite3_bind_int64(stmt, 2, peerId)
        var rows: [(Int32, Int32, String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let v = sqlite3_column_int(stmt, 0)
            let ts = sqlite3_column_int(stmt, 1)
            let text: String? = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
            rows.append((v, ts, text))
        }
        return rows
    }

    private func exec(_ sql: String) {
        guard let db = db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
