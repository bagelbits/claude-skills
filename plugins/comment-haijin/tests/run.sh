#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
FAIL=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAIL=1; }

echo "== comment-haijin: manifest & wiring =="

NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).name)")
[ "$NAME" = "comment-haijin" ] && pass "plugin.json name matches folder" || fail "name mismatch: $NAME"

VERSION=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).version)")
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && pass "version is bare semver" || fail "bad version: $VERSION"

DESC=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).description || '')")
[ -n "$DESC" ] && pass "description non-empty" || fail "description empty"

node -e '
const fs = require("fs"), path = require("path");
const root = process.argv[1];
const hooks = JSON.parse(fs.readFileSync(path.join(root, "hooks/hooks.json")));
let ok = true;
for (const entry of hooks.hooks.PreToolUse) {
  for (const h of entry.hooks) {
    const m = /\$\{CLAUDE_PLUGIN_ROOT\}\/(.*?)"/.exec(h.command);
    if (m && !fs.existsSync(path.join(root, m[1]))) { console.error("missing: " + m[1]); ok = false; }
  }
}
if (!hooks.hooks.UserPromptSubmit) { console.error("no UserPromptSubmit"); ok = false; }
const matchers = hooks.hooks.PreToolUse.map(e => e.matcher);
if (!matchers.includes("Write|Edit|MultiEdit|NotebookEdit")) { console.error("missing write matcher"); ok = false; }
if (!matchers.includes("mcp__plugin_github_github__create_pull_request")) { console.error("missing gh-mcp matcher"); ok = false; }
const bash = hooks.hooks.PreToolUse.filter(e => e.matcher === "Bash");
if (bash.length !== 1) { console.error("expected exactly one Bash entry, got " + bash.length); ok = false; }
const unknown = hooks.hooks.PreToolUse.flatMap(e => Object.keys(e)).filter(k => k !== "matcher" && k !== "hooks");
if (unknown.length) { console.error("unsupported hook entry keys: " + unknown.join(", ")); ok = false; }
process.exit(ok ? 0 : 1);
' "$PLUGIN_ROOT" && pass "hooks.json wiring" || fail "hooks.json wiring"

diff -r "$PLUGIN_ROOT/vendor/comment-core" "$REPO_ROOT/packages/comment-core" >/dev/null 2>&1 \
  && pass "vendored comment-core matches canonical" || fail "vendored comment-core drifted"

echo "== vendored comment-core selftests =="
node "$PLUGIN_ROOT/vendor/comment-core/selftest.mjs" >/tmp/comment-haijin-selftest.$$ 2>&1 \
  && pass "vendored comment-core selftests pass" || { fail "vendored comment-core selftest failed"; cat /tmp/comment-haijin-selftest.$$; }
rm -f /tmp/comment-haijin-selftest.$$

echo "== analyzer import =="
node -e "import('$PLUGIN_ROOT/hooks/haijin-rules.mjs').then(()=>console.log('ok')).catch(e=>{console.error(e);process.exit(1)})" \
  && pass "haijin-rules.mjs imports cleanly" || fail "haijin-rules.mjs import failed"

echo "== write gate =="
TMP=$(mktemp -d)

# a // line comment is denied on form alone -- haiku form requires a
# /** ... */ block, so this never reaches the syllable counter at all.
echo '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// a lone line comment\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out1"
grep -q "x.ts" "$TMP/out1" && pass "line-form comment denied naming file" || fail "line-form comment not denied"

# Regression: a // line whose content trips the shared UNSPEAKABLE detector
# (here, a digit) reads as kind "skipped", not "prose" -- the line-form
# check must still catch it on form alone, before any content scan.
echo '{"tool_name":"Write","tool_input":{"file_path":"unspeakable.ts","content":"const x = 1;\n// retry after 3 seconds\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out1b"
grep -q "unspeakable.ts:2" "$TMP/out1b" && pass "unspeakable // line still denied on form alone" \
  || fail "unspeakable // line was not denied"
grep -qF "a line comment cannot carry a haiku" "$TMP/out1b" && pass "unspeakable // line denied with line-form reason" \
  || fail "unspeakable // line missing line-form reason"

# a verified 5-7-5 triple, counted with the real syllable analyzer before
# pasting in: "an old silent pond" (5), "the wind moves across the field"
# (7), "leaves drift on the pond" (5).
echo '{"tool_name":"Write","tool_input":{"file_path":"y.ts","content":"const x = 1;\n/**\n * an old silent pond\n * the wind moves across the field\n * leaves drift on the pond\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out2"
[ ! -s "$TMP/out2" ] && pass "conforming haiku block produces no output" || fail "conforming block produced output"

