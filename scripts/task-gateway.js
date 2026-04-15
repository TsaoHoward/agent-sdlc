const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const { loadPolicyBundle, resolveTaskPolicy } = require("./lib/policy-loader");
const {
  ensureProjectState,
  getRepoRoot,
  toRepoRelativePath,
  writeJson,
} = require("./lib/project-state");

function printUsage() {
  console.error(
    "Usage: node scripts/task-gateway.js normalize-gitea-issue-comment --event <event-json-path>",
  );
}

function parseArguments(argv) {
  if (argv.length < 4) {
    printUsage();
    process.exit(1);
  }

  const [command, flag, eventPath] = argv.slice(2);
  if (command !== "normalize-gitea-issue-comment" || flag !== "--event" || !eventPath) {
    printUsage();
    process.exit(1);
  }

  return {
    command,
    eventPath: path.resolve(eventPath),
  };
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function utcNow() {
  return new Date().toISOString();
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null && value !== "");
}

function parseHostFromUrl(urlValue) {
  if (!urlValue) {
    return null;
  }

  try {
    return new URL(urlValue).host;
  } catch (error) {
    return null;
  }
}

function normalizeEventEnvelope(filePath) {
  const rawText = fs.readFileSync(filePath, "utf8");
  const eventData = JSON.parse(rawText);
  const payload = eventData.payload || eventData;
  const headers = eventData.headers || {};

  return {
    rawText,
    eventData,
    payload,
    headers,
    eventType: firstDefined(
      eventData.eventType,
      eventData.source_event_type,
      headers["x-gitea-event"],
      headers["X-Gitea-Event"],
      headers["x-gogs-event"],
      headers["X-Gogs-Event"],
    ),
    deliveryId: firstDefined(
      eventData.delivery,
      eventData.deliveryId,
      eventData.source_event_id,
      headers["x-gitea-delivery"],
      headers["X-Gitea-Delivery"],
      headers["x-gogs-delivery"],
      headers["X-Gogs-Delivery"],
    ),
  };
}

function buildRejectionGuidance(detail) {
  return [
    "Request rejected by the Phase 1 task-intake contract.",
    detail,
    "Expected format:",
    "@agent run <docs|code|review|ci>",
    "summary: <short human intent>",
  ].join("\n");
}

function reject(reasonCode, message) {
  return {
    status: "rejected",
    reasonCode,
    message,
    rejectionComment: buildRejectionGuidance(message),
  };
}

function parseCommand(commentBody, policyBundle) {
  const commandContract =
    policyBundle.commandContract && Object.keys(policyBundle.commandContract).length > 0
      ? policyBundle.commandContract
      : null;
  if (!commandContract) {
    throw new Error("Task command contract could not be loaded from policy.");
  }

  const normalizedBody = String(commentBody || "").replace(/\r\n/gu, "\n");
  const nonEmptyLines = normalizedBody
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "");

  if (nonEmptyLines.length === 0) {
    return reject("malformed_command", "Comment body is empty.");
  }

  const firstLinePattern = new RegExp(
    `^${escapeRegex(commandContract.mention)}\\s+${escapeRegex(commandContract.verb)}\\s+(\\S+)$`,
    "i",
  );
  const firstLineMatch = nonEmptyLines[0].match(firstLinePattern);
  if (!firstLineMatch) {
    return reject(
      "malformed_command",
      "First line must match '@agent run <docs|code|review|ci>'.",
    );
  }

  const taskToken = firstLineMatch[1].toLowerCase();
  const allowedTokens = policyBundle.taskClasses
    .flatMap((taskClass) => taskClass.commandTokens || [])
    .filter((token) => token && token !== "")
    .sort();

  if (!allowedTokens.includes(taskToken)) {
    return reject(
      "unsupported_task_class",
      `Unsupported task token '${taskToken}'. Allowed tokens: ${allowedTokens.join(", ")}.`,
    );
  }

  if (nonEmptyLines.length > 2) {
    return reject(
      "malformed_command",
      "Only the command line and one optional summary line are supported in Phase 1.",
    );
  }

  let summary = null;
  if (nonEmptyLines.length === 2) {
    const summaryLine = nonEmptyLines[1];
    if (!summaryLine.toLowerCase().startsWith("summary:")) {
      return reject(
        "malformed_command",
        "Only the 'summary:' field is supported after the command line.",
      );
    }

    summary = summaryLine.slice("summary:".length).trim();
    if (!summary) {
      return reject("malformed_command", "The 'summary:' field must not be empty.");
    }

    if (summary.length > commandContract.maxSummaryLength) {
      return reject(
        "malformed_command",
        `The 'summary:' field must be at most ${commandContract.maxSummaryLength} characters.`,
      );
    }
  }

  return {
    status: "accepted",
    taskToken,
    summary,
    commandText: nonEmptyLines.join("\n"),
  };
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

function deriveSourceEventId(envelope, payload, repositoryRef, triggerActorRef, commandText) {
  if (envelope.deliveryId) {
    return envelope.deliveryId;
  }

  const canonicalFallback = JSON.stringify({
    repositoryRef,
    issueNumber: payload.issue && payload.issue.number,
    commentId: payload.comment && payload.comment.id,
    triggerActorRef,
    commandText,
    createdAt: payload.comment && payload.comment.created_at,
    action: payload.action,
  });

  return `generated:gitea:issue_comment:${sha256(canonicalFallback).slice(0, 16)}`;
}

