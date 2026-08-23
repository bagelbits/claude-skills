# Vendored third-party code

| Package | Version | License | Path |
|---|---|---|---|
| syllable | 5.0.1 | MIT | `vendor/syllable.mjs`, `vendor/problematic.mjs` |
| pluralize | 8.0.0 | MIT | `vendor/pluralize/` |
| normalize-strings | 1.1.1 | MIT | **not vendored** — replaced by `vendor/normalize-shim.mjs` |

Fetched via `npm install syllable@5.0.1 pluralize@8.0.0` into a scratch
directory, then copied as source (no `node_modules`, no build step — plugins
run these files directly with `node`).

Edits applied, and only these:
1. `from 'normalize-strings'` → `from './normalize-shim.mjs'`
2. `from 'pluralize'` → `from './pluralize/pluralize.js'`
3. `from './problematic.js'` → `from './problematic.mjs'`

Integrity (npm tarball, from `npm view <pkg>@<version> dist.integrity`):
- syllable@5.0.1: `sha512-HWtNCp6v7J8H0lrT8j1HHjfOLltRoDcC7QRFVu25p4BE52JqetXG65nqC7CsatT8WQRfY4Qvh93BWJIUxbmXFg==`
- pluralize@8.0.0: `sha512-Nc3IT5yHzflTfbjgqWcCPpo7DaKy4FnpB0l/zCAW0Tc7jxAiuqSxHasntB3D7887LSrA93kDJ9IXovxJYxyLCA==`

Licenses: `LICENSE-syllable`, `LICENSE-pluralize` (verbatim from the npm
package).