echo "not json" | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out3"
[ ! -s "$TMP/out3" ] && pass "malformed payload fails open" || fail "malformed payload produced output"

# double-escaped \\r\\n so the JSON text carries the *escape sequence*, not
# raw control bytes -- literal CR/LF in a JSON string is invalid and would
# make JSON.parse throw, which is not what this case is testing.
printf '{"tool_name":"Write","tool_input":{"file_path":"z.ts","content":"const x=1;\\r\\n// a lone line comment\\r\\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out4"
grep -q "z.ts" "$TMP/out4" && pass "CRLF payload still analyzed" || fail "CRLF payload not analyzed"

# 25 identical unmetered "// a lone line comment" lines: haijin has no
# run-aggregation for line-form findings, so this is exactly 25 findings,
# one per line. Verify the exact rendered shape: preamble states the TRUE
# total (25), body is 20 rendered rows + exactly one "... and 5 more." row.
node -e '
const lines = [];
for (let i = 0; i < 25; i++) lines.push("// a lone line comment");
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "big.ts", content: lines.join("\n") } }));
' > "$TMP/big.json"
node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" < "$TMP/big.json" > "$TMP/out5"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out5','utf8')); console.log('parsed')" > "$TMP/parsed" 2>&1
grep -q parsed "$TMP/parsed" && pass "deny with many findings still parses as JSON" || fail "large deny failed to parse"
node -e '
const fs = require("fs");
const o = JSON.parse(fs.readFileSync("'"$TMP"'/out5", "utf8"));
const reason = o.hookSpecificOutput.permissionDecisionReason;
const lines = reason.split("\n");
const ok = reason.includes("adds 25 line(s) that break haiku form")
  && lines.length === 22
  && lines[lines.length - 1] === "  … and 5 more.";
process.exit(ok ? 0 : 1);
' && pass ">20 findings render exact 20-row + tally overflow shape, true total in preamble" \
  || fail "overflow rendering shape or true-total count wrong"

# A genuinely large payload: one // line built from "the " repeated many
# times. Line-form findings echo the raw line body verbatim (no breakdown
# needed), so this alone is enough to push the deny JSON payload written
# to stdout past the ~64KiB pipe buffer deny.mjs's writeSync comment warns
# about.
node -e '
const big = "the ".repeat(30000).trim();
const content = "// " + big;
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "huge.ts", content } }));
' > "$TMP/huge.json"
node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" < "$TMP/huge.json" > "$TMP/out6"
BYTES=$(wc -c < "$TMP/out6" | tr -d ' ')
[ "$BYTES" -gt 65536 ] && pass "deny payload genuinely exceeds 64KiB pipe buffer ($BYTES bytes)" \
  || fail "deny payload only $BYTES bytes, not genuinely >64KiB"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out6','utf8')); console.log('parsed')" > "$TMP/parsed6" 2>&1
grep -q parsed "$TMP/parsed6" && pass "genuinely >64KiB deny still parses as JSON" || fail "genuinely large deny failed to parse"
grep -q "huge.ts" "$TMP/out6" && pass "genuinely >64KiB deny still names offending file" || fail "genuinely large deny missing filename"

# Regression for Finding 1: an Edit payload carries no lineMap (only Write
# provides one), but the grouped shape/syllable analysis (blockUnits) must
# still run against it. A complete 3-line block (a multiple of three, so no
# ragged-tail finding fires) with a genuine syllable mismatch on line 2 --
# "the wind moves across" is 5 syllables, needs 7 -- can only be caught by
# that grouped path; the per-line // form check never touches a /** */
# block at all.
node -e '
process.stdout.write(JSON.stringify({
  tool_name: "Edit",
  tool_input: {
    file_path: "edited.ts",
    old_string: "const z = 1;",
    new_string: "const z = 1;\n/**\n * an old silent pond\n * the wind moves across\n * leaves drift on the pond\n */",
  },
}));
' | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out-edit"
grep -q "edited.ts" "$TMP/out-edit" && pass "Edit payload: grouped shape/syllable rule denies a bad haiku block" \
  || fail "Edit payload: grouped shape/syllable rule did not fire"
grep -q "needs 7" "$TMP/out-edit" && pass "Edit payload: syllable-mismatch finding produced (grouped rule ran)" \
  || fail "Edit payload: syllable-mismatch finding missing"

