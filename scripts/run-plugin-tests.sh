#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

echo "=== packages/comment-core selftest ==="
node "$ROOT/packages/comment-core/selftest.mjs" || FAIL=1

for plugin_tests in "$ROOT"/plugins/*/tests/run.sh; do
  plugin_dir=$(dirname "$(dirname "$plugin_tests")")
  plugin_name=$(basename "$plugin_dir")
  echo ""
  echo "=== $plugin_name ==="
  bash "$plugin_tests" || FAIL=1
done

echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "run-plugin-tests: one or more suites FAILED"
  exit 1
fi
echo "run-plugin-tests: all suites passed"
