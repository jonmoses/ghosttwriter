import Foundation

/// The `state.db` schema and its migrations.
enum WorkbenchSchema {
    static let version = 1

    static func migrate(_ db: SQLiteDB) throws {
        if try db.userVersion() < 1 {
            try db.transaction {
                try db.exec("""
                CREATE TABLE sessions (
                    id TEXT PRIMARY KEY,
                    claude_session_id TEXT UNIQUE,
                    surface_id TEXT,
                    cwd TEXT NOT NULL,
                    repo_root TEXT,
                    title TEXT NOT NULL,
                    color TEXT NOT NULL,
                    status TEXT NOT NULL,
                    manual_done INTEGER NOT NULL DEFAULT 0,
                    note TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    closed_at TEXT
                );
                CREATE TABLE goals (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    done INTEGER NOT NULL DEFAULT 0,
                    author TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    done_at TEXT
                );
                CREATE TABLE goal_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    goal_id INTEGER,
                    kind TEXT NOT NULL,
                    text TEXT NOT NULL,
                    author TEXT NOT NULL,
                    at TEXT NOT NULL
                );
                CREATE TABLE ui_state (
                    key TEXT PRIMARY KEY,
                    value TEXT
                );
                CREATE INDEX goals_session_position ON goals(session_id, position);
                CREATE INDEX sessions_closed_at ON sessions(closed_at);
                PRAGMA user_version = 1;
                """)
            }
        }
    }
}
