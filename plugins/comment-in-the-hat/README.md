# comment-in-the-hat

Blocks new prose comments that don't pair into rhyming couplets scanning as
anapestic meter — Dr. Seuss-style doggerel form (AABB, 7-12 syllables per
line). Enforced at write time and at commit/PR time, using the same real CMU
Pronouncing Dictionary oracle for both, so a comment that passes locally
can't slip through at commit.

## Rule

Consecutive prose comment lines in a code file — whether `//` line comments
or the lines inside a `/** ... */` block — are read in order and grouped
into couplets, two lines at a time. Each line of a couplet must independently
scan as anapestic meter: 7 to 12 syllables, stress falling on the beat. The
two lines of a couplet must also rhyme with each other, judged by the last
word of each line. A block can chain multiple couplets in a row; every prose
line still has to belong to a pair. A lone trailing prose line with no
partner — an odd count in its comment — is denied as unpaired, even if that
line scans perfectly fine on its own; add a second, rhyming line, or drop it.

Meter and rhyme are both decided by a real pronouncing-dictionary oracle
(`vendor/comment-core/analyzers/cmudict.mjs`, backed by
`vendor/cmudict-map.txt.gz`), not a hand-rolled heuristic — the same oracle
the write and commit gates use, and the one `tests/run.sh` asserts against
directly.

## The `cat-in-the-hat:` hatch

A line the oracle can't speak — an identifier, a number, a URL, a code
snippet — normally just drops out of scanning on its own. But if a comment
mixes a genuinely unspeakable line with couplet verse, that combination is
flagged (`block`): hoist the unspeakable token out of the way instead. A
`cat-in-the-hat:`-prefixed line does that: it's never scanned, and it must
sit at the very top of its comment, above every couplet line. Put it
anywhere else in the comment and it's flagged too (`hoist`) — the hatch only
works from the top. Shared markers (`TODO`, `FIXME`, `NOTE`, `HACK`, `XXX`,
`eslint`/`prettier`/`biome-` directives, `@tag`s, bare URLs) are exempt the
same way, no prefix needed.

## Known deviation: the AA/AO fold

CMU's dictionary transcribes the cot/caught merger (`AA` vs `AO`) as two
distinct phonemes, but many English speakers don't hear them as different.
The vendored oracle folds `AO` into `AA` when building the rhyme key, so
word pairs most readers hear as rhyming aren't rejected on a phonemic
distinction they wouldn't notice. This is a deliberate choice, not a bug —
see `vendor/VENDOR.md` for the full rationale and the alternative that was
considered and not taken.

## Skills

`green-eggs-and-hamify` — rewrites existing comments into rhyming anapestic
AABB couplets: converting stray line comments into paired couplets,
completing unpaired lines, fixing meter, and re-hoisting misplaced
`cat-in-the-hat:` lines. It verifies every rewrite through the same real
oracle the gate uses (`oracle.scanMeter`, `oracle.rhymes`) rather than
trusting scansion by ear, and reports exactly what changed. Invoke it to fix
reported violations or to hamify a file ahead of time.

`green-eggs-and-hamify-text` — composes original AABB couplets from any
given text (a PR summary, a review note, a suggestion) rather than repairing
an existing comment. Verified through the same oracle. Invoke it to leave a
Seuss-style poem as a PR comment.

`green-eggs-and-hamify-pr-comment` — formats a PR review (a top-level verdict
plus per-finding inline comments) as Dr. Seuss doggerel without losing any
technical substance: each finding pairs a 4-line AABB rhyme with a plain-text
explanation and concrete fix, then posts the whole thing as one review via
`gh api .../pulls/:number/reviews`. Unlike the gate above, this skill doesn't
touch code comments — it's for hamifying the review *of* a PR, and always
previews the full output before posting.

## Turning Off The Gate

Set `COMMENT_HAT_OFF=1` to silence the write and commit/PR gates without
disabling the plugin — the `green-eggs-and-hamify` skill stays available.

- **Session only:** `export COMMENT_HAT_OFF=1` before launching Claude Code.
- **Persistent:** add it to `.claude/settings.json`, then delete the line to
  re-arm the gate:
  ```json
  { "env": { "COMMENT_HAT_OFF": "1" } }
  ```

## Compatibility

This plugin imposes its own fixed verse form on comments, so it conflicts
with any other plugin that imposes a different one on the same lines:
install at most one of `comment-in-the-hat`, `comment-bard`, or
`comment-haijin` at a time. It's also incompatible with `comment-reaper`,
which enforces a "why, not what" content rule orthogonal to — and sometimes
at odds with — a fixed verse form.

## Development

`vendor/comment-core` is a synced copy of `packages/comment-core` — edit the
canonical package, then run `node scripts/sync-comment-core.mjs` from the
repo root. `vendor/cmudict-map.txt.gz`, `vendor/LICENSE-cmudict`, and
`vendor/VENDOR.md` are plugin-local and untouched by that sync; rebuild the
map with `scripts/build-cmudict.mjs` per the instructions in
`vendor/VENDOR.md` if the pinned CMU dictionary commit ever needs to move.
`tests/run.sh` is the spec-as-tests, including real-oracle assertions
against the vendored map itself; run it after any change here.