function normalizeTaskRequest(repoRoot, eventPath) {
  const statePaths = ensureProjectState(repoRoot);
  const policyBundle = loadPolicyBundle(repoRoot);
  const envelope = normalizeEventEnvelope(eventPath);
  const payload = envelope.payload;

  if (envelope.eventType && envelope.eventType !== "issue_comment") {
    return reject(
      "unsupported_event_type",
      `Expected 'issue_comment' but received '${envelope.eventType}'.`,
    );
  }

  if (payload.action && payload.action !== "created") {
    return reject(
      "unsupported_event_action",
      `Only newly created issue comments are supported in Phase 1. Received '${payload.action}'.`,
    );
  }

  if (!payload.repository || !payload.comment || !payload.issue) {
    return reject(
      "missing_context",
      "The event payload must include repository, issue, and comment objects.",
    );
  }

  const repositoryHost =
    parseHostFromUrl(payload.repository.html_url) ||
    parseHostFromUrl(payload.repository.clone_url) ||
    parseHostFromUrl(payload.repository.ssh_url) ||
    "localhost";
  const repositoryFullName = payload.repository.full_name;

  if (!repositoryFullName) {
    return reject("missing_context", "Repository full_name is required.");
  }

  if (!payload.repository.default_branch) {
    return reject("missing_context", "Repository default_branch is required.");
  }

  const repositoryRef = `gitea:${repositoryHost}/${repositoryFullName}`;
  const issueRef = `${repositoryRef}#issue/${payload.issue.number}`;
  const commentRef = `${repositoryRef}#comment/${payload.comment.id}`;
  const triggerUsername = firstDefined(
    payload.sender && payload.sender.username,
    payload.sender && payload.sender.login,
    payload.comment.user && payload.comment.user.username,
    payload.comment.user && payload.comment.user.login,
  );

  if (!triggerUsername) {
    return reject("missing_context", "The triggering user could not be resolved from the event payload.");
  }

  const triggerActorRef = `gitea:${repositoryHost}/users/${triggerUsername}`;
  const commandParseResult = parseCommand(payload.comment.body, policyBundle);
  if (commandParseResult.status === "rejected") {
    return commandParseResult;
  }

  const resolvedPolicy = resolveTaskPolicy(
    policyBundle,
    commandParseResult.taskToken,
    "issue_comment",
  );
  if (!resolvedPolicy) {
    return reject(
      "policy_resolution_failed",
      `No task policy matched token '${commandParseResult.taskToken}' for issue_comment.`,
    );
  }

  if (resolvedPolicy.taskClass.summaryRequired && !commandParseResult.summary) {
    return reject(
      "malformed_command",
      `Task token '${commandParseResult.taskToken}' requires a non-empty 'summary:' field.`,
    );
  }

  const sourceEventId = deriveSourceEventId(
    envelope,
    payload,
    repositoryRef,
    triggerActorRef,
    commandParseResult.commandText,
  );
  const taskRequestId = `trq-${sha256(sourceEventId).slice(0, 12)}`;
  const approvalState = resolvedPolicy.approvalRule.defaultApprovalState;
  const submittedAt = utcNow();

  const taskRequest = {
    task_request_id: taskRequestId,
    source_system: "gitea",
    source_event_id: sourceEventId,
    source_event_type: "issue_comment",
    repository_ref: repositoryRef,
    default_branch_ref: payload.repository.default_branch,
    target_branch_ref: payload.repository.default_branch,
    trigger_actor_ref: triggerActorRef,
    task_class: resolvedPolicy.taskClass.id,
    execution_profile_id: resolvedPolicy.executionProfile.id,
    runtime_capability_set_id: resolvedPolicy.runtimeCapabilitySet.id,
    approval_state: approvalState,
    policy_refs: resolvedPolicy.policyRefs,
    traceability_refs: {
      repository_ref: repositoryRef,
      issue_ref: issueRef,
      comment_ref: commentRef,
      source_payload_ref: toRepoRelativePath(repoRoot, eventPath),
    },
    submitted_at: submittedAt,
    issue_ref: issueRef,
    comment_ref: commentRef,
    command_text: commandParseResult.commandText,
    source_payload_ref: toRepoRelativePath(repoRoot, eventPath),
  };

  if (commandParseResult.summary) {
    taskRequest.summary = commandParseResult.summary;
  }

  if (approvalState === "approval-required") {
    taskRequest.approval_reason = `Approval required by policy rule '${resolvedPolicy.approvalRule.id}'.`;
  }

  if (approvalState === "rejected") {
    taskRequest.rejection_reason = `Rejected by policy rule '${resolvedPolicy.approvalRule.id}'.`;
  }

  const taskRequestPath = path.join(statePaths.taskRequestStateDir, `${taskRequestId}.json`);
  writeJson(taskRequestPath, taskRequest);

  return {
    status: "accepted",
    taskRequestId,
    approvalState,
    taskRequestPath,
    taskRequest,
  };
}

function main() {
  try {
    const { eventPath } = parseArguments(process.argv);
    const repoRoot = getRepoRoot();
    const result = normalizeTaskRequest(repoRoot, eventPath);

    if (result.status === "accepted") {
      console.log(
        JSON.stringify(
          {
            status: result.status,
            task_request_id: result.taskRequestId,
            approval_state: result.approvalState,
            task_request_path: toRepoRelativePath(repoRoot, result.taskRequestPath),
          },
          null,
          2,
        ),
      );
      process.exit(0);
    }

    console.log(JSON.stringify(result, null, 2));
    process.exit(2);
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
