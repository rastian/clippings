import Foundation
import SQLite3

/// Every transaction opens its own connection. SQLite coordinates app/extension processes;
/// no pointer or mutable connection crosses a Swift concurrency boundary.
public actor LocalStore {
    public nonisolated let url: URL
    public init(url: URL) { self.url = url }

    public func read() throws -> Snapshot { try transaction { $0 } }
    @discardableResult
    public func transaction<T: Sendable>(_ body: @Sendable (inout Snapshot) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw LinkinError.storage("Could not open your saved links. Please try again.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5_000)
        func execute(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw LinkinError.storage("Your saved links could not be updated. Please try again.") }
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw LinkinError.storage("Could not read saved links.") }
            var state = Snapshot()
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                do { state = try JSONDecoder().decode(Snapshot.self, from: data) }
                catch { sqlite3_finalize(statement); throw LinkinError.storage("The local library could not be read. Your data has been preserved; do not reinstall the app.") }
            } else if step != SQLITE_DONE { sqlite3_finalize(statement); throw LinkinError.storage("Could not read saved links.") }
            sqlite3_finalize(statement)
            guard state.version == 1 else { throw LinkinError.incompatibleSchema }
            let result = try body(&state)
            let data = try JSONEncoder().encode(state)
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO state(id,payload) VALUES(1,?)", -1, &statement, nil) == SQLITE_OK else { throw LinkinError.storage("Could not save your changes.") }
            defer { sqlite3_finalize(statement) }
            let code = data.withUnsafeBytes { bytes -> Int32 in
                sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), nil)
                return sqlite3_step(statement)
            }
            guard code == SQLITE_DONE else { throw LinkinError.storage("Could not save your changes. Your device may be out of storage.") }
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
