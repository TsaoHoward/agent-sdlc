const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const { spawnSync } = require("child_process");

const { loadPolicyBundle, resolveTaskPolicy } = require("./lib/policy-loader");
const {
  ensureProjectState,
  getRepoRoot,
  toRepoRelativePath,
  writeJson,
} = require("./lib/project-state");
const { readGiteaBootstrapConfig } = require("./lib/gitea-client");

const DEFAULT_WEBHOOK_HOST = "127.0.0.1";
const DEFAULT_WEBHOOK_PORT = 4010;
const DEFAULT_WEBHOOK_ROUTE = "/hooks/gitea/issue-comment";

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node scripts/task-gateway.js normalize-gitea-issue-comment --event <event-json-path> [--auto-start-session]",
      "  node scripts/task-gateway.js serve-configured-gitea-webhook",
      "  node scripts/task-gateway.js serve-gitea-webhook [--host <host>] [--port <port>] [--route <path>] [--no-auto-start-session]",
    ].join("\n"),
  );
}

function parseArguments(argv) {
  if (argv.length < 3) {
    printUsage();
    process.exit(1);
  }

  const command = argv[2];
  if (command === "serve-configured-gitea-webhook") {
    if (argv.length !== 3) {
      printUsage();
      process.exit(1);
    }

    return {
      command,
    };
  }

  if (command === "normalize-gitea-issue-comment") {
    const options = {
      command,
      eventPath: null,
      autoStartSession: false,
    };

    for (let index = 3; index < argv.length; index += 1) {
      const token = argv[index];
      if (token === "--event") {
        options.eventPath = path.resolve(argv[index + 1]);
        index += 1;
        continue;
      }

      if (token === "--auto-start-session") {
        options.autoStartSession = true;
        continue;
      }

      printUsage();
      process.exit(1);
    }

    if (!options.eventPath) {
      printUsage();
      process.exit(1);
    }

    return options;
  }

  if (command === "serve-gitea-webhook") {
    const options = {
      command,
      host: DEFAULT_WEBHOOK_HOST,
      port: DEFAULT_WEBHOOK_PORT,
      route: DEFAULT_WEBHOOK_ROUTE,
      autoStartSession: true,
    };

    for (let index = 3; index < argv.length; index += 1) {
      const token = argv[index];
      if (token === "--host") {
        options.host = argv[index + 1];
        index += 1;
        continue;
      }

      if (token === "--port") {
        options.port = Number(argv[index + 1]);
        index += 1;
        continue;
      }

      if (token === "--route") {
        options.route = argv[index + 1];
        index += 1;
        continue;
      }

      if (token === "--no-auto-start-session") {
        options.autoStartSession = false;
        continue;
      }

      printUsage();
      process.exit(1);
    }

    if (!options.host || !options.route || !Number.isInteger(options.port) || options.port < 1) {
      printUsage();
      process.exit(1);
    }

    return options;
  }

  printUsage();
  process.exit(1);
}

function normalizeConfiguredRoute(route, fallbackRoute) {
  const normalized = String(route || fallbackRoute || "").trim();
  if (!normalized) {
    return "/";
  }

  return normalized.startsWith("/") ? normalized : `/${normalized}`;
}

