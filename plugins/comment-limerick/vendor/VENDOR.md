# Vendored data: CMU Pronouncing Dictionary

Source: https://github.com/cmusphinx/cmudict, commit `74790861f652b15e4ac49015a90074ad62a27690`.
License: BSD-2-Clause (`LICENSE-cmudict`, verbatim from the pinned commit).

Copied verbatim from `comment-in-the-hat`'s vendor directory — same pinned
commit, same build, no re-fetch. `comment-limerick` is the second plugin
that needs the CMU rhyme/meter oracle, so it carries its own copy rather
than sharing `comment-in-the-hat`'s (each plugin is a self-contained,
independently-installable unit — see `scripts/build-cmudict.mjs` if the
pinned commit ever needs to move):
```bash
SHA=74790861f652b15e4ac49015a90074ad62a27690
curl -fsSL "https://raw.githubusercontent.com/cmusphinx/cmudict/$SHA/cmudict.dict" \
  | node scripts/build-cmudict.mjs > vendor/cmudict-map.txt.gz
```
Refuses to build if fewer than 100,000 words parse (expect ~126k) — a
truncated fetch fails loudly instead of silently shipping a partial oracle.
The pinned commit parsed 125,633 words.

## Known deviation from raw CMU transcription

CMU transcribes the cot/caught merger (`AA` vs `AO`) as distinct phonemes,
which many English speakers don't hear as different. `analyzers/cmudict.mjs`
folds `AO → AA` when building the rime key used by `rhymes()`, so word pairs
a speaker hears as rhyming aren't rejected on a phonemic distinction most
readers don't perceive. This is an intentional deviation shared with
`comment-in-the-hat` — see that plugin's `vendor/VENDOR.md` for the full
rationale.

## Known deviation from source file separator format

The upstream `cmudict.dict` at this repo uses a single space to separate
the headword from its phoneme string, not the double space of the classic
cmudict-0.7b format. `parseCmudict()` splits on the first run of whitespace
rather than requiring exactly two literal spaces, so both formats parse
identically.
