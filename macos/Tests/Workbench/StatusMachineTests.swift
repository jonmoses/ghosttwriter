import Testing
import WorkbenchProtocol
@testable import Ghostty

struct StatusMachineTests {
    @Test(arguments: [
        (SessionStatus.idle, "SessionStart", SessionStatus.waiting),
        (.waiting, "UserPromptSubmit", .working),
        (.working, "Notification", .needsInput),
        (.needsInput, "PostToolUse", .working),
        (.needsInput, "UserPromptSubmit", .working),
        (.working, "PostToolUse", .working),
        (.working, "Stop", .waiting),
        (.waiting, "SessionEnd", .idle),
        (.working, "SessionEnd", .idle),
        (.needsInput, "SessionEnd", .idle),
        (.waiting, "Notification", .waiting),
        (.idle, "Bogus", .idle),
    ])
    func transition(from: SessionStatus, event: String, to: SessionStatus) {
        #expect(StatusMachine.next(from, event: event) == to)
    }
}
