# Ghosttwriter

Ghosttwriter is a macOS-only fork of Ghostty for running several Claude Code
sessions side by side. The terminal core is unchanged. Ghosttwriter adds a
workbench around it:

- **A vertical tab sidebar.** Tabs are grouped by git repo (non-repo tabs go
  under "Other", pinned tabs go in a Pinned section at the top). Each row
  shows the tab's Claude color, title, directory, branch with ↑ahead ↓behind,
  a dirty marker ●, the Claude status badge and goal progress "done/total".
  The native tab bar is never shown, and ⌘1–⌘9 follow the sidebar order.
- **A goals panel per session.** A short checklist of high-level outcomes
  that both you and Claude write to. Every add, check, uncheck and remove is
  logged with who did it and when.
- **A resume dashboard.** Closing a tab with a live Claude session asks
  "Still to finish?" and saves the session with that note. The dashboard
  reopens it in a new tab with `claude --resume`, in the same directory and
  color, with its goals intact.
- **A side pane per tab.** It shows HTML, Markdown or PDF beside the terminal
  and reloads when the file changes. Small static HTML pages appear instead
  as an inline snapshot card over the bottom of the terminal.

Claude talks to the app only through the `gtw` command, which is bundled in
the app and on `PATH` in every Ghosttwriter shell. The Claude Code plugin in
`claude-plugin/` wires Claude's hooks to `gtw hook` and teaches Claude when to
use the other `gtw` commands.

Ghosttwriter reads the same `~/.config/ghostty/config` as Ghostty and adds no
config keys. Its bundle id is `com.jonmoses.ghosttwriter`, and Sparkle updates
are off.

## Building

Requires macOS 14 or later, Xcode, Zig 0.17.0 and nushell (`brew install
nushell`).

1. Install Zig 0.17.0. `brew install zig` works if `zig version` reports
   0.17.x; otherwise put the 0.17.0 tarball from ziglang.org on `PATH`.
2. Build the core library once:

   ```sh
   zig build -Demit-macos-app=false
   ```

3. Build the app (the Debug build lands in `macos/build/Debug/Ghostty.app`,
   with `gtw` inside it at `Contents/MacOS/gtw`):

   ```sh
   macos/build.nu
   ```

Tests:

```sh
swift test --package-path macos/gtw     # gtw
sh claude-plugin/tests/hooks.sh         # plugin hooks
macos/build.nu --action test            # app unit tests
sh macos/scripts/workbench-smoke        # builds, launches the app, drives gtw, quits
sh macos/scripts/check-upstream-merge   # merge with upstream/main stays in the allowed files
```

## Installing the Claude Code plugin

From the repo root:

```sh
claude plugin marketplace add ./claude-plugin
claude plugin install ghosttwriter@ghosttwriter
```

The plugin forwards SessionStart, UserPromptSubmit, PostToolUse,
Notification, Stop and SessionEnd to `gtw hook`, and its skill tells Claude to
set 1 to 4 goals at the start of a task, check a goal only once its outcome is
verified, leave a `gtw note` when it stops with work left, and use `gtw show`
for any page it wants you to look at.

## Shell setup

In `~/.zshrc`, replace

```sh
source ~/.config/ghostty/tabcolor.zsh
```

with

```sh
source <repo>/claude-plugin/shell/ghosttwriter.zsh
```

where `<repo>` is this checkout. Ghosttwriter now picks each tab's color
itself and exports it as `TABCOLOR`; the script's `claude()` wrapper appends
`/color $TABCOLOR` under the same rules as `tabcolor.zsh` did.

## Shortcuts

| Shortcut | Action                    |
| -------- | ------------------------- |
| ⌘⌥S      | Toggle the sidebar        |
| ⌘⌥P      | Toggle the side pane      |
| ⌘⌥R      | Open the resume dashboard |
| ⌘⌥G      | Focus the goal add field  |

They are also in the Workbench menu. In the resume dashboard, Enter resumes
the selected session and ⌫ deletes it.

## `gtw` command reference

```
gtw goal add "<text>"            # prints the new goal's index (1-based)
gtw goal done <index>
gtw goal undo <index>
gtw goal rm <index>
gtw goal list [--json]            # "[x] 1. text" per line
gtw note "<text>"                 # set the session's still-to-finish note; "" clears it
gtw status done|clear             # set or clear the manual done flag
gtw show <file> [--pane|--inline]
gtw color <name>                  # change the tab color; prints "/color <name>" for the user to run in Claude
gtw hook                          # reads Claude hook JSON on stdin and forwards it
gtw info [--json]                 # surface, session record, claude session id, status
```

Global flags: `--surface <uuid>` (default `$GHOSTTWRITER_SURFACE`) and
`--socket <path>` (default `$GHOSTTWRITER_SOCKET`).

Exit codes: 0 ok, 1 the app reported an error (message on stderr), 2 usage
error, 3 app not reachable. `gtw hook` always exits 0 and prints nothing.

Goal commands run from Claude (where `CLAUDECODE=1`) are logged with author
`claude`; anything else is logged as `user`.

`gtw show` sends `.pdf` and `.md` files to the side pane. An `.html` file goes
inline only if it is at most 200 KB, has no `<script`, and renders no taller
than 600 px; otherwise it opens in the pane. `--pane` and `--inline` override
that. Inline output from Claude's Bash tool becomes a snapshot card; run by
you in a shell, it is drawn into scrollback as a Kitty graphics image.

Every Ghosttwriter shell has these set:

```
GHOSTTWRITER_SURFACE=<this surface's UUID>
TABCOLOR=<red|blue|green|yellow|purple|orange|pink|cyan>
GHOSTTWRITER_SOCKET=$HOME/Library/Application Support/Ghosttwriter/gtw.sock
```

## Where state lives

Everything is in `~/Library/Application Support/Ghosttwriter/`:

- `state.db`: SQLite (WAL mode, `PRAGMA user_version = 1`) holding session
  records, goals, the goal event log, group order and pins. Only the app
  writes it. Closed records are kept for 90 days or until there are 500 of
  them, pruned at launch.
- `gtw.sock`: the control socket `gtw` talks to (mode 0600, directory 0700).

## First real use checklist

Run once on the built app:

1. Open 8 tabs across 3 repos plus `~`. Check the groups and colors, that no
   tab bar shows, and that ⌘1–⌘9 match the sidebar.
2. Run `claude` in two tabs. The badges go working → waiting live, and a
   permission prompt shows "!".
3. Ask Claude to set goals. They appear in the panel with author claude, and
   the log lists them.
4. ⌘W one Claude tab, edit the note, save. ⌘⌥R lists it. Enter resumes the
   same session in the same cwd and color, with goals intact.
5. Quit the app with 2 Claude tabs open, relaunch, and check that both are in
   the dashboard with auto notes.
6. Ask Claude to write a small HTML mockup and `gtw show` it, which should
   give a card. Then a long report, which should open in the pane. Edit the
   report and check that the pane reloads with its scroll position kept.
7. Run `gtw show small.html` yourself in a plain shell and check that the
   image appears in scrollback.
8. Run `git merge upstream/main` on a scratch branch (or
   `sh macos/scripts/check-upstream-merge`) and check that conflicts touch
   only the upstream files Ghosttwriter edits.
