---
name: nantucket-pr-comment
description: Format PR review output as AABBA limericks while keeping every technical finding intact. Use when asked for a limerick PR review or approval. Produces one review body plus N inline comments, each a limerick blockquote plus a plain-text explanation, posted via the GitHub reviews API.
---

# nantucket-pr-comment

Turn an ordinary PR review into AABBA limericks **without losing any technical
substance**. The verse is the wrapper; the finding underneath must stay accurate,
actionable, and identical in meaning to a normal review. Do the real review
first, then versify. If the form forces an inaccuracy, rewrite the verse, not
the claim.

Not for code comments (use `comment-limerick`'s comment skill) or commit messages.

## Inputs

A PR (owner/repo + number), a verdict (`APPROVE` | `REQUEST_CHANGES` |
`COMMENT`), and findings: file, right-side line, severity (`low` | `medium` |
`high`), category, one-line summary, and a plain-text explanation with the fix.
If none are supplied, run the normal review first.

## Output contract

Top-level body:

```
**Review — <approving|requesting changes|commenting>** _(<n> non-blocking follow-ups)_

> <verse: one or more whole limericks (5 lines each) summarizing the change and verdict>

<1 plain paragraph: what's sound, why the verdict, findings below>
```

Each inline comment:

```
**Finding N — <short summary>** _(<severity>, <category>)_

> <verse: exactly one limerick, 5 lines AABBA, describing the defect>

<plain text: failure scenario + concrete fix. No verse here.>
```

Rules:
- Lines 1, 2, 5 rhyme and run 7-10 syllables; lines 3, 4 rhyme and run 5-7.
  With the plugin installed, verify with the oracle in the `nantucket` skill
  (step 3).
- No humor requirement; rhyme and meter are what matter.
- Backtick code identifiers; never rename a symbol to rhyme.
- Every limerick must encode the actual defect. No praise-only filler.
- Severity and category live in the header, never in the verse.
- Anchor each finding at `path` + right-side `line`; spread shared lines apart.

Example inline comment:

```
**Finding 1 — Vista `vaSecId` check fails open** _(medium, correctness)_

> When `getById` hands back a void,
> the `?.` leaves the guard destroyed.
> No Vista is found,
> so no SecID is bound,
> and the invite goes out unalloyed.

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
