/**
 * This bard's own rule made plain: count every beat,
 * ten syllables a line, iambic feet.
 */
import {
  readLine as coreReadLine,
  blockRuns,
  isCodeFile,
  makeExempt,
  analyzeDiff as coreAnalyzeDiff,
  diffFindings as coreDiffFindings,
  renderFindings,
} from "../vendor/comment-core/index.mjs";
import { countLine, breakdown } from "../vendor/comment-core/analyzers/syllable.mjs";

const EXEMPT = makeExempt("bard:");
const METER = 10;

const MIXED_REASON =
  "not meterable, yet a line in the same block scans — a block reads as all verse or all plain. Hoist the token onto its own exempt line (`bard:` or a JSDoc tag), or rephrase without it";

function readLine(raw) {
  const reading = coreReadLine(raw, { exempt: EXEMPT });
  if (reading.kind !== "prose") return reading;
  return { ...reading, syllables: countLine(reading.body) };
}

export function analyzeLines(file, lines, lineMap) {
  if (!isCodeFile(file)) return [];
  const readings = lines.map((l) => readLine(l));
  const findings = [];

  readings.forEach((r, i) => {
    if (r.kind !== "prose") return;
    if (r.syllables !== METER) {
      findings.push({
        file,
        line: lineMap ? lineMap[i] : undefined,
        text: r.body,
        reason: `${r.syllables} syllable(s), needs 10 (${breakdown(r.body)})`,
      });
    }
  });

  if (lineMap) {
    for (const run of blockRuns(lines, lineMap)) {
      const hasScanning = run.some((i) => readings[i].kind === "prose" && readings[i].syllables === METER);
      if (!hasScanning) continue;
      for (const i of run) {
        if (readings[i].kind === "skipped") {
          findings.push({ file, line: lineMap[i], text: lines[i].trim(), reason: MIXED_REASON });
        }
      }
    }
  }

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
    `Blocked: ${subject} adds ${findings.length} line(s) that don't scan. comment-bard: every prose comment line must be exactly 10 syllables (iambic pentameter). ` +
    `If one line in a /** ... */ block scans, every line in that block must — split a long thought across two metered lines rather than leaving one unmetered. ` +
    `Tokens that can never be metered (identifiers, numbers, URLs) belong on their own \`bard:\`-prefixed line, exempt from the count. Fix these, then retry:`;
  return `${preamble}\n${renderFindings(findings, { format })}`;
}
