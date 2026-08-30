# comment-limerick

Blocks new prose comments that don't fit AABBA limerick form — five lines,
lines 1/2/5 rhyming and scanning as anapestic trimeter (7-10 syllables),
lines 3/4 rhyming and scanning as anapestic dimeter (5-7 syllables).
Enforced at write time and at commit/PR time, using the same real CMU
Pronouncing Dictionary oracle for both, so a comment that passes locally
can't slip through at commit. No humor requirement — form only.

## Rule

Prose comments must live inside a `/** ... */` block — a `//` line comment
is denied on form alone, before content is even checked, since a limerick
needs five lines and a line comment only ever gives you one.

Within a block, prose lines group into limericks five at a time, read in
order:

| Line | Role | Rhymes with | Meter |
|---|---|---|---|
| 1 | A | 2, 5 | anapestic, 7-10 syllables |
| 2 | A | 1, 5 | anapestic, 7-10 syllables |
| 3 | B | 4 | anapestic, 5-7 syllables |
| 4 | B | 3 | anapestic, 5-7 syllables |
| 5 | A | 1, 2 | anapestic, 7-10 syllables |

A block can chain multiple limericks in a row; a block's total prose line
count must be a multiple of five. Lines past the last complete multiple of
five are flagged as a ragged tail, regardless of their own scan or rhyme —
finish the limerick, or fold the tail into the one above it.

Meter and rhyme are both decided by the same real pronouncing-dictionary
oracle `comment-in-the-hat` uses (`vendor/comment-core/analyzers/cmudict.mjs`,
backed by `vendor/cmudict-map.txt.gz`), not a hand-rolled heuristic.

## The `nantucket:` hatch

A line the oracle can't speak — an identifier, a number, a URL, a code
snippet — normally just drops out of scanning on its own. But if a comment
mixes a genuinely unspeakable line with limerick verse, that combination is
flagged: hoist the unspeakable token out of the way instead. A
`nantucket:`-prefixed line does that: it's never scanned, and — unlike
`comment-in-the-hat`'s `cat-in-the-hat:` — it has no positional requirement,
it can sit anywhere in its comment. Shared markers (`TODO`, `FIXME`, `NOTE`,
`HACK`, `XXX`, `eslint`/`prettier`/`biome-` directives, `@tag`s, bare URLs)
are exempt the same way, no prefix needed.

## No humor requirement

The gate checks rhyme and meter only. A limerick that scans and rhymes but
isn't funny still passes.

## Skill

`nantucket` — rewrites existing comments into AABBA limericks: converting
stray prose into complete five-line limericks, completing a short group,
fixing meter per line-role, fixing rhyme, and re-hoisting `nantucket:` lines
that ended up mixed into scanned content. It verifies every rewrite through
the same real oracle the gate uses (`oracle.scanMeter`, `oracle.rhymes`)
rather than trusting scansion by ear, and reports exactly what changed.

## Turning Off The Gate

Set `COMMENT_LIMERICK_OFF=1` to silence the write and commit/PR gates
without disabling the plugin — the `nantucket` skill stays available.

- **Session only:** `export COMMENT_LIMERICK_OFF=1` before launching Claude Code.
- **Persistent:** add it to `.claude/settings.json`, then delete the line to
  re-arm the gate:
  ```json
  { "env": { "COMMENT_LIMERICK_OFF": "1" } }
  ```

## Compatibility

This plugin imposes its own fixed verse form on comments, so it conflicts
with any other plugin that imposes a different one on the same lines:
install at most one of `comment-bard`, `comment-haijin`, `comment-in-the-hat`,
or `comment-limerick` at a time. It's also incompatible with
`comment-reaper`, which enforces a "why, not what" content rule orthogonal
to — and sometimes at odds with — a fixed verse form.

## Development

`vendor/comment-core` is a synced copy of `packages/comment-core` — edit the
canonical package, then run `node scripts/sync-comment-core.mjs` from the
repo root. `vendor/cmudict-map.txt.gz`, `vendor/LICENSE-cmudict`, and
`vendor/VENDOR.md` are plugin-local and untouched by that sync — see
`vendor/VENDOR.md` if the pinned CMU dictionary commit ever needs to move.
`tests/run.sh` is the spec-as-tests, including real-oracle assertions
against the vendored map itself; run it after any change here.
