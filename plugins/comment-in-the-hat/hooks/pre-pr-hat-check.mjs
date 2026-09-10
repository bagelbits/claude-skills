import { branchDiff, deny, firesBranchGate, readPayload } from "../vendor/comment-core/index.mjs";
import { analyzeDiff, denyReason } from "./hat-rules.mjs";

readPayload((payload) => {
  if (!firesBranchGate(payload)) return;
  const base = branchDiff();
  if (!base) return;
  const findings = analyzeDiff(base.diff);
  if (findings.length > 0) deny(denyReason(findings, "the branch diff"));
});
