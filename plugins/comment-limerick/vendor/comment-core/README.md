# comment-core

Shared, form-agnostic engine behind the `comment-*` plugin family: comment
extraction/classification (`extract.mjs`), unified-diff walking (`diff.mjs`),
deny-hook plumbing (`deny.mjs`), and two opt-in linguistic analyzers
(`analyzers/syllable.mjs`, `analyzers/cmudict.mjs`).

`index.mjs` re-exports only the plumbing (`extract.mjs`, `diff.mjs`,
`deny.mjs`). Analyzers are never re-exported from `index.mjs` — import the one
you need by subpath. Plumbing is form-agnostic; it never decides whether a
comment is "good."

No `node_modules`. Third-party code is vendored as source under `vendor/` —
see `VENDOR.md`. Run `node selftest.mjs` to exercise every module.

Consumed by each plugin as a verbatim git-subdir copy at
`plugins/<name>/vendor/comment-core` — see `scripts/sync-comment-core.mjs` at
the repo root. Never hand-edit a plugin's vendored copy; edit here and re-run
the sync script.
