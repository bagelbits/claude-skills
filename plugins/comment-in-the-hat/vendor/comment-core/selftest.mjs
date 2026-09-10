import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const modules = [
  "extract.mjs", "diff.mjs", "deny.mjs", "hook.mjs",
  "analyzers/syllable.mjs", "analyzers/cmudict.mjs",
];

for (const mod of modules) {
  execFileSync("node", [path.join(here, mod), "--selftest"], { stdio: "inherit" });
}

console.log("comment-core: all selftests passed");
