# Backlog

One line per item: `- YYYY-MM-DD · what · why: ... · from: plan-slug`. Pruned at every ship.

- 2026-11-09 · Built app's name still shows "Ghostty": generated Info.plist takes CFBundleName from $(PRODUCT_NAME) · why: constraint 2 asks for product name Ghosttwriter · from: ghosttwriter-v1
- 2026-11-09 · Install swiftlint and lint every new Workbench and gtw Swift file · why: no new file has been linted · from: ghosttwriter-v1
- 2026-11-09 · DockTilePlugin still reads UserDefaults suites com.mitchellh.ghostty* · why: custom dock icon no longer follows the app's setting under com.jonmoses.ghosttwriter · from: ghosttwriter-v1
- 2026-11-09 · Refresh git status immediately on pwd change, not only on the 5 s poll · why: constraint 11 · from: ghosttwriter-v1
- 2026-11-09 · Ghostty's native Move Tab actions can reorder tabs against the sidebar until it re-syncs · why: constraint 4 (⌘1–⌘9 follow sidebar order) · from: ghosttwriter-v1
- 2026-11-09 · WorkbenchStore.swift:77 a split left as a tab's only surface drops out of ColorAllocator counts · why: its color can be handed to a new tab · from: ghosttwriter-v1
- 2026-11-09 · Exercise undo-close of a tab or split, and dragging a split into a new tab, in the live app · why: only checked by reading the code · from: ghosttwriter-v1
- 2026-11-09 · surfaceClosed runs at SurfaceView deinit, so a closed tab's record is saved when undo expires · why: a crash in that window loses the save · from: ghosttwriter-v1
- 2026-11-09 · Quick-terminal surfaces get WorkbenchEnvironment and take part in color allocation (SurfaceView_AppKit.swift:392) · why: they are not tabs · from: ghosttwriter-v1
- 2026-11-09 · Build gtw phase is alwaysOutOfDate with a hand-kept inputPaths list (project.pbxproj:70) · why: runs every build; new gtw files must be added by hand · from: ghosttwriter-v1
- 2026-11-09 · TabGroupBridge is created one run-loop turn after the window appears (WorkbenchContainer.swift:70) to avoid the launch AttributeGraph trap · why: confirm the sidebar renders on every launch · from: ghosttwriter-v1
- 2026-11-09 · WorkbenchSidebar.body reads window.tabGroup during updates · why: safe only because the bridge created the group first · from: ghosttwriter-v1
- 2026-11-09 · TabGroupBridge.hideTabBar uses private selector _setTabBarIsVisible:force: (TabGroupBridge.swift:98) · why: a rename in AppKit breaks constraint 4 · from: ghosttwriter-v1
- 2026-11-09 · TabGroupBridge.move fires KVO on the intermediate state between removeWindow and insertWindow (TabGroupBridge.swift:52) · why: observers see a 4-tab group mid-move · from: ghosttwriter-v1
- 2026-11-09 · ProcessGitRunner reads stdout to EOF before checking the timeout and kills only git, not its process group (GitStatusService.swift:58,111) · why: a grandchild holding the pipe defeats the 2 s timeout · from: ghosttwriter-v1
- 2026-11-09 · A timeout or error in rev-parse --show-toplevel is treated as "not a repo" (GitStatusService.swift:112) · why: a slow repo moves to "Other" instead of showing "?" · from: ghosttwriter-v1
- 2026-11-09 · Git poll Timer registers in the default run-loop mode only (GitStatusService.swift:152) · why: no refresh while a menu or drag is tracking · from: ghosttwriter-v1
- 2026-11-09 · Git slot release goes through an unstructured Task in a defer (GitStatusService.swift:174) · why: release order is not guaranteed · from: ghosttwriter-v1
- 2026-11-09 · WorkbenchStore.transact does not restore liveSurfaces on failure (WorkbenchStore.swift:551) · why: a failed attach can leave a changed color in memory · from: ghosttwriter-v1
- 2026-11-09 · setNote has no author, so every note event is logged as user (WorkbenchStore.swift:303) · why: notes Claude sets via gtw are misattributed · from: ghosttwriter-v1
- 2026-11-09 · Crash recovery closes every orphaned record, even ones with no Claude id, goals or note (WorkbenchStore.swift:126) · why: clutters the resume dashboard · from: ghosttwriter-v1
- 2026-11-09 · Tests for deleteRecord + goal-event cascade, crash-orphan recovery, and ui_state persistence of group order and pins · why: constraint 19 and restore paths are untested · from: ghosttwriter-v1
- 2026-11-09 · Tests for the ControlServer show timeout and bad-request decode path · why: constraint 15 path is untested · from: ghosttwriter-v1
- 2026-11-09 · SocketListener deinit calls stop() via queue.sync, and SO_RCVTIMEO is per read, not per request (SocketListener.swift:405,462) · why: deadlock risk if deinit runs on the queue; slow clients can hold a connection · from: ghosttwriter-v1
- 2026-11-09 · gtw parseGlobals strips --surface/--socket anywhere in argv, including inside goal or note text (Gtw.swift:154) · why: such text is silently altered · from: ghosttwriter-v1
- 2026-11-09 · GoalsPanel swipeActions on goal rows do nothing (GoalsPanel.swift:110) · why: dead UI on macOS List · from: ghosttwriter-v1
- 2026-11-09 · NSCursor push/pop in onHover can unbalance the cursor stack (WorkbenchSidebar.swift:490, SidePane.swift:84) · why: wrong cursor sticks after a drag handle disappears · from: ghosttwriter-v1
- 2026-11-09 · SidePane loadHTMLString fallback leaves temp pages, never swept after a crash, and the read grant is often "/" (SidePane.swift:197) · why: temp files leak; read access wider than needed · from: ghosttwriter-v1
- 2026-11-09 · SnapshotRenderer.render has no timeout or cancellation (SnapshotRenderer.swift:167) · why: a page that never finishes loading hangs its show request · from: ghosttwriter-v1
- 2026-11-09 · Snapshot card PNGs in NSTemporaryDirectory are never deleted (WorkbenchShowRouter.swift:261) · why: temp files leak · from: ghosttwriter-v1
- 2026-11-09 · ShowRouting.renderWidth is zero or negative for terminal width under 24 pt (ShowRouting.swift:61) · why: renderer gets an invalid width · from: ghosttwriter-v1
- 2026-11-09 · Snapshot card Esc/focus dismissal not checked visually · why: only unit-tested · from: ghosttwriter-v1
- 2026-11-09 · A repeated close request while the close sheet is open queues a second sheet (WorkbenchCloseHook.swift:54) · why: double ⌘W shows two sheets · from: ghosttwriter-v1
- 2026-11-09 · CloseDecisionTests subtitle test depends on the English locale (CloseDecisionTests.swift:58) · why: fails on other locales · from: ghosttwriter-v1
- 2026-11-09 · workbench-smoke leaves the app running when it fails after launch, and uses the real Application Support dir with a GUI launch · why: not CI-safe · from: ghosttwriter-v1
- 2026-11-09 · check-upstream-merge prints "upstream merge ok ()" when there are no conflicts (check-upstream-merge:9) · why: cosmetic · from: ghosttwriter-v1
