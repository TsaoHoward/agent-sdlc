const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const {
  ensureProjectState,
  getRepoRoot,
  toRepoRelativePath,
  writeJson,
} = require("./lib/project-state");
const { launchWorkerRuntime, DEFAULT_WORKER_IMAGE } = require("./lib/runtime-launcher");

function printUsage() {
  console.error(
    "Usage: node scripts/agent-control.js start-session --task-request <task-request-json-path> [--auto-create-proposal]",
  );
}

function parseArguments(argv) {
  if (argv.length < 4) {
    printUsage();
    process.exit(1);
  }

  const [command, flag, taskRequestPath, ...rest] = argv.slice(2);
  if (command !== "start-session" || flag !== "--task-request" || !taskRequestPath) {
    printUsage();
    process.exit(1);
  }

  const options = {
    taskRequestPath: path.resolve(taskRequestPath),
    autoCreateProposal: false,
  };

  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    if (token === "--auto-create-proposal") {
      options.autoCreateProposal = true;
      continue;
    }

    printUsage();
    process.exit(1);
  }

  return options;
}

function utcNow() {
  return new Date().toISOString();
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function loadTaskRequest(taskRequestPath) {
  return JSON.parse(fs.readFileSync(taskRequestPath, "utf8"));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function buildContextReferences(taskRequest) {
  return [
    "README.md",
    "docs/roadmap.md",
    "docs/wbs.md",
    ...(taskRequest.policy_refs || []),
  ];
}

function createSessionRecord(repoRoot, taskRequestPath, taskRequest, agentSessionId, startedAt) {
  return {
    agent_session_id: agentSessionId,
    task_request_id: taskRequest.task_request_id,
    execution_profile_id: taskRequest.execution_profile_id,
    runtime_capability_set_id: taskRequest.runtime_capability_set_id,
    session_state: "starting",
    runtime_handoff_status: "starting",
    task_request_path: toRepoRelativePath(repoRoot, taskRequestPath),
    policy_refs: taskRequest.policy_refs || [],
    context_refs: buildContextReferences(taskRequest),
    created_at: startedAt,
    updated_at: startedAt,
    started_at: startedAt,
    artifact_refs: [],
  };
}

function persistSessionRecord(statePaths, sessionRecord) {
  const sessionRecordPath = path.join(
    statePaths.agentSessionStateDir,
    `${sessionRecord.agent_session_id}.json`,
  );
  writeJson(sessionRecordPath, sessionRecord);
  return sessionRecordPath;
}

function markBlockedApproval(taskRequest) {
  return {
    status: "blocked",
    reasonCode: "approval_required",
    message:
      "The task request is not auto-approved, so Phase 1 session start is blocked pending approval handling.",
    approval_state: taskRequest.approval_state,
  };
}

function createProposal(repoRoot, sessionRecordPath) {
  const proposalSurfacePath = path.join(repoRoot, "scripts", "proposal-surface.js");
  const result = spawnSync(
    process.execPath,
    [proposalSurfacePath, "create-gitea-pr", "--session", sessionRecordPath],
    {
      cwd: repoRoot,
      encoding: "utf8",
    },
  );

  if (result.error) {
    throw new Error(`Proposal surface failed before launch: ${result.error.message}`);
  }

  let parsedOutput = null;
  const outputText = (result.stdout || "").trim();
  if (outputText) {
    parsedOutput = JSON.parse(outputText);
  }

  if (result.status !== 0) {
    const failureText =
      (parsedOutput && parsedOutput.message) ||
      (result.stderr || result.stdout || "proposal surface failed").trim();
    throw new Error(`Proposal surface failed: ${failureText}`);
  }

  return parsedOutput || {
    status: "proposal-created",
  };
}

function main() {
  try {
    const repoRoot = getRepoRoot();
    const statePaths = ensureProjectState(repoRoot);
    const { taskRequestPath, autoCreateProposal } = parseArguments(process.argv);
    const taskRequest = loadTaskRequest(taskRequestPath);

    if (taskRequest.approval_state !== "auto-approved") {
      console.log(JSON.stringify(markBlockedApproval(taskRequest), null, 2));
      process.exit(2);
    }

    const startedAt = utcNow();
    const agentSessionId = `ags-${sha256(`${taskRequest.task_request_id}:${startedAt}`).slice(0, 12)}`;
    const sessionRecord = createSessionRecord(
      repoRoot,
      taskRequestPath,
      taskRequest,
      agentSessionId,
      startedAt,
    );
    let sessionRecordPath = persistSessionRecord(statePaths, sessionRecord);

    try {
      const runtimeLaunch = launchWorkerRuntime({
        repoRoot,
        statePaths,
        sessionRecord,
        taskRequest,
      });
      sessionRecord.session_state = "running";
      sessionRecord.runtime_handoff_status = "workspace-prepared";
      sessionRecord.runtime_handoff_reason =
        "Worker runtime launched successfully and prepared a session-local workspace.";
      sessionRecord.runtime_worker = {
        runner: "docker",
        image: runtimeLaunch.workerImage || DEFAULT_WORKER_IMAGE,
        container_name: runtimeLaunch.containerName,
      };
      sessionRecord.workspace_ref = toRepoRelativePath(repoRoot, runtimeLaunch.workspaceDir);
      sessionRecord.artifact_dir_ref = toRepoRelativePath(repoRoot, runtimeLaunch.artifactDir);
      sessionRecord.artifact_refs = runtimeLaunch.artifactRefs;
      sessionRecord.runtime_launch_ref = toRepoRelativePath(repoRoot, runtimeLaunch.launchResultPath);
      sessionRecord.runtime_log_ref = toRepoRelativePath(repoRoot, runtimeLaunch.launchLogPath);
      sessionRecord.runtime_started_at = runtimeLaunch.launchedAt;
      sessionRecord.runtime_completed_at = runtimeLaunch.completedAt;
      sessionRecord.updated_at = utcNow();
      sessionRecordPath = persistSessionRecord(statePaths, sessionRecord);
    } catch (runtimeError) {
      const artifactOutput = runtimeError.artifactOutput || {};
      sessionRecord.session_state = "failed";
      sessionRecord.runtime_handoff_status = "runtime-start-failed";
      sessionRecord.failure_code = "runtime_start_failed";
      sessionRecord.runtime_handoff_reason = runtimeError.message;
      sessionRecord.updated_at = utcNow();
      sessionRecord.artifact_refs = artifactOutput.artifactRefs || sessionRecord.artifact_refs;
      sessionRecord.runtime_launch_ref = artifactOutput.runtimeLaunchPath
        ? toRepoRelativePath(repoRoot, artifactOutput.runtimeLaunchPath)
        : sessionRecord.runtime_launch_ref;
      sessionRecord.runtime_log_ref = artifactOutput.runtimeLogPath
        ? toRepoRelativePath(repoRoot, artifactOutput.runtimeLogPath)
        : sessionRecord.runtime_log_ref;
      sessionRecordPath = persistSessionRecord(statePaths, sessionRecord);

      console.log(
        JSON.stringify(
          {
            agent_session_id: agentSessionId,
            status: sessionRecord.session_state,
            runtime_handoff_status: sessionRecord.runtime_handoff_status,
            session_record_path: toRepoRelativePath(repoRoot, sessionRecordPath),
            message: runtimeError.message,
          },
          null,
          2,
        ),
      );
      process.exit(1);
    }

    let proposalResult = null;
    if (autoCreateProposal) {
      try {
        proposalResult = createProposal(repoRoot, sessionRecordPath);
        Object.assign(sessionRecord, readJson(sessionRecordPath));
      } catch (proposalError) {
        sessionRecord.session_state = "failed";
        sessionRecord.failure_code = "proposal_creation_failed";
        sessionRecord.runtime_handoff_status = "proposal-creation-failed";
        sessionRecord.runtime_handoff_reason = proposalError.message;
        sessionRecord.updated_at = utcNow();
        sessionRecordPath = persistSessionRecord(statePaths, sessionRecord);

        console.log(
          JSON.stringify(
            {
              agent_session_id: agentSessionId,
              status: sessionRecord.session_state,
              runtime_handoff_status: sessionRecord.runtime_handoff_status,
              session_record_path: toRepoRelativePath(repoRoot, sessionRecordPath),
              message: proposalError.message,
            },
            null,
            2,
          ),
        );
        process.exit(1);
      }
    }

    const output = {
      agent_session_id: agentSessionId,
      status: sessionRecord.session_state,
      runtime_handoff_status: sessionRecord.runtime_handoff_status,
      session_record_path: toRepoRelativePath(repoRoot, sessionRecordPath),
      workspace_ref: sessionRecord.workspace_ref,
      artifact_dir_ref: sessionRecord.artifact_dir_ref,
    };

    if (proposalResult) {
      output.proposal = {
        status: proposalResult.status,
        created: proposalResult.created,
        proposal_ref: proposalResult.proposal_ref,
        proposal_url: proposalResult.proposal_url,
        proposal_title: proposalResult.proposal_title,
        branch_ref: proposalResult.branch_ref,
        traceability_metadata_ref: proposalResult.traceability_metadata_ref,
      };
    }

    console.log(JSON.stringify(output, null, 2));
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
