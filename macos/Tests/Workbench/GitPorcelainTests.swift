import Testing
@testable import Ghostty

struct GitPorcelainTests {
    @Test func cleanWithUpstream() {
        let out = "# branch.oid abc\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -1\n"
        #expect(GitPorcelain.parse(out) == GitState(branch: "main", ahead: 2, behind: 1, staged: 0, unstaged: 0, untracked: 0))
    }

    @Test func countsStagedUnstagedUntracked() {
        let out = """
        # branch.head feat
        1 M. N... 100644 100644 100644 a a f1
        1 .M N... 100644 100644 100644 a a f2
        1 MM N... 100644 100644 100644 a a f3
        2 R. N... 100644 100644 100644 a a R100 new\told
        u UU N... 1 2 3 4 a b c conflict
        ? new.txt
        ? other.txt
        """
        let g = GitPorcelain.parse(out)
        #expect(g.branch == "feat" && g.staged == 3 && g.unstaged == 3 && g.untracked == 2 && g.isDirty)
    }

    @Test func detachedAndNoUpstream() {
        let g = GitPorcelain.parse("# branch.oid 1234567890abcdef\n# branch.head (detached)\n")
        #expect(g.branch == "1234567" && g.ahead == 0 && g.behind == 0 && !g.isDirty)
    }

    @Test func untrackedOnly() {
        #expect(GitPorcelain.parse("# branch.head main\n? a\n").untracked == 1)
    }
}
