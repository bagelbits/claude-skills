/**
 * This is the rule here:
 * each comment inside must scan
 * in five, seven, five
 */
import {
  readLine as coreReadLine,
  blockRuns as blockUnits,
  isCodeFile,
  makeExempt,
  LINE_COMMENT,
  BLOCK_ONELINE,
  analyzeDiff as coreAnalyzeDiff,
  diffFindings as coreDiffFindings,
  renderFindings,
} from "../vendor/comment-core/index.mjs";
import { countLine, breakdown } from "../vendor/comment-core/analyzers/syllable.mjs";

const EXEMPT = makeExempt("haijin:", "bard:");
const HAIKU = [5, 7, 5];

const LINE_FORM_REASON =
  "a line comment cannot carry a haiku — move this into a /** ... */ block whose prose lines count 5-7-5";
const MIXED_REASON =
  "not meterable, yet a line in the same comment is verse — hoist the token onto its own exempt line (`haijin:` or a JSDoc tag), or rephrase without it";

function readLine(raw) {
  const reading = coreReadLine(raw, { exempt: EXEMPT });
  const clean = raw.replace(/\r$/, "");
  const form = LINE_COMMENT.test(clean) && !BLOCK_ONELINE.test(clean) ? "line" : "block";
  if (reading.kind !== "prose") return { ...reading, form };
  return { ...reading, form, syllables: countLine(reading.body) };
}

function shapeReason(n) {
  const need = 3 - (n % 3);
  let msg = `${n} prose line(s) in this block; a haiku is three lines of 5-7-5, and a sequence a multiple of three — add ${need} more line(s)`;
  if (n > 3) msg += `, or fold ${need === 1 ? "this line" : "these lines"} into the haiku above`;
  return msg;
}

export function analyzeLines(file, lines, lineMap) {
  if (!isCodeFile(file)) return [];
  const readings = lines.map((l) => readLine(l));
  const findings = [];

  readings.forEach((r, i) => {
    if (r.kind === "prose" && r.form === "line") {
      findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: r.body, reason: LINE_FORM_REASON });
    }
  });

  for (const block of blockUnits(lines, lineMap)) {
    const proseIdx = block.filter((i) => readings[i].kind === "prose" && readings[i].form === "block");
    if (proseIdx.length === 0) continue;

    for (const i of block) {
      if (readings[i].kind === "skipped") {
        findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: lines[i].trim(), reason: MIXED_REASON });
      }
    }

    const whole = proseIdx.length - (proseIdx.length % 3);
    proseIdx.forEach((i, pos) => {
      if (pos >= whole) {
        findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: readings[i].body, reason: shapeReason(proseIdx.length) });
        return;
      }
      const want = HAIKU[pos % 3];
      if (readings[i].syllables !== want) {
        findings.push({
          file, line: lineMap ? lineMap[i] : undefined, text: readings[i].body,
          reason: `${readings[i].syllables} syllable(s) on line ${(pos % 3) + 1} of the haiku, needs ${want} (${breakdown(readings[i].body)})`,
        });
      }
    });
  }

  findings.sort((a, b) => (a.line ?? 0) - (b.line ?? 0));
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
  const preamble =
    `Blocked: ${subject} adds ${findings.length} line(s) that break haiku form. comment-haijin: prose comments live in /** ... */ blocks whose lines count 5-7-5; a // line comment cannot carry a haiku. ` +
    `Longer notes chain whole haiku — a block's prose line count must be a multiple of three (3, 6, 9…). If one line in a block is verse, every line in that block must be. ` +
    `Tokens that can never be metered belong on their own \`haijin:\`-prefixed line. Fix these, then retry:`;
  return `${preamble}\n${renderFindings(findings, { format })}`;
}
