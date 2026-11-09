---
name: ghosttwriter
description: Use in a Ghosttwriter terminal (GHOSTTWRITER_SURFACE is set) when starting a task, finishing one, stopping with work left, or showing the user an HTML, Markdown or PDF file
---

# Ghosttwriter

Ghosttwriter shows this session's goals, note and status in its sidebar. Report them with `gtw`.

If `GHOSTTWRITER_SURFACE` is unset, you are not in Ghosttwriter: do nothing and ignore the rest of this skill.

## Starting a task

Add 1 to 4 high-level goals with `gtw goal add`. Goals are outcomes, not steps.

```sh
gtw goal add "identify the source of the bug"
gtw goal add "fix it with a regression test"
```

`gtw goal add` prints the new goal's number. `gtw goal list` shows them all.

## Finishing a goal

Run `gtw goal done <n>` only after the outcome has been verified, for example after the test passes or you have seen the fix work. Never check a goal you have only attempted.

## Stopping with work left

Before you stop with work left, set the still-to-finish note so the user can pick it up later:

```sh
gtw note "- fix the flaky retry test
- update the changelog"
```

`gtw note ""` clears it once nothing is left.

## Showing the user a file

Use `gtw show <file>` for any HTML, Markdown or PDF file the user should look at.

- `gtw show mockup.html --inline` for a small mockup, drawn in the terminal.
- `gtw show report.md --pane` for a document, opened in the side pane.
- Without a flag, Ghosttwriter picks.
