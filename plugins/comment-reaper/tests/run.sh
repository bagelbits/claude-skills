#!/usr/bin/env bash
set -uo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
FAIL=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAIL=1; }

echo "== comment-reaper: manifest & wiring =="

NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/.claude-plugin/plugin.json')).name)")
[ "$NAME" = "comment-reaper" ] && pass "plugin.json name matches folder" || fail "name mismatch: $NAME"

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

echo "== analyzer import =="
node -e "import('$PLUGIN_ROOT/hooks/reaper-rules.mjs').then(()=>console.log('ok')).catch(e=>{console.error(e);process.exit(1)})" \
  && pass "reaper-rules.mjs imports cleanly" || fail "reaper-rules.mjs import failed"

echo "== write gate =="
TMP=$(mktemp -d)

echo '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"const x = 1;\n// sets the value\n"}}' \
  | node "$PLUGIN_ROOT/hooks/reaper-filter.mjs" > "$TMP/out1"
grep -q "x.ts" "$TMP/out1" && pass "violating write denied naming file" || fail "violation not denied"

echo '{"tool_name":"Write","tool_input":{"file_path":"y.ts","content":"const x = 1; // retry avoids a race with the webhook\n"}}' \
  | node "$PLUGIN_ROOT/hooks/reaper-filter.mjs" > "$TMP/out2"
[ ! -s "$TMP/out2" ] && pass "conforming write produces no output" || fail "conforming write produced output"

echo "not json" | node "$PLUGIN_ROOT/hooks/reaper-filter.mjs" > "$TMP/out3"
[ ! -s "$TMP/out3" ] && pass "malformed payload fails open" || fail "malformed payload produced output"

# double-escaped \\r\\n so the JSON text carries the *escape sequence*, not
# raw control bytes -- literal CR/LF in a JSON string is invalid and would
# make JSON.parse throw, which is not what this case is testing.
printf '{"tool_name":"Write","tool_input":{"file_path":"z.ts","content":"const x=1;\\r\\n// sets the value\\r\\n"}}' \
  | node "$PLUGIN_ROOT/hooks/reaper-filter.mjs" > "$TMP/out4"
grep -q "z.ts" "$TMP/out4" && pass "CRLF payload still analyzed" || fail "CRLF payload not analyzed"

node -e '
const lines = [];
for (let i = 0; i < 25; i++) lines.push("// sets value " + i);
process.stdout.write(JSON.stringify({ tool_name: "Write", tool_input: { file_path: "big.ts", content: lines.join("\n") } }));
' > "$TMP/big.json"
node "$PLUGIN_ROOT/hooks/reaper-filter.mjs" < "$TMP/big.json" > "$TMP/out5"
node -e "JSON.parse(require('fs').readFileSync('$TMP/out5','utf8')); console.log('parsed')" > "$TMP/parsed" 2>&1
grep -q parsed "$TMP/parsed" && pass "deny >64KiB still parses as JSON" || fail "large deny failed to parse"
grep -q "more\." "$TMP/out5" && pass ">20 findings render overflow tally" || fail "no overflow tally"

echo "== commit/PR gate =="
GITTMP=$(mktemp -d)
git -C "$GITTMP" init -q
git -C "$GITTMP" checkout -q -b main
git -C "$GITTMP" commit -q --allow-empty -m base
printf 'const x = 1;\n// sets the value\n' > "$GITTMP/a.ts"
git -C "$GITTMP" add a.ts
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-reaper-check.mjs")
echo "$OUT" | grep -q "a.ts" && pass "violating branch denied naming file" || fail "violating branch not denied"

# a.ts was staged but never committed -- `git checkout -b` carries the index
# forward, so without this reset it would still show up (and still violate)
# in every later branch's --cached diff against main.
git -C "$GITTMP" reset --hard -q

git -C "$GITTMP" checkout -q -b clean-branch main
printf 'const y = 2;\n' > "$GITTMP/b.ts"
git -C "$GITTMP" add b.ts
OUT=$(cd "$GITTMP" && node "$PLUGIN_ROOT/hooks/pre-pr-reaper-check.mjs")
[ -z "$OUT" ] && pass "clean branch produces no output" || fail "clean branch produced output"

NOTGIT=$(mktemp -d)
OUT=$(cd "$NOTGIT" && node "$PLUGIN_ROOT/hooks/pre-pr-reaper-check.mjs")
[ -z "$OUT" ] && pass "outside git repo fails open" || fail "outside git repo produced output"

git -C "$GITTMP" checkout -q -b hostile main
git -C "$GITTMP" config core.quotePath true
git -C "$GITTMP" config diff.noprefix true
git -C "$GITTMP" config diff.mnemonicPrefix true
git -C "$GITTMP" config diff.relative true
git -C "$GITTMP" config color.ui always
mkdir -p "$GITTMP/sub"
printf 'const x = 1;\n// sets the value\n' > "$GITTMP/sub/c.ts"
git -C "$GITTMP" add sub/c.ts
OUT=$(cd "$GITTMP/sub" && node "$PLUGIN_ROOT/hooks/pre-pr-reaper-check.mjs")
echo "$OUT" | grep -q "sub/c.ts" && pass "hostile diff config still denies with correct path" || fail "hostile diff config broke path resolution: $OUT"

echo "== scan script =="
OUT=$(node "$PLUGIN_ROOT/scripts/reaper-scan.mjs" "$GITTMP/a.ts")
echo "$OUT" | grep -q '"target":"paths"' && pass "path mode reports target: paths" || fail "path mode target wrong"

rm -rf "$TMP" "$GITTMP" "$NOTGIT"

if [ "$FAIL" -ne 0 ]; then echo "comment-reaper: FAILED"; exit 1; fi
echo "comment-reaper: all tests passed"
