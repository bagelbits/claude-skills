---
name: reap
description: Aggressively cull redundant, narrating, or commented-out comments per the comment-reaper house rule (why, not what). Use when asked to clean up comments, audit comments, or "reap" comments in changed or specified files.
---

# reap

Comment the non-obvious *why*, never the *what*. The gate hooks only block
*new* violations on write/commit — this skill goes back and cleans up what's
already there.

## 1. Scan

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/reaper-scan.mjs" [paths...]
```

With paths: scans exactly those files (`target: "paths"`). With none:
scans the branch diff (`target` is the resolved base branch name, or
`null` if none resolved — `null` is not "clean", it means fall back to
asking the user for paths).

`files` lists every path actually read — a missing/unreadable path is
silently absent, don't assume it was clean. `findings` is
`{file, line, text, reason}[]`.

## 2. Read every comment, not just findings

The scan is conservative by design — a floor, not a ceiling. Read every
comment in `files` and apply the self-evident test: if removing it wouldn't
confuse a future reader, delete it.

## 3. Fix table

| Situation | Action |
|---|---|
| `reason: "commented-out code"` | Delete the dead code entirely. |
| `reason: 'reads as "what", not "why"'` | Delete, or replace with the real non-obvious reason if one exists. |
| `reason: "N consecutive comment lines — use a block comment"` | Convert to `/** ... */` if worth keeping; otherwise delete. |
| Unflagged but narrates what code already says | Delete anyway. |
| Explains a real non-obvious constraint, workaround, or invariant | Keep, tighten the wording. |

Never touch lines starting with: `ponytail:`, `eslint`, `@ts-`,
`prettier`, `biome-`, `c8 `, `istanbul `, `v8 `, `TODO`, `FIXME`,
`NOTE`, `HACK`, `XXX`, or a bare URL.

## 4. Present the plan before editing

List what you intend to delete/rewrite/keep, file by file, before touching
anything — a "narrating" comment might be load-bearing docs for an external
reader the scan can't see.

## 5. Report honestly

State exactly what you removed and kept, and why. Don't invent extra cleanup
beyond comments — this skill is comment-only.
