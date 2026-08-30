/**
 * There once was a bug in the code
 * It broke every build down the road
 * It crashed every night
 * gave the team quite a fright
 * and vanished the moment it showed
 */
import {
  readLine as coreReadLine,
  blockRuns,
  isCodeFile,
  makeExempt,
  LINE_COMMENT,
  BLOCK_ONELINE,
  analyzeDiff as coreAnalyzeDiff,
  diffFindings as coreDiffFindings,
  renderFindings,
} from "../vendor/comment-core/index.mjs";
import { createCmudict } from "../vendor/comment-core/analyzers/cmudict.mjs";

const EXEMPT = makeExempt("nantucket:");
const oracle = createCmudict(new URL("../vendor/cmudict-map.txt.gz", import.meta.url));

const ROLE = ["A", "A", "B", "B", "A"];
const METER = { A: { min: 7, max: 10 }, B: { min: 5, max: 7 } };

const LINE_FORM_REASON =
  "a line comment cannot carry a limerick — move this into a /** ... */ block whose five lines follow AABBA form";
const MIXED_REASON =
  "not speakable, yet a line in the same comment is verse — hoist the token onto its own exempt line (`nantucket:`), or rephrase without it";

function readLine(raw) {
  const reading = coreReadLine(raw, { exempt: EXEMPT });
  const clean = raw.replace(/\r$/, "");
  const form = LINE_COMMENT.test(clean) && !BLOCK_ONELINE.test(clean) ? "line" : "block";
  if (reading.kind !== "prose") return { ...reading, form };
  const oov = reading.words.some((w) => oracle.pronunciations(w) === null);
  return oov ? { kind: "skipped", form } : { ...reading, form };
}

function lastWord(words) {
  return words[words.length - 1];
}

function shapeReason(n) {
  const need = 5 - (n % 5);
  let msg = `${n} prose line(s) in this block; a limerick is five lines of AABBA, and a sequence must be a multiple of five — add ${need} more line(s)`;
  if (n > 5) msg += `, or fold ${need === 1 ? "this line" : "these lines"} into the limerick above`;
  return msg;
}

function checkRhyme(findings, file, lineMap, readings, aIdx, bIdx, role) {
  if (oracle.rhymes(lastWord(readings[aIdx].words), lastWord(readings[bIdx].words))) return;
  findings.push({
    file,
    line: lineMap ? lineMap[bIdx] : undefined,
    text: readings[bIdx].body,
    kind: "rhyme",
    partnerLine: lineMap ? lineMap[aIdx] : undefined,
    partnerText: readings[aIdx].body,
    reason: `does not rhyme with "${readings[aIdx].body}" — a limerick's ${role}-lines must rhyme`,
  });
}

export function analyzeLines(file, lines, lineMap) {
  if (!isCodeFile(file)) return [];
  const readings = lines.map((l) => readLine(l));
  const findings = [];

  readings.forEach((r, i) => {
    if ((r.kind === "prose" || r.kind === "skipped") && r.form === "line") {
      findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: r.body ?? lines[i].trim(), kind: "form", reason: LINE_FORM_REASON });
    }
  });

  for (const block of blockRuns(lines, lineMap)) {
    const proseIdx = block.filter((i) => readings[i].kind === "prose" && readings[i].form === "block");
    if (proseIdx.length === 0) continue;

    for (const i of block) {
      if (readings[i].kind === "skipped") {
        findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: lines[i].trim(), kind: "block", reason: MIXED_REASON });
      }
    }

    const whole = proseIdx.length - (proseIdx.length % 5);
    proseIdx.forEach((i, pos) => {
      if (pos >= whole) {
        findings.push({ file, line: lineMap ? lineMap[i] : undefined, text: readings[i].body, kind: "shape", reason: shapeReason(proseIdx.length) });
      }
    });

    for (let g = 0; g < whole; g += 5) {
      const group = proseIdx.slice(g, g + 5);

      group.forEach((i, pos) => {
        const role = ROLE[pos];
        const meter = oracle.scanMeter(readings[i].words, METER[role]);
        if (meter.ok === false) {
          findings.push({
            file, line: lineMap ? lineMap[i] : undefined, text: readings[i].body, kind: "meter",
            reason: `line ${pos + 1} of the limerick (role ${role}): ${meter.reason}`,
          });
        }
      });

      const [l1, l2, l3, l4, l5] = group;
      checkRhyme(findings, file, lineMap, readings, l1, l2, "A");
      checkRhyme(findings, file, lineMap, readings, l2, l5, "A");
      checkRhyme(findings, file, lineMap, readings, l3, l4, "B");
    }
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
  const partner = f.kind === "rhyme" ? ` (partner ${f.file}${f.partnerLine ? ":" + f.partnerLine : ""})` : "";
  return `  [${f.kind}] ${f.file}${f.line ? ":" + f.line : ""} — ${f.reason}: "${f.text}"${partner}`;
}

export function denyReason(findings, subject) {
  const preamble =
    `Blocked: ${subject} adds ${findings.length} line(s) that break AABBA limerick form. comment-limerick: prose comments live in /** ... */ blocks whose five lines follow AABBA rhyme (1,2,5 rhyme; 3,4 rhyme) with anapestic meter (7–10 syllables for lines 1/2/5, 5–7 for lines 3/4); a // line comment cannot carry a limerick. ` +
    `Longer notes chain whole limericks — a block's prose line count must be a multiple of five (5, 10, 15…). Tokens that can never be metered belong on their own \`nantucket:\`-prefixed line (no positional requirement). No humor requirement — form only. Fix these, then retry:`;
  return `${preamble}\n${renderFindings(findings, { format })}`;
}
