# comment-limerick Design

## Goal

Add `comment-limerick`, a fifth `comment-*` plugin, as a sibling to
`comment-bard`, `comment-haijin`, and `comment-in-the-hat`. It gates new
prose comments on AABBA limerick form: five lines, lines 1/2/5 (the "A"
lines) rhyming with each other and scanning as anapestic trimeter, lines 3/4
(the "B" lines) rhyming with each other and scanning as anapestic dimeter.
Enforced at write time and commit/PR time, using the same real CMU
Pronouncing Dictionary oracle `comment-in-the-hat` already uses for both.

No humor requirement — form only. A limerick that scans and rhymes but
isn't funny still passes.

## Non-goals

- Not touching `comment-reaper`'s content-based rule.
- Not changing `comment-bard`'s or `comment-haijin`'s enforced behavior —
  the one shared-code change (below) is additive and defaults to the exact
  current `comment-in-the-hat` behavior.
- Not re-fetching or re-parsing the CMU dictionary from source; the new
  plugin vendors a copy of the same pinned, already-built data
  `comment-in-the-hat` ships.

## Shared-code change: parameterize `scanMeter`

`packages/comment-core/analyzers/cmudict.mjs`'s `scanMeter(words)` and its
internal `scanConstraint(C)` currently hardcode the 7–12 syllable window
`comment-in-the-hat` needs for its AABB couplets. The underlying stress
check (`strongAt`: last syllable of the line is stressed, and every third
syllable counting back from the end is stressed — the anapestic "da-da-DUM"
pattern) is already independent of line length.

Change the signature to `scanMeter(words, { min = 7, max = 12 } = {})`,
threading `min`/`max` into `scanConstraint(C, min, max)` and into the
too-short/too-long error message (`` `${len} syllable(s), needs ${min}–${max}
for anapestic meter` ``). Every existing call site (`comment-in-the-hat`'s
`hat-rules.mjs`) omits the second argument, so its behavior — and its
existing tests — are unchanged.

Edit the canonical `packages/comment-core`, run
`node scripts/sync-comment-core.mjs` from the repo root to re-vendor into
all plugins (`comment-reaper`, `comment-bard`, `comment-haijin`,
`comment-in-the-hat`, and the new `comment-limerick`).

`comment-limerick` calls the parameterized form directly:
- A-lines (1, 2, 5): `scanMeter(words, { min: 7, max: 10 })`
- B-lines (3, 4): `scanMeter(words, { min: 5, max: 7 })`

## Rule

Prose comments must live in a `/** ... */` block. A `//` line comment is
denied on form alone, before content is checked — a limerick needs five
lines and a line comment only ever gives one (same posture as
`comment-haijin` toward haiku).

Within a block, prose lines group into limericks five at a time, read in
order:

| Position | Role | Rhymes with | Meter |
|---|---|---|---|
| 1 | A | 2, 5 | anapestic, 7–10 syllables |
| 2 | A | 1, 5 | anapestic, 7–10 syllables |
| 3 | B | 4 | anapestic, 5–7 syllables |
| 4 | B | 3 | anapestic, 5–7 syllables |
| 5 | A | 1, 2 | anapestic, 7–10 syllables |

Rhyme is checked as a chain (line1~line2, line2~line5, line3~line4) via
`oracle.rhymes()` — since the oracle's rhyme key is exact match, a chain of
adjacent pairs implies all three A-lines share a rhyme, no separate
all-pairs check needed.

A block can chain multiple limericks — total prose line count must be a
multiple of 5. A count that isn't is a ragged tail: the lines beyond the
last complete multiple of 5 are flagged, regardless of their own
scan/rhyme, mirroring `comment-haijin`'s `shapeReason`.

As with the other two form plugins, a block is judged as a whole for
meterability: if any prose line in the block is part of a scanning-checked
group, an unspeakable (OOV) line in that same block is flagged rather than
silently skipped, pointing at the hatch below.

## Hatch and exemptions

