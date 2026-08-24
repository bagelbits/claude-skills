---
name: green-eggs-and-hamify
description: Rewrite existing comments into rhyming anapestic AABB couplets to satisfy the comment-in-the-hat gate. Use when asked to hamify comments, fix rhyme/meter violations, or make comments "scan and rhyme."
---

# green-eggs-and-hamify

Consecutive prose comment lines must pair into rhyming AABB couplets, each
line scanning as anapestic meter (7-12 syllables). Never quote or paraphrase
the source book this plugin is a lighthearted nod to — write original lines.

## 1. Scan

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/hat-scan.mjs" [paths...]
```

Findings carry a `kind`: `meter` (doesn't scan anapestic), `hoist` (a
`cat-in-the-hat:` escape line sits below prose instead of at the top),
`block` (an unspeakable line shares a comment with verse), `rhyme` (a
couplet's second line doesn't rhyme with its partner — see `partnerLine`),
or `unpaired` (an odd trailing line with no rhyme partner).

## 2. Fix table

| `kind` | Action |
|---|---|
| `meter` | Reword until it scans — see step 3, don't guess by ear. |
| `hoist` | Move the `cat-in-the-hat:` line to the top of the comment. |
| `block` | Hoist the unspeakable token onto a `cat-in-the-hat:` line, or reword without it. |
| `rhyme` | Change the line's last word to rhyme with its partner (named in the reason) — verify with `oracle.rhymes`, not by ear. |
| `unpaired` | Add a second, rhyming line to complete the couplet, or delete the odd one out. |

## 3. Verify every rewrite through the same oracle the gate uses

```bash
node -e '
import("${CLAUDE_PLUGIN_ROOT}/vendor/comment-core/analyzers/cmudict.mjs").then(async ({ createCmudict }) => {
  const oracle = createCmudict(new URL("${CLAUDE_PLUGIN_ROOT}/vendor/cmudict-map.txt.gz", "file:///"));
  console.log("meter A:", oracle.scanMeter(process.argv[1].split(/\s+/)));
  console.log("meter B:", oracle.scanMeter(process.argv[2].split(/\s+/)));
  console.log("rhymes:", oracle.rhymes(process.argv[1].split(/\s+/).pop(), process.argv[2].split(/\s+/).pop()));
});
' "line one" "line two"
```
CMU transcription can surprise you (silent letters, unexpected stress) —
trust the oracle over your ear, always.

## 4. Never touch

Shared markers, and `cat-in-the-hat:`-prefixed lines already at the top of
their comment.

## 5. Present the plan, then report honestly

List every couplet you intend to rewrite before editing, with the verified
meter/rhyme check output for each. Report exactly what changed afterward.
