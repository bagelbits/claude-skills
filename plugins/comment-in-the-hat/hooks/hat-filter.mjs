import { deny } from "../vendor/comment-core/index.mjs";
import { analyzeLines, denyReason } from "./hat-rules.mjs";

function addedLines(newStr, oldStr) {
  const oldSet = new Set((oldStr ?? "").split("\n").map((l) => l.trim()));
  return (newStr ?? "").split("\n").map((l) => (oldSet.has(l.trim()) ? "" : l));
}

function extract(payload) {
  const { tool_name, tool_input } = payload;
  if (!tool_input) return null;

  if (tool_name === "Write") {
    const lines = String(tool_input.content ?? "").split("\n");
    return { file: tool_input.file_path, lines, lineMap: lines.map((_, i) => i + 1) };
  }
  if (tool_name === "Edit") {
    return { file: tool_input.file_path, lines: addedLines(tool_input.new_string, tool_input.old_string), lineMap: undefined };
  }
  if (tool_name === "MultiEdit") {
    const lines = (tool_input.edits ?? []).flatMap((e) => addedLines(e.new_string, e.old_string));
    return { file: tool_input.file_path, lines, lineMap: undefined };
  }
  if (tool_name === "NotebookEdit") {
    const lines = String(tool_input.new_source ?? "").split("\n");
    return { file: tool_input.notebook_path, lines, lineMap: undefined };
  }
  return null;
}

let raw = "";
process.stdin.on("data", (c) => { raw += c; });
process.stdin.on("end", () => {
  try {
    const extracted = extract(JSON.parse(raw));
    if (!extracted) return process.exit(0);
    const findings = analyzeLines(extracted.file, extracted.lines, extracted.lineMap);
    if (findings.length > 0) deny(denyReason(findings, "this write"));
    process.exit(0);
  } catch {
    process.exit(0);
  }
});
