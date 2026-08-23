---
name: verse
description: Rewrite existing comments into iambic pentameter (exactly ten syllables per prose line) to satisfy the comment-bard gate. Use when asked to versify comments, fix bard violations, or make comments "scan."
---

# verse

Every prose comment line in a code file must scan as iambic pentameter —
exactly ten syllables. Trust the analyzer over your own ear; hand-counting
syllables is unreliable, the tool isn't.

## 1. Scan

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/bard-scan.mjs" [paths...]
```

Path mode (`target: "paths"`) scans exactly those files. Branch mode
(`target`: the resolved base name, or `null` if none resolved — `null`
is not "clean") scans the current branch diff. `files` lists every path
actually read.

## 2. Fix table (by finding shape)

| Situation | Action |
|---|---|
| `"<n> syllable(s), needs 10 (<breakdown>)"`, n < 10 | Add a word or syllable without changing meaning. |
| `"<n> syllable(s), needs 10 (<breakdown>)"`, n > 10 | Trim a word; prefer a shorter synonym over dropping content. |
| Mixed-block reason (not meterable, yet a line in the block scans) | Hoist the unmetered token onto its own `bard:`-prefixed line, or rephrase without the code identifier/number/URL that made it unspeakable. |

The `<breakdown>` field (`word/n word/n …`) shows exactly which word the
count came from — use it to find the syllable to add or cut, don't guess.

## 3. Verify every rewrite through the same counter the gate uses

```bash
node -e '
import("${CLAUDE_PLUGIN_ROOT}/vendor/comment-core/analyzers/syllable.mjs").then(({ countLine, breakdown }) => {
  console.log(countLine(process.argv[1]), breakdown(process.argv[1]));
});
' "your rewritten line here"
```
Don't trust your ear or a mental count — the vendored counter has its own
exception table and desilencing rules; only it decides what the gate accepts.

## 4. Never touch

Lines matching the shared exempt markers (`TODO`, `FIXME`, `NOTE`,
`HACK`, `XXX`, `eslint`/`prettier`/`biome-` directives, `@tags`,
bare URLs) or a `bard:`-prefixed line — these are exempt by design, not
bugs to fix.

## 5. Present the plan, then report honestly

List every line you intend to rewrite and its before/after syllable count
before editing. After editing, report exactly what changed — don't claim a
line scans without having run it through the counter above.
