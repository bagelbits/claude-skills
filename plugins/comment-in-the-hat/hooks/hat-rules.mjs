/**
 * Two lines of prose must rhyme and share one beat
 * So each terse note feels light and stays neat
 */
import {
  readLine as coreReadLine,
  commentUnits,
  isCodeFile,
  makeExempt,
  analyzeDiff as coreAnalyzeDiff,
  diffFindings as coreDiffFindings,
  renderFindings,
} from "../vendor/comment-core/index.mjs";
import { createCmudict } from "../vendor/comment-core/analyzers/cmudict.mjs";

const EXEMPT = makeExempt("cat-in-the-hat:");
const oracle = createCmudict(new URL("../vendor/cmudict-map.txt.gz", import.meta.url));

function readLine(raw) {
  const reading = coreReadLine(raw, { exempt: EXEMPT });
  if (reading.kind !== "prose") return reading;
  const oov = reading.words.some((w) => oracle.pronunciations(w) === null);
  return oov ? { kind: "skipped" } : reading;
}

function lastWord(words) {
  return words[words.length - 1];
}

export function analyzeLines(file, lines, lineMap) {
  if (!isCodeFile(file)) return [];
  const readings = lines.map((l) => readLine(l));
  const findings = [];

  readings.forEach((r, i) => {
    if (r.kind !== "prose") return;
    const meter = oracle.scanMeter(r.words);
    if (meter.ok === false) {
      findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: r.body, kind: "meter", reason: meter.reason });
    }
  });

  for (const unit of commentUnits(readings, lineMap)) {
    const proseIdx = unit.filter((i) => readings[i].kind === "prose");
    const firstProse = proseIdx[0];

    for (const i of unit) {
      const raw = lines[i].replace(/\r$/, "");
      if (readings[i].kind === "exempt" && /cat-in-the-hat:/i.test(raw) && firstProse !== undefined && i > firstProse) {
        findings.push({
          file, line: lineMap ? lineMap[i] : undefined, text: raw.trim(), kind: "hoist",
          reason: "a `cat-in-the-hat:` line must sit at the top of its comment, above every couplet line",
        });
      }
      if (readings[i].kind === "skipped" && proseIdx.length > 0) {
        findings.push({
          file, line: lineMap ? lineMap[i] : undefined, text: lines[i].trim(), kind: "block",
          reason: "not speakable, yet a line in the same comment is verse — hoist the token onto a `cat-in-the-hat:` line, or rephrase",
        });
      }
    }

    for (let p = 0; p < proseIdx.length - 1; p += 2) {
      const aIdx = proseIdx[p];
      const bIdx = proseIdx[p + 1];
      const a = readings[aIdx];
      const b = readings[bIdx];
      if (!oracle.rhymes(lastWord(a.words), lastWord(b.words))) {
        findings.push({
          file, line: lineMap ? lineMap[bIdx] : undefined, text: b.body, kind: "rhyme",
          partnerLine: lineMap ? lineMap[aIdx] : undefined, partnerText: a.body,
          reason: `does not rhyme with "${a.body}" — a couplet's two lines must rhyme`,
        });
      }
    }
    if (proseIdx.length % 2 === 1) {
      const last = proseIdx[proseIdx.length - 1];
      findings.push({
        file, line: lineMap ? lineMap[last] : undefined, text: readings[last].body, kind: "unpaired",
        reason: "has no rhyming partner — a couplet needs two lines; add a rhyming line",
      });
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
  const partner = f.kind === "rhyme" ? ` (partner ${f.file}${f.partnerLine ? ":" + f.partnerLine : ""})` : "";
  return `  [${f.kind}] ${f.file}${f.line ? ":" + f.line : ""} — ${f.reason}: "${f.text}"${partner}`;
}

export function denyReason(findings, subject) {
  const preamble =
    `Blocked: ${subject} adds ${findings.length} line(s) that break AABB couplet form. comment-in-the-hat: consecutive prose comment lines must pair into rhyming couplets (AABB), each line scanning as anapestic meter (7–12 syllables). ` +
    `A \`cat-in-the-hat:\`-prefixed line must sit at the top of its comment, above every couplet line — it's the only escape hatch. See the green-eggs-and-hamify skill to rewrite. Fix these, then retry:`;
  return `${preamble}\n${renderFindings(findings, { format })}`;
}
