---
name: haiku
description: Rewrite existing comments into 5-7-5 haiku blocks to satisfy the comment-haijin gate. Use when asked to haiku-ify comments, fix haijin violations, or move // comments into a block.
---

# haiku

Prose comments live in `/** ... */` blocks whose lines count 5-7-5; a
`//` line comment cannot carry a haiku and is denied on form alone. Longer
notes chain whole haiku — a block's prose line count must be a multiple of
three. Trust the analyzer's syllable counts over your own ear.

## 1. Scan

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/haijin-scan.mjs" [paths...]
```

Path mode (`target: "paths"`) scans exactly those files; branch mode
(`target`: resolved base name, or `null` if none resolved) scans the
current branch diff.

## 2. Fix table (by finding shape)

| Situation | Action |
|---|---|
| "a line comment cannot carry a haiku…" | Convert the `//` line into a `/** ... */` block; expand or trim to a 5-7-5 triple. |
| "not meterable, yet a line in the same comment is verse…" | Hoist the unspeakable token onto its own `haijin:`-prefixed line, or rephrase without it. |
| "N prose line(s) in this block…add K more line(s)" | Add lines to complete the next whole haiku, or fold the ragged tail into the haiku above it. |
| "<got> syllable(s) on line P of the haiku, needs <want>" | Add or trim a word on that specific line — use the `<breakdown>` in the reason to find which word to touch. |

## 3. Verify every rewrite

```bash
node -e '
import("${CLAUDE_PLUGIN_ROOT}/vendor/comment-core/analyzers/syllable.mjs").then(({ countLine, breakdown }) => {
  console.log(countLine(process.argv[1]), breakdown(process.argv[1]));
});
' "your rewritten line here"
```

## 4. Never touch

Shared markers (`TODO`, `FIXME`, `NOTE`, `HACK`, `XXX`,
`eslint`/`prettier`/`biome-` directives, `@tags`, bare URLs), and
`haijin:`/`bard:`-prefixed lines.

## 5. Present the plan, then report honestly

List every block you intend to reshape, with before/after line counts and
syllable counts, before editing. Report exactly what changed afterward —
don't claim a block scans without running it through the counter above.
