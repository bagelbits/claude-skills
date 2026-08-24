#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
FAIL=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAIL=1; }

echo "== comment-in-the-hat: manifest & wiring =="

NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).name)")
[ "$NAME" = "comment-in-the-hat" ] && pass "plugin.json name matches folder" || fail "name mismatch: $NAME"

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
if (bash.length !== 2 || new Set(bash.map(e => e.if)).size !== 2) { console.error("Bash entries not distinct"); ok = false; }
process.exit(ok ? 0 : 1);
' "$PLUGIN_ROOT" && pass "hooks.json wiring" || fail "hooks.json wiring"

diff -r "$PLUGIN_ROOT/vendor/comment-core" "$REPO_ROOT/packages/comment-core" >/dev/null 2>&1 \
  && pass "vendored comment-core matches canonical" || fail "vendored comment-core drifted"

echo "== provenance: hat-local vendor files =="
[ -f "$PLUGIN_ROOT/vendor/cmudict-map.txt.gz" ] && pass "vendor/cmudict-map.txt.gz present" || fail "vendor/cmudict-map.txt.gz missing"
[ -f "$PLUGIN_ROOT/vendor/VENDOR.md" ] && pass "vendor/VENDOR.md present" || fail "vendor/VENDOR.md missing"
[ -f "$PLUGIN_ROOT/vendor/LICENSE-cmudict" ] && pass "vendor/LICENSE-cmudict present" || fail "vendor/LICENSE-cmudict missing"
grep -q -- "--selftest" "$PLUGIN_ROOT/scripts/build-cmudict.mjs" \
  && fail "build-cmudict.mjs unexpectedly has a --selftest guard" \
  || pass "build-cmudict.mjs has no --selftest guard (one-shot data-generation script)"

echo "== vendored comment-core selftests =="
node "$PLUGIN_ROOT/vendor/comment-core/selftest.mjs" >/tmp/comment-hat-selftest.$$ 2>&1 \
  && pass "vendored comment-core selftests pass" || { fail "vendored comment-core selftest failed"; cat /tmp/comment-hat-selftest.$$; }
rm -f /tmp/comment-hat-selftest.$$

echo "== analyzer import =="
node -e "import('$PLUGIN_ROOT/hooks/hat-rules.mjs').then(()=>console.log('ok')).catch(e=>{console.error(e);process.exit(1)})" \
  && pass "hat-rules.mjs imports cleanly" || fail "hat-rules.mjs import failed"

echo "== write gate =="
TMP=$(mktemp -d)

# A single anapestic comment line with no partner to pair against -- hat
# requires couplets to pair AABB, so a lone prose line is denied as
# "unpaired" even though it scans meter cleanly on its own. Verified via the
# real oracle: "The cat in the hat likes to sit on a mat" scans ok:true.
echo '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// The cat in the hat likes to sit on a mat\n"}}' \
  | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out1"
grep -q "x.ts" "$TMP/out1" && pass "unpaired comment line denied naming file" || fail "unpaired comment line not denied"

# A verified AABB couplet, checked with the real oracle before pasting in:
# "The cat in the hat likes to sit on a mat" and "A dog in a hat likes to
# chase the lost cat" each scan anapestic (7-12 syllables) and "mat"/"cat"
# rhyme.
echo '{"tool_name":"Write","tool_input":{"file_path":"y.ts","content":"const x = 1;\n/**\n * The cat in the hat likes to sit on a mat\n * A dog in a hat likes to chase the lost cat\n */\n"}}' \
  | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out2"
[ ! -s "$TMP/out2" ] && pass "conforming AABB couplet block produces no output" || fail "conforming block produced output"

echo "not json" | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out3"
[ ! -s "$TMP/out3" ] && pass "malformed payload fails open" || fail "malformed payload produced output"

