const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const {
  buildRepositoryUrls,
  createPullRequest,
  getRepository,
  listPullRequests,
  loadLocalGiteaSettings,
  parseGiteaRepositoryRef,
  updatePullRequest,
} = require("./lib/gitea-client");
const { ensureProjectState, getRepoRoot, toRepoRelativePath, writeJson } = require("./lib/project-state");
const { buildTraceabilityBlock, deriveReviewStatus } = require("./lib/traceability");

const COMMIT_AUTHOR_NAME = process.env.AGENT_SDLC_COMMIT_AUTHOR_NAME || "Agent SDLC Bot";
const COMMIT_AUTHOR_EMAIL =
  process.env.AGENT_SDLC_COMMIT_AUTHOR_EMAIL || "agent-sdlc@example.local";

function printUsage() {
  console.error(
    "Usage: node scripts/proposal-surface.js create-gitea-pr --session <agent-session-json-path>",
  );
}

function parseArguments(argv) {
  if (argv.length !== 5 || argv[2] !== "create-gitea-pr" || argv[3] !== "--session") {
    printUsage();
    process.exit(1);
  }

  return {
    command: "create-gitea-pr",
    sessionRecordPath: path.resolve(argv[4]),
  };
}

function utcNow() {
  return new Date().toISOString();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function runGit(workspaceDir, args, options = {}) {
  const configArgs = [
    "-c",
    `safe.directory=${workspaceDir}`,
    ...(options.extraConfigs || []).flatMap((value) => ["-c", value]),
  ];
  const result = spawnSync("git", [...configArgs, ...args], {
    cwd: workspaceDir,
    encoding: "utf8",
  });

  if (result.error) {
    throw new Error(`Git command failed before execution: ${result.error.message}`);
  }

  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || `git ${args.join(" ")} failed`).trim();
    throw new Error(message);
  }

  return {
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
  };
}

