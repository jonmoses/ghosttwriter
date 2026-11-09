import Foundation

/// Parses `git status --porcelain=v2 --branch` output.
enum GitPorcelain {
    static func parse(_ output: String) -> GitState {
        var g = GitState(branch: "", ahead: 0, behind: 0, staged: 0, unstaged: 0, untracked: 0)
        var oid = ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ")
            switch parts.first {
            case "#":
                if parts.count >= 3, parts[1] == "branch.oid" { oid = String(parts[2]) }
                if parts.count >= 3, parts[1] == "branch.head" { g.branch = String(parts[2]) }
                if parts.count >= 4, parts[1] == "branch.ab" {
                    g.ahead = Int(parts[2].dropFirst()) ?? 0
                    g.behind = Int(parts[3].dropFirst()) ?? 0
                }
            case "u":
                // An unmerged entry still needs work in the tree: count it once, as unstaged.
                g.unstaged += 1
            case "1", "2":
                guard parts.count >= 2 else { break }
                let xy = Array(parts[1])
                guard xy.count >= 2 else { break }
                if xy[0] != "." { g.staged += 1 }
                if xy[1] != "." { g.unstaged += 1 }
            case "?":
                g.untracked += 1
            default:
                break
            }
        }
        if g.branch == "(detached)" { g.branch = String(oid.prefix(7)) }
        return g
    }
}
