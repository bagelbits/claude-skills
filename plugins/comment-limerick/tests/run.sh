#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
FAIL=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAIL=1; }

echo "== comment-limerick: manifest & wiring =="

NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).name)")
[ "$NAME" = "comment-limerick" ] && pass "plugin.json name matches folder" || fail "name mismatch: $NAME"

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

echo "== provenance: limerick-local vendor files =="
[ -f "$PLUGIN_ROOT/vendor/cmudict-map.txt.gz" ] && pass "vendor/cmudict-map.txt.gz present" || fail "vendor/cmudict-map.txt.gz missing"
[ -f "$PLUGIN_ROOT/vendor/VENDOR.md" ] && pass "vendor/VENDOR.md present" || fail "vendor/VENDOR.md missing"
[ -f "$PLUGIN_ROOT/vendor/LICENSE-cmudict" ] && pass "vendor/LICENSE-cmudict present" || fail "vendor/LICENSE-cmudict missing"
diff "$PLUGIN_ROOT/vendor/cmudict-map.txt.gz" "$REPO_ROOT/plugins/comment-in-the-hat/vendor/cmudict-map.txt.gz" >/dev/null 2>&1 \
  && pass "vendored cmudict-map.txt.gz identical to comment-in-the-hat's" || fail "vendored cmudict-map.txt.gz diverged from comment-in-the-hat's"

echo "== vendored comment-core selftests =="
node "$PLUGIN_ROOT/vendor/comment-core/selftest.mjs" >/tmp/comment-limerick-selftest.$$ 2>&1 \
  && pass "vendored comment-core selftests pass" || { fail "vendored comment-core selftest failed"; cat /tmp/comment-limerick-selftest.$$; }
rm -f /tmp/comment-limerick-selftest.$$

echo "== analyzer import =="
node -e "import('$PLUGIN_ROOT/hooks/limerick-rules.mjs').then(()=>console.log('ok')).catch(e=>{console.error(e);process.exit(1)})" \
  && pass "limerick-rules.mjs imports cleanly" || fail "limerick-rules.mjs import failed"

echo "== write gate: conforming limerick =="
TMP=$(mktemp -d)

# The five-line namesake limerick, verified with the real oracle in Task 4:
# all three rhyme checks true, all five lines scan for their role.
echo '{"tool_name":"Write","tool_input":{"file_path":"ok.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished the moment it showed\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out1"
[ ! -s "$TMP/out1" ] && pass "conforming AABBA limerick produces no output" || fail "conforming limerick produced output: $(cat "$TMP/out1")"

echo "not json" | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out2"
[ ! -s "$TMP/out2" ] && pass "malformed payload fails open" || fail "malformed payload produced output"

# double-escaped \\r\\n so the JSON text carries the *escape sequence*, not
# raw control bytes -- literal CR/LF in a JSON string is invalid.
printf '{"tool_name":"Write","tool_input":{"file_path":"z.ts","content":"const x=1;\\r\\n// stray line comment\\r\\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out3"
grep -q "z.ts" "$TMP/out3" && pass "CRLF payload still analyzed" || fail "CRLF payload not analyzed"

echo "== // line comment denied on form =="
echo '{"tool_name":"Write","tool_input":{"file_path":"lineform.ts","content":"const x = 1;\n// There once was a bug in the code\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out4"
grep -q "lineform.ts:2" "$TMP/out4" && pass "// prose comment denied naming file:line" || fail "// prose comment not denied"
grep -q "cannot carry a limerick" "$TMP/out4" && pass "// prose comment denied with form reason" || fail "// prose comment missing form reason"

echo "== non-rhyming A-line denied =="
# Line 5 changed to "and vanished before it was seen" -- verified in Step 1
# to scan fine (ok:true) but not rhyme with "code"/"road" (rhymes=false).
echo '{"tool_name":"Write","tool_input":{"file_path":"norhyme.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished before it was seen\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out5"
grep -q "norhyme.ts:7" "$TMP/out5" && pass "non-rhyming A-line denied naming file:line" || fail "non-rhyming A-line not denied"
grep -q "A-lines must rhyme" "$TMP/out5" && pass "non-rhyming A-line carries rhyme reason" || fail "non-rhyming A-line missing rhyme reason"