function parseIssueNumber(issueRef) {
  const match = String(issueRef || "").match(/#issue\/(\d+)$/u);
  return match ? Number(match[1]) : null;
}

function deriveSummaryLabel(taskRequest) {
  if (taskRequest.summary) {
    return taskRequest.summary;
  }

  const labelByTaskClass = {
    documentation_update: "update documentation",
    bounded_code_change: "propose bounded change",
    review_follow_up: "address review follow-up",
    ci_failure_investigation: "investigate CI failure",
  };

  return labelByTaskClass[taskRequest.task_class] || "propose change";
}

function buildBranchName(taskRequest) {
  return `agent/${taskRequest.task_request_id}`;
}

function buildProposalTitle(taskRequest) {
  const summaryLabel = deriveSummaryLabel(taskRequest);
  const issueNumber = parseIssueNumber(taskRequest.issue_ref);
  if (issueNumber) {
    return `agent: ${summaryLabel} (#${issueNumber})`;
  }

  return `agent: ${summaryLabel}`;
}

function buildProposalBody(taskRequest, sessionRecord) {
  const parts = [
    buildTraceabilityBlock({
      task_request_id: taskRequest.task_request_id,
      agent_session_id: sessionRecord.agent_session_id,
      source_ref: taskRequest.issue_ref || taskRequest.pull_request_ref || taskRequest.comment_ref || "n/a",
      execution_profile_id: taskRequest.execution_profile_id,
      runtime_capability_set_id: taskRequest.runtime_capability_set_id,
      metadata_path: `.agent-sdlc/traceability/${taskRequest.task_request_id}.json`,
      verification_metadata_path: ".agent-sdlc/ci/verification-metadata.json",
      ci: {
        ci_status: "pending",
      },
      review_status: deriveReviewStatus("pending").label,
    }),
  ];

  if (taskRequest.summary) {
    parts.push("## Proposed Intent");
    parts.push(taskRequest.summary);
  }

  if (taskRequest.command_text) {
    parts.push("## Trigger Command");
    parts.push("```text");
    parts.push(taskRequest.command_text);
    parts.push("```");
  }

  return `${parts.join("\n\n")}\n`;
}

function ensureWorkspaceAvailable(repoRoot, sessionRecord) {
  if (!sessionRecord.workspace_ref) {
    throw new Error("Session record does not include workspace_ref.");
  }

  const workspaceDir = path.join(repoRoot, sessionRecord.workspace_ref);
  if (!fs.existsSync(workspaceDir)) {
    throw new Error(`Prepared workspace '${sessionRecord.workspace_ref}' was not found.`);
  }

  return workspaceDir;
}

function ensureBranchAndCommit(workspaceDir, branchName, traceabilityWorkspacePath, commitMessage) {
  runGit(workspaceDir, ["checkout", "-B", branchName]);
  runGit(workspaceDir, ["add", "-A"]);
  runGit(workspaceDir, ["add", "-f", traceabilityWorkspacePath]);

  const staged = runGit(workspaceDir, ["diff", "--cached", "--name-only"]).stdout
    .split(/\r?\n/gu)
    .map((line) => line.trim())
    .filter((line) => line !== "");

  if (staged.length === 0) {
    throw new Error("No staged proposal content was found in the prepared workspace.");
  }

  runGit(
    workspaceDir,
    ["commit", "-m", commitMessage],
    {
      extraConfigs: [
        `user.name=${COMMIT_AUTHOR_NAME}`,
        `user.email=${COMMIT_AUTHOR_EMAIL}`,
      ],
    },
  );
}

function pushBranch(workspaceDir, remoteUrl, branchName, basicAuthHeader) {
  runGit(
    workspaceDir,
    ["push", "--force", remoteUrl, `HEAD:refs/heads/${branchName}`],
    {
      extraConfigs: [`http.extraHeader=AUTHORIZATION: Basic ${basicAuthHeader}`],
    },
  );
}

function buildTraceabilityArtifact(repoRoot, taskRequest, sessionRecord, branchName, proposalInfo) {
  return {
    traceability_version: 1,
    created_at: utcNow(),
    task_request_id: taskRequest.task_request_id,
    agent_session_id: sessionRecord.agent_session_id,
    source_event_id: taskRequest.source_event_id,
    source_event_type: taskRequest.source_event_type,
    repository_ref: taskRequest.repository_ref,
    issue_ref: taskRequest.issue_ref || null,
    comment_ref: taskRequest.comment_ref || null,
    execution_profile_id: taskRequest.execution_profile_id,
    runtime_capability_set_id: taskRequest.runtime_capability_set_id,
    policy_refs: taskRequest.policy_refs || [],
    ...(proposalInfo.proposalRef
      ? {
          proposal_ref: proposalInfo.proposalRef,
        }
      : {}),
    ...(proposalInfo.proposalUrl
      ? {
          proposal_url: proposalInfo.proposalUrl,
        }
      : {}),
    ...(proposalInfo.proposalTitle
      ? {
          proposal_title: proposalInfo.proposalTitle,
        }
      : {}),
    proposal_state: proposalInfo.proposalState || "open",
    branch_ref: branchName,
    metadata_path: `.agent-sdlc/traceability/${taskRequest.task_request_id}.json`,
    source_payload_ref: taskRequest.source_payload_ref || null,
    task_request_path: toRepoRelativePath(repoRoot, path.join(repoRoot, sessionRecord.task_request_path)),
    session_record_path: toRepoRelativePath(repoRoot, path.join(repoRoot, ".agent-sdlc", "state", "agent-sessions", `${sessionRecord.agent_session_id}.json`)),
    ci: {
      ci_status: "pending",
      ci_run_ref: null,
      ci_run_url: null,
      verification_metadata_path: ".agent-sdlc/ci/verification-metadata.json",
    },
    review: {
      status: deriveReviewStatus("pending").id,
      proposal_body_sync_status: "pending",
    },
  };
}

function writeTraceabilityWorkspaceArtifact(workspaceDir, taskRequest, artifact) {
  const relativeArtifactPath = path.join(".agent-sdlc", "traceability", `${taskRequest.task_request_id}.json`);
  const absoluteArtifactPath = path.join(workspaceDir, relativeArtifactPath);
  fs.mkdirSync(path.dirname(absoluteArtifactPath), { recursive: true });
  writeJson(absoluteArtifactPath, artifact);
  return {
    relativeArtifactPath: relativeArtifactPath.replace(/\\/gu, "/"),
    absoluteArtifactPath,
  };
}

function writeTraceabilityStateArtifact(statePaths, taskRequest, artifact) {
  const absoluteArtifactPath = path.join(
    statePaths.traceabilityDir,
    `${taskRequest.task_request_id}.json`,
  );
  fs.mkdirSync(path.dirname(absoluteArtifactPath), { recursive: true });
  writeJson(absoluteArtifactPath, artifact);
  return absoluteArtifactPath;
}

function findExistingPullRequest(pullRequests, owner, branchName, baseBranch) {
  return pullRequests.find((pullRequest) => {
    const headRef = pullRequest.head && pullRequest.head.ref;
    const headLabel = pullRequest.head && pullRequest.head.label;
    const baseRef = pullRequest.base && pullRequest.base.ref;
    return (
      baseRef === baseBranch &&
      (headRef === branchName || headLabel === `${owner}:${branchName}`)
    );
  });
}

function buildProposalInfoFromPullRequest(repositoryInfo, pullRequest, proposalTitle = null) {
  const proposalIndex = pullRequest.number || pullRequest.index;
  return {
    proposalRef: `gitea:${repositoryInfo.host}/${repositoryInfo.owner}/${repositoryInfo.repo}#pull/${proposalIndex}`,
    proposalUrl: pullRequest.html_url || pullRequest.url || null,
    proposalTitle: proposalTitle || pullRequest.title || null,
    proposalState: pullRequest.state || "open",
  };
}

async function resolveProposalSeed(settings, repositoryRef, taskRequest, branchName) {
  const parsedRepository = parseGiteaRepositoryRef(repositoryRef);
  const existingPullRequests = await listPullRequests(
    settings,
    parsedRepository.owner,
    parsedRepository.repo,
    repositoryRef,
  );
  const existingPullRequest = findExistingPullRequest(
    existingPullRequests || [],
    parsedRepository.owner,
    branchName,
    taskRequest.target_branch_ref,
  );

  return {
    repositoryInfo: parsedRepository,
    existingPullRequest,
  };
}

async function createOrUpdatePullRequest(
  settings,
  repositoryRef,
  taskRequest,
  sessionRecord,
  branchName,
  resolvedProposalSeed = null,
) {
  const parsedRepository =
    (resolvedProposalSeed && resolvedProposalSeed.repositoryInfo) ||
    parseGiteaRepositoryRef(repositoryRef);
  const proposalTitle = buildProposalTitle(taskRequest);
  const proposalBody = buildProposalBody(taskRequest, sessionRecord);
  const existingPullRequest =
    resolvedProposalSeed && Object.prototype.hasOwnProperty.call(resolvedProposalSeed, "existingPullRequest")
      ? resolvedProposalSeed.existingPullRequest
      : null;

  if (existingPullRequest) {
    const updatedPullRequest = await updatePullRequest(
      settings,
      parsedRepository.owner,
      parsedRepository.repo,
      existingPullRequest.number || existingPullRequest.index,
      {
        title: proposalTitle,
        body: proposalBody,
      },
      repositoryRef,
    );

    return {
      pullRequest: updatedPullRequest,
      proposalTitle,
      created: false,
    };
  }

  let createdPullRequest;
  try {
    createdPullRequest = await createPullRequest(
      settings,
      parsedRepository.owner,
      parsedRepository.repo,
      {
        title: proposalTitle,
        body: proposalBody,
        base: taskRequest.target_branch_ref,
        head: branchName,
      },
      repositoryRef,
    );
  } catch (error) {
    if (error.statusCode === 422) {
      createdPullRequest = await createPullRequest(
        settings,
        parsedRepository.owner,
        parsedRepository.repo,
        {
          title: proposalTitle,
          body: proposalBody,
          base: taskRequest.target_branch_ref,
          head: `${parsedRepository.owner}:${branchName}`,
        },
        repositoryRef,
      );
    } else {
      throw error;
    }
  }

  return {
    pullRequest: createdPullRequest,
    proposalTitle,
    created: true,
  };
}

async function main() {
  try {
    const repoRoot = getRepoRoot();
    const statePaths = ensureProjectState(repoRoot);
    const { sessionRecordPath } = parseArguments(process.argv);
    const sessionRecord = readJson(sessionRecordPath);
    const taskRequestPath = path.join(repoRoot, sessionRecord.task_request_path);
    const taskRequest = readJson(taskRequestPath);

    const workspaceDir = ensureWorkspaceAvailable(repoRoot, sessionRecord);
    const settings = loadLocalGiteaSettings(repoRoot);
    const repositoryInfo = parseGiteaRepositoryRef(taskRequest.repository_ref);
    const remoteUrls = buildRepositoryUrls(
      settings,
      repositoryInfo.owner,
      repositoryInfo.repo,
      taskRequest.repository_ref,
    );
    const repository = await getRepository(
      settings,
      repositoryInfo.owner,
      repositoryInfo.repo,
      taskRequest.repository_ref,
    );

    if (!repository) {
      throw new Error(
        `Target Gitea repository '${repositoryInfo.owner}/${repositoryInfo.repo}' does not exist at ${remoteUrls.webUrl}.`,
      );
    }

    const branchName = buildBranchName(taskRequest);
    const basicAuthHeader = Buffer.from(`${settings.username}:${settings.password}`, "utf8").toString(
      "base64",
    );
    const resolvedProposalSeed = await resolveProposalSeed(
      settings,
      taskRequest.repository_ref,
      taskRequest,
      branchName,
    );

    const proposalSeed = resolvedProposalSeed.existingPullRequest
      ? buildProposalInfoFromPullRequest(
          resolvedProposalSeed.repositoryInfo,
          resolvedProposalSeed.existingPullRequest,
          buildProposalTitle(taskRequest),
        )
      : {
          proposalRef: null,
          proposalUrl: null,
          proposalTitle: buildProposalTitle(taskRequest),
          proposalState: "open",
        };
    const traceabilityArtifact = buildTraceabilityArtifact(
      repoRoot,
      taskRequest,
      sessionRecord,
      branchName,
      proposalSeed,
    );
    const traceabilityPath = writeTraceabilityWorkspaceArtifact(
      workspaceDir,
      taskRequest,
      traceabilityArtifact,
    );

    ensureBranchAndCommit(
      workspaceDir,
      branchName,
      traceabilityPath.relativeArtifactPath,
      `agent: prepare proposal for ${taskRequest.task_request_id}`,
    );
    pushBranch(workspaceDir, remoteUrls.gitUrl, branchName, basicAuthHeader);

    const proposalResult = await createOrUpdatePullRequest(
      settings,
      taskRequest.repository_ref,
      taskRequest,
      sessionRecord,
      branchName,
      resolvedProposalSeed,
    );
    const pullRequest = proposalResult.pullRequest;
    const proposalInfo = buildProposalInfoFromPullRequest(
      repositoryInfo,
      pullRequest,
      proposalResult.proposalTitle,
    );

    const shouldRewriteTraceability =
      traceabilityArtifact.proposal_ref !== proposalInfo.proposalRef ||
      traceabilityArtifact.proposal_url !== proposalInfo.proposalUrl ||
      traceabilityArtifact.proposal_title !== proposalInfo.proposalTitle ||
      traceabilityArtifact.proposal_state !== proposalInfo.proposalState;

    if (shouldRewriteTraceability) {
      traceabilityArtifact.proposal_ref = proposalInfo.proposalRef;
      traceabilityArtifact.proposal_url = proposalInfo.proposalUrl;
      traceabilityArtifact.proposal_title = proposalInfo.proposalTitle;
      traceabilityArtifact.proposal_state = proposalInfo.proposalState;
      writeJson(traceabilityPath.absoluteArtifactPath, traceabilityArtifact);
    }

    const stateTraceabilityPath = writeTraceabilityStateArtifact(
      statePaths,
      taskRequest,
      traceabilityArtifact,
    );
    const stateTraceabilityRef = toRepoRelativePath(repoRoot, stateTraceabilityPath);
    const workspaceTraceabilityRef = toRepoRelativePath(repoRoot, traceabilityPath.absoluteArtifactPath);

    sessionRecord.session_state = "completed";
    sessionRecord.updated_at = utcNow();
    sessionRecord.completed_at = sessionRecord.updated_at;
    sessionRecord.proposal_ref = proposalInfo.proposalRef;
    sessionRecord.proposal_url = proposalInfo.proposalUrl;
    sessionRecord.proposal_title = proposalInfo.proposalTitle;
    sessionRecord.proposal_branch_ref = branchName;
    sessionRecord.traceability_metadata_ref = stateTraceabilityRef;
    sessionRecord.artifact_refs = [
      ...(sessionRecord.artifact_refs || []),
      stateTraceabilityRef,
      workspaceTraceabilityRef,
    ].filter((value, index, values) => values.indexOf(value) === index);
    writeJson(sessionRecordPath, sessionRecord);

    console.log(
      JSON.stringify(
        {
          status: "proposal-created",
          created: proposalResult.created,
          task_request_id: taskRequest.task_request_id,
          agent_session_id: sessionRecord.agent_session_id,
          proposal_ref: proposalInfo.proposalRef,
          proposal_url: proposalInfo.proposalUrl,
          proposal_title: proposalInfo.proposalTitle,
          branch_ref: branchName,
          traceability_metadata_ref: stateTraceabilityRef,
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
