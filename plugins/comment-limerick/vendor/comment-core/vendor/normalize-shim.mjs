/**
 * Local replacement for the `normalize-strings` npm package (not vendored —
 * comments are ASCII in practice, so the full package isn't needed). Folds
 * accents the same way: NFD decomposition + diacritic strip.
 */
export default function normalizeStrings(str) {
  return str.normalize("NFD").replace(/[̀-ͯ]/g, "");
}