echo "== out-of-range A-line meter denied =="
# Verified in Step 1: 19 syllables, ok:false, outside the 7-10 A-line window.
echo '{"tool_name":"Write","tool_input":{"file_path":"ameter.ts","content":"const x = 1;\n/**\n * the code was entirely too long and kept running past every limit\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished the moment it showed\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out6"
grep -q "ameter.ts:3" "$TMP/out6" && pass "out-of-range A-line denied naming file:line" || fail "out-of-range A-line not denied"
grep -q "19 syllable(s), needs 7–10" "$TMP/out6" && pass "out-of-range A-line carries correct syllable count and window" || fail "out-of-range A-line reason wrong: $(cat "$TMP/out6")"

echo "== out-of-range B-line meter denied =="
# Verified in Step 1: 11 syllables, ok:false, outside the 5-7 B-line window.
echo '{"tool_name":"Write","tool_input":{"file_path":"bmeter.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * it crashed every single night of the week\n * gave the team quite a fright\n * and vanished the moment it showed\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out7"
grep -q "bmeter.ts:5" "$TMP/out7" && pass "out-of-range B-line denied naming file:line" || fail "out-of-range B-line not denied"
grep -q "11 syllable(s), needs 5–7" "$TMP/out7" && pass "out-of-range B-line carries correct syllable count and window" || fail "out-of-range B-line reason wrong: $(cat "$TMP/out7")"

echo "== ragged-tail shape rule =="
# The five conforming lines plus one extra (repeating line 1's text) --
# lines 1-5 form a complete limerick and must NOT be flagged; line 6 is a
# ragged tail and must be flagged regardless of its own scan/rhyme.
echo '{"tool_name":"Write","tool_input":{"file_path":"ragged.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished the moment it showed\n * There once was a bug in the code\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out8"
grep -q "ragged.ts:8" "$TMP/out8" && pass "6th prose line (past the whole limerick) flagged as ragged tail" || fail "ragged tail not flagged"
grep -q "6 prose line(s) in this block" "$TMP/out8" && pass "ragged-tail finding carries the true block line count" || fail "ragged-tail finding missing block line count"
grep -qF "ragged.ts:3" "$TMP/out8" && fail "1st line of the complete limerick wrongly flagged" || pass "1st line of the complete limerick not flagged"
grep -qF "ragged.ts:7" "$TMP/out8" && fail "5th line of the complete limerick wrongly flagged" || pass "5th line of the complete limerick not flagged"

echo "== orphan one-liner block comment =="
# A standalone /** ... */ one-liner previously produced zero findings: it's
# tagged form: "block" (excluding it from the // line-form check) but
# blockRuns() never opens a run for a line with both /** and */ on it
# (excluding it from the grouped shape/rhyme/meter check too), so it fell
# through both mechanisms. "It crashed every night" is one of the verified
# namesake lines (6 syllables, a fine limerick B-line in isolation), but
# alone it is only 1 of the 5 lines a limerick needs.
echo '{"tool_name":"Write","tool_input":{"file_path":"orphan.ts","content":"const x = 1;\n/** It crashed every night */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out-orphan1"
grep -q "orphan.ts:2" "$TMP/out-orphan1" && pass "standalone one-liner block comment now flagged (was silently allowed)" \
  || fail "standalone one-liner block comment still bypasses the gate"
grep -q "1 prose line(s) in this block" "$TMP/out-orphan1" && pass "standalone one-liner flagged with the ragged-tail shape reason" \
  || fail "standalone one-liner missing shape reason: $(cat "$TMP/out-orphan1")"