# double-escaped \\r\\n so the JSON text carries the *escape sequence*, not
# raw control bytes -- literal CR/LF in a JSON string is invalid and would
# make JSON.parse throw, which is not what this case is testing.
printf '{"tool_name":"Write","tool_input":{"file_path":"z.ts","content":"const x=1;\\r\\n// The cat in the hat likes to sit on a mat\\r\\n"}}' \
  | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out4"
grep -q "z.ts" "$TMP/out4" && pass "CRLF payload still analyzed" || fail "CRLF payload not analyzed"

# 25 identical unpaired comment lines, each separated by an unrelated code
# line so every "// ..." forms its own one-line comment unit (no accidental
# pairing) -- exactly 25 findings, one per line. Verify the exact rendered
# shape: preamble states the TRUE total (25), body is 20 rendered rows + one
# "... and 5 more." tally row.
node -e '
const lines = [];
for (let i = 0; i < 25; i++) {
  lines.push("// The cat in the hat likes to sit on a mat");
  lines.push("const noop" + i + " = " + i + ";");
}
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "big.ts", content: lines.join("\n") } }));
' > "$TMP/big.json"
node "$PLUGIN_ROOT/hooks/hat-filter.mjs" < "$TMP/big.json" > "$TMP/out5"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out5','utf8')); console.log('parsed')" > "$TMP/parsed" 2>&1
grep -q parsed "$TMP/parsed" && pass "deny with many findings still parses as JSON" || fail "large deny failed to parse"
node -e '
const fs = require("fs");
const o = JSON.parse(fs.readFileSync("'"$TMP"'/out5", "utf8"));
const reason = o.hookSpecificOutput.permissionDecisionReason;
const lines = reason.split("\n");
const ok = reason.includes("adds 25 line(s) that break AABB couplet form")
  && lines.length === 22
  && lines[lines.length - 1] === "  … and 5 more.";
process.exit(ok ? 0 : 1);
' && pass ">20 findings render exact 20-row + tally overflow shape, true total in preamble" \
  || fail "overflow rendering shape or true-total count wrong"

# A genuinely large payload: one // line built from "the " repeated many
# times. "the" is a function word (candidate "?"), so the combined pattern
# is 30000 "?" characters -- far outside the 7-12 syllable window -- and
# fails the meter check immediately (independent of pairing), echoing the
# raw line body verbatim. That alone is enough to push the deny JSON
# payload written to stdout past the ~64KiB pipe buffer deny.mjs's
# writeSync comment warns about.
node -e '
const big = "the ".repeat(30000).trim();
const content = "// " + big;
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "huge.ts", content } }));
' > "$TMP/huge.json"
node "$PLUGIN_ROOT/hooks/hat-filter.mjs" < "$TMP/huge.json" > "$TMP/out6"
BYTES=$(wc -c < "$TMP/out6" | tr -d ' ')
[ "$BYTES" -gt 65536 ] && pass "deny payload genuinely exceeds 64KiB pipe buffer ($BYTES bytes)" \
  || fail "deny payload only $BYTES bytes, not genuinely >64KiB"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out6','utf8')); console.log('parsed')" > "$TMP/parsed6" 2>&1
grep -q parsed "$TMP/parsed6" && pass "genuinely >64KiB deny still parses as JSON" || fail "genuinely large deny failed to parse"
grep -q "huge.ts" "$TMP/out6" && pass "genuinely >64KiB deny still names offending file" || fail "genuinely large deny missing filename"

# Regression for Finding 1: an Edit payload carries no lineMap, but the
# grouped couplet-pairing analysis (commentUnits) must still run against
# it. A single anapestic prose line with no rhyming partner scans meter
# cleanly on its own -- only the grouped "unpaired" check catches it.
node -e '
process.stdout.write(JSON.stringify({
  tool_name: "Edit",
  tool_input: {
    file_path: "edited.ts",
    old_string: "const z = 1;",
    new_string: "const z = 1;\n// The cat in the hat likes to sit on a mat",
  },
}));
' | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out-edit"
grep -q "edited.ts" "$TMP/out-edit" && pass "Edit payload: grouped couplet-pairing rule denies an unpaired line" \
  || fail "Edit payload: grouped couplet-pairing rule did not fire"
