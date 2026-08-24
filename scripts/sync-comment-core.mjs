import { cpSync, rmSync, existsSync } from "node:fs";
import { readdirSync } from "node:fs";

const SRC = new URL("../packages/comment-core", import.meta.url);
const PLUGINS_DIR = new URL("../plugins/", import.meta.url);

const plugins = readdirSync(PLUGINS_DIR, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

for (const name of plugins) {
  const dest = new URL(`../plugins/${name}/vendor/comment-core`, import.meta.url);
  if (existsSync(dest)) rmSync(dest, { recursive: true, force: true });
  cpSync(SRC, dest, { recursive: true });
  console.log(`synced comment-core -> plugins/${name}/vendor/comment-core`);
}