# Five one-liners on consecutive lines must chain into one complete,
# correctly-scanning limerick (AABBA) and produce NO findings -- the same
# verified namesake five lines used elsewhere in this file, just written as
# five separate one-liner comments instead of one multi-line block.
echo '{"tool_name":"Write","tool_input":{"file_path":"chained.ts","content":"const x = 1;\n/** There once was a bug in the code */\n/** It broke every build down the road */\n/** It crashed every night */\n/** gave the team quite a fright */\n/** and vanished the moment it showed */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out-orphan2"
[ ! -s "$TMP/out-orphan2" ] && pass "five chained one-liners forming a complete limerick produce no output" \
  || fail "chained one-liner limerick wrongly denied: $(cat "$TMP/out-orphan2")"

# A one-liner with a genuine meter mismatch must still be caught, proving
# the full per-role meter/rhyme check (not just the shape/count check) runs
# over one-liner-derived groups. Reuses the already-verified out-of-range
# B-line fixture (11 syllables, outside the 5-7 B-line window) as one-liner
# line 3 in an otherwise-conforming 5-line one-liner chain.
echo '{"tool_name":"Write","tool_input":{"file_path":"chainedbad.ts","content":"const x = 1;\n/** There once was a bug in the code */\n/** It broke every build down the road */\n/** it crashed every single night of the week */\n/** gave the team quite a fright */\n/** and vanished the moment it showed */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out-orphan3"
grep -q "chainedbad.ts:4" "$TMP/out-orphan3" && pass "chained one-liner with wrong meter on its line flagged" \
  || fail "chained one-liner meter mismatch not caught: $(cat "$TMP/out-orphan3")"
grep -q "11 syllable(s), needs 5–7" "$TMP/out-orphan3" && pass "chained one-liner meter-mismatch finding names the syllable count and window" \
  || fail "chained one-liner meter-mismatch finding missing detail: $(cat "$TMP/out-orphan3")"

echo "== nantucket: hatch =="
# A nantucket: line mixed anywhere among the five conforming lines is never
# scanned and carries no positional requirement -- zero findings.
echo '{"tool_name":"Write","tool_input":{"file_path":"hatch-ok.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * nantucket: fooBarBaz\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished the moment it showed\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out9"
[ ! -s "$TMP/out9" ] && pass "nantucket: hatch anywhere in the comment produces no output" || fail "properly hatched block wrongly denied: $(cat "$TMP/out9")"

echo "== mixed-block: unspeakable line without hatch =="
# Same unspeakable token, but NOT nantucket:-prefixed -- must be flagged,
# even though the five real prose lines still form one complete, conforming
# limerick group on their own.
echo '{"tool_name":"Write","tool_input":{"file_path":"mixed.ts","content":"const x = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished the moment it showed\n * fooBarBaz\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out10"
grep -q "mixed.ts:8" "$TMP/out10" && pass "unhatched unspeakable line in a scanning block denied" || fail "unhatched unspeakable line not denied"
grep -q "hoist the token onto its own exempt line" "$TMP/out10" && pass "mixed-block finding carries the hoist reason" || fail "mixed-block finding missing hoist reason"

echo "== Edit payload: grouped rules still run without a lineMap =="
# Regression for the same class of bug fixed in hat/bard: an Edit payload
# carries no lineMap, but the grouped shape/meter/rhyme analysis (blockRuns)
# must still run against it.
node -e '
process.stdout.write(JSON.stringify({
  tool_name: "Edit",
  tool_input: {
    file_path: "edited.ts",
    old_string: "const z = 1;",
    new_string: "const z = 1;\n/**\n * There once was a bug in the code\n * It broke every build down the road\n * It crashed every night\n * gave the team quite a fright\n * and vanished before it was seen\n */",
  },
}));
' | node "$PLUGIN_ROOT/hooks/limerick-filter.mjs" > "$TMP/out-edit"
grep -q "edited.ts" "$TMP/out-edit" && pass "Edit payload: grouped rhyme rule denies a non-rhyming A-line" || fail "Edit payload: grouped rule did not fire"
grep -q "A-lines must rhyme" "$TMP/out-edit" && ! grep -q "undefined" "$TMP/out-edit" \
  && pass "Edit-path rhyme finding produced with no 'undefined' partner line" \
  || fail "Edit-path rhyme finding missing or partner line rendered as 'undefined': $(cat "$TMP/out-edit")"

