#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
FAIL=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAIL=1; }

echo "== comment-bard: manifest & wiring =="

NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).name)")
[ "$NAME" = "comment-bard" ] && pass "plugin.json name matches folder" || fail "name mismatch: $NAME"

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
node "$PLUGIN_ROOT/vendor/comment-core/selftest.mjs" >/tmp/comment-bard-selftest.$$ 2>&1 \
  && pass "vendored comment-core selftests pass" || { fail "vendored comment-core selftest failed"; cat /tmp/comment-bard-selftest.$$; }
rm -f /tmp/comment-bard-selftest.$$

echo "== analyzer import =="
node -e "import('$PLUGIN_ROOT/hooks/bard-rules.mjs').then(()=>console.log('ok')).catch(e=>{console.error(e);process.exit(1)})" \
  && pass "bard-rules.mjs imports cleanly" || fail "bard-rules.mjs import failed"

echo "== write gate =="
TMP=$(mktemp -d)

echo '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// this short line here will not scan today\n"}}' \
  | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out1"
grep -q "x.ts" "$TMP/out1" && pass "unmetered write denied naming file" || fail "unmetered write not denied"

# "the counting tool agrees this line is fine" verified via the syllable
# analyzer as exactly 10 syllables before pasting it in here.
echo '{"tool_name":"Write","tool_input":{"file_path":"y.ts","content":"const x = 1; // the counting tool agrees this line is fine\n"}}' \
  | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out2"
[ ! -s "$TMP/out2" ] && pass "metered write produces no output" || fail "metered write produced output"

echo "not json" | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out3"
[ ! -s "$TMP/out3" ] && pass "malformed payload fails open" || fail "malformed payload produced output"

# double-escaped \\r\\n so the JSON text carries the *escape sequence*, not
# raw control bytes -- literal CR/LF in a JSON string is invalid and would
# make JSON.parse throw, which is not what this case is testing.
printf '{"tool_name":"Write","tool_input":{"file_path":"z.ts","content":"const x=1;\\r\\n// this short line here will not scan today\\r\\n"}}' \
  | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out4"
grep -q "z.ts" "$TMP/out4" && pass "CRLF payload still analyzed" || fail "CRLF payload not analyzed"

# 25 identical unmetered "// this short line here will not scan today"
# lines: bard has no run-aggregation like reaper's MULTILINE_RUN, so this
# is exactly 25 findings, one per line. Verify the exact rendered shape:
# preamble states the TRUE total (25), body is 20 rendered rows + exactly
# one "... and 5 more." tally row.
node -e '
const lines = [];
for (let i = 0; i < 25; i++) lines.push("// this short line here will not scan today");
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "big.ts", content: lines.join("\n") } }));
' > "$TMP/big.json"
node "$PLUGIN_ROOT/hooks/bard-filter.mjs" < "$TMP/big.json" > "$TMP/out5"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out5','utf8')); console.log('parsed')" > "$TMP/parsed" 2>&1
grep -q parsed "$TMP/parsed" && pass "deny with many findings still parses as JSON" || fail "large deny failed to parse"
node -e '
const fs = require("fs");
const o = JSON.parse(fs.readFileSync("'"$TMP"'/out5", "utf8"));
const reason = o.hookSpecificOutput.permissionDecisionReason;
const lines = reason.split("\n");
const ok = reason.includes("adds 25 line(s) that don'"'"'t scan")
  && lines.length === 22
  && lines[lines.length - 1] === "  … and 5 more.";
process.exit(ok ? 0 : 1);
' && pass ">20 findings render exact 20-row + tally overflow shape, true total in preamble" \
  || fail "overflow rendering shape or true-total count wrong"

# A genuinely large payload: one prose line built from "the " repeated many
# times, so its breakdown alone is >64KiB -- the deny JSON payload written
# to stdout must itself exceed the ~64KiB pipe buffer deny.mjs's writeSync
# comment warns about.
node -e '
const big = "the ".repeat(30000).trim();
const content = "// " + big;
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "huge.ts", content } }));
' > "$TMP/huge.json"
node "$PLUGIN_ROOT/hooks/bard-filter.mjs" < "$TMP/huge.json" > "$TMP/out6"
BYTES=$(wc -c < "$TMP/out6" | tr -d ' ')
[ "$BYTES" -gt 65536 ] && pass "deny payload genuinely exceeds 64KiB pipe buffer ($BYTES bytes)" \
  || fail "deny payload only $BYTES bytes, not genuinely >64KiB"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out6','utf8')); console.log('parsed')" > "$TMP/parsed6" 2>&1
grep -q parsed "$TMP/parsed6" && pass "genuinely >64KiB deny still parses as JSON" || fail "genuinely large deny failed to parse"
grep -q "huge.ts" "$TMP/out6" && pass "genuinely >64KiB deny still names offending file" || fail "genuinely large deny missing filename"

