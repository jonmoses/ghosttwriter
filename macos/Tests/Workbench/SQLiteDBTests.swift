import Foundation
import Testing
@testable import Ghostty

struct SQLiteDBTests {
    func tempDB() throws -> SQLiteDB {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("wb-\(UUID()).db").path
        return try SQLiteDB(path: p)
    }

    @Test func migrateCreatesSchemaV1() throws {
        let db = try tempDB()
        try WorkbenchSchema.migrate(db)
        #expect(try db.userVersion() == 1)
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").compactMap { row -> String? in
            if case .text(let s) = row["name"] { return s }; return nil
        }
        #expect(tables.contains("sessions") && tables.contains("goals") && tables.contains("goal_events") && tables.contains("ui_state"))
        let journal = try db.query("PRAGMA journal_mode").first?["journal_mode"]
        #expect(journal == .text("wal"))
    }

    @Test func migrateIsIdempotent() throws {
        let db = try tempDB()
        try WorkbenchSchema.migrate(db)
        try WorkbenchSchema.migrate(db)
        #expect(try db.userVersion() == 1)
    }

    @Test func paramsAndTransactionRollback() throws {
        let db = try tempDB()
        try WorkbenchSchema.migrate(db)
        try db.run("INSERT INTO ui_state(key, value) VALUES(?, ?)", [.text("k"), .text("v")])
        #expect(try db.query("SELECT value FROM ui_state WHERE key = ?", [.text("k")]).first?["value"] == .text("v"))
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try db.transaction { try db.run("DELETE FROM ui_state"); throw Boom() }
        }
        #expect(try db.query("SELECT count(*) AS n FROM ui_state").first?["n"] == .int(1))
    }

    @Test func deletingSessionCascadesToGoalsAndEvents() throws {
        let db = try tempDB()
        try WorkbenchSchema.migrate(db)
        try db.run("INSERT INTO sessions(id, cwd, title, color, status, manual_done, note, created_at, updated_at) VALUES('s','/','t','red','idle',0,'','x','x')")
        try db.run("INSERT INTO goals(session_id, position, text, done, author, created_at) VALUES('s',0,'g',0,'user','x')")
        try db.run("INSERT INTO goal_events(session_id, goal_id, kind, text, author, at) VALUES('s',1,'add','g','user','x')")
        try db.run("DELETE FROM sessions WHERE id='s'")
        #expect(try db.query("SELECT count(*) AS n FROM goals").first?["n"] == .int(0))
        #expect(try db.query("SELECT count(*) AS n FROM goal_events").first?["n"] == .int(0))
    }
}
