import Foundation

/// What is being closed: one tab, a whole window, or the app.
enum CloseScope {
    case tab, window, app
}

/// Decides when the close sheet appears and what a resumed tab types.
@MainActor
enum CloseDecision {
    /// Only a tab close of a non-idle session that is not done asks for a note.
    static func shouldPresentSheet(_ record: SessionRecord?, scope: CloseScope) -> Bool {
        guard scope == .tab, let record else { return false }
        return record.status != .idle && !WorkbenchStore.isDone(record)
    }

    /// The initial input for a resumed tab, or nil when Claude never started.
    static func resumeInput(_ record: SessionRecord) -> String? {
        guard let id = record.claudeSessionId, !id.isEmpty else { return nil }
        return "claude --resume \(id)\n"
    }
}