# Regression for Finding 1: an Edit payload carries no lineMap, but the
# grouped mixed-block analysis (blockRuns) must still run against it. One
# scanning 10-syllable line plus one line with an unspeakable token, in the
# same /** ... */ block -- the per-line meter check alone never touches the
# unspeakable line; only the grouped mixed-block check catches it.
node -e '
process.stdout.write(JSON.stringify({
  tool_name: "Edit",
  tool_input: {
    file_path: "edited.ts",
    old_string: "const z = 1;",
    new_string: "const z = 1;\n/**\n * the counting tool agrees this line is fine\n * fileName.ts holds the answer we need here\n */",
  },
}));
' | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out-edit"
grep -q "edited.ts" "$TMP/out-edit" && pass "Edit payload: grouped mixed-block rule denies an unspeakable line in a scanning block" \
  || fail "Edit payload: grouped mixed-block rule did not fire"
grep -q "not meterable, yet a line in the same block scans" "$TMP/out-edit" && pass "Edit payload: mixed-block finding produced (grouped rule ran)" \
  || fail "Edit payload: mixed-block finding missing"

echo "== mixed-block rule =="
# One scanning prose line plus one line with an unspeakable token in the
# same /** ... */ block: a block reads as all verse or all plain, so the
# unspeakable line must be flagged even though the meter check alone
# never touches it.
echo '{"tool_name":"Write","tool_input":{"file_path":"mixed.ts","content":"const z = 1;\n/**\n * the counting tool agrees this line is fine\n * fileName.ts holds the answer we need here\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/bard-filter.mjs" > "$TMP/out7"
grep -q "mixed.ts:4" "$TMP/out7" && pass "unspeakable line in a scanning block denied" || fail "mixed block violation not denied"
grep -q "not meterable, yet a line in the same block scans" "$TMP/out7" && pass "mixed-block finding carries the mixed-block reason" \
  || fail "mixed-block finding missing its reason"

echo "== commit/PR gate =="
COMMIT_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
GITTMP=$(mktemp -d)
git -C "$GITTMP" init -q
git -C "$GITTMP" checkout -q -b main
git -C "$GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// this short line here will not scan today\n' > "$GITTMP/a.ts"
git -C "$GITTMP" add a.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "violating branch denied naming file" || fail "violating branch not denied"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
[ -z "$OUT" ] && pass "unrelated Bash command skips the branch scan" || fail "unrelated Bash command still scanned the branch"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"mcp__plugin_github_github__create_pull_request","tool_input":{}}' | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "gh MCP pull-request tool still scans the branch" || fail "gh MCP pull-request tool did not scan"

OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs" < /dev/null)
[ -z "$OUT" ] && pass "empty payload fails open" || fail "empty payload produced output"

# a.ts was staged but never committed -- `git checkout -b` carries the index
# forward, so without this reset it would still show up (and still violate)
# in every later branch's --cached diff against main.
git -C "$GITTMP" reset --hard -q

git -C "$GITTMP" checkout -q -b clean-branch main
printf 'const y = 2;\n' > "$GITTMP/b.ts"
git -C "$GITTMP" add b.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
[ -z "$OUT" ] && pass "clean branch produces no output" || fail "clean branch produced output"

