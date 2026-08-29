# comment-bard

Blocks new prose comments that don't scan as iambic pentameter — every
comment line in a code file must be exactly ten syllables. Enforced at write
time and at commit/PR time, using the same syllable counter for both, so a
line that passes locally can't slip through at commit.

## Rule

Every prose line inside a `//` comment or a `/** ... */` block must scan as
exactly ten syllables (iambic pentameter — the meter isn't stress-checked,
only the syllable count is). A line that comes in over or under ten
syllables is denied, with the exact count and a word-by-word breakdown so
you can see which word to add or cut.

## Mixed-block rule

A `/** ... */` block is judged as a whole: if any line in the block scans as
a metered ten-syllable line, then every other line in that same block must
also scan. A line that contains a token the syllable counter can never speak
— an identifier, a number, a URL — is normally just skipped rather than
counted, but sitting next to a line that does scan makes it a violation: a
block reads as all verse or all plain, never a mix. Hoist the unspeakable
token onto its own exempt line, or rephrase the line without it.

## Escape hatches

Two kinds of line are never checked for meter:

- **Shared markers** — lines starting with `TODO`, `FIXME`, `NOTE`, `HACK`,
  `XXX`, an `eslint`/`prettier`/`biome-` directive, an `@tag`, or a bare URL.
- **`bard:`-prefixed lines** — a line you mark yourself, for content that can
  never be metered (an identifier, a number, a code snippet).

## Skill

`verse` — rewrites existing comments into iambic pentameter, verifying each
rewrite through the real syllable counter rather than a hand count. Invoke
it to fix reported violations or to versify a file ahead of time.

## Turning Off The Gate

Set `COMMENT_BARD_OFF=1` to silence the write and commit/PR gates without
disabling the plugin — the `verse` skill stays available.

- **Session only:** `export COMMENT_BARD_OFF=1` before launching Claude Code.
- **Persistent:** add it to `.claude/settings.json`, then delete the line to
  re-arm the gate:
  ```json
  { "env": { "COMMENT_BARD_OFF": "1" } }
  ```

## Compatibility

This plugin comments in strict iambic pentameter, so it conflicts with any
other plugin that imposes a different comment form on the same lines: install
at most one of `comment-bard`, `comment-haijin`, or `comment-in-the-hat` at a
time. It's also incompatible with `comment-reaper`, which enforces a
"why, not what" content rule orthogonal to — and sometimes at odds with —
a fixed syllable count.

## Development

`vendor/comment-core` is a synced copy of `packages/comment-core` — edit the
canonical package, then run `node scripts/sync-comment-core.mjs` from the
repo root. `tests/run.sh` is the spec-as-tests; run it after any change here.
