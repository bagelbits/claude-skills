# comment-reaper

Blocks new comments that narrate what code already says, hide commented-out
dead code, or stack 3+ lines that should be a `/** ... */` block. Conservative
by design — flags only near-certain junk, so the same analyzer can safely
block a write, not just warn.

## Rule

Comment the non-obvious *why*, never the *what*. See the global CLAUDE.md
house rule this plugin encodes.

## Escape hatches

Lines starting with `ponytail:`, `eslint`, `@ts-`, `prettier`, `biome-`,
`c8 `, `istanbul `, `v8 `, `TODO`, `FIXME`, `NOTE`, `HACK`, `XXX`, or a bare
URL are never flagged.

## Skill

`reap` — cleans up existing comments beyond what the write/commit gates catch.
Invoke it to audit a branch or a set of files.

## Compatibility

This plugin wants redundant comments removed, so it's incompatible with
`comment-bard`, `comment-haijin`, and `comment-in-the-hat`, which all want
comments versified into a fixed form — a "why, not what" content rule is
orthogonal to, and sometimes at odds with, enforcing meter or rhyme on the
same lines.

## Development

`vendor/comment-core` is a synced copy of `packages/comment-core` — edit the
canonical package, then run `node scripts/sync-comment-core.mjs` from the
repo root. `tests/run.sh` is the spec-as-tests; run it after any change here.