echo "== real-map oracle assertions =="
node -e '
import("'"$PLUGIN_ROOT"'/vendor/comment-core/analyzers/cmudict.mjs").then(({ createCmudict }) => {
  const oracle = createCmudict(new URL("file://'"$PLUGIN_ROOT"'/vendor/cmudict-map.txt.gz"));
  const checks = [
    ["code/road rhyme", oracle.rhymes("code", "road") === true],
    ["road/showed rhyme", oracle.rhymes("road", "showed") === true],
    ["night/fright rhyme", oracle.rhymes("night", "fright") === true],
    ["code/seen do not rhyme", oracle.rhymes("code", "seen") === false],
  ];
  let ok = true;
  for (const [name, pass] of checks) { console.log((pass ? "  PASS: " : "  FAIL: ") + name); if (!pass) ok = false; }
  process.exit(ok ? 0 : 1);
});
' && pass "real-map rhyme assertions" || fail "real-map rhyme assertions"

# The namesake limerick lives at the top of hooks/limerick-rules.mjs. All
# five lines must independently scan for their role per the real oracle.
node -e '
import("'"$PLUGIN_ROOT"'/vendor/comment-core/analyzers/cmudict.mjs").then(({ createCmudict }) => {
  const oracle = createCmudict(new URL("file://'"$PLUGIN_ROOT"'/vendor/cmudict-map.txt.gz"));
  const A = { min: 7, max: 10 };
  const B = { min: 5, max: 7 };
  const lines = [
    ["There once was a bug in the code", A],
    ["It broke every build down the road", A],
    ["It crashed every night", B],
    ["gave the team quite a fright", B],
    ["and vanished the moment it showed", A],
  ];
  let ok = true;
  lines.forEach(([line, range], i) => {
    const r = oracle.scanMeter(line.split(/\s+/), range);
    console.log((r.ok ? "  PASS" : "  FAIL") + `: namesake limerick line ${i + 1} scans`);
    if (!r.ok) ok = false;
  });
  process.exit(ok ? 0 : 1);
});
' || fail "namesake limerick meter check"

echo "== commit/PR gate =="
COMMIT_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}'
GITTMP=$(mktemp -d)
git -C "$GITTMP" init -q
git -C "$GITTMP" checkout -q -b main
git -C "$GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// stray line comment\n' > "$GITTMP/a.ts"
git -C "$GITTMP" add a.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "violating branch denied naming file" || fail "violating branch not denied"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs")
[ -z "$OUT" ] && pass "unrelated Bash command skips the branch scan" || fail "unrelated Bash command still scanned the branch"

