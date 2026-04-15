const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const {
  ensureProjectState,
  getRepoRoot,
  toRepoRelativePath,
  writeJson,
} = require("./lib/project-state");

function printUsage() {
  console.error(
    "Usage: node scripts/agent-control.js start-session --task-request <task-request-json-path>",
  );
}

function parseArguments(argv) {
  if (argv.length < 4) {
    printUsage();
    process.exit(1);
  }

  const [command, flag, taskRequestPath] = argv.slice(2);
  if (command !== "start-session" || flag !== "--task-request" || !taskRequestPath) {
    printUsage();
    process.exit(1);
  }

  return {
    taskRequestPath: path.resolve(taskRequestPath),
  };
}

function utcNow() {
  return new Date().toISOString();
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function main() {
  try {
    const repoRoot = getRepoRoot();
    const statePaths = ensureProjectState(repoRoot);
    const { taskRequestPath } = parseArguments(process.argv);
    const taskRequest = JSON.parse(fs.readFileSync(taskRequestPath, "utf8"));

    if (taskRequest.approval_state !== "auto-approved") {
      console.log(
        JSON.stringify(
          {
            status: "blocked",
            reasonCode: "approval_required",
            message:
              "The task request is not auto-approved, so Phase 1 session start is blocked pending approval handling.",
          },
          null,
          2,
        ),
      );
      process.exit(2);
    }

    const startedAt = utcNow();
    const agentSessionId = `ags-${sha256(`${taskRequest.task_request_id}:${startedAt}`).slice(0, 12)}`;
    const sessionRecord = {
      agent_session_id: agentSessionId,
      task_request_id: taskRequest.task_request_id,
      execution_profile_id: taskRequest.execution_profile_id,
      runtime_capability_set_id: taskRequest.runtime_capability_set_id,
      session_state: "pending",
      runtime_handoff_status: "not-started",
      runtime_handoff_reason:
        "Worker runtime scaffold is not implemented yet; this record is the Phase 1 session-start placeholder.",
      task_request_path: toRepoRelativePath(repoRoot, taskRequestPath),
      policy_refs: taskRequest.policy_refs || [],
      context_refs: [
        "README.md",
        "docs/roadmap.md",
        "docs/wbs.md",
        ...(taskRequest.policy_refs || []),
      ],
      created_at: startedAt,
      updated_at: startedAt,
      started_at: startedAt,
      artifact_refs: [],
    };

    const sessionRecordPath = path.join(statePaths.agentSessionStateDir, `${agentSessionId}.json`);
    writeJson(sessionRecordPath, sessionRecord);

    console.log(
      JSON.stringify(
        {
          agent_session_id: agentSessionId,
          status: sessionRecord.session_state,
          runtime_handoff_status: sessionRecord.runtime_handoff_status,
          session_record_path: toRepoRelativePath(repoRoot, sessionRecordPath),
        },
        null,
        2,
      ),
    );
  } catch (error) {
    console.log(
      JSON.stringify(
        {
          status: "error",
          message: error.message,
        },
        null,
        2,
      ),
    );
    process.exit(1);
  }
}

main();
