---
name: green-eggs-and-hamify-text
description: Compose original rhyming anapestic AABB couplets from any given text — a PR summary, a review note, a suggestion — Dr. Seuss-style. Use when asked to hamify text, turn a comment or summary into a poem, or leave Seuss-style verse on a PR.
---

# green-eggs-and-hamify-text

Turn arbitrary input text into original rhyming couplets: AABB, each line
scanning as anapestic meter (7-12 syllables), verified by the same real
oracle `comment-in-the-hat` gates code comments on. Unlike
`green-eggs-and-hamify`, the input here isn't an existing source comment to
repair — it's free text to paraphrase into new verse from scratch. Never
quote or paraphrase the source book this plugin is a lighthearted nod to —
write wholly original lines.

## 1. Compress the input to its core point(s)

Read the source text and boil it down to the one or two ideas it's actually
making. A couplet only works if it carries one idea per pair, so don't try
to preserve every clause — paraphrase for meaning and let the form dictate
line breaks. A longer input becomes a chain of couplets, one couplet per
idea, not one overstuffed pair.

Paraphrase around any token the oracle can't speak (an identifier, a number,
a URL) rather than embedding it in a scanned line — this output is prose
verse, not a code comment, so there's no `cat-in-the-hat:` hatch to hoist it
onto.

## 2. Draft couplets, one idea at a time

Write two rhyming lines per idea, each within 7-12 syllables, stress falling
on the anapestic beat (da-da-DUM). Draft loosely first to get the rhyme and
meaning right, then tighten for scansion.

## 3. Verify every couplet through the same oracle the gate uses

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
trust the oracle over your ear, always. Reword and re-run until every
couplet passes both checks.

## 4. Present the result, then report honestly

Show the finished verse. If it's headed to a PR, present it as a comment
body, not a code change. Report which lines needed rework to pass the
oracle — don't claim a couplet scans or rhymes without having run it.
