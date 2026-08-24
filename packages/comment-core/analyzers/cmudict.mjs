/**
 * Only the hat plugin makes use of this
 * the word map stays local to that plugin
 * since it's too big to bundle with every
 * consumer of the shared core package here
 */
import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

export const FUNCTION_WORDS = new Set([
  "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "from", "with",
  "up", "out", "off", "as", "so", "if", "but", "and", "or", "nor", "yet",
  "than", "that", "this", "these", "those", "it", "its", "he", "she", "we",
  "they", "you", "i", "me", "him", "her", "us", "them", "my", "your", "his",
  "our", "their", "is", "are", "was", "were", "be", "been", "am", "do", "did",
  "does", "has", "have", "had", "can", "could", "will", "would", "shall",
  "should", "may", "might", "must", "not", "no", "all", "each", "both",
  "some", "any", "none", "one", "two", "when", "where", "who", "whom",
  "which", "what", "why", "how", "then", "now", "here", "there", "just",
  "quite", "too", "very", "own", "such", "other", "else",
]);

export function normalizeWord(word) {
  return word.toLowerCase().replace(/[^a-z']/g, "");
}

function isVowelPhoneme(p) {
  return /[012]$/.test(p);
}

const STRESS_CHAR = { 1: "S", 0: "w", 2: "?" };

/**
 * This fold joins two vowels many speakers
 * hear as one, though the source keeps them apart
 * Folding them into the rime key is done
 * on purpose, noted in the vendor notes
 */
function foldNearMergers(phonemeBase) {
  return phonemeBase === "AO" ? "AA" : phonemeBase;
}

export function pronounce(phonemes) {
  const vowelIdx = [];
  phonemes.forEach((p, i) => { if (isVowelPhoneme(p)) vowelIdx.push(i); });

  const stress = vowelIdx.map((i) => STRESS_CHAR[phonemes[i].slice(-1)]).join("");

  let start = -1;
  for (const i of vowelIdx) {
    const s = phonemes[i].slice(-1);
    if (s === "1" || s === "2") start = i;
  }
  if (start === -1) start = vowelIdx.length ? vowelIdx[vowelIdx.length - 1] : 0;

  const rime = phonemes
    .slice(start)
    .map((p) => foldNearMergers(p.replace(/[012]$/, "")))
    .join(" ");

  return { rime, stress };
}

const VARIANT = /^(.+)\((\d+)\)$/;

export function parseCmudict(text) {
  const map = new Map();

  for (const line of text.split("\n")) {
    if (!line || line.startsWith(";;;")) continue;
    const split = /^(\S+)\s+(.+)$/.exec(line);
    if (!split) continue;

    const rawWord = split[1];
    const phonemes = split[2].trim().split(/\s+/);
    const variantMatch = VARIANT.exec(rawWord);
    const headword = normalizeWord(variantMatch ? variantMatch[1] : rawWord);
    if (!headword) continue;

    const entry = pronounce(phonemes);
    const existing = map.get(headword) ?? [];
    if (!existing.some((v) => v.rime === entry.rime && v.stress === entry.stress)) {
      existing.push(entry);
    }
    map.set(headword, existing);
  }

  return map;
}

export function serializeMap(map) {
  const rows = [];
  for (const [word, variants] of map) {
    rows.push(`${word}\t${variants.map((v) => `${v.rime}|${v.stress}`).join(";")}`);
  }
  return rows.join("\n");
}

function strongAt(len, p) {
  return p % 3 === (len - 1) % 3;
}

function scanConstraint(C) {
  if (C.length < 7 || C.length > 12) return false;
  for (let p = 0; p < C.length; p++) {
    const req = strongAt(C.length, p) ? "S" : "w";
    if (C[p] !== "?" && C[p] !== req) return false;
  }
  return true;
}

function combinePatterns(perWord) {
  const total = perWord.reduce((acc, c) => acc * c.length, 1);
  if (total > 256) return [perWord.map((c) => c[0]).join("")];

  let combos = [""];
  for (const cands of perWord) {
    const next = [];
    for (const prefix of combos) for (const c of cands) next.push(prefix + c);
    combos = next;
  }
  return combos;
}

export function createCmudict(mapPath) {
  let map = null;

  function load() {
    if (map) return map;
    const gz = readFileSync(mapPath);
    const text = gunzipSync(gz).toString("utf8");
    map = new Map();
    for (const line of text.split("\n")) {
      if (!line) continue;
      const [word, encoded] = line.split("\t");
      map.set(word, encoded.split(";").map((v) => {
        const [rime, stress] = v.split("|");
        return { rime, stress };
      }));
    }
    return map;
  }

  function pronunciations(w) {
    return load().get(normalizeWord(w)) ?? null;
  }

  function rimeKeys(w) {
    const v = pronunciations(w);
    return v ? v.map((x) => x.rime) : null;
  }

  function rhymes(a, b) {
    const na = normalizeWord(a);
    const nb = normalizeWord(b);
    if (na === nb) return false;
    const ra = rimeKeys(na);
    const rb = rimeKeys(nb);
    if (!ra || !rb) return false;
    return ra.some((r) => rb.includes(r));
  }

  function wordCandidates(w) {
    const nw = normalizeWord(w);
    if (FUNCTION_WORDS.has(nw)) return ["?"];
    const variants = pronunciations(nw);
    if (!variants) return null;
    const patterns = variants.map((v) => (v.stress.length <= 1 ? "?" : v.stress));
    return [...new Set(patterns)];
  }

  function offendingWord(words, perWord) {
    for (let i = 0; i < words.length; i++) {
      if (perWord[i].length === 1 && perWord[i][0] !== "?") return words[i];
    }
    return words[words.length - 1];
  }

  function scanMeter(words) {
    const perWord = [];
    for (const w of words) {
      const cands = wordCandidates(w);
      if (cands === null) return { oov: true };
      perWord.push(cands);
    }

    const combos = combinePatterns(perWord);
    if (combos.some(scanConstraint)) return { ok: true };

    const len = combos[0]?.length ?? 0;
    if (len < 7 || len > 12) {
      return { ok: false, reason: `${len} syllable(s), needs 7–12 for anapestic meter` };
    }
    return {
      ok: false,
      reason: `does not scan as anapest — the fixed stress of "${offendingWord(words, perWord)}" lands off the beat`,
    };
  }

  return { pronunciations, rimeKeys, rhymes, scanMeter };
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function selftest() {
  const fixture = [
    "CAT  K AE1 T",
    "HAT  HH AE1 T",
    "READ  R IY1 D",
    "RED  R EH1 D",
    "THOUGH  DH OW1",
    "TOUGH  T AH1 F",
    "ELEPHANT  EH1 L AH0 F AH0 N T",
  ].join("\n");

  const map = parseCmudict(fixture);
  assert(map.get("cat")[0].rime === "AE T", "rime is the CVC tail sans stress digit");
  assert(map.get("elephant")[0].stress === "Sww", "full-word stress pattern captured");

  const serialized = serializeMap(map);
  const roundTrip = new Map(serialized.split("\n").map((row) => {
    const [word, enc] = row.split("\t");
    return [word, enc.split(";").map((v) => { const [rime, stress] = v.split("|"); return { rime, stress }; })];
  }));
  assert(roundTrip.get("cat")[0].rime === "AE T", "serialize/parse round-trips");

  console.log("analyzers/cmudict.mjs selftest OK (unit-level; real-map assertions live in comment-in-the-hat's tests/run.sh)");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("cmudict.mjs")) selftest();
