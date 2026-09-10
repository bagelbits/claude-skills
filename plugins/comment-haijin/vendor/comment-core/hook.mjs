/**
 * A hook can be matched on the name of a tool,
 * and nothing beyond it, and that is the rule;
 * the command in the payload decides it instead,
 * so a Bash that is idle gets nothing to read.
 */
const GIT_COMMIT = /(?:^|[\s;&|(])git\b[^;&|]*\bcommit\b/;
const GH_PR_CREATE = /(?:^|[\s;&|(])gh\b[^;&|]*\bpr\b[^;&|]*\bcreate\b/;

export function isBranchGateCommand(command) {
  const text = String(command ?? "");
  return GIT_COMMIT.test(text) || GH_PR_CREATE.test(text);
}

export function firesBranchGate(payload) {
  const { tool_name, tool_input } = payload ?? {};
  if (tool_name !== "Bash") return true;
  return isBranchGateCommand(tool_input?.command);
}

export function readPayload(run) {
  if (process.stdin.isTTY) return process.exit(0);

  let raw = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => { raw += chunk; });
  process.stdin.on("end", () => {
    try {
      run(JSON.parse(raw));
    } catch {
      process.exit(0);
    }
    process.exit(0);
  });
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function selftest() {
  assert(isBranchGateCommand("git commit -m 'x'"), "plain git commit");
  assert(isBranchGateCommand("git -C /tmp/repo commit --amend"), "git commit with leading options");
  assert(isBranchGateCommand("git add . && git commit -m x"), "git commit later in a chain");
  assert(isBranchGateCommand("gh pr create --fill"), "plain gh pr create");
  assert(isBranchGateCommand("gh pr --repo o/r create"), "gh pr create with interleaved options");

  assert(!isBranchGateCommand("git status"), "unrelated git command");
  assert(!isBranchGateCommand("gh pr list"), "unrelated gh command");
  assert(!isBranchGateCommand("ls -la"), "unrelated command");
  assert(!isBranchGateCommand(undefined), "missing command");

  assert(firesBranchGate({ tool_name: "Bash", tool_input: { command: "git commit" } }), "Bash gate opens on commit");
  assert(!firesBranchGate({ tool_name: "Bash", tool_input: { command: "npm test" } }), "Bash gate stays shut otherwise");
  assert(!firesBranchGate({ tool_name: "Bash" }), "Bash with no input stays shut");
  assert(firesBranchGate({ tool_name: "mcp__plugin_github_github__create_pull_request" }), "non-Bash tools always fire");
  assert(firesBranchGate(undefined), "unreadable payload fires");

  console.log("hook.mjs selftest OK");
}

if (process.argv.includes("--selftest") && process.argv[1]?.endsWith("hook.mjs")) selftest();