function resolveConfiguredWebhookOptions(repoRoot) {
  const { config } = readGiteaBootstrapConfig(repoRoot);
  const issueCommentWebhook =
    (config.controlHost && config.controlHost.issueCommentWebhook) || {};

  if (issueCommentWebhook.enabled === false) {
    throw new Error("Configured issue-comment webhook is disabled in Gitea bootstrap config.");
  }

  const options = {
    command: "serve-gitea-webhook",
    host: issueCommentWebhook.host || DEFAULT_WEBHOOK_HOST,
    port: Number(issueCommentWebhook.port || DEFAULT_WEBHOOK_PORT),
    route: normalizeConfiguredRoute(issueCommentWebhook.route, DEFAULT_WEBHOOK_ROUTE),
    autoStartSession: issueCommentWebhook.autoStartSession !== false,
  };

  if (!options.host || !options.route || !Number.isInteger(options.port) || options.port < 1) {
    throw new Error("Configured issue-comment webhook host, port, or route is invalid.");
  }

  return options;
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

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
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

function normalizeEventEnvelopeFromFile(filePath) {
  const rawText = fs.readFileSync(filePath, "utf8");
  const eventData = JSON.parse(rawText);
  const payload = eventData.payload || eventData;
  const headers = eventData.headers || {};

  return buildNormalizedEnvelope({
    rawText,
    payload,
    headers,
    eventData,
  });
}

function buildNormalizedEnvelope({ rawText, payload, headers, eventData = null }) {
  return {
    rawText,
    eventData,
    payload,
    headers,
    eventType: firstDefined(
      eventData && eventData.eventType,
      eventData && eventData.source_event_type,
      headers["x-gitea-event"],
      headers["X-Gitea-Event"],
      headers["x-gogs-event"],
      headers["X-Gogs-Event"],
    ),
    deliveryId: firstDefined(
      eventData && eventData.delivery,
      eventData && eventData.deliveryId,
      eventData && eventData.source_event_id,
      headers["x-gitea-delivery"],
      headers["X-Gitea-Delivery"],
      headers["x-gogs-delivery"],
      headers["X-Gogs-Delivery"],
    ),
  };
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

function persistSourceEvent(repoRoot, statePaths, envelope) {
  const persistedAt = utcNow();
  const sourceEventId = envelope.deliveryId || `generated-event:${sha256(envelope.rawText).slice(0, 16)}`;
  const fileId = `sev-${sha256(sourceEventId).slice(0, 12)}`;
  const sourceEventPath = path.join(statePaths.sourceEventStateDir, `${fileId}.json`);

  writeJson(sourceEventPath, {
    source_event_record_id: fileId,
    source_event_id: sourceEventId,
    source_event_type: envelope.eventType || null,
    persisted_at: persistedAt,
    headers: envelope.headers,
    payload: envelope.payload,
    raw_text: envelope.rawText,
  });

  return sourceEventPath;
}

function normalizeTaskRequest(repoRoot, statePaths, envelope, sourcePayloadRef) {
  const policyBundle = loadPolicyBundle(repoRoot);
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
      source_payload_ref: sourcePayloadRef,
    },
    submitted_at: submittedAt,
    issue_ref: issueRef,
    comment_ref: commentRef,
    command_text: commandParseResult.commandText,
    source_payload_ref: sourcePayloadRef,
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

function startAgentSession(repoRoot, taskRequestPath, options = {}) {
  const agentControlPath = path.join(repoRoot, "scripts", "agent-control.js");
  const args = [agentControlPath, "start-session", "--task-request", taskRequestPath];
  if (options.autoCreateProposal) {
    args.push("--auto-create-proposal");
  }
  const result = spawnSync(
    process.execPath,
    args,
    {
      cwd: repoRoot,
      encoding: "utf8",
    },
  );

  if (result.error) {
    throw new Error(`Session starter failed before launch: ${result.error.message}`);
  }

  let parsedOutput = null;
  const outputText = (result.stdout || "").trim();
  if (outputText) {
    parsedOutput = JSON.parse(outputText);
  }

  if (result.status !== 0 && (!parsedOutput || parsedOutput.status !== "blocked")) {
    const failureText = (result.stderr || result.stdout || "session starter failed").trim();
    throw new Error(`Session starter failed: ${failureText}`);
  }

  return parsedOutput || {
    status: result.status === 0 ? "started" : "unknown",
  };
}

function buildAcceptedOutput(repoRoot, normalizeResult, sessionStartResult = null) {
  const output = {
    status: normalizeResult.status,
    task_request_id: normalizeResult.taskRequestId,
    approval_state: normalizeResult.approvalState,
    task_request_path: toRepoRelativePath(repoRoot, normalizeResult.taskRequestPath),
  };

  if (sessionStartResult) {
    output.session_start = sessionStartResult;
  }

  return output;
}

function handleNormalizeFromFile(repoRoot, eventPath, autoStartSession) {
  const statePaths = ensureProjectState(repoRoot);
  const envelope = normalizeEventEnvelopeFromFile(eventPath);
  const sourcePayloadRef = toRepoRelativePath(repoRoot, eventPath);
  const sourceEventPath = persistSourceEvent(repoRoot, statePaths, envelope);
  const normalizeResult = normalizeTaskRequest(
    repoRoot,
    statePaths,
    envelope,
    sourcePayloadRef,
  );

  if (normalizeResult.status !== "accepted") {
    return normalizeResult;
  }

  let sessionStartResult = null;
  if (autoStartSession && normalizeResult.approvalState === "auto-approved") {
    sessionStartResult = startAgentSession(repoRoot, normalizeResult.taskRequestPath, {
      autoCreateProposal: true,
    });
  }

  return buildAcceptedOutput(repoRoot, normalizeResult, sessionStartResult);
}

function writeJsonResponse(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
  });
  response.end(`${JSON.stringify(payload, null, 2)}\n`);
}

