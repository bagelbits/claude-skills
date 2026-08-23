/** comment-reaper's rule: comment the non-obvious why, never the what. */
import {
  isCodeFile,
  analyzeDiff as coreAnalyzeDiff,
  diffFindings as coreDiffFindings,
  renderFindings,
} from "../vendor/comment-core/index.mjs";

const EXEMPT = /^(ponytail:|eslint|@ts-|prettier|biome-|c8 |istanbul |v8 |TODO|FIXME|NOTE|HACK|XXX|https?:)/i;

const COMMENTED_CODE =
  /^(const |let |var |return\b|if\s*\(|for\s*\(|while\s*\(|switch\s*\(|function\b|class\b|import\b|export\b|await\b|async\b|console\.|\w+\s*\([^)]*\)\s*[;{]?\s*$|.*[;{]\s*$)/;

const WHAT_VERB =
  /^(set|sets|setting|get|gets|getting|return|returns|returning|increment|decrement|loop|loops|iterate|iterates|create|creates|creating|initialize|initializes|declare|declares|assign|assigns|call|calls|calling|define|defines|store|stores|instantiate|instantiates)\b/i;

const MULTILINE_RUN = 3;
const CONTINUATION = /^[a-z]/;

const LINE_RE = /^\s*\/\/\s?(.*)$/;
const HASH_RE = /^\s*(?:\/\/|#)\s?(.*)$/;

function commentBody(raw, allowHash) {
  const line = raw.replace(/\r$/, "");
  const m = (allowHash ? HASH_RE : LINE_RE).exec(line);
  if (!m) return null;
  const body = m[1];
  if (!body || EXEMPT.test(body)) return null;
  return body;
}

export function analyzeLines(file, lines, lineMap) {
  if (!isCodeFile(file)) return [];
  const allowHash = /\.tf$/.test(file);
  const findings = [];

  let run = [];
  const flush = () => {
    if (run.length >= MULTILINE_RUN) {
      const first = run[0];
      findings.push({
        file,
        line: lineMap ? lineMap[first] : undefined,
        text: lines[first].trim(),
        reason: `${run.length} consecutive comment lines — use a block comment (/* ... */)`,
      });
    }
    run = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const body = commentBody(lines[i], allowHash);

    if (body === null) {
      flush();
      continue;
    }

    if (run.length > 0 && CONTINUATION.test(body)) run.push(i);
    else { flush(); run = [i]; }

    const words = body.trim().split(/\s+/).filter(Boolean);

    if (COMMENTED_CODE.test(body)) {
      findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: body, reason: "commented-out code" });
    } else if (WHAT_VERB.test(body) && words.length <= 8) {
      findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: body, reason: 'reads as "what", not "why"' });
    }
  }
  flush();

  return findings;
}

export function analyzeDiff(diff) {
  return coreAnalyzeDiff(diff, analyzeLines);
}

export function diffFindings(diff, read) {
  return coreDiffFindings(diff, read, analyzeLines);
}

function format(f) {
  return `  ${f.file}${f.line ? ":" + f.line : ""} — ${f.reason}: "${f.text}"`;
}

export function denyReason(findings, subject) {
  const preamble = `Blocked: ${subject} adds ${findings.length} redundant comment(s). comment-reaper: comment the non-obvious *why*, never the *what*; use /** ... */ for multiline. Remove or rewrite these, then retry:`;
  return `${preamble}\n${renderFindings(findings, { format })}`;
}
