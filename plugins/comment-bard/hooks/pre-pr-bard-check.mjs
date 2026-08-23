import { branchDiff, deny } from "../vendor/comment-core/index.mjs";
import { analyzeDiff, denyReason } from "./bard-rules.mjs";

try {
  const base = branchDiff();
  if (!base) process.exit(0);
  const findings = analyzeDiff(base.diff);
  if (findings.length > 0) deny(denyReason(findings, "the branch diff"));
  process.exit(0);
} catch {
  process.exit(0);
}
