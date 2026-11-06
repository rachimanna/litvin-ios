import Foundation
import SQLite3

public final class LitvinDeletedStore {
    private let db: OpaquePointer?

    public init(path: String) {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            self.db = nil
            return
        }
        self.db = handle
        self.exec("""
            CREATE TABLE IF NOT EXISTS deleted(
                message_id INTEGER NOT NULL,
                peer_id INTEGER NOT NULL,
                ts INTEGER NOT NULL,
                text TEXT,
                media_blob BLOB,
                attributes_blob BLOB,
                PRIMARY KEY(message_id, peer_id)
            );
        """)
        self.exec("CREATE INDEX IF NOT EXISTS idx_deleted_peer ON deleted(peer_id, ts DESC);")
    }

    deinit { if let db = db { sqlite3_close(db) } }

    public func record(messageId: Int64, peerId: Int64, ts: Int32, text: String?, mediaBlob: Data?, attributesBlob: Data?) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO deleted(message_id, peer_id, ts, text, media_blob, attributes_blob) VALUES (?,?,?,?,?,?);"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, messageId)
        sqlite3_bind_int64(stmt, 2, peerId)
        sqlite3_bind_int(stmt, 3, ts)
        if let t = text { sqlite3_bind_text(stmt, 4, t, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } else { sqlite3_bind_null(stmt, 4) }
        if let b = mediaBlob { b.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 5, ptr.baseAddress, Int32(b.count), nil) } } else { sqlite3_bind_null(stmt, 5) }
        if let b = attributesBlob { b.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(b.count), nil) } } else { sqlite3_bind_null(stmt, 6) }
        _ = sqlite3_step(stmt)
    }

    public struct Row {
        public let messageId: Int64
        public let peerId: Int64
        public let ts: Int32
        public let text: String?
    }

    public func list(peerId: Int64, limit: Int = 200) -> [Row] {
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT message_id, ts, text FROM deleted WHERE peer_id = ? ORDER BY ts DESC LIMIT ?;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, peerId)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mid = sqlite3_column_int64(stmt, 0)
            let ts = sqlite3_column_int(stmt, 1)
            let text: String? = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) }
            rows.append(Row(messageId: mid, peerId: peerId, ts: ts, text: text))
        }
        return rows
    }

    private func exec(_ sql: String) {
        guard let db = db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
