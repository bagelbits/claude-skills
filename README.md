# claude-skills

A Claude Code plugin marketplace of comment-quality gates. Each plugin blocks
`Write`/`Edit` calls and `git commit`/PR creation that add a comment
violating its rule, nudges with a reminder on every prompt, and ships a
skill to rewrite existing comments into its form on demand.

## Install

```bash
claude plugin marketplace add bagelbits/claude-skills
```

Then install whichever plugin fits:

```bash
claude plugin install comment-reaper@claude-skills
claude plugin install comment-bard@claude-skills
claude plugin install comment-haijin@claude-skills
claude plugin install comment-in-the-hat@claude-skills
```

(Or the equivalent `/plugin marketplace add` / `/plugin install` slash
commands inside an interactive session.)

## Plugins

| Plugin | Rule |
|---|---|
| [`comment-reaper`](plugins/comment-reaper) | Comment the non-obvious *why*, never the *what*. Blocks commented-out code, narrating "what" comments, and comment runs that should be a block. |
| [`comment-bard`](plugins/comment-bard) | Every prose comment line must scan as iambic pentameter — exactly ten syllables. |
| [`comment-haijin`](plugins/comment-haijin) | Prose comments live in `/** ... */` blocks whose lines count 5-7-5 (haiku); `//` line comments are denied on form. |
| [`comment-in-the-hat`](plugins/comment-in-the-hat) | Prose comments pair into rhyming anapestic couplets (AABB, Dr. Seuss-style meter), verified against a real CMU pronunciation dictionary. |

## Turning Off A Gate

Each poetry plugin (`comment-bard`, `comment-haijin`, `comment-in-the-hat`)
can have its blocking write and commit/PR gate silenced independently,
without uninstalling the plugin — its rewrite skill stays available either
way. `comment-reaper` has no toggle; it's always on.

| Plugin | Env var |
|---|---|
| `comment-bard` | `COMMENT_BARD_OFF=1` |
| `comment-haijin` | `COMMENT_HAIKU_OFF=1` |
| `comment-in-the-hat` | `COMMENT_HAT_OFF=1` |

Set the var for the current session only (`export COMMENT_BARD_OFF=1` before
launching Claude Code), or persist it in `.claude/settings.json`:

```json
{ "env": { "COMMENT_BARD_OFF": "1" } }
```

Delete the line to re-arm the gate. See each plugin's README for details.

## Compatibility

Install **at most one** of `comment-bard`, `comment-haijin`, and
`comment-in-the-hat` — they enforce mutually contradictory forms. None of
the three pair with `comment-reaper`, which wants comments *deleted* rather
than versified.

## Shared engine

All four plugins are built on `packages/comment-core`, a shared,
form-agnostic engine (comment extraction/classification, diff walking,
deny-hook plumbing, syllable counting, and a CMU pronunciation oracle). Each
plugin vendors its own verbatim copy — see [`packages/comment-core`](packages/comment-core)
and `scripts/sync-comment-core.mjs` if you're modifying the shared code.

## License

MIT — see [LICENSE](LICENSE).