`nantucket:`-prefixed lines are exempt from scanning — no positional
requirement (unlike `comment-in-the-hat`'s `cat-in-the-hat:`, which must sit
at the top of its comment; `comment-limerick` follows `comment-haijin`'s
simpler "exempt anywhere" behavior instead, since positional grouping here
is already handled by the five-line role table above). Shared markers
(`TODO`, `FIXME`, `NOTE`, `HACK`, `XXX`, `eslint`/`prettier`/`biome-`
directives, `@tag`s, bare URLs) are exempt the same way, no prefix needed —
reuse `makeExempt("nantucket:")`.

## Vendoring

`comment-limerick` vendors:
- `vendor/comment-core/` — synced copy, same as every plugin.
- `vendor/cmudict-map.txt.gz`, `vendor/LICENSE-cmudict`, `vendor/VENDOR.md` —
  copied verbatim from `comment-in-the-hat`'s vendor directory (same pinned
  CMU commit, same build). No re-fetch from network; the data is
  content-identical, only the consuming plugin differs.

## Files

Mirrors `comment-bard`'s layout, since both plugins gate on line-level scan
checks plus (for limerick) rhyme:

```
plugins/comment-limerick/
  .claude-plugin/plugin.json
  README.md
  hooks/
    hooks.json
    limerick-rules.mjs         # analyzeLines/analyzeDiff/diffFindings/denyReason
    limerick-filter.mjs        # write-time PreToolUse gate
    pre-pr-limerick-check.mjs  # commit/PR gate
  scripts/
    limerick-scan.mjs          # ad hoc / CI scan entrypoint
  skills/
    nantucket/SKILL.md         # rewrite skill
  tests/
    run.sh
  vendor/
    comment-core/              # synced
    cmudict-map.txt.gz         # copied from comment-in-the-hat
    LICENSE-cmudict
    VENDOR.md
```

`limerick-rules.mjs` follows `hat-rules.mjs`'s shape (it's the closest
existing sibling — rhyme plus real-oracle meter) adapted from couplets to
the five-line role table above, and from `oracle.scanMeter(words)` to
`oracle.scanMeter(words, { min, max })` per role.

## Skill: `nantucket`

Rewrites existing comments into AABBA limerick form: converting stray prose
into complete five-line limericks, completing a short group, fixing meter
per line-role (trimeter for A-lines, dimeter for B-lines), fixing rhyme,
and re-hoisting `nantucket:` lines that ended up mixed into scanned
content. Verifies every rewrite through the real oracle
(`oracle.scanMeter`, `oracle.rhymes`) rather than trusting scansion by ear,
and reports exactly what changed — same discipline as
`green-eggs-and-hamify` and `verse`.

## Compatibility

Add `comment-limerick` to the mutual-exclusion note in all four sibling
READMEs (`comment-bard`, `comment-haijin`, `comment-in-the-hat`,
`comment-limerick`): install at most one of the four verse-form plugins at
a time. `comment-limerick` is incompatible with `comment-reaper` for the
same reason the others are — a fixed verse form is orthogonal to (and
sometimes at odds with) a "why, not what" content rule.

## Testing

`tests/run.sh` follows the existing pattern (spec-as-tests, real-oracle
assertions against the vendored map): valid five-line limericks pass; a
non-rhyming A-line, a non-rhyming B-line, an A-line out of the 7–10
syllable window, a B-line out of the 5–7 syllable window, a `//` prose
comment (denied on form), a ragged tail (block with 6 or 8 prose lines),
and a `nantucket:` hatch line all get dedicated cases. Also add one test to
`comment-in-the-hat`'s `tests/run.sh` (or confirm existing tests still
pass) proving `scanMeter(words)` called with no options is unchanged after
the parameterization.

## Open items resolved during brainstorming

- Naming: plugin `comment-limerick`, rewrite skill `nantucket`, hatch
  marker `nantucket:`.
- Meter strictness: full anapestic stress-check (not syllable-count-only),
  via the parameterized shared `scanMeter`.
- A-line/B-line syllable ranges: 7–10 and 5–7 respectively.
