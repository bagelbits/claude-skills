# comment-haijin

Blocks new prose comments that don't fit 5-7-5 haiku form. Prose comments
must live inside a `/** ... */` block whose lines count five, seven, five
syllables; a `//` line comment is denied outright, on form alone, before its
content is ever counted. Enforced at write time and at commit/PR time, using
the same syllable counter for both, so a comment that passes locally can't
slip through at commit.

## Rule

Every prose comment in a code file must be a `/** ... */` block, and the
prose lines inside that block must scan as a haiku: five syllables, seven
syllables, five syllables, in that order. A `//` line comment can never
satisfy this — there's no way to fit three lines of verse onto one line — so
it's denied purely because of its form, without the syllable counter even
running on its content. Moving the same words into a block comment is the
fix.

## Line-comment-denied-on-form

This is the rule most likely to surprise a contributor coming from
`comment-bard`: bard checks meter regardless of comment style, but haijin
rejects every `//` prose comment immediately, before counting anything. A
haiku needs three lines to breathe in, and a line comment only ever gives
you one.

## Chain-in-threes rule

A block isn't limited to one haiku — longer notes can chain several in a
row — but the block's total prose line count must always be a whole
multiple of three (3, 6, 9, …). If a block has, say, five prose lines, the
first three are checked as a complete haiku and the trailing two are flagged
as a ragged tail, regardless of what those two lines' own syllable counts
happen to be: finish the second haiku (add one more line) or fold the tail
into the haiku above it. The fix table in the `haiku` skill covers this and
every other finding shape.

As with `comment-bard`, a block is judged as a whole for meterability too:
if any line in the block is verse, every line in that block must be. A line
containing a token the syllable counter can never speak (an identifier, a
number, a URL) is normally just skipped, but sitting next to a verse line in
the same block makes it a violation — hoist it onto its own exempt line, or
rephrase without it.

## Escape hatches

Two kinds of line are never checked:

- **Shared markers** — lines starting with `TODO`, `FIXME`, `NOTE`, `HACK`,
  `XXX`, an `eslint`/`prettier`/`biome-` directive, an `@tag`, or a bare URL.
- **`haijin:` or `bard:`-prefixed lines** — a line you mark yourself, for
  content that can never be metered (an identifier, a number, a code
  snippet). Both prefixes are recognized so a file touched by either plugin
  in its history doesn't need its exempt lines rewritten.

## Skill

`haiku` — rewrites existing comments into 5-7-5 form: converting `//` lines
into blocks, completing or folding ragged tails, and fixing individual
lines' syllable counts. It verifies every rewrite through the real syllable
counter (`vendor/comment-core/analyzers/syllable.mjs`) rather than trusting
a hand count, and reports exactly what changed. Invoke it to fix reported
violations or to haiku-ify a file ahead of time.

## Compatibility

This plugin comments in strict haiku form, so it conflicts with any other
plugin that imposes a different comment form on the same lines: install at
most one of `comment-haijin`, `comment-bard`, or `comment-in-the-hat` at a
time. It's also incompatible with `comment-reaper`, which enforces a
"why, not what" content rule orthogonal to — and sometimes at odds with — a
fixed verse form.

## Development

`vendor/comment-core` is a synced copy of `packages/comment-core` — edit the
canonical package, then run `node scripts/sync-comment-core.mjs` from the
repo root. `tests/run.sh` is the spec-as-tests; run it after any change
here.