grep -q "has no rhyming partner" "$TMP/out-edit" && pass "Edit payload: unpaired finding produced (grouped rule ran)" \
  || fail "Edit payload: unpaired finding missing"

echo "== cat-in-the-hat: hatch =="
# A cat-in-the-hat: line sitting at the TOP of the comment, above an
# otherwise-conforming couplet, hoists the unspeakable camelCase token out
# of the way -- zero findings.
node -e '
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "hatch-ok.ts", content: "const x = 1;\n/**\n * cat-in-the-hat: fooBarBaz\n * The cat in the hat likes to sit on a mat\n * A dog in a hat likes to chase the lost cat\n */\n" } }));
' | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out7"
[ ! -s "$TMP/out7" ] && pass "top-of-comment cat-in-the-hat: hatch produces no output" || fail "properly hatched block wrongly denied"

# The same hatch line, but *after* the first couplet line instead of above
# it -- must be flagged as a "hoist" finding, not silently accepted.
node -e '
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "hatch-bad.ts", content: "const x = 1;\n/**\n * The cat in the hat likes to sit on a mat\n * cat-in-the-hat: fooBarBaz\n * A dog in a hat likes to chase the lost cat\n */\n" } }));
' | node "$PLUGIN_ROOT/hooks/hat-filter.mjs" > "$TMP/out8"
grep -q "hatch-bad.ts:4" "$TMP/out8" && grep -q "must sit at the top of its comment" "$TMP/out8" \
  && pass "mid-comment cat-in-the-hat: line flagged as hoist violation" \
  || fail "mid-comment hatch line not flagged as hoist violation"

echo "== real-map oracle assertions =="
node -e '
import("'"$PLUGIN_ROOT"'/vendor/comment-core/analyzers/cmudict.mjs").then(({ createCmudict }) => {
  const oracle = createCmudict(new URL("file://'"$PLUGIN_ROOT"'/vendor/cmudict-map.txt.gz"));
  const checks = [
    ["read/red rhyme", oracle.rhymes("read", "red") === true],
    ["though/tough do not rhyme", oracle.rhymes("though", "tough") === false],
    ["mat/hat rhyme", oracle.rhymes("mat", "hat") === true],
  ];
  let ok = true;
  for (const [name, pass] of checks) { console.log((pass ? "  PASS: " : "  FAIL: ") + name); if (!pass) ok = false; }
  process.exit(ok ? 0 : 1);
});
' && pass "real-map rhyme assertions" || fail "real-map rhyme assertions"

# The namesake couplet lives at the top of hooks/hat-rules.mjs:
#   "Two lines of prose must rhyme and share one beat"
#   "So each terse note feels light and stays neat"
# Both lines must independently scan as anapestic meter per the real oracle.
node -e '
import("'"$PLUGIN_ROOT"'/vendor/comment-core/analyzers/cmudict.mjs").then(({ createCmudict }) => {
  const oracle = createCmudict(new URL("file://'"$PLUGIN_ROOT"'/vendor/cmudict-map.txt.gz"));
  const a = "Two lines of prose must rhyme and share one beat".split(/\s+/);
  const b = "So each terse note feels light and stays neat".split(/\s+/);
  const okA = oracle.scanMeter(a).ok === true;
  const okB = oracle.scanMeter(b).ok === true;
  console.log((okA ? "  PASS" : "  FAIL") + ": namesake couplet line A scans");
  console.log((okB ? "  PASS" : "  FAIL") + ": namesake couplet line B scans");
  process.exit(okA && okB ? 0 : 1);
});
' || fail "namesake couplet meter check"

