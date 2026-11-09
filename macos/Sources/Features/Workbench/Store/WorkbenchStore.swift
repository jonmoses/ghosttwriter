import Foundation
import OSLog
import WorkbenchProtocol

/// Holds sessions, goals, events, group order and pins in memory and mirrors them to SQLite.
@MainActor
final class WorkbenchStore: ObservableObject {
    /// The app's store at ~/Library/Application Support/Ghosttwriter/state.db.
    static let shared: WorkbenchStore = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ghosttwriter", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return try WorkbenchStore(dbPath: dir.appendingPathComponent("state.db").path)
        } catch {
            WorkbenchStore.logger.error("cannot open state.db, using an in-memory store: \(String(describing: error))")
            // swiftlint:disable:next force_try
            return try! WorkbenchStore(dbPath: ":memory:")
        }
    }()

    static let retentionDays = 90
    static let maxClosedRecords = 500

    @Published private(set) var records: [UUID: SessionRecord] = [:]   // live and closed
    @Published private(set) var surfaceRecord: [UUID: UUID] = [:]       // surface id → record id
    @Published private(set) var liveSurfaces: [UUID: LiveSurface] = [:] // every open surface
    @Published private(set) var git: [String: GitState] = [:]           // repo root → state
    @Published private(set) var repoRoots: [String: String] = [:]       // cwd → repo root
    @Published var groupOrder: [String] = [] {
        didSet { saveUIState("group_order", groupOrder) }
    }
    @Published var pinned: Set<UUID> = [] {
        didSet { saveUIState("pinned", pinned.map(\.uuidString).sorted()) }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jonmoses.ghosttwriter", category: "workbench")

    private let db: SQLiteDB
    private let now: () -> Date

    /// Surfaces opened as splits of another surface. They share their tab's color and are
    /// left out when counting colors among live tabs (constraint 13).
    private var splitSurfaces: Set<UUID> = []

    /// Surface → the record `close(surface:note:)` saved for it, so a tab whose close is
    /// undone can take the record back. Cleared when the surface leaves the live set.
    private var closedRecord: [UUID: UUID] = [:]

    init(dbPath: String, now: @escaping () -> Date = Date.init) throws {
        self.db = try SQLiteDB(path: dbPath)
        self.now = now
        try WorkbenchSchema.migrate(db)
        try load()

        // Records still attached to a surface are left over from a crash.
        let orphans = records.values.filter { $0.surfaceId != nil }
        if !orphans.isEmpty {
            try transact {
                for r in orphans { try closeRecord(r.id, note: Self.autoNote(r)) }
            }
        }
        try prune()
    }

    // MARK: Surfaces

    @discardableResult
    func surfaceOpened(_ surface: UUID, cwd: String, inheritFrom parent: UUID?) -> ClaudeColor {
        let color: ClaudeColor
        if let existing = liveSurfaces[surface] {
            color = existing.color
        } else if let parent, let p = liveSurfaces[parent] {
            color = p.color
            splitSurfaces.insert(surface)
        } else {
            var rng = SystemRandomNumberGenerator()
            let tabColors = liveSurfaces.values.filter { !splitSurfaces.contains($0.id) }.map(\.color)
            color = ColorAllocator.pick(inUse: tabColors, using: &rng)
        }
        let title = liveSurfaces[surface]?.title ?? ""
        liveSurfaces[surface] = LiveSurface(id: surface, cwd: cwd, title: title, color: color)
        return color
    }

    func surfaceChanged(_ surface: UUID, cwd: String?, title: String?) {
        guard var live = liveSurfaces[surface] else { return }
        if let cwd { live.cwd = cwd }
        if let title { live.title = title }
        if live != liveSurfaces[surface] { liveSurfaces[surface] = live }

        guard let rid = surfaceRecord[surface], var r = records[rid] else { return }
        let before = r
        if let cwd { r.cwd = cwd }
        if let title { r.title = title }
        guard r != before else { return }
        logFailure("surfaceChanged") { try transact { try save(r) } }
    }

    func surfaceClosed(_ surface: UUID) {
        if let rid = surfaceRecord[surface], let r = records[rid], r.closedAt == nil {
            logFailure("surfaceClosed") {
                try transact {
                    if r.claudeSessionId != nil || !r.goals.isEmpty {
                        try closeRecord(rid, note: Self.autoNote(r))
                    } else {
                        try deleteRow(rid)
                    }
                }
            }
        }
        surfaceRecord[surface] = nil
        liveSurfaces[surface] = nil
        splitSurfaces.remove(surface)
        closedRecord[surface] = nil
    }

    /// The record attached to `surface`, or else the one the close sheet just saved for it.
    /// Read when a surface leaves the live set so an undone close can reattach it.
    func lastRecord(for surface: UUID) -> UUID? {
        surfaceRecord[surface] ?? closedRecord[surface]
    }

    func color(for surface: UUID) -> ClaudeColor? {
        liveSurfaces[surface]?.color
    }

    func setColor(surface: UUID, _ color: ClaudeColor) throws {
        try requireLive(surface)
        if let rid = surfaceRecord[surface], var r = records[rid] {
            r.color = color
            r.updatedAt = now()
            try transact { try save(r) }
        }
        liveSurfaces[surface]?.color = color
    }

    // MARK: Records

    func record(for surface: UUID, create: Bool) throws -> SessionRecord? {
        if let rid = surfaceRecord[surface], let r = records[rid] { return r }
        guard create else { return nil }
        try requireLive(surface)
        return try transact { try ensureRecord(surface) }
    }

    func handleHook(surface: UUID, event: HookEvent) throws {
        try requireLive(surface)
        try transact {
            let rid: UUID
            if event.name == "SessionStart" {
                rid = try attach(surface, event: event)
            } else if let existing = surfaceRecord[surface] {
                rid = existing
            } else {
                return
            }
            guard var r = records[rid] else { return }
            r.status = StatusMachine.next(r.status, event: event.name)
            if !event.cwd.isEmpty { r.cwd = event.cwd }
            r.updatedAt = now()
            try save(r)
        }
    }

    // MARK: Goals

    func addGoal(surface: UUID, text: String, author: Author) throws -> Int {
        try requireLive(surface)
        return try transact {
            var r = try ensureRecord(surface)
            let at = now()
            try db.run(
                "INSERT INTO goals(session_id, position, text, done, author, created_at) VALUES(?, ?, ?, 0, ?, ?)",
                [.text(r.id.uuidString), .int(Int64(r.goals.count)), .text(text), .text(author.rawValue), .text(Self.iso(at))])
            let goal = Goal(id: db.lastInsertRowID, text: text, done: false, author: author, createdAt: at, doneAt: nil)
            r.goals.append(goal)
            try logEvent(r.id, goalId: goal.id, kind: .add, text: text, author: author)
            r.updatedAt = at
            try save(r)
            return r.goals.count
        }
    }

    func setGoal(surface: UUID, index: Int, done: Bool, author: Author) throws {
        try requireLive(surface)
        try transact {
            var r = try ensureRecord(surface)
            guard r.goals.indices.contains(index - 1) else { throw WorkbenchError.noSuchGoal(index) }
            var goal = r.goals[index - 1]
            guard goal.done != done else { return }
            let at = now()
            goal.done = done
            goal.doneAt = done ? at : nil
            try db.run(
                "UPDATE goals SET done = ?, done_at = ? WHERE id = ?",
                [.int(done ? 1 : 0), goal.doneAt.map { .text(Self.iso($0)) } ?? .null, .int(goal.id)])
            r.goals[index - 1] = goal
            try logEvent(r.id, goalId: goal.id, kind: done ? .done : .undo, text: goal.text, author: author)
            r.updatedAt = at
            try save(r)
        }
    }

    func removeGoal(surface: UUID, index: Int, author: Author) throws {
        try requireLive(surface)
        try transact {
            var r = try ensureRecord(surface)
            guard r.goals.indices.contains(index - 1) else { throw WorkbenchError.noSuchGoal(index) }
            let goal = r.goals.remove(at: index - 1)
            try db.run("DELETE FROM goals WHERE id = ?", [.int(goal.id)])
            for (position, g) in r.goals.enumerated() where position >= index - 1 {
                try db.run("UPDATE goals SET position = ? WHERE id = ?", [.int(Int64(position)), .int(g.id)])
            }
            try logEvent(r.id, goalId: goal.id, kind: .remove, text: goal.text, author: author)
            r.updatedAt = now()
            try save(r)
        }
    }

    func events(record: UUID) throws -> [GoalEvent] {
        try db.query(
            "SELECT id, goal_id, kind, text, author, at FROM goal_events WHERE session_id = ? ORDER BY id",
            [.text(record.uuidString)]
        ).compactMap { row in
            guard let id = row["id"]?.intValue,
                  let kind = row["kind"]?.textValue.flatMap(GoalEventKind.init(rawValue:)) else { return nil }
            return GoalEvent(
                id: id,
                goalId: row["goal_id"]?.intValue,
                kind: kind,
                text: row["text"]?.textValue ?? "",
                author: row["author"]?.textValue.flatMap(Author.init(rawValue:)) ?? .user,
                at: row["at"]?.textValue.flatMap(Self.date) ?? .distantPast)
        }
    }

    // MARK: Note and done

    func setNote(surface: UUID, text: String, author: Author) throws {
        try requireLive(surface)
        try transact {
            var r = try ensureRecord(surface)
            r.note = text
            r.updatedAt = now()
            try save(r)
            try logEvent(r.id, goalId: nil, kind: .note, text: text, author: author)
        }
    }

    func setManualDone(surface: UUID, _ done: Bool) throws {
        try requireLive(surface)
        try transact {
            var r = try ensureRecord(surface)
            r.manualDone = done
            r.updatedAt = now()
            try save(r)
        }
    }

    // MARK: Close and resume

    /// Closes the surface's record with `note`, or deletes it when `note` is nil.
    func close(surface: UUID, note: String?) throws {
        try requireLive(surface)
        guard let rid = surfaceRecord[surface] else { return }
        try transact {
            if let note {
                try closeRecord(rid, note: note)
            } else {
                try deleteRow(rid)
            }
        }
        if note == nil {
            pinned.remove(rid)
        } else {
            closedRecord[surface] = rid
        }
    }

    func reattach(record: UUID, to surface: UUID) throws {
        try requireLive(surface)
        guard records[record] != nil else { throw WorkbenchError.notFound("record \(record.uuidString)") }
        try transact { try attachRecord(record, to: surface) }
    }

    /// Closed records, newest first, whose title, cwd, note or goals contain `query`.
    func closedRecords(matching query: String) -> [SessionRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return sortedClosed().filter { r in
            q.isEmpty
                || r.title.localizedCaseInsensitiveContains(q)
                || r.cwd.localizedCaseInsensitiveContains(q)
                || r.note.localizedCaseInsensitiveContains(q)
                || r.goals.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    func deleteRecord(_ id: UUID) throws {
        guard records[id] != nil else { return }
        try transact { try deleteRow(id) }
        pinned.remove(id)
    }

    /// Deletes closed records older than 90 days, then all but the newest 500 closed.
    func prune() throws {
        let cutoff = now().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let doomed = sortedClosed().enumerated().filter { i, r in
            i >= Self.maxClosedRecords || (r.closedAt ?? .distantFuture) < cutoff
        }.map(\.element.id)
        guard !doomed.isEmpty else { return }
        try transact {
            for id in doomed { try deleteRow(id) }
        }
        let gone = pinned.intersection(doomed)
        if !gone.isEmpty { pinned.subtract(gone) }
    }

    /// Closes every attached record with its auto note. Used at quit and window close.
    func saveAllLive() throws {
        let attached = surfaceRecord.values.compactMap { records[$0] }.filter { $0.closedAt == nil }
        guard !attached.isEmpty else { return }
        try transact {
            for r in attached { try closeRecord(r.id, note: Self.autoNote(r)) }
        }
    }

    // MARK: Git

    func applyGit(cwd: String, repoRoot: String?, state: GitState?) {
        if repoRoots[cwd] != repoRoot { repoRoots[cwd] = repoRoot }
        if let repoRoot {
            if git[repoRoot] != state { git[repoRoot] = state }
        }
        let changed = surfaceRecord.values.compactMap { records[$0] }
            .filter { $0.cwd == cwd && $0.repoRoot != repoRoot }
        guard !changed.isEmpty else { return }
        logFailure("applyGit") {
            try transact {
                for var r in changed {
                    r.repoRoot = repoRoot
                    try save(r)
                }
            }
        }
    }

    // MARK: Derived state

    /// The record's note, or else its unchecked goals as "- " lines.
    static func autoNote(_ record: SessionRecord) -> String {
        if !record.note.isEmpty { return record.note }
        return record.goals.filter { !$0.done }.map { "- " + $0.text }.joined(separator: "\n")
    }

    static func isDone(_ record: SessionRecord) -> Bool {
        record.manualDone || (!record.goals.isEmpty && record.goals.allSatisfy(\.done))
    }

    static func badge(for record: SessionRecord?) -> Badge {
        guard let record else { return .none }
        switch record.status {
        case .idle: return .none
        case .working: return .spinner
        case .needsInput: return .attention
        case .waiting: return isDone(record) ? .done : .hollow
        }
    }

    // MARK: Private: attach rules (spec 4.1)

    private func attach(_ surface: UUID, event: HookEvent) throws -> UUID {
        let sid = event.sessionId
        let current = surfaceRecord[surface].flatMap { records[$0] }
        guard !sid.isEmpty else { return try ensureRecord(surface).id }

        // 1. Already attached to this session.
        if let current, current.claudeSessionId == sid { return current.id }

        // 2. A live or closed record has this session: resume it here.
        if let other = records.values.first(where: { $0.claudeSessionId == sid }) {
            try attachRecord(other.id, to: surface)
            return other.id
        }

        if var current {
            // 3. Goals were typed before Claude started.
            if current.claudeSessionId == nil {
                current.claudeSessionId = sid
                try save(current)
                return current.id
            }
            // 4. /clear: keep goals and note under the new id.
            if event.source == "clear" {
                let old = current.claudeSessionId ?? ""
                current.claudeSessionId = sid
                try save(current)
                try logEvent(current.id, goalId: nil, kind: .relinked, text: "\(old) → \(sid)", author: .claude)
                return current.id
            }
            // A different Claude session started in this surface: close the old record.
            try detachCurrent(from: surface)
        }

        // 5. A new record.
        var r = try ensureRecord(surface)
        r.claudeSessionId = sid
        try save(r)
        return r.id
    }

    /// Attaches `id` to `surface`, displacing the surface's current record and
    /// detaching `id` from any other surface.
    private func attachRecord(_ id: UUID, to surface: UUID) throws {
        guard var r = records[id] else { throw WorkbenchError.notFound("record \(id.uuidString)") }
        if surfaceRecord[surface] != id { try detachCurrent(from: surface) }
        if let old = r.surfaceId, old != surface, surfaceRecord[old] == id { surfaceRecord[old] = nil }
        r.surfaceId = surface
        r.closedAt = nil
        r.updatedAt = now()
        try save(r)
        surfaceRecord[surface] = id
        liveSurfaces[surface]?.color = r.color
    }

    /// Closes (or deletes, when empty) the record attached to `surface`.
    private func detachCurrent(from surface: UUID) throws {
        guard let rid = surfaceRecord[surface], let r = records[rid] else { return }
        if r.claudeSessionId != nil || !r.goals.isEmpty || !r.note.isEmpty {
            try closeRecord(rid, note: Self.autoNote(r))
        } else {
            try deleteRow(rid)
        }
    }

    // MARK: Private: writes (call inside `transact`)

    /// The surface's record, created from its `LiveSurface` with status idle if missing.
    private func ensureRecord(_ surface: UUID) throws -> SessionRecord {
        if let rid = surfaceRecord[surface], let r = records[rid] { return r }
        guard let live = liveSurfaces[surface] else { throw WorkbenchError.unknownSurface(surface) }
        let at = now()
        let r = SessionRecord(
            id: UUID(), claudeSessionId: nil, surfaceId: surface, cwd: live.cwd,
            repoRoot: repoRoots[live.cwd], title: live.title, color: live.color, status: .idle,
            manualDone: false, note: "", goals: [], createdAt: at, updatedAt: at, closedAt: nil)
        try save(r)
        surfaceRecord[surface] = r.id
        return r
    }

    private func closeRecord(_ id: UUID, note: String) throws {
        guard var r = records[id] else { return }
        if let s = r.surfaceId, surfaceRecord[s] == id { surfaceRecord[s] = nil }
        let at = now()
        r.note = note
        r.closedAt = at
        r.surfaceId = nil
        r.status = .idle
        r.updatedAt = at
        try save(r)
    }

    private func deleteRow(_ id: UUID) throws {
        try db.run("DELETE FROM sessions WHERE id = ?", [.text(id.uuidString)])
        if let s = records[id]?.surfaceId, surfaceRecord[s] == id { surfaceRecord[s] = nil }
        records[id] = nil
    }

    /// Writes the session row (not its goals) and updates `records`.
    private func save(_ r: SessionRecord) throws {
        try db.run("""
            INSERT INTO sessions(id, claude_session_id, surface_id, cwd, repo_root, title, color, status,
                                 manual_done, note, created_at, updated_at, closed_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                claude_session_id = excluded.claude_session_id, surface_id = excluded.surface_id,
                cwd = excluded.cwd, repo_root = excluded.repo_root, title = excluded.title,
                color = excluded.color, status = excluded.status, manual_done = excluded.manual_done,
                note = excluded.note, updated_at = excluded.updated_at, closed_at = excluded.closed_at
            """, [
                .text(r.id.uuidString), r.claudeSessionId.map { .text($0) } ?? .null,
                r.surfaceId.map { .text($0.uuidString) } ?? .null, .text(r.cwd),
                r.repoRoot.map { .text($0) } ?? .null, .text(r.title), .text(r.color.rawValue),
                .text(r.status.rawValue), .int(r.manualDone ? 1 : 0), .text(r.note),
                .text(Self.iso(r.createdAt)), .text(Self.iso(r.updatedAt)),
                r.closedAt.map { .text(Self.iso($0)) } ?? .null,
            ])
        records[r.id] = r
    }

    private func logEvent(_ record: UUID, goalId: Int64?, kind: GoalEventKind, text: String, author: Author) throws {
        try db.run(
            "INSERT INTO goal_events(session_id, goal_id, kind, text, author, at) VALUES(?, ?, ?, ?, ?, ?)",
            [.text(record.uuidString), goalId.map { .int($0) } ?? .null, .text(kind.rawValue),
             .text(text), .text(author.rawValue), .text(Self.iso(now()))])
    }

    /// Runs `body` in one SQLite transaction, restoring the in-memory maps if it throws.
    private func transact<T>(_ body: () throws -> T) throws -> T {
        let savedRecords = records
        let savedSurfaceRecord = surfaceRecord
        do {
            return try db.transaction(body)
        } catch {
            records = savedRecords
            surfaceRecord = savedSurfaceRecord
            throw error
        }
    }

    private func requireLive(_ surface: UUID) throws {
        guard liveSurfaces[surface] != nil else { throw WorkbenchError.unknownSurface(surface) }
    }

    private func logFailure(_ what: String, _ body: () throws -> Void) {
        do { try body() } catch { Self.logger.error("\(what) failed: \(String(describing: error))") }
    }

    private func sortedClosed() -> [SessionRecord] {
        records.values.filter { $0.closedAt != nil }.sorted { a, b in
            if a.closedAt != b.closedAt { return a.closedAt! > b.closedAt! }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.id.uuidString > b.id.uuidString
        }
    }

    // MARK: Private: loading and ui_state

    private func load() throws {
        var goals: [String: [Goal]] = [:]
        for row in try db.query(
            "SELECT id, session_id, text, done, author, created_at, done_at FROM goals ORDER BY session_id, position") {
            guard let sid = row["session_id"]?.textValue, let id = row["id"]?.intValue else { continue }
            goals[sid, default: []].append(Goal(
                id: id,
                text: row["text"]?.textValue ?? "",
                done: row["done"]?.intValue == 1,
                author: row["author"]?.textValue.flatMap(Author.init(rawValue:)) ?? .user,
                createdAt: row["created_at"]?.textValue.flatMap(Self.date) ?? .distantPast,
                doneAt: row["done_at"]?.textValue.flatMap(Self.date)))
        }

        var loaded: [UUID: SessionRecord] = [:]
        for row in try db.query("SELECT * FROM sessions") {
            guard let idText = row["id"]?.textValue, let id = UUID(uuidString: idText) else { continue }
            loaded[id] = SessionRecord(
                id: id,
                claudeSessionId: row["claude_session_id"]?.textValue,
                surfaceId: row["surface_id"]?.textValue.flatMap(UUID.init(uuidString:)),
                cwd: row["cwd"]?.textValue ?? "",
                repoRoot: row["repo_root"]?.textValue,
                title: row["title"]?.textValue ?? "",
                color: row["color"]?.textValue.flatMap(ClaudeColor.init(rawValue:)) ?? .blue,
                status: row["status"]?.textValue.flatMap(SessionStatus.init(rawValue:)) ?? .idle,
                manualDone: row["manual_done"]?.intValue == 1,
                note: row["note"]?.textValue ?? "",
                goals: goals[idText] ?? [],
                createdAt: row["created_at"]?.textValue.flatMap(Self.date) ?? .distantPast,
                updatedAt: row["updated_at"]?.textValue.flatMap(Self.date) ?? .distantPast,
                closedAt: row["closed_at"]?.textValue.flatMap(Self.date))
        }
        records = loaded

        groupOrder = try loadUIState("group_order") ?? []
        pinned = Set((try loadUIState("pinned") ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func loadUIState(_ key: String) throws -> [String]? {
        guard let json = try db.query("SELECT value FROM ui_state WHERE key = ?", [.text(key)]).first?["value"]?.textValue
        else { return nil }
        return try? JSONDecoder().decode([String].self, from: Data(json.utf8))
    }

    private func saveUIState(_ key: String, _ value: [String]) {
        logFailure("save \(key)") {
            let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
            try db.run(
                "INSERT INTO ui_state(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(key), .text(json)])
        }
    }

    // MARK: Private: timestamps (ISO 8601 UTC)

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
    private static func date(_ text: String) -> Date? { isoFormatter.date(from: text) }
}

private extension SQLValue {
    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var intValue: Int64? {
        if case .int(let v) = self { return v }
        return nil
    }
}
