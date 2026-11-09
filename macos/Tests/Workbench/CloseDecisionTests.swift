import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
struct CloseDecisionTests {
    func rec(status: SessionStatus, goals: [Bool] = [], manualDone: Bool = false, sid: String? = "c1") -> SessionRecord {
        SessionRecord(id: UUID(), claudeSessionId: sid, surfaceId: UUID(), cwd: "/work/api", repoRoot: "/work/api", title: "fix refunds",
                      color: .pink, status: status, manualDone: manualDone, note: "",
                      goals: goals.enumerated().map { Goal(id: Int64($0.offset), text: "g\($0.offset)", done: $0.element, author: .user, createdAt: .now, doneAt: nil) },
                      createdAt: .now, updatedAt: .now, closedAt: nil)
    }

    @Test func sheetOnlyForTabCloseOfActiveUnfinishedSession() {
        #expect(CloseDecision.shouldPresentSheet(rec(status: .waiting), scope: .tab))
        #expect(CloseDecision.shouldPresentSheet(rec(status: .working, goals: [true, false]), scope: .tab))
        #expect(!CloseDecision.shouldPresentSheet(rec(status: .waiting, goals: [true]), scope: .tab))
        #expect(!CloseDecision.shouldPresentSheet(rec(status: .waiting, manualDone: true), scope: .tab))
        #expect(!CloseDecision.shouldPresentSheet(rec(status: .idle, goals: [false]), scope: .tab))
        #expect(!CloseDecision.shouldPresentSheet(nil, scope: .tab))
        #expect(!CloseDecision.shouldPresentSheet(rec(status: .working), scope: .window))
        #expect(!CloseDecision.shouldPresentSheet(rec(status: .working), scope: .app))
    }

    @Test func resumeInputOnlyWithClaudeSession() {
        #expect(CloseDecision.resumeInput(rec(status: .idle)) == "claude --resume c1\n")
        #expect(CloseDecision.resumeInput(rec(status: .idle, sid: nil)) == nil)
    }

    @Test func prefillMatchesAutoNote() {
        #expect(WorkbenchStore.autoNote(rec(status: .waiting, goals: [true, false, false])) == "- g1\n- g2")
    }

    @Test func subtitle() {
        var r = rec(status: .idle, goals: [true, false])
        r.closedAt = Date(timeIntervalSince1970: 1_000_000)
        #expect(ResumeDashboardModel.subtitle(r, now: Date(timeIntervalSince1970: 1_000_000 + 7_200)) == "api · 1/2 goals · 2 hours ago")
    }

    @Test func dashboardRowsFilterByQuery() throws {
        let s = try WorkbenchStore(dbPath: FileManager.default.temporaryDirectory.appendingPathComponent("rd-\(UUID()).db").path)
        let S = UUID(); _ = s.surfaceOpened(S, cwd: "/work/api", inheritFrom: nil)
        try s.handleHook(surface: S, event: HookEvent(name: "SessionStart", sessionId: "c9", cwd: "/work/api", source: nil, message: nil))
        try s.close(surface: S, note: "refund edge case")
        let m = ResumeDashboardModel(store: s)
        #expect(m.rows.count == 1)
        m.query = "nothing"; #expect(m.rows.isEmpty)
        m.query = "REFUND"; #expect(m.rows.count == 1)
    }
}
