import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
struct WorkbenchStoreTests {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("wbs-\(UUID()).db").path
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func store() throws -> WorkbenchStore { let t = clock; return try WorkbenchStore(dbPath: path, now: { t }) }
    func hook(_ name: String, _ sid: String, source: String? = nil) -> HookEvent {
        HookEvent(name: name, sessionId: sid, cwd: "/repo", source: source, message: nil)
    }

    @Test func sessionStartCreatesRecordAndWaits() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1", source: "startup"))
        let r = try #require(try s.record(for: S, create: false))
        #expect(r.claudeSessionId == "c1" && r.status == .waiting && r.surfaceId == S)
    }

    @Test func goalsTypedBeforeClaudeAreAdopted() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        _ = try s.addGoal(surface: S, text: "find the bug", author: .user)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
        #expect(s.records.count == 1)
        #expect(try s.record(for: S, create: false)?.goals.map(\.text) == ["find the bug"])
    }

    @Test func clearRelinksAndKeepsGoals() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
        _ = try s.addGoal(surface: S, text: "ship fix", author: .claude)
        try s.setNote(surface: S, text: "tests left", author: .user)
        try s.handleHook(surface: S, event: hook("SessionStart", "c2", source: "clear"))
        let r = try #require(try s.record(for: S, create: false))
        #expect(r.claudeSessionId == "c2" && r.goals.count == 1 && r.note == "tests left" && s.records.count == 1)
        #expect(try s.events(record: r.id).contains { $0.kind == .relinked })
    }

    @Test func resumeHookAfterReattachKeepsOneRecord() throws {
        let s = try store(); let A = UUID(), B = UUID()
        _ = s.surfaceOpened(A, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: A, event: hook("SessionStart", "c1"))
        _ = try s.addGoal(surface: A, text: "g", author: .user)
        try s.close(surface: A, note: "later bits")
        s.surfaceClosed(A)
        let rec = try #require(s.closedRecords(matching: "").first)
        _ = s.surfaceOpened(B, cwd: "/repo", inheritFrom: nil)
        try s.reattach(record: rec.id, to: B)
        try s.handleHook(surface: B, event: hook("SessionStart", "c1", source: "resume"))
        #expect(s.records.count == 1)
        let r = try #require(try s.record(for: B, create: false))
        #expect(r.closedAt == nil && r.note == "later bits" && r.goals.count == 1)
    }

    @Test func indicesFollowDisplayOrderAfterRemove() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        #expect(try s.addGoal(surface: S, text: "a", author: .user) == 1)
        #expect(try s.addGoal(surface: S, text: "b", author: .user) == 2)
        #expect(try s.addGoal(surface: S, text: "c", author: .user) == 3)
        try s.removeGoal(surface: S, index: 1, author: .user)
        try s.setGoal(surface: S, index: 2, done: true, author: .claude)
        let goals = try #require(try s.record(for: S, create: false)).goals
        #expect(goals.map(\.text) == ["b", "c"] && goals.map(\.done) == [false, true])
        #expect(throws: WorkbenchError.noSuchGoal(3)) { try s.setGoal(surface: S, index: 3, done: true, author: .user) }
    }

    @Test func eachGoalChangeLogsOneEventWithAuthor() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        _ = try s.addGoal(surface: S, text: "a", author: .claude)
        try s.setGoal(surface: S, index: 1, done: true, author: .user)
        try s.setGoal(surface: S, index: 1, done: false, author: .user)
        try s.removeGoal(surface: S, index: 1, author: .claude)
        let r = try #require(try s.record(for: S, create: false))
        #expect(try s.events(record: r.id).map { "\($0.kind.rawValue):\($0.author.rawValue)" } == ["add:claude", "done:user", "undo:user", "remove:claude"])
    }

    @Test func unknownSurfaceThrows() throws {
        let s = try store()
        let ghost = UUID()
        #expect(throws: WorkbenchError.unknownSurface(ghost)) { _ = try s.addGoal(surface: ghost, text: "x", author: .user) }
    }

    @Test func surfaceClosedSavesAutoNote() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
        _ = try s.addGoal(surface: S, text: "a", author: .user)
        _ = try s.addGoal(surface: S, text: "b", author: .user)
        try s.setGoal(surface: S, index: 1, done: true, author: .user)
        s.surfaceClosed(S)
        #expect(s.closedRecords(matching: "").first?.note == "- b")
    }

    @Test func plainShellSurfaceLeavesNoRecord() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/tmp", inheritFrom: nil)
        s.surfaceClosed(S)
        #expect(s.records.isEmpty)
    }

    @Test func survivesReopen() throws {
        let S = UUID()
        do {
            let s = try store()
            _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
            try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
            _ = try s.addGoal(surface: S, text: "a", author: .user)
            try s.saveAllLive()
        }
        let s2 = try store()
        let r = try #require(s2.closedRecords(matching: "").first)
        #expect(r.claudeSessionId == "c1" && r.goals.map(\.text) == ["a"] && r.surfaceId == nil)
    }

    @Test func pruneKeeps500NewestWithin90Days() throws {
        let s = try store()
        for i in 0..<510 {
            let S = UUID()
            _ = s.surfaceOpened(S, cwd: "/r\(i)", inheritFrom: nil)
            try s.handleHook(surface: S, event: hook("SessionStart", "c\(i)"))
            s.surfaceClosed(S)
        }
        try s.prune()
        #expect(s.closedRecords(matching: "").count == 500)
        let later = Date(timeIntervalSince1970: 1_800_000_000 + 91 * 86_400)
        let s2 = try WorkbenchStore(dbPath: path, now: { later })
        #expect(s2.closedRecords(matching: "").isEmpty)
    }

    @Test func searchMatchesNoteTitleAndCwd() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/work/payments", inheritFrom: nil)
        try s.handleHook(surface: S, event: HookEvent(name: "SessionStart", sessionId: "c1", cwd: "/work/payments", source: nil, message: nil))
        try s.setNote(surface: S, text: "refund edge case", author: .user)
        s.surfaceClosed(S)
        #expect(s.closedRecords(matching: "refund").count == 1)
        #expect(s.closedRecords(matching: "payments").count == 1)
        #expect(s.closedRecords(matching: "zzz").isEmpty)
    }

    @Test func undoneSheetCloseCanReattachRecord() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
        let rid = try #require(try s.record(for: S, create: false)?.id)
        try s.close(surface: S, note: "later")
        // What surfacesDetached reads before the surface leaves the live set.
        #expect(s.lastRecord(for: S) == rid)
        s.surfaceClosed(S)
        #expect(s.lastRecord(for: S) == nil)
        // Undo brings the surface back and reattaches; later hooks land on the record.
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.reattach(record: rid, to: S)
        try s.handleHook(surface: S, event: hook("UserPromptSubmit", "c1"))
        let r = try #require(try s.record(for: S, create: false))
        #expect(r.id == rid && r.closedAt == nil && r.status == .working)
    }

    @Test func discardedSheetCloseLeavesNothingToReattach() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.handleHook(surface: S, event: hook("SessionStart", "c1"))
        try s.close(surface: S, note: nil)
        #expect(s.lastRecord(for: S) == nil && s.records.isEmpty)
    }

    @Test func noteEventKeepsAuthor() throws {
        let s = try store(); let S = UUID()
        _ = s.surfaceOpened(S, cwd: "/repo", inheritFrom: nil)
        try s.setNote(surface: S, text: "from claude", author: .claude)
        let r = try #require(try s.record(for: S, create: false))
        let e = try #require(try s.events(record: r.id).last)
        #expect(e.kind == .note && e.author == .claude)
    }

    @Test func colorCountsEachTabOnce() throws {
        let s = try store(); let A = UUID()
        let x = s.surfaceOpened(A, cwd: "/", inheritFrom: nil)
        _ = s.surfaceOpened(UUID(), cwd: "/", inheritFrom: A)
        _ = s.surfaceOpened(UUID(), cwd: "/", inheritFrom: A)
        // Every other color on two tabs; x on one tab (three surfaces).
        for c in ClaudeColor.allCases where c != x {
            for _ in 0..<2 {
                let t = UUID()
                _ = s.surfaceOpened(t, cwd: "/", inheritFrom: nil)
                try s.setColor(surface: t, c)
            }
        }
        #expect(s.surfaceOpened(UUID(), cwd: "/", inheritFrom: nil) == x)
    }

    @Test func splitsInheritColor() throws {
        let s = try store(); let A = UUID(), B = UUID()
        let c = s.surfaceOpened(A, cwd: "/", inheritFrom: nil)
        #expect(s.surfaceOpened(B, cwd: "/", inheritFrom: A) == c)
    }

    @Test func badgeAndDone() throws {
        var r = SessionRecord(id: UUID(), claudeSessionId: "c", surfaceId: UUID(), cwd: "/", repoRoot: nil, title: "", color: .red,
                              status: .waiting, manualDone: false, note: "", goals: [], createdAt: .now, updatedAt: .now, closedAt: nil)
        #expect(WorkbenchStore.badge(for: nil) == .none)
        #expect(WorkbenchStore.badge(for: r) == .hollow)
        r.status = .working; #expect(WorkbenchStore.badge(for: r) == .spinner)
        r.status = .needsInput; #expect(WorkbenchStore.badge(for: r) == .attention)
        r.status = .idle; #expect(WorkbenchStore.badge(for: r) == .none)
        r.status = .waiting
        r.goals = [Goal(id: 1, text: "a", done: true, author: .user, createdAt: .now, doneAt: .now)]
        #expect(WorkbenchStore.isDone(r) && WorkbenchStore.badge(for: r) == .done)
        r.goals = []; r.manualDone = true
        #expect(WorkbenchStore.badge(for: r) == .done)
    }
}