echo "== two-line non-rhyming couplet denied =="
# Both lines verified with the real oracle to scan anapestic (7-12
# syllables, correct stress) on their own -- only their rhyme fails ("mat"
# and "street" don't rhyme), so the finding must be "rhyme", not "meter".
TMP2=$(mktemp -d)
cat > "$TMP2/a.ts" <<'EOF'
// The cat in the hat likes to sit on a mat
// A dog in a hat likes to run down the street
EOF
OUT=$(node "$PLUGIN_ROOT/scripts/hat-scan.mjs" "$TMP2/a.ts")
echo "$OUT" | grep -q '"line":2' && echo "$OUT" | grep -q "does not rhyme" \
  && pass "non-rhyming couplet flagged on a.ts:2 with 'does not rhyme'" \
  || { echo "  FAIL: non-rhyming couplet not flagged as expected: $OUT"; FAIL=1; }
rm -rf "$TMP2"

echo "== commit/PR gate =="
GITTMP=$(mktemp -d)
git -C "$GITTMP" init -q
git -C "$GITTMP" checkout -q -b main
git -C "$GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// The cat in the hat likes to sit on a mat\n' > "$GITTMP/a.ts"
git -C "$GITTMP" add a.ts
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "violating branch denied naming file" || fail "violating branch not denied"

# a.ts was staged but never committed -- `git checkout -b` carries the index
# forward, so without this reset it would still show up (and still violate)
# in every later branch's --cached diff against main.
git -C "$GITTMP" reset --hard -q

git -C "$GITTMP" checkout -q -b clean-branch main
printf 'const y = 2;\n' > "$GITTMP/b.ts"
git -C "$GITTMP" add b.ts
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
[ -z "$OUT" ] && pass "clean branch produces no output" || fail "clean branch produced output"

