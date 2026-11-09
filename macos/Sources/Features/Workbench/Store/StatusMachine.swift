import WorkbenchProtocol

/// The session status transitions driven by Claude Code hook events (spec Figure 3).
enum StatusMachine {
    static func next(_ status: SessionStatus, event: String) -> SessionStatus {
        switch (status, event) {
        case (_, "SessionEnd"): return .idle
        case (_, "SessionStart"): return .waiting
        case (_, "UserPromptSubmit"): return .working
        case (.working, "Notification"): return .needsInput
        case (.needsInput, "PostToolUse"), (.working, "PostToolUse"): return .working
        case (_, "Stop"): return .waiting
        default: return status
        }
    }
}
