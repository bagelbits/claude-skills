/**
 * Load-bearing regexes and shared classification logic for every plugin's
 * comment analyzer. Exact patterns are pinned by the spec — do not "clean up."
 */

export const LINE_COMMENT      = /^\s*\/\/\s?(.*)$/;
export const LINE_COMMENT_HASH = /^\s*(?:\/\/|#)\s?(.*)$/;
export const BLOCK_BODY        = /^\s*\*\s?(.*)$/;
export const BLOCK_ONELINE     = /^\s*\/\*\*?\s*(.*?)\s*\*\/\s*$/;
export const BLOCK_OPENER      = /^\s*\/\*\*?\s*(.+)$/;
export const BLOCK_START       = /^\s*\/\*/;
export const BLOCK_END         = /\*\//;

export const UNSPEAKABLE = [
  /`[^`]*`/,
  /\b[a-z]+[A-Z]/,
  /\b[A-Z][a-z]+[A-Z]/,
  /\b\w+_\w+\b/,
  /\b\w+\.\w+\b/,
  /\b[\w.-]+\/[\w.-]+/,
  /\b[A-Z]{2,}\b/,
  /\d/,
];

export const CODE_EXT    = /\.(ts|tsx|js|jsx|mjs|cjs|tf)$/;
export const THIRD_PARTY = /(^|[\\/])(vendor|node_modules|\.terraform)[\\/]/;

export function isCodeFile(file) {
  const path = file ?? "";
  return CODE_EXT.test(path) && !THIRD_PARTY.test(path);
}

const SHARED_MARKERS =
  "ponytail:|eslint|prettier|biome-|istanbul |TODO|FIXME|NOTE|HACK|XXX|@\\w+|https?:";

export const makeExempt = (...prefixes) =>
  new RegExp(`^(${[...prefixes, SHARED_MARKERS].join("|")})`, "i");

const LETTER_WORD = /[A-Za-z][A-Za-z']*/g;

export function readLine(line, { allowHash = false, exempt } = {}) {
  const raw = line.replace(/\r$/, "");
  let body = null;

  const oneLine = BLOCK_ONELINE.exec(raw);
  if (oneLine) {
    body = oneLine[1];
  } else {
    const lineMatch = (allowHash ? LINE_COMMENT_HASH : LINE_COMMENT).exec(raw);
    if (lineMatch) {
      body = lineMatch[1];
    } else {
      const blockBody = BLOCK_BODY.exec(raw);
      if (blockBody) {
        body = blockBody[1];
      } else if (!BLOCK_END.test(raw)) {
        const opener = BLOCK_OPENER.exec(raw);
        if (opener) body = opener[1];
      }
    }
  }

  if (body === null || body === "" || body === "/") return { kind: "none" };
  if (exempt && exempt.test(body)) return { kind: "exempt" };

  const words = body.match(LETTER_WORD) ?? [];
  if (words.length === 0) return { kind: "none" };

  if (UNSPEAKABLE.some((re) => re.test(body))) return { kind: "skipped" };

  return { kind: "prose", body, words };
}

export function blockRuns(lines, lineMap) {
  const runs = [];
  let current = null;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i].replace(/\r$/, "");

    if (current) {
      const contiguous = !lineMap || lineMap[i] === lineMap[i - 1] + 1;
      if (contiguous) {
        current.push(i);
        if (BLOCK_END.test(raw)) {
          runs.push(current);
          current = null;
        }
        continue;
      }
      current = null;
    }

    if (BLOCK_START.test(raw) && !BLOCK_END.test(raw)) {
      current = [i];
    }
  }

  return runs;
}

export function commentUnits(readings, lineMap) {
  const units = [];
  let current = null;

  for (let i = 0; i < readings.length; i++) {
    if (readings[i].kind === "none") {
      current = null;
      continue;
    }
    const contiguous = current && (!lineMap || lineMap[i] === lineMap[i - 1] + 1);
    if (contiguous) {
      current.push(i);
    } else {
      current = [i];
      units.push(current);
    }
  }

  return units;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function selftest() {
  assert(isCodeFile("src/x.ts"), "ts is code");
  assert(isCodeFile("infra/main.tf"), "tf is code");
  assert(!isCodeFile("vendor/x.ts"), "vendor path excluded");
  assert(!isCodeFile("node_modules/x.ts"), "node_modules path excluded");
  assert(isCodeFile("my-vendor/x.ts"), "word containing vendor is not a path segment match");
  assert(isCodeFile("vendors.ts"), "word containing vendor is not excluded");
  assert(!isCodeFile("README.md"), "md is not code");

  assert(readLine("// hello world").kind === "prose", "line comment is prose");
  assert(readLine("// 'tis a test").words[0] === "tis", "leading apostrophe stripped");
  assert(readLine("// don't stop").words[0] === "don't", "internal apostrophe kept");
  assert(readLine("//").kind === "none", "empty line comment is none");
  assert(readLine("// TODO: fix").kind === "skipped", "allcaps TODO trips UNSPEAKABLE when no exempt passed");
  assert(readLine("code();").kind === "none", "non-comment line is none");
  assert(readLine("// camelCase here").kind === "skipped", "camelCase is unspeakable");
  assert(readLine("// has a number 4").kind === "skipped", "digit is unspeakable");
  assert(readLine("/** one line block */").kind === "prose", "one-line block is prose");
  assert(readLine(" * continuation line").kind === "prose", "block body line is prose");
  assert(readLine("/** open", {}).kind === "prose", "block opener with prose is prose");
  assert(readLine("*/").kind === "none", "bare block end has no opener body");

  const exempt = makeExempt("bard:");
  assert(readLine("// bard: skip me", { exempt }).kind === "exempt", "custom prefix exempt");
  assert(readLine("// TODO fix later", { exempt }).kind === "exempt", "shared marker exempt");

  const lines = ["/**", " * one", " * two", " */", "code();"];
  const runs = blockRuns(lines);
  assert(runs.length === 1 && runs[0].length === 4, "one contiguous block run of 4 lines");

  const brokenLineMap = [1, 2, 10, 11];
  const brokenLines = ["/**", " * one", " * two", " */"];
  const brokenRuns = blockRuns(brokenLines, brokenLineMap);
  assert(brokenRuns.length === 0, "non-contiguous lineMap drops the run");

  const readings = [
    readLine("// a"), readLine("// b"), { kind: "none" }, readLine("// c"),
  ];
  const units = commentUnits(readings);
  assert(units.length === 2 && units[0].length === 2 && units[1].length === 1, "commentUnits groups adjacency");

  console.log("extract.mjs selftest OK");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("extract.mjs")) selftest();