function startWebhookServer(repoRoot, options) {
  const statePaths = ensureProjectState(repoRoot);
  const server = http.createServer((request, response) => {
    if (request.method !== "POST" || request.url !== options.route) {
      writeJsonResponse(response, request.method === "POST" ? 404 : 405, {
        status: "rejected",
        message: "Only POST requests to the configured webhook route are supported.",
      });
      return;
    }

    const chunks = [];
    request.on("data", (chunk) => {
      chunks.push(chunk);
    });

    request.on("end", () => {
      try {
        const rawText = Buffer.concat(chunks).toString("utf8");
        const payload = JSON.parse(rawText);
        const envelope = buildNormalizedEnvelope({
          rawText,
          payload,
          headers: request.headers,
        });
        const sourceEventPath = persistSourceEvent(repoRoot, statePaths, envelope);
        const normalizeResult = normalizeTaskRequest(
          repoRoot,
          statePaths,
          envelope,
          toRepoRelativePath(repoRoot, sourceEventPath),
        );

        if (normalizeResult.status !== "accepted") {
          writeJsonResponse(response, 202, normalizeResult);
          return;
        }

        let sessionStartResult = null;
        if (options.autoStartSession && normalizeResult.approvalState === "auto-approved") {
          sessionStartResult = startAgentSession(repoRoot, normalizeResult.taskRequestPath, {
            autoCreateProposal: true,
          });
        }

        writeJsonResponse(
          response,
          202,
          buildAcceptedOutput(repoRoot, normalizeResult, sessionStartResult),
        );
      } catch (error) {
        writeJsonResponse(response, 500, {
          status: "error",
          message: error.message,
        });
      }
    });

    request.on("error", (error) => {
      writeJsonResponse(response, 500, {
        status: "error",
        message: error.message,
      });
    });
  });

  server.listen(options.port, options.host, () => {
    console.log(
      JSON.stringify(
        {
          status: "listening",
          host: options.host,
          port: options.port,
          route: options.route,
          auto_start_session: options.autoStartSession,
        },
        null,
        2,
      ),
    );
  });
}

function main() {
  try {
    const repoRoot = getRepoRoot();
    const options = parseArguments(process.argv);

    if (options.command === "normalize-gitea-issue-comment") {
      const result = handleNormalizeFromFile(repoRoot, options.eventPath, options.autoStartSession);

      if (result.status === "accepted") {
        console.log(JSON.stringify(result, null, 2));
        process.exit(0);
      }

      console.log(JSON.stringify(result, null, 2));
      process.exit(2);
    }

    if (options.command === "serve-configured-gitea-webhook") {
      startWebhookServer(repoRoot, resolveConfiguredWebhookOptions(repoRoot));
      return;
    }

    if (options.command === "serve-gitea-webhook") {
      startWebhookServer(repoRoot, options);
      return;
    }

    printUsage();
    process.exit(1);
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
