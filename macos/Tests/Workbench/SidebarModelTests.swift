import AppKit
import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
struct SidebarModelTests {
    func store() throws -> WorkbenchStore {
        try WorkbenchStore(dbPath: FileManager.default.temporaryDirectory.appendingPathComponent("sb-\(UUID()).db").path)
    }
    let windows = (0..<4).map { _ in NSObject() }   // kept alive so the identifiers stay distinct
    var w1: ObjectIdentifier { ObjectIdentifier(windows[0]) }
    var w2: ObjectIdentifier { ObjectIdentifier(windows[1]) }
    var w3: ObjectIdentifier { ObjectIdentifier(windows[2]) }
    var w4: ObjectIdentifier { ObjectIdentifier(windows[3]) }

    @Test func groupsByRepoWithOtherLastAndPinnedFirst() throws {
        let s = try store(); let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        _ = s.surfaceOpened(a, cwd: "/w/api/src", inheritFrom: nil)
        _ = s.surfaceOpened(b, cwd: "/w/web", inheritFrom: nil)
        _ = s.surfaceOpened(c, cwd: "/tmp", inheritFrom: nil)
        _ = s.surfaceOpened(d, cwd: "/w/api", inheritFrom: nil)
        s.applyGit(cwd: "/w/api/src", repoRoot: "/w/api", state: GitState(branch: "main", ahead: 1, behind: 0, staged: 0, unstaged: 2, untracked: 0))
        s.applyGit(cwd: "/w/api", repoRoot: "/w/api", state: GitState(branch: "main", ahead: 1, behind: 0, staged: 0, unstaged: 2, untracked: 0))
        s.applyGit(cwd: "/w/web", repoRoot: "/w/web", state: GitState(branch: "dev", ahead: 0, behind: 0, staged: 0, unstaged: 0, untracked: 0))
        s.applyGit(cwd: "/tmp", repoRoot: nil, state: nil)
        _ = try s.addGoal(surface: d, text: "x", author: .user)
        s.pinned = [try #require(try s.record(for: d, create: false)).id]
        let secs = SidebarModel.sections(tabs: [.init(surface: a, window: w1), .init(surface: b, window: w2), .init(surface: c, window: w3), .init(surface: d, window: w4)], store: s)
        #expect(secs.map(\.label) == ["Pinned", "api", "web", "Other"])
        #expect(secs[0].rows.map(\.id) == [d])
        #expect(secs[1].rows.map(\.id) == [a])
        #expect(secs[1].rows[0].gitLabel == "main ↑1" && secs[1].rows[0].dirty && secs[1].rows[0].cwdName == "src")
        #expect(secs[0].rows[0].progress == "0/1")
        #expect(secs[3].rows[0].progress == nil)
    }

    @Test func groupOrderIsRespected() throws {
        let s = try store(); let a = UUID(), b = UUID()
        _ = s.surfaceOpened(a, cwd: "/w/api", inheritFrom: nil); _ = s.surfaceOpened(b, cwd: "/w/web", inheritFrom: nil)
        s.applyGit(cwd: "/w/api", repoRoot: "/w/api", state: nil); s.applyGit(cwd: "/w/web", repoRoot: "/w/web", state: nil)
        s.groupOrder = ["/w/web", "/w/api"]
        let secs = SidebarModel.sections(tabs: [.init(surface: a, window: w1), .init(surface: b, window: w2)], store: s)
        #expect(secs.map(\.label) == ["web", "api"])
        #expect(SidebarModel.tabOrder(secs) == [w2, w1])
    }

    @Test func gitLabels() {
        #expect(SidebarModel.gitLabel(nil) == "")
        #expect(SidebarModel.gitLabel(GitState(branch: "main", ahead: 0, behind: 3, staged: 0, unstaged: 0, untracked: 0)) == "main ↓3")
        #expect(SidebarModel.gitLabel(GitState(branch: "main", ahead: 2, behind: 3, staged: 0, unstaged: 0, untracked: 0)) == "main ↑2 ↓3")
        #expect(SidebarModel.gitLabel(GitState(branch: "main", ahead: 0, behind: 0, staged: 0, unstaged: 0, untracked: 0, timedOut: true)) == "main ?")
    }

    @Test func dragOnlyWithinOwnGroup() throws {
        let s = try store(); let a = UUID()
        _ = s.surfaceOpened(a, cwd: "/w/api", inheritFrom: nil)
        s.applyGit(cwd: "/w/api", repoRoot: "/w/api", state: nil)
        let secs = SidebarModel.sections(tabs: [.init(surface: a, window: w1)], store: s)
        let row = secs[0].rows[0]
        #expect(SidebarModel.canMove(row, toSection: "/w/api", sections: secs))
        #expect(!SidebarModel.canMove(row, toSection: "", sections: secs))
    }
}