OUT=$(cd "$GITTMP" && echo '{"tool_name":"mcp__plugin_github_github__create_pull_request","tool_input":{}}' | node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "gh MCP pull-request tool still scans the branch" || fail "gh MCP pull-request tool did not scan"

OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs" < /dev/null)
[ -z "$OUT" ] && pass "empty payload fails open" || fail "empty payload produced output"

git -C "$GITTMP" reset --hard -q

git -C "$GITTMP" checkout -q -b clean-branch main
printf 'const y = 2;\n' > "$GITTMP/b.ts"
git -C "$GITTMP" add b.ts
OUT=$(cd "$GITTMP" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs")
[ -z "$OUT" ] && pass "clean branch produces no output" || fail "clean branch produced output"

NOTGIT=$(mktemp -d)
OUT=$(cd "$NOTGIT" && echo "$COMMIT_PAYLOAD" | node "$PLUGIN_ROOT/hooks/pre-pr-limerick-check.mjs")
[ -z "$OUT" ] && pass "outside git repo fails open" || fail "outside git repo produced output"

echo "== scan script =="
OUT=$(node "$PLUGIN_ROOT/scripts/limerick-scan.mjs" "$GITTMP/a.ts")
echo "$OUT" | grep -q '"target":"paths"' && pass "path mode reports target: paths" || fail "path mode target wrong"

SCANTMP=$(mktemp -d)
git -C "$SCANTMP" init -q
git -C "$SCANTMP" checkout -q -b main
git -C "$SCANTMP" commit -q --allow-empty -m base
OUT=$(cd "$SCANTMP" && node "$PLUGIN_ROOT/scripts/limerick-scan.mjs")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(o.target === "main" && Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "branch mode with clean diff reports resolved base and empty findings" \
  || fail "branch mode clean-diff shape wrong: $OUT"
rm -rf "$SCANTMP"

mkdir -p "$TMP/vendor"
printf 'const x = 1;\n// stray line comment\n' > "$TMP/vendor/dummy.ts"
OUT=$(node "$PLUGIN_ROOT/scripts/limerick-scan.mjs" "$TMP/vendor/dummy.ts")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "vendor/ path produces zero findings (third-party exclusion)" \
  || fail "vendor/ path was analyzed for findings: $OUT"

rm -rf "$TMP" "$GITTMP" "$NOTGIT"

echo "== meta-constraint: limerick's own source passes its own gate =="
OUT=$(node "$PLUGIN_ROOT/scripts/limerick-scan.mjs" "$PLUGIN_ROOT"/hooks/*.mjs "$PLUGIN_ROOT"/scripts/*.mjs)
FINDINGS_COUNT=$(echo "$OUT" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).findings.length)")
[ "$FINDINGS_COUNT" = "0" ] && pass "limerick's own hooks/*.mjs and scripts/*.mjs pass its own gate" || fail "limerick's own source has $FINDINGS_COUNT violation(s): $OUT"

echo "== gate toggle: COMMENT_LIMERICK_OFF =="
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
PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// stray line comment\n"}}'

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_LIMERICK_OFF=1 bash -c "$WRITE_CMD" > "$TOGGLE_TMP/on"
[ ! -s "$TOGGLE_TMP/on" ] && pass "COMMENT_LIMERICK_OFF=1 bypasses write gate (no output)" \
  || fail "COMMENT_LIMERICK_OFF=1 did not bypass write gate: $(cat "$TOGGLE_TMP/on")"

echo "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$WRITE_CMD" > "$TOGGLE_TMP/off"
grep -q "x.ts" "$TOGGLE_TMP/off" && pass "write gate still denies with COMMENT_LIMERICK_OFF unset" \
  || fail "write gate did not deny with COMMENT_LIMERICK_OFF unset"

GATE_GITTMP=$(mktemp -d)
git -C "$GATE_GITTMP" init -q
git -C "$GATE_GITTMP" checkout -q -b main
git -C "$GATE_GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// stray line comment\n' > "$GATE_GITTMP/a.ts"
git -C "$GATE_GITTMP" add a.ts

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" COMMENT_LIMERICK_OFF=1 bash -c "$COMMIT_CMD")
[ -z "$OUT" ] && pass "COMMENT_LIMERICK_OFF=1 bypasses commit gate (no output)" \
  || fail "COMMENT_LIMERICK_OFF=1 did not bypass commit gate: $OUT"

OUT=$(cd "$GATE_GITTMP" && echo "$COMMIT_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$COMMIT_CMD")
echo "$OUT" | grep -q "a.ts" && pass "commit gate still denies with COMMENT_LIMERICK_OFF unset" \
  || fail "commit gate did not deny with COMMENT_LIMERICK_OFF unset"

rm -rf "$TOGGLE_TMP" "$GATE_GITTMP"

if [ "$FAIL" -ne 0 ]; then echo "comment-limerick: FAILED"; exit 1; fi
echo "comment-limerick: all tests passed"
