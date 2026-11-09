import Foundation
import WorkbenchProtocol

/// One Claude session's record: live while its surface is open, closed afterwards.
struct SessionRecord: Identifiable, Equatable {
    var id: UUID
    var claudeSessionId: String?
    var surfaceId: UUID?
    var cwd: String
    var repoRoot: String?
    var title: String
    var color: ClaudeColor
    var status: SessionStatus
    var manualDone: Bool
    var note: String
    var goals: [Goal]
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?
}

struct Goal: Identifiable, Equatable {
    var id: Int64
    var text: String
    var done: Bool
    var author: Author
    var createdAt: Date
    var doneAt: Date?
}

enum GoalEventKind: String {
    case add, done, undo, remove, relinked, note
}

struct GoalEvent: Identifiable, Equatable {
    var id: Int64
    var goalId: Int64?
    var kind: GoalEventKind
    var text: String
    var author: Author
    var at: Date
}

struct GitState: Equatable {
    var branch: String
    var ahead: Int
    var behind: Int
    var staged: Int
    var unstaged: Int
    var untracked: Int
    var timedOut: Bool = false
    var isDirty: Bool { staged + unstaged + untracked > 0 }
}

struct HookEvent: Equatable {
    var name: String
    var sessionId: String
    var cwd: String
    var source: String?
    var message: String?
}

struct LiveSurface: Equatable {
    var id: UUID
    var cwd: String
    var title: String
    var color: ClaudeColor
}

enum Badge: Equatable {
    case none, spinner, hollow, attention, done
}

struct ShowResult: Equatable {
    var placed: ShowPlacement
    var png: String?
}

@MainActor
protocol ShowPresenter: AnyObject {
    func show(path: String, mode: ShowMode, tty: Bool, surface: UUID) async throws -> ShowResult
}

enum WorkbenchError: Error, Equatable, CustomStringConvertible {
    case unknownSurface(UUID)
    case noSuchGoal(Int)
    case unknownColor(String)
    case notFound(String)
    case unavailable(String)

    var description: String {
        switch self {
        case .unknownSurface(let id): return "unknown surface \(id.uuidString)"
        case .noSuchGoal(let n): return "no goal \(n)"
        case .unknownColor(let name): return "unknown color \(name)"
        case .notFound(let x): return "not found: \(x)"
        case .unavailable(let x): return "\(x) unavailable"
        }
    }
}