echo "== ragged-tail shape rule =="
# A block with 5 prose lines: the first three form a complete, correctly
# scanning haiku (5-7-5: "an old silent pond" / "the wind moves across the
# field" / "leaves drift on the pond"), and two more prose lines trail
# after it. A block's prose line count must be a multiple of three, so
# every line at position >= the largest whole multiple of three (here:
# index 3 and 4, i.e. lines 4 and 5 of the block) must be flagged as a
# ragged tail -- regardless of what those lines' own syllable counts are.
echo '{"tool_name":"Write","tool_input":{"file_path":"ragged.ts","content":"const z = 1;\n/**\n * an old silent pond\n * the wind moves across the field\n * leaves drift on the pond\n * quiet morning walk\n * cold winter night sky\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out7"
grep -q "ragged.ts:6" "$TMP/out7" && pass "4th prose line (past the whole haiku) flagged as ragged tail" \
  || fail "4th prose line not flagged"
grep -q "ragged.ts:7" "$TMP/out7" && pass "5th prose line (past the whole haiku) flagged as ragged tail" \
  || fail "5th prose line not flagged"
grep -q "5 prose line(s) in this block" "$TMP/out7" && pass "ragged-tail finding carries the true block line count" \
  || fail "ragged-tail finding missing block line count"
grep -qF "ragged.ts:3" "$TMP/out7" && fail "first line of the complete haiku wrongly flagged" \
  || pass "first line of the complete haiku not flagged"
grep -qF "ragged.ts:4" "$TMP/out7" && fail "second line of the complete haiku wrongly flagged" \
  || pass "second line of the complete haiku not flagged"
grep -qF "ragged.ts:5" "$TMP/out7" && fail "third line of the complete haiku wrongly flagged" \
  || pass "third line of the complete haiku not flagged"

echo "== orphan one-liner block comment =="
# A standalone /** ... */ one-liner previously produced zero findings: it's
# tagged form: "block" (excluding it from the // line-form check) but
# blockRuns() never opens a run for a line with both /** and */ on it
# (excluding it from the grouped shape/syllable check too), so it fell
# through both mechanisms. "an old silent pond" is 5 syllables and is a
# fine haiku LINE, but alone it is only 1 of the 3 lines a haiku needs.
echo '{"tool_name":"Write","tool_input":{"file_path":"orphan.ts","content":"const x = 1;\n/** an old silent pond */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out-orphan1"
grep -q "orphan.ts:2" "$TMP/out-orphan1" && pass "standalone one-liner block comment now flagged (was silently allowed)" \
  || fail "standalone one-liner block comment still bypasses the gate"
grep -q "1 prose line(s) in this block" "$TMP/out-orphan1" && pass "standalone one-liner flagged with the ragged-tail shape reason" \
  || fail "standalone one-liner missing shape reason: $(cat "$TMP/out-orphan1")"

# Three one-liners on consecutive lines must chain into one complete,
# correctly-scanning haiku (5-7-5) and produce NO findings -- the same
# verified triple used elsewhere in this file, just written as three
# separate one-liner comments instead of one multi-line block.
echo '{"tool_name":"Write","tool_input":{"file_path":"chained.ts","content":"const x = 1;\n/** an old silent pond */\n/** the wind moves across the field */\n/** leaves drift on the pond */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out-orphan2"
[ ! -s "$TMP/out-orphan2" ] && pass "three chained one-liners forming a complete haiku produce no output" \
  || fail "chained one-liner haiku wrongly denied: $(cat "$TMP/out-orphan2")"

# A one-liner with a genuine syllable mismatch must still be caught, proving
# the full per-position 5-7-5 check (not just the shape/count check) runs
# over one-liner-derived groups. "the wind moves across" is 5 syllables and
# occupies the 7-syllable (2nd) position of the haiku.
echo '{"tool_name":"Write","tool_input":{"file_path":"chainedbad.ts","content":"const x = 1;\n/** an old silent pond */\n/** the wind moves across */\n/** leaves drift on the pond */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/haijin-filter.mjs" > "$TMP/out-orphan3"
grep -q "chainedbad.ts:3" "$TMP/out-orphan3" && pass "chained one-liner with wrong syllable count on its line flagged" \
  || fail "chained one-liner syllable mismatch not caught"
grep -q "needs 7" "$TMP/out-orphan3" && pass "chained one-liner syllable-mismatch finding names the needed count" \
  || fail "chained one-liner syllable-mismatch finding missing detail: $(cat "$TMP/out-orphan3")"

echo "== commit/PR gate =="
COMMIT_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
GITTMP=$(mktemp -d)
git -C "$GITTMP" init -q
git -C "$GITTMP" checkout -q -b main
git -C "$GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// a lone line comment\n' > "$GITTMP/a.ts"
git -C "$GITTMP" add a.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "violating branch denied naming file" || fail "violating branch not denied"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
[ -z "$OUT" ] && pass "unrelated Bash command skips the branch scan" || fail "unrelated Bash command still scanned the branch"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"mcp__plugin_github_github__create_pull_request","tool_input":{}}' | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "gh MCP pull-request tool still scans the branch" || fail "gh MCP pull-request tool did not scan"

OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs" < /dev/null)
[ -z "$OUT" ] && pass "empty payload fails open" || fail "empty payload produced output"

# a.ts was staged but never committed -- `git checkout -b` carries the index
# forward, so without this reset it would still show up (and still violate)
# in every later branch's --cached diff against main.
git -C "$GITTMP" reset --hard -q

git -C "$GITTMP" checkout -q -b clean-branch main
printf 'const y = 2;\n' > "$GITTMP/b.ts"
git -C "$GITTMP" add b.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
[ -z "$OUT" ] && pass "clean branch produces no output" || fail "clean branch produced output"

NOTGIT=$(mktemp -d)
OUT=$(cd "$NOTGIT" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
[ -z "$OUT" ] && pass "outside git repo fails open" || fail "outside git repo produced output"

git -C "$GITTMP" checkout -q -b hostile main
git -C "$GITTMP" config core.quotePath true
git -C "$GITTMP" config diff.noprefix true
git -C "$GITTMP" config diff.mnemonicPrefix true
git -C "$GITTMP" config diff.relative true
git -C "$GITTMP" config color.ui always
mkdir -p "$GITTMP/sub"
printf 'const x = 1;\n// a lone line comment\n' > "$GITTMP/sub/c.ts"
git -C "$GITTMP" add sub/c.ts
OUT=$(cd "$GITTMP/sub" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
echo "$OUT" | grep -q "sub/c.ts" && pass "hostile diff config still denies with correct path" || fail "hostile diff config broke path resolution: $OUT"
git -C "$GITTMP" reset --hard -q

# Filename with a space: git pads the "+++ b/..." header with a trailing
# tab when the path contains a space. headerPath() must strip that tab, not
# fold it into the filename or corrupt it.
git -C "$GITTMP" checkout -q -b spacey main
printf 'const x = 1;\n// a lone line comment\n' > "$GITTMP/my file.ts"
git -C "$GITTMP" add "my file.ts"
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
echo "$OUT" | grep -q "my file.ts:2" && pass "space-containing filename denied with tab stripped, not corrupted" \
  || fail "space-containing filename mishandled: $OUT"
git -C "$GITTMP" reset --hard -q

# Non-ASCII filename alongside a normal one, both violating (with different
# line-form comment text, so each finding is unambiguous). diff.mjs's
# DIFF_CONFIG forces `-c core.quotePath=false` on every git invocation (see
# diff.mjs), which defeats octal-escaping of non-ASCII bytes even when the
# repo config (set here) tries to force quoting back on -- so café.ts's raw
# UTF-8 name should come through the header intact rather than being
# quoted-and-dropped, and neither file's finding should bleed into the
# other's.
git -C "$GITTMP" checkout -q -b nonascii main
git -C "$GITTMP" config core.quotePath true
printf 'const y = 2;\n// a lone haiku attempt\n' > "$GITTMP/café.ts"
printf 'const z = 3;\n// another failed comment\n' > "$GITTMP/normal.ts"
git -C "$GITTMP" add "café.ts" normal.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-haijin-check.mjs")
echo "$OUT" | grep -q "adds 2 line(s) that break haiku form" && pass "non-ASCII + normal filename: both findings counted, none dropped" \
  || fail "non-ASCII + normal filename: wrong finding count: $OUT"
echo "$OUT" | grep -qF 'café.ts:2 — a line comment cannot carry a haiku — move this into a /** ... */ block whose prose lines count 5-7-5: \"a lone haiku attempt\"' && pass "non-ASCII filename correctly attributed its own finding" \
  || fail "non-ASCII filename finding missing or misattributed: $OUT"
echo "$OUT" | grep -qF 'normal.ts:2 — a line comment cannot carry a haiku — move this into a /** ... */ block whose prose lines count 5-7-5: \"another failed comment\"' && pass "normal filename finding not polluted by non-ASCII neighbor" \
  || fail "normal filename finding missing or polluted: $OUT"
git -C "$GITTMP" reset --hard -q
git -C "$GITTMP" config --unset core.quotePath || true

echo "== scan script =="
OUT=$(node "$PLUGIN_ROOT/scripts/haijin-scan.mjs" "$GITTMP/a.ts")
echo "$OUT" | grep -q '"target":"paths"' && pass "path mode reports target: paths" || fail "path mode target wrong"

# Branch mode with no args, from inside a repo with a resolvable base and
# nothing staged: target must be the resolved base branch name (not null,
# not omitted), and findings must be an explicit empty array.
SCANTMP=$(mktemp -d)
git -C "$SCANTMP" init -q
git -C "$SCANTMP" checkout -q -b main
git -C "$SCANTMP" commit -q --allow-empty -m base
OUT=$(cd "$SCANTMP" && node "$PLUGIN_ROOT/scripts/haijin-scan.mjs")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(o.target === "main" && Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "branch mode with clean diff reports resolved base and empty findings" \
  || fail "branch mode clean-diff shape wrong: $OUT"
rm -rf "$SCANTMP"

# Vendored/third-party path: isCodeFile() excludes anything under
# vendor/, node_modules/, or .terraform/, so scanning it must yield zero
# findings even though the (still-a-comment) line inside it would otherwise
# violate the rule.
mkdir -p "$TMP/vendor"
printf 'const x = 1;\n// a lone line comment\n' > "$TMP/vendor/dummy.ts"
OUT=$(node "$PLUGIN_ROOT/scripts/haijin-scan.mjs" "$TMP/vendor/dummy.ts")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "vendor/ path produces zero findings (third-party exclusion)" \
  || fail "vendor/ path was analyzed for findings: $OUT"

rm -rf "$TMP" "$GITTMP" "$NOTGIT"

echo "== meta-constraint: haijin's own source passes its own gate =="
OUT=$(node "$PLUGIN_ROOT/scripts/haijin-scan.mjs" "$PLUGIN_ROOT"/hooks/*.mjs "$PLUGIN_ROOT"/scripts/*.mjs)
FINDINGS_COUNT=$(echo "$OUT" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).findings.length)")
[ "$FINDINGS_COUNT" = "0" ] && pass "haijin's own hooks/*.mjs and scripts/*.mjs pass its own gate" || fail "haijin's own source has $FINDINGS_COUNT violation(s): $OUT"

echo "== gate toggle: COMMENT_HAIKU_OFF =="
# Exercises the real wired command strings from hooks.json (not the .mjs
# scripts directly), so this proves the env-var short-circuit actually
# lives on the path Claude Code invokes.
WRITE_CMD=$(node -e '
const hooks = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const entry = hooks.hooks.PreToolUse.find(e => e.matcher === "Write|Edit|MultiEdit|NotebookEdit");
process.stdout.write(entry.hooks[0].command);
' "$PLUGIN_ROOT/hooks/hooks.json")
COMMIT_CMD=$(node -e '
const hooks = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const entry = hooks.hooks.PreToolUse.find(e => e.matcher === "Bash");
process.stdout.write(entry.hooks[0].command);
' "$PLUGIN_ROOT/hooks/hooks.json")

TOGGLE_TMP=$(mktemp -d)
PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// a lone line comment\n"}}'

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_HAIKU_OFF=1 bash -c "$WRITE_CMD" > "$TOGGLE_TMP/on"
[ ! -s "$TOGGLE_TMP/on" ] && pass "COMMENT_HAIKU_OFF=1 bypasses write gate (no output)" \
  || fail "COMMENT_HAIKU_OFF=1 did not bypass write gate: $(cat "$TOGGLE_TMP/on")"

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$WRITE_CMD" > "$TOGGLE_TMP/off"
grep -q "x.ts" "$TOGGLE_TMP/off" && pass "write gate still denies with COMMENT_HAIKU_OFF unset" \
  || fail "write gate did not deny with COMMENT_HAIKU_OFF unset"

GATE_GITTMP=$(mktemp -d)
git -C "$GATE_GITTMP" init -q
git -C "$GATE_GITTMP" checkout -q -b main
git -C "$GATE_GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// a lone line comment\n' > "$GATE_GITTMP/a.ts"
git -C "$GATE_GITTMP" add a.ts

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_HAIKU_OFF=1 bash -c "$COMMIT_CMD")
[ -z "$OUT" ] && pass "COMMENT_HAIKU_OFF=1 bypasses commit gate (no output)" \
  || fail "COMMENT_HAIKU_OFF=1 did not bypass commit gate: $OUT"

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$COMMIT_CMD")
echo "$OUT" | grep -q "a.ts" && pass "commit gate still denies with COMMENT_HAIKU_OFF unset" \
  || fail "commit gate did not deny with COMMENT_HAIKU_OFF unset"

rm -rf "$TOGGLE_TMP" "$GATE_GITTMP"

if [ "$FAIL" -ne 0 ]; then echo "comment-haijin: FAILED"; exit 1; fi
echo "comment-haijin: all tests passed"