NOTGIT=$(mktemp -d)
OUT=$(cd "$NOTGIT" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
[ -z "$OUT" ] && pass "outside git repo fails open" || fail "outside git repo produced output"

git -C "$GITTMP" checkout -q -b hostile main
git -C "$GITTMP" config core.quotePath true
git -C "$GITTMP" config diff.noprefix true
git -C "$GITTMP" config diff.mnemonicPrefix true
git -C "$GITTMP" config diff.relative true
git -C "$GITTMP" config color.ui always
mkdir -p "$GITTMP/sub"
printf 'const x = 1;\n// this short line here will not scan today\n' > "$GITTMP/sub/c.ts"
git -C "$GITTMP" add sub/c.ts
OUT=$(cd "$GITTMP/sub" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
echo "$OUT" | grep -q "sub/c.ts" && pass "hostile diff config still denies with correct path" || fail "hostile diff config broke path resolution: $OUT"
git -C "$GITTMP" reset --hard -q

# Filename with a space: git pads the "+++ b/..." header with a trailing
# tab when the path contains a space. headerPath() must strip that tab, not
# fold it into the filename or corrupt it.
git -C "$GITTMP" checkout -q -b spacey main
printf 'const x = 1;\n// this short line here will not scan today\n' > "$GITTMP/my file.ts"
git -C "$GITTMP" add "my file.ts"
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
echo "$OUT" | grep -q "my file.ts:2" && pass "space-containing filename denied with tab stripped, not corrupted" \
  || fail "space-containing filename mishandled: $OUT"
git -C "$GITTMP" reset --hard -q

# Non-ASCII filename alongside a normal one, both violating (with different
# unmetered lines, so each finding is unambiguous). diff.mjs's DIFF_CONFIG
# forces `-c core.quotePath=false` on every git invocation (see diff.mjs),
# which defeats octal-escaping of non-ASCII bytes even when the repo config
# (set here) tries to force quoting back on -- so café.ts's raw UTF-8 name
# should come through the header intact rather than being quoted-and-dropped,
# and neither file's finding should bleed into the other's.
git -C "$GITTMP" checkout -q -b nonascii main
git -C "$GITTMP" config core.quotePath true
printf 'const y = 2;\n// this short line here will not scan today\n' > "$GITTMP/café.ts"
printf 'const z = 3;\n// the count comes up short of what we need\n' > "$GITTMP/normal.ts"
git -C "$GITTMP" add "café.ts" normal.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-bard-check.mjs")
echo "$OUT" | grep -q "adds 2 line(s) that don't scan" && pass "non-ASCII + normal filename: both findings counted, none dropped" \
  || fail "non-ASCII + normal filename: wrong finding count: $OUT"
echo "$OUT" | grep -qF 'café.ts:2 — 9 syllable(s), needs 10 (this/1 short/1 line/1 here/1 will/1 not/1 scan/1 today/2): \"this short line here will not scan today\"' && pass "non-ASCII filename correctly attributed its own finding" \
  || fail "non-ASCII filename finding missing or misattributed: $OUT"
echo "$OUT" | grep -qF 'normal.ts:2 — 9 syllable(s), needs 10 (the/1 count/1 comes/1 up/1 short/1 of/1 what/1 we/1 need/1): \"the count comes up short of what we need\"' && pass "normal filename finding not polluted by non-ASCII neighbor" \
  || fail "normal filename finding missing or polluted: $OUT"
git -C "$GITTMP" reset --hard -q
git -C "$GITTMP" config --unset core.quotePath || true

echo "== scan script =="
OUT=$(node "$PLUGIN_ROOT/scripts/bard-scan.mjs" "$GITTMP/a.ts")
echo "$OUT" | grep -q '"target":"paths"' && pass "path mode reports target: paths" || fail "path mode target wrong"

# Branch mode with no args, from inside a repo with a resolvable base and
# nothing staged: target must be the resolved base branch name (not null,
# not omitted), and findings must be an explicit empty array.
SCANTMP=$(mktemp -d)
git -C "$SCANTMP" init -q
git -C "$SCANTMP" checkout -q -b main
git -C "$SCANTMP" commit -q --allow-empty -m base
OUT=$(cd "$SCANTMP" && node "$PLUGIN_ROOT/scripts/bard-scan.mjs")
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
printf 'const x = 1;\n// this short line here will not scan today\n' > "$TMP/vendor/dummy.ts"
OUT=$(node "$PLUGIN_ROOT/scripts/bard-scan.mjs" "$TMP/vendor/dummy.ts")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "vendor/ path produces zero findings (third-party exclusion)" \
  || fail "vendor/ path was analyzed for findings: $OUT"

rm -rf "$TMP" "$GITTMP" "$NOTGIT"

echo "== meta-constraint: bard's own source passes its own gate =="
OUT=$(node "$PLUGIN_ROOT/scripts/bard-scan.mjs" "$PLUGIN_ROOT"/hooks/*.mjs "$PLUGIN_ROOT"/scripts/*.mjs)
FINDINGS_COUNT=$(echo "$OUT" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).findings.length)")
[ "$FINDINGS_COUNT" = "0" ] && pass "bard's own hooks/*.mjs and scripts/*.mjs pass its own gate" || fail "bard's own source has $FINDINGS_COUNT unmetered line(s): $OUT"

echo "== gate toggle: COMMENT_BARD_OFF =="
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
PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// this short line here will not scan today\n"}}'

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_BARD_OFF=1 bash -c "$WRITE_CMD" > "$TOGGLE_TMP/on"
[ ! -s "$TOGGLE_TMP/on" ] && pass "COMMENT_BARD_OFF=1 bypasses write gate (no output)" \
  || fail "COMMENT_BARD_OFF=1 did not bypass write gate: $(cat "$TOGGLE_TMP/on")"

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$WRITE_CMD" > "$TOGGLE_TMP/off"
grep -q "x.ts" "$TOGGLE_TMP/off" && pass "write gate still denies with COMMENT_BARD_OFF unset" \
  || fail "write gate did not deny with COMMENT_BARD_OFF unset"

GATE_GITTMP=$(mktemp -d)
git -C "$GATE_GITTMP" init -q
git -C "$GATE_GITTMP" checkout -q -b main
git -C "$GATE_GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// this short line here will not scan today\n' > "$GATE_GITTMP/a.ts"
git -C "$GATE_GITTMP" add a.ts

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_BARD_OFF=1 bash -c "$COMMIT_CMD")
[ -z "$OUT" ] && pass "COMMENT_BARD_OFF=1 bypasses commit gate (no output)" \
  || fail "COMMENT_BARD_OFF=1 did not bypass commit gate: $OUT"

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$COMMIT_CMD")
echo "$OUT" | grep -q "a.ts" && pass "commit gate still denies with COMMENT_BARD_OFF unset" \
  || fail "commit gate did not deny with COMMENT_BARD_OFF unset"

rm -rf "$TOGGLE_TMP" "$GATE_GITTMP"

if [ "$FAIL" -ne 0 ]; then echo "comment-bard: FAILED"; exit 1; fi
echo "comment-bard: all tests passed"
