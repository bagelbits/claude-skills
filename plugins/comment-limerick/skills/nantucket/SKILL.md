---
name: nantucket
description: Rewrite existing comments into AABBA limericks to satisfy the comment-limerick gate. Use when asked to limerick-ify comments, fix rhyme/meter violations, or make comments "scan and rhyme in five lines."
---

# nantucket

Prose comments live in `/** ... */` blocks whose five lines follow AABBA
form: lines 1, 2, 5 rhyme and scan as anapestic trimeter (7-10 syllables);
lines 3, 4 rhyme and scan as anapestic dimeter (5-7 syllables). A `//` line
comment can never satisfy this — a limerick needs five lines, and a line
comment only ever gives you one.

**No humor requirement.** The gate checks rhyme and meter only. A limerick
that scans and rhymes but isn't funny already passes — don't rewrite a
passing limerick chasing a punchline.

## 1. Scan

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/limerick-scan.mjs" [paths...]
```

Path mode (`target: "paths"`) scans exactly those files; branch mode
(`target`: resolved base name, or `null` if none resolved) scans the
current branch diff. Findings carry a `kind`: `form` (a `//` prose comment,
denied outright), `meter` (a line doesn't scan for its role), `rhyme` (an
A-line or B-line doesn't rhyme with its partner — see `partnerLine`),
`block` (an unspeakable line shares a comment with verse), or `shape` (the
block's prose line count isn't a multiple of five).

## 2. Fix table

| `kind` | Action |
|---|---|
| `form` | Move the line into a `/** ... */` block. |
| `meter` | Reword until it scans for its role — see step 3, don't guess by ear. |
| `rhyme` | Change the line's last word to rhyme with its partner (named in the reason) — verify with `oracle.rhymes`, not by ear. |
| `block` | Hoist the unspeakable token onto a `nantucket:` line, or reword without it. |
| `shape` | Add lines to complete the limerick (a multiple of five), or fold the tail into the limerick above. |

## 3. Verify every rewrite through the same oracle the gate uses

```bash
node -e '
import("${CLAUDE_PLUGIN_ROOT}/vendor/comment-core/analyzers/cmudict.mjs").then(async ({ createCmudict }) => {
  const oracle = createCmudict(new URL("${CLAUDE_PLUGIN_ROOT}/vendor/cmudict-map.txt.gz", "file:///"));
  const A = { min: 7, max: 10 };
  const B = { min: 5, max: 7 };
  const lines = process.argv.slice(1);
  const roles = ["A", "A", "B", "B", "A"];
  lines.forEach((l, i) => console.log(`line ${i + 1} (${roles[i]}):`, oracle.scanMeter(l.split(/\s+/), roles[i] === "A" ? A : B)));
  console.log("1~2 rhyme:", oracle.rhymes(lines[0].split(/\s+/).pop(), lines[1].split(/\s+/).pop()));
  console.log("2~5 rhyme:", oracle.rhymes(lines[1].split(/\s+/).pop(), lines[4].split(/\s+/).pop()));
  console.log("3~4 rhyme:", oracle.rhymes(lines[2].split(/\s+/).pop(), lines[3].split(/\s+/).pop()));
});
' "line one" "line two" "line three" "line four" "line five"
```
CMU transcription can surprise you (silent letters, unexpected stress) —
trust the oracle over your ear, always.

## 4. Never touch

Shared markers, and `nantucket:`-prefixed lines — these have no positional
requirement (unlike `comment-in-the-hat`'s `cat-in-the-hat:`, a `nantucket:`
line can sit anywhere in its comment).

## 5. Present the plan, then report honestly

List every limerick you intend to rewrite before editing, with the
verified meter/rhyme check output for each line. Report exactly what
changed afterward.
