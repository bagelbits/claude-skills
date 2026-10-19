---
name: verse-pr-comment
description: Format PR review output as iambic pentameter (ten syllables per verse line) while keeping every technical finding intact. Use when asked for a Shakespearean, bardic, or iambic-pentameter PR review or approval. Produces one review body plus N inline comments, each a verse blockquote plus a plain-text explanation, posted via the GitHub reviews API.
---

# verse-pr-comment

Turn an ordinary PR review into iambic pentameter **without losing any technical
substance**. The verse is the wrapper; the finding underneath must stay accurate,
actionable, and identical in meaning to a normal review. Do the real review
first, then versify. If the form forces an inaccuracy, rewrite the verse, not
the claim.

Not for code comments (use `comment-bard`'s comment skill) or commit messages.

## Inputs

A PR (owner/repo + number), a verdict (`APPROVE` | `REQUEST_CHANGES` |
`COMMENT`), and findings: file, right-side line, severity (`low` | `medium` |
`high`), category, one-line summary, and a plain-text explanation with the fix.
If none are supplied, run the normal review first.

## Output contract

Top-level body:

```
**Review — <approving|requesting changes|commenting>** _(<n> non-blocking follow-ups)_

> <verse: a rhyming-couplet or blank-verse summary, 2-8 lines of ten syllables each>

<1 plain paragraph: what's sound, why the verdict, findings below>
```

Each inline comment:

```
**Finding N — <short summary>** _(<severity>, <category>)_

> <verse: exactly 2 lines of ten syllables, a rhyming couplet describing the defect>

<plain text: failure scenario + concrete fix. No verse here.>
```

Rules:
- Every verse line is ten syllables, da-DUM x5. Count carefully; with the
  plugin installed, verify with the counter in the `verse` skill (step 3).
- Backtick code identifiers; never rename a symbol to fit the meter. A
  backticked identifier may break the count: that is acceptable in a PR, but
  prefer phrasing that keeps it speakable.
- Every couplet must encode the actual defect. No praise-only filler.
- Severity and category live in the header, never in the verse.
- Anchor each finding at `path` + right-side `line`; spread shared lines apart.

Example inline comment:

```
**Finding 1 — Vista `vaSecId` check fails open** _(medium, correctness)_

> When `getById` returns nothing, the guard is gone;
> the Vista invite slips on through at dawn.

If `getById(ehrInstanceId)` returns `undefined`, `ehrInstance?.ehrType === EhrType.Vista`
is false and the `vaSecId` requirement is skipped. Fail closed when the instance
can't be resolved.
```

## Posting

Post as **one** review (body + all inline comments) so it is a single notification:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews --method POST --input review.json
```

`review.json`:

```json
{
  "commit_id": "<head sha>",
  "event": "APPROVE",
  "body": "<top-level block>",
  "comments": [
    { "path": "<file>", "line": <n>, "side": "RIGHT", "body": "<inline block>" }
  ]
}
```

- `event`: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
- Head sha: `gh pr view <n> --json headRefOid`.
- Each `line` must be in the PR diff on the RIGHT side, or the API rejects it.
- Write `review.json` to a temp file; verse has newlines and quotes. Check the
  response `state`.

## Preview-before-post

Show the user the full formatted review and get a go-ahead before calling the
API. Reviewing a PR is outward-facing.
