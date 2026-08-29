---
name: green-eggs-and-hamify-pr-comment
description: Format PR review output as Dr. Seuss / Green-Eggs-and-Ham doggerel while keeping every technical finding intact. Use when the user asks to "hamify", "seuss-ify", "green eggs and ham", or wants a rhyming PR review/approval. Produces one review body + N inline comments, each pairing a 4-line rhyme with a plain-text explanation, then posts via the GitHub reviews API.
---

# green-eggs-and-hamify-pr-comment

Turn an ordinary PR review into Dr. Seuss doggerel **without losing any technical
substance**. The rhyme is the wrapper; the finding underneath must stay accurate,
actionable, and identical in meaning to a normal review.

This is a presentation layer only. Do the real review first (find the bugs),
then hamify. Never let the meter bend a fact — if a rhyme forces an inaccuracy,
rewrite the rhyme, not the claim.

## When to use

- User says "hamify", "green eggs and ham", "seuss-ify this review", "rhyming review".
- User asks to approve / comment on a PR *and* wants the playful format.

Do **not** use for: commit messages, code comments, anything that lands in the
codebase, or a review where the user wants plain output.

## Inputs

- A PR (number or URL) and its owner/repo.
- A verdict: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
- A list of findings, each with: file path, right-side line number, severity
  (`low` | `medium` | `high`), category (`correctness`, `reuse`, `efficiency`,
  `simplification`, `altitude`, `conventions`, `test-coverage`, …), a one-line
  summary, and a plain-text explanation with the concrete fix.

If findings aren't supplied, run the normal review process to produce them first.

## Output contract

Two block types. **Both** use the same header line, then a blockquote rhyme, then
a plain-text paragraph.

### 1. Top-level review body

```
**Review — <verdict-word>** _(<n> non-blocking follow-ups)_

> <4–16 lines of doggerel summarizing the change and verdict,
> grouped into 4-line stanzas separated by a blank `>` line>

<1 short plain-text paragraph: what's sound, why the verdict, that findings are below>
```

- `<verdict-word>`: `approving` / `requesting changes` / `commenting`.
- The parenthetical tag is optional context (finding count, or `blocking` / `non-blocking`).

### 2. Each inline comment

```
**Finding N — <short summary>** _(<severity>, <category>)_

> <exactly 4 lines of doggerel, AABB rhyme, describing the defect>

<plain-text: the real explanation + the concrete fix. No rhyme here.>
```

Rules:
- Header: `**Finding N — summary**` then ` _(severity, category)_` in italics.
- Rhyme: **4 lines, AABB** (lines 1–2 rhyme, lines 3–4 rhyme), as a `>` blockquote.
  Bouncy anapestic/Seuss meter. May name code symbols in backticks inside the verse.
- Explanation: one plain paragraph, no rhyme, states the failure scenario and the
  fix exactly as a normal review would. This is what the author acts on.
- Anchor: `path` + right-side `line`. If two findings share a line, move one to a
  nearby related line so they don't stack.

## Rhyme rules

- AABB, 4 lines per finding. Summary stanzas may be longer but stay in 4-line groups.
- Keep it playful (Seuss cadence, light repetition, "I do not / I will not" riffs are on-theme).
- Technical terms and identifiers stay exact — backtick them; never rhyme by renaming a symbol.
- No praise-only filler. Every rhyme must encode the actual defect.
- Severity/category live in the header, never buried in the verse.

## Posting

Post the whole thing as **one** review (body + all inline comments) via the reviews
API so it's a single notification, not N comments:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews \
  --method POST \
  --input review.json
```

`review.json` shape:

```json
{
  "commit_id": "<head sha of the PR branch>",
  "event": "APPROVE",
  "body": "<top-level body block>",
  "comments": [
    { "path": "<file>", "line": <n>, "side": "RIGHT", "body": "<inline block>" }
  ]
}
```

- Get the head sha with `git rev-parse <branch>` or `gh pr view <n> --json headRefOid`.
- Each inline `line` must be a line present in the PR diff on the RIGHT side, or the
  API rejects it.
- Write `review.json` to a temp file (rhymes have newlines/quotes that are painful to
  inline in a shell arg). Verify state from the response: `state == "APPROVED"` etc.

## Preview-before-post

Always show the user the full formatted output (body + every inline) and get a
go-ahead before calling the API. Approving/commenting on a PR is outward-facing.

## Worked example

Top-level (approve):

```
**Review — approving** _(2 non-blocking follow-ups)_

> I do not require an `ehrId`.
> I will not need it, VA-P!
> Not for a SAML, not with a UPN,
> not when the org just wants to sign in.
>
> The tests are green, the diff is clean,
> the leanest change these eyes have seen.

Core refactor is sound and behavior-preserving. Two follow-ups below — non-blocking.
```

Inline:

```
**Finding 1 — Vista `vaSecId` check fails open** _(medium, correctness)_

> When the instance comes back as an undefined thing,
> the `?.` just shrugs and the Vista check takes wing.
> No `ehrType` resolved, so no SecID plea —
> a Vista invite slips out, fancy-free.

If `getById(ehrInstanceId)` returns `undefined`, `ehrInstance?.ehrType === EhrType.Vista`
is false and the guard is skipped, so a scoped Vista invite with a missing instance doc
bypasses the `vaSecId` requirement. Fail closed when the instance can't be resolved.
```