NOTGIT=$(mktemp -d)
OUT=$(cd "$NOTGIT" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
[ -z "$OUT" ] && pass "outside git repo fails open" || fail "outside git repo produced output"

git -C "$GITTMP" checkout -q -b hostile main
git -C "$GITTMP" config core.quotePath true
git -C "$GITTMP" config diff.noprefix true
git -C "$GITTMP" config diff.mnemonicPrefix true
git -C "$GITTMP" config diff.relative true
git -C "$GITTMP" config color.ui always
mkdir -p "$GITTMP/sub"
printf 'const x = 1;\n// The cat in the hat likes to sit on a mat\n' > "$GITTMP/sub/c.ts"
git -C "$GITTMP" add sub/c.ts
OUT=$(cd "$GITTMP/sub" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
echo "$OUT" | grep -q "sub/c.ts" && pass "hostile diff config still denies with correct path" || fail "hostile diff config broke path resolution: $OUT"
git -C "$GITTMP" reset --hard -q

# Filename with a space: git pads the "+++ b/..." header with a trailing
# tab when the path contains a space. headerPath() must strip that tab, not
# fold it into the filename or corrupt it.
git -C "$GITTMP" checkout -q -b spacey main
printf 'const x = 1;\n// The cat in the hat likes to sit on a mat\n' > "$GITTMP/my file.ts"
git -C "$GITTMP" add "my file.ts"
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
echo "$OUT" | grep -q "my file.ts:2" && pass "space-containing filename denied with tab stripped, not corrupted" \
  || fail "space-containing filename mishandled: $OUT"
git -C "$GITTMP" reset --hard -q

# Non-ASCII filename alongside a normal one, both violating (with different
# unpaired lines, so each finding is unambiguous). diff.mjs's DIFF_CONFIG
# forces `-c core.quotePath=false` on every git invocation (see diff.mjs),
# which defeats octal-escaping of non-ASCII bytes even when the repo config
# (set here) tries to force quoting back on -- so café.ts's raw UTF-8 name
# should come through the header intact rather than being quoted-and-dropped,
# and neither file's finding should bleed into the other's.
git -C "$GITTMP" checkout -q -b nonascii main
git -C "$GITTMP" config core.quotePath true
printf 'const y = 2;\n// The cat in the hat likes to sit on a mat\n' > "$GITTMP/café.ts"
printf 'const z = 3;\n// A fish in the hat likes to swim with the cat\n' > "$GITTMP/normal.ts"
git -C "$GITTMP" add "café.ts" normal.ts
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-hat-check.mjs")
echo "$OUT" | grep -q "adds 2 line(s) that break AABB couplet form" && pass "non-ASCII + normal filename: both findings counted, none dropped" \
  || fail "non-ASCII + normal filename: wrong finding count: $OUT"
echo "$OUT" | grep -qF 'café.ts:2 — has no rhyming partner — a couplet needs two lines; add a rhyming line: \"The cat in the hat likes to sit on a mat\"' && pass "non-ASCII filename correctly attributed its own finding" \
  || fail "non-ASCII filename finding missing or misattributed: $OUT"
echo "$OUT" | grep -qF 'normal.ts:2 — has no rhyming partner — a couplet needs two lines; add a rhyming line: \"A fish in the hat likes to swim with the cat\"' && pass "normal filename finding not polluted by non-ASCII neighbor" \
  || fail "normal filename finding missing or polluted: $OUT"
git -C "$GITTMP" reset --hard -q
git -C "$GITTMP" config --unset core.quotePath || true

echo "== scan script =="
OUT=$(node "$PLUGIN_ROOT/scripts/hat-scan.mjs" "$GITTMP/a.ts")
echo "$OUT" | grep -q '"target":"paths"' && pass "path mode reports target: paths" || fail "path mode target wrong"

# Branch mode with no args, from inside a repo with a resolvable base and
# nothing staged: target must be the resolved base branch name (not null,
# not omitted), and findings must be an explicit empty array.
SCANTMP=$(mktemp -d)
git -C "$SCANTMP" init -q
git -C "$SCANTMP" checkout -q -b main
git -C "$SCANTMP" commit -q --allow-empty -m base
OUT=$(cd "$SCANTMP" && node "$PLUGIN_ROOT/scripts/hat-scan.mjs")
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
printf 'const x = 1;\n// The cat in the hat likes to sit on a mat\n' > "$TMP/vendor/dummy.ts"
OUT=$(node "$PLUGIN_ROOT/scripts/hat-scan.mjs" "$TMP/vendor/dummy.ts")
node -e '
const o = JSON.parse(process.argv[1]);
process.exit(Array.isArray(o.findings) && o.findings.length === 0 ? 0 : 1);
' "$OUT" && pass "vendor/ path produces zero findings (third-party exclusion)" \
  || fail "vendor/ path was analyzed for findings: $OUT"

rm -rf "$TMP" "$GITTMP" "$NOTGIT"

echo "== meta-constraint: hat's own source passes its own gate =="
# build-cmudict.mjs (scripts/*.mjs) is a one-shot data-generation script and
# would be exempt from this gate as tooling rather than a runtime-consumed
# source file -- it happens to carry no prose comments of its own either
# way, so scanning the full scripts/*.mjs glob alongside hooks/*.mjs is
# consistent with excluding it on purpose.
OUT=$(node "$PLUGIN_ROOT/scripts/hat-scan.mjs" "$PLUGIN_ROOT"/hooks/*.mjs "$PLUGIN_ROOT"/scripts/*.mjs)
FINDINGS_COUNT=$(echo "$OUT" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf8')).findings.length)")
[ "$FINDINGS_COUNT" = "0" ] && pass "hat's own hooks/*.mjs and scripts/*.mjs pass its own gate" || fail "hat's own source has $FINDINGS_COUNT violation(s): $OUT"

if [ "$FAIL" -ne 0 ]; then echo "comment-in-the-hat: FAILED"; exit 1; fi
echo "comment-in-the-hat: all tests passed"
