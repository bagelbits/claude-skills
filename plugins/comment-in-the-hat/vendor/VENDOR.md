# Vendored data: CMU Pronouncing Dictionary

Source: https://github.com/cmusphinx/cmudict, commit `74790861f652b15e4ac49015a90074ad62a27690`.
License: BSD-2-Clause (`LICENSE-cmudict`, verbatim from the pinned commit).

Built with `../scripts/build-cmudict.mjs`:
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
readers don't perceive. This is an intentional deviation, not a bug — see
spec §8 for the alternative (document as a known limitation, not chosen here).

## Known deviation from source file separator format

The upstream `cmudict.dict` at this repo uses a single space to separate
the headword from its phoneme string (the pocketsphinx dictionary format),
not the double space of the classic cmudict-0.7b format. `parseCmudict()`
in `analyzers/cmudict.mjs` splits on the first run of whitespace (one or
more spaces) rather than requiring exactly two literal spaces, so both
formats parse identically.
