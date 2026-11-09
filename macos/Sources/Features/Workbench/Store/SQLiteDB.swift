import Foundation
import SQLite3

/// A value bound to or read from a SQLite statement.
enum SQLValue: Equatable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
}

/// A SQLite failure with its result code and message.
struct SQLiteError: Error {
    let code: Int32
    let message: String
}

/// SQLite's SQLITE_TRANSIENT destructor, which tells SQLite to copy bound data.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin wrapper around one SQLite connection.
final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(db)
            throw SQLiteError(code: rc, message: message)
        }
        handle = db
        _ = try query("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that take no parameters and return no rows.
    func exec(_ sql: String) throws {
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw error(rc) }
    }

    /// Runs one statement with parameters, discarding any rows.
    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { return }
            if rc != SQLITE_ROW { throw error(rc) }
        }
    }

    /// Runs one statement with parameters and returns every row keyed by column name.
    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[String: SQLValue]] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: SQLValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error(rc) }
            var row: [String: SQLValue] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = column(stmt, i)
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs `body` inside BEGIN IMMEDIATE / COMMIT, rolling back and rethrowing on error.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    func userVersion() throws -> Int {
        guard case .int(let v) = try query("PRAGMA user_version").first?["user_version"] else { return 0 }
        return Int(v)
    }

    // MARK: Private

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw error(rc) }
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            let brc: Int32
            switch value {
            case .null: brc = sqlite3_bind_null(stmt, idx)
            case .int(let v): brc = sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): brc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v): brc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            }
            guard brc == SQLITE_OK else {
                let err = error(brc)
                sqlite3_finalize(stmt)
                throw err
            }
        }
        return stmt
    }

    private func column(_ stmt: OpaquePointer?, _ i: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(stmt, i))
        case SQLITE_NULL: return .null
        default:
            guard let p = sqlite3_column_text(stmt, i) else { return .null }
            return .text(String(cString: p))
        }
    }

    private func error(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }
}
