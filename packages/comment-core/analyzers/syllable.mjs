/**
 * Verse plugins (bard, haijin) both import this by subpath — never from
 * index.mjs, since counting syllables is a form-specific opinion, not
 * plumbing.
 */
import { syllable as vendoredSyllable } from "../vendor/syllable.mjs";
import pluralize from "../vendor/pluralize/pluralize.js";

export const SYLLABLE_EXCEPTIONS = {
  area: 3, barbeque: 3, dogged: 2, doing: 2, going: 2, jagged: 2, poem: 2,
  queued: 1, ragged: 2, risque: 2, rugged: 2, science: 2, seeing: 2, wicked: 2,
};

const VOICED_ES_TAIL = /([sxz]|ch|sh|[cg])$/;

function normalize(word) {
  let w = word;
  if (/ques$/.test(w)) w = w.replace(/ques$/, "qs");
  else if (/que$/.test(w)) w = w.replace(/ue$/, "");
  if (/[^tdr]ed$/.test(w)) w = w.replace(/ed$/, "");
  return w;
}

export function countSyllables(word) {
  const clean = word.toLowerCase().replace(/[^a-z']/g, "");
  if (!clean) return 0;

  if (clean in SYLLABLE_EXCEPTIONS) return SYLLABLE_EXCEPTIONS[clean];

  if (clean.endsWith("es")) {
    const singular = pluralize.singular(clean);
    if (singular !== clean) {
      const bare = singular.replace(/e$/, "");
      if (VOICED_ES_TAIL.test(bare)) return countSyllables(singular) + 1;
      if (singular in SYLLABLE_EXCEPTIONS) return SYLLABLE_EXCEPTIONS[singular];
    }
  }

  return vendoredSyllable(normalize(clean));
}

export function countLine(body) {
  return (body.split(/\s+/).map((t) => t.replace(/[^A-Za-z']/g, "")).filter(Boolean))
    .reduce((sum, tok) => sum + countSyllables(tok), 0);
}

export function breakdown(body) {
  return body.split(/\s+/).map((t) => t.replace(/[^A-Za-z']/g, "")).filter(Boolean)
    .map((tok) => `${tok}/${countSyllables(tok)}`).join(" ");
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

const WORDS = {
  cat: 1, dog: 1, hello: 2, banana: 3, elephant: 3, syllable: 3,
  area: 3, barbeque: 3, dogged: 2, doing: 2, going: 2, jagged: 2, poem: 2,
  queued: 1, ragged: 2, risque: 2, rugged: 2, science: 2, seeing: 2, wicked: 2,
  boxes: 2, houses: 2, wishes: 2, churches: 2, judges: 2, cats: 1, dogs: 1,
  walked: 1, wanted: 2, needed: 2, hundred: 2, sacred: 2,
  antique: 2, unique: 2, plaque: 1,
  "don't": 1, "'tis": 1,
};

function selftest() {
  for (const [word, expected] of Object.entries(WORDS)) {
    const got = countSyllables(word);
    assert(got === expected, `countSyllables("${word}") = ${got}, expected ${expected}`);
  }

  for (const [exc, n] of Object.entries(SYLLABLE_EXCEPTIONS)) {
    const raw = vendoredSyllable(normalize(exc));
    assert(raw !== n, `exception "${exc}" no longer needed — vendored counter already returns ${n}`);
  }

  assert(countLine("the cat sat") === 3, "countLine sums tokens");
  assert(breakdown("the cat") === "the/1 cat/1", "breakdown formats word/n pairs");

  console.log("analyzers/syllable.mjs selftest OK");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("syllable.mjs")) selftest();
