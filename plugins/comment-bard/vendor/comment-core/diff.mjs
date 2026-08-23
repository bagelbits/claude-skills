/**
 * This is the only place line math is done
 * for added lines; each plugin's diff walk comes
 * through here, so guessing where a comment fell
 * gets solved a single time, and only once
 */
import { execFileSync } from "node:child_process";

export const HUNK        = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/;
export const FILE_HEADER = /^\+\+\+ (b\/|"b\/)/;
export const DIFF_FLAGS  = ["--no-ext-diff", "--no-color", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/"];
export const DIFF_CONFIG = ["-c", "core.quotePath=false", "-c", "diff.relative=false"];

export function headerPath(raw) {
  if (raw.startsWith('+++ "b/')) return null;
  const m = /^\+\+\+ b\/(.*)$/.exec(raw);
  if (!m) return null;
  return m[1].replace(/\t$/, "");
}

export function walkAddedLines(diff, onAdded, onFile) {
  let file = null;
  let newLine = 1;

  for (const line of diff.split("\n")) {
    if (FILE_HEADER.test(line)) {
      file = headerPath(line);
      newLine = 1;
      if (file !== null && onFile) onFile(file);
      continue;
    }
    const hunk = HUNK.exec(line);
    if (hunk) {
      newLine = Number(hunk[1]);
      continue;
    }
    if (line.startsWith("+")) {
      if (line === "+++ /dev/null") continue;
      if (file !== null) onAdded(file, newLine, line.slice(1));
      newLine++;
      continue;
    }
    if (line === "" || line.startsWith(" ")) {
      newLine++;
    }
  }
}

export function analyzeDiff(diff, analyzeLines) {
  const findings = [];
  const batches = new Map();
  const order = [];

  walkAddedLines(
    diff,
    (file, lineNo, text) => {
      if (!batches.has(file)) {
        batches.set(file, { lines: [], lineMap: [] });
        order.push(file);
      }
      const b = batches.get(file);
      b.lines.push(text);
      b.lineMap.push(lineNo);
    },
  );

  for (const file of order) {
    const { lines, lineMap } = batches.get(file);
    findings.push(...analyzeLines(file, lines, lineMap));
  }

  return findings;
}

export function addedLineNumbers(diff) {
  const map = new Map();
  walkAddedLines(diff, (file, lineNo) => {
    if (!map.has(file)) map.set(file, new Set());
    map.get(file).add(lineNo);
  });
  return map;
}

export function diffFindings(diff, read, analyzeLines) {
  const files = diffFiles(diff);
  const added = addedLineNumbers(diff);
  const findings = [];

  for (const file of files) {
    let content;
    try {
      content = read(file);
    } catch {
      continue;
    }
    const lines = content.split("\n");
    const lineMap = lines.map((_, i) => i + 1);
    const fileFindings = analyzeLines(file, lines, lineMap);
    const addedSet = added.get(file) ?? new Set();
    for (const f of fileFindings) {
      if (addedSet.has(f.line) || (f.partnerLine && addedSet.has(f.partnerLine))) {
        findings.push(f);
      }
    }
  }

  return findings;
}

export function diffFiles(diff) {
  const seen = new Set();
  const files = [];
  walkAddedLines(diff, () => {}, (file) => {
    if (!seen.has(file)) {
      seen.add(file);
      files.push(file);
    }
  });
  return files;
}

export function git(args) {
  return execFileSync("git", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 64 * 1024 * 1024,
  });
}

export function readStaged(root, file) {
  return git(["-C", root, "show", ":" + file]);
}

const BASES = ["origin/main", "main", "origin/master", "master"];

export function branchDiff() {
  let root;
  try {
    root = git(["rev-parse", "--show-toplevel"]).trim();
  } catch {
    return null;
  }

  for (const base of BASES) {
    try {
      git(["-C", root, "rev-parse", "--verify", base]);
    } catch {
      continue;
    }
    const diff = git([
      ...DIFF_CONFIG, "-C", root, "diff", ...DIFF_FLAGS,
      "--merge-base", base, "--cached",
    ]);
    return { base, root, diff };
  }

  return null;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function selftest() {
  assert(headerPath("+++ b/src/x.ts") === "src/x.ts", "plain header path");
  assert(headerPath('+++ "b/weird\\303\\251.ts"') === null, "quoted header dropped");
  assert(headerPath("+++ b/name with space.ts\t") === "name with space.ts", "trailing tab stripped");

  const diff = [
    "diff --git a/x.ts b/x.ts",
    "index 000..111 100644",
    "--- a/x.ts",
    "+++ b/x.ts",
    "@@ -1,2 +1,3 @@",
    " context",
    "+added one",
    "+++ i;",
    " context2",
  ].join("\n");

  const added = [];
  walkAddedLines(diff, (file, line, text) => added.push({ file, line, text }));
  assert(added.length === 2, "two added lines including the ++i guard case");
  assert(added[0].line === 2 && added[0].text === "added one", "first added line numbered correctly");
  assert(added[1].line === 3 && added[1].text === "++ i;", "'+++ i;' still treated as an added line, not a header");

  assert(diffFiles(diff).length === 1 && diffFiles(diff)[0] === "x.ts", "diffFiles dedupes and returns touched path");

  const nums = addedLineNumbers(diff);
  assert(nums.get("x.ts").has(2) && nums.get("x.ts").has(3), "addedLineNumbers tracks both added lines");

  console.log("diff.mjs selftest OK");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("diff.mjs")) selftest();
