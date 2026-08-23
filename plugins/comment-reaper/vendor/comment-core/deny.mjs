/**
 * writeSync, not process.stdout.write: the hook harness reads stdout over a
 * pipe (~64 KiB buffer). An async write can still be draining when
 * process.exit fires, truncating the JSON right when there's most to report.
 */
import { writeSync } from "node:fs";

export const MAX_RENDERED = 20;

export function renderFindings(findings, { format, max = MAX_RENDERED } = {}) {
  const rest = findings.length - max;
  return findings.slice(0, max).map(format)
    .concat(rest > 0 ? [`  … and ${rest} more.`] : []).join("\n");
}

export function deny(reason) {
  const payload = JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
  writeSync(1, payload);
  process.exit(0);
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function selftest() {
  const findings = Array.from({ length: 25 }, (_, i) => ({ line: i + 1 }));
  const rendered = renderFindings(findings, { format: (f) => `line ${f.line}` });
  assert(rendered.includes("… and 5 more."), "renders overflow tally for >20 findings");
  assert(rendered.split("\n").length === 21, "20 rendered rows + 1 tally row");

  const small = renderFindings([{ line: 1 }], { format: (f) => `line ${f.line}` });
  assert(small === "line 1", "no tally row under the max");

  console.log("deny.mjs selftest OK");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("deny.mjs")) selftest();
