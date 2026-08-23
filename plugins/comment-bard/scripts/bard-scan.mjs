import { readFileSync } from "node:fs";
import { branchDiff, diffFiles } from "../vendor/comment-core/index.mjs";
import { analyzeLines, diffFindings } from "../hooks/bard-rules.mjs";

const args = process.argv.slice(2);

function pathMode(paths) {
  const files = [];
  const findings = [];
  for (const p of paths) {
    let content;
    try { content = readFileSync(p, "utf8"); } catch { continue; }
    files.push(p);
    const lines = content.split("\n");
    findings.push(...analyzeLines(p, lines, lines.map((_, i) => i + 1)));
  }
  console.log(JSON.stringify({ target: "paths", files, findings }));
}

function branchMode() {
  const base = branchDiff();
  if (!base) {
    console.log(JSON.stringify({ target: null, files: [], findings: [] }));
    return;
  }
  const files = diffFiles(base.diff);
  const findings = diffFindings(base.diff, (f) => readFileSync(`${base.root}/${f}`, "utf8"), analyzeLines);
  console.log(JSON.stringify({ target: base.base, files, findings }));
}

if (args.length > 0) pathMode(args);
else branchMode();
process.exit(0);
