import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { parseCmudict, serializeMap } from "../vendor/comment-core/analyzers/cmudict.mjs";

function readInput() {
  const pathArg = process.argv[2];
  return pathArg ? readFileSync(pathArg, "utf8") : readFileSync(0, "utf8");
}

const map = parseCmudict(readInput());

if (map.size < 100000) {
  console.error(`refusing to build: only ${map.size} words parsed, expected ~126000`);
  process.exit(1);
}

process.stdout.write(gzipSync(Buffer.from(serializeMap(map), "utf8")));
