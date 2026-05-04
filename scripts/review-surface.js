const fs = require("fs");
const http = require("http");
const path = require("path");

const {
  getPullRequest,
  listRepositoryActionRuns,
  listPullReviews,
  loadLocalGiteaSettings,
  readGiteaBootstrapConfig,
  updatePullRequest,
} = require("./lib/gitea-client");
const { ensureProjectState, getRepoRoot, toRepoRelativePath, writeJson } = require("./lib/project-state");
const {
  buildTraceabilityBlock,
  deriveReviewStatus,
  labelForReviewStatus,
  replaceTraceabilityBlock,
} = require("./lib/traceability");

const DEFAULT_WEBHOOK_HOST = "127.0.0.1";
const DEFAULT_WEBHOOK_PORT = 4011;
const DEFAULT_WEBHOOK_ROUTE = "/hooks/gitea/pull-request-review";
const DEFAULT_CI_TRACEABILITY_SYNC_ROUTE = "/hooks/internal/ci-traceability";

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node scripts/review-surface.js sync-gitea-proposal-traceability --session <agent-session-json-path>",
      "  node scripts/review-surface.js sync-gitea-proposal-traceability --proposal <gitea:host/owner/repo#pull/index>",
      "  node scripts/review-surface.js sync-gitea-pr-review-outcome --session <agent-session-json-path>",
      "  node scripts/review-surface.js sync-gitea-pr-review-outcome --proposal <gitea:host/owner/repo#pull/index>",
      "  node scripts/review-surface.js sync-gitea-pr-review-event --event <event-json-path>",
      "  node scripts/review-surface.js serve-configured-gitea-review-webhook",
      "  node scripts/review-surface.js serve-gitea-review-webhook [--host <host>] [--port <port>] [--route <path>]",
    ].join("\n"),
  );
}

function parseArguments(argv) {
  if (argv.length < 3) {
    printUsage();
    process.exit(1);
  }

  const command = argv[2];
  if (command === "serve-configured-gitea-review-webhook") {
    if (argv.length !== 3) {
      printUsage();
      process.exit(1);
    }

    return {
      command,
    };
  }

  if (command === "sync-gitea-proposal-traceability") {
    const options = {
      command,
      sessionRecordPath: null,
      proposalRef: null,
    };

    for (let index = 3; index < argv.length; index += 1) {
      const token = argv[index];
      if (token === "--session") {
        options.sessionRecordPath = path.resolve(argv[index + 1]);
        index += 1;
        continue;
      }

      if (token === "--proposal") {
        options.proposalRef = argv[index + 1];
        index += 1;
        continue;
      }

      printUsage();
      process.exit(1);
    }

    if ((options.sessionRecordPath && options.proposalRef) || (!options.sessionRecordPath && !options.proposalRef)) {
      printUsage();
      process.exit(1);
    }

    return options;
  }

  if (command === "sync-gitea-pr-review-outcome") {
    const options = {
      command,
      sessionRecordPath: null,
      proposalRef: null,
    };

    for (let index = 3; index < argv.length; index += 1) {
      const token = argv[index];
      if (token === "--session") {
        options.sessionRecordPath = path.resolve(argv[index + 1]);
        index += 1;
        continue;
      }

      if (token === "--proposal") {
        options.proposalRef = argv[index + 1];
        index += 1;
        continue;
      }

      printUsage();
      process.exit(1);
    }

    if ((options.sessionRecordPath && options.proposalRef) || (!options.sessionRecordPath && !options.proposalRef)) {
      printUsage();
      process.exit(1);
    }

    return options;
  }

  if (command === "sync-gitea-pr-review-event") {
    const options = {
      command,
      eventPath: null,
    };

    for (let index = 3; index < argv.length; index += 1) {
      const token = argv[index];
      if (token === "--event") {
        options.eventPath = path.resolve(argv[index + 1]);
        index += 1;
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

  if (command === "serve-gitea-review-webhook") {
    const options = {
      command,
      host: DEFAULT_WEBHOOK_HOST,
      port: DEFAULT_WEBHOOK_PORT,
      route: DEFAULT_WEBHOOK_ROUTE,
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

function resolveConfiguredReviewWebhookOptions(repoRoot) {
  const { config } = readGiteaBootstrapConfig(repoRoot);
  const reviewWebhook = (config.controlHost && config.controlHost.reviewWebhook) || {};

  if (reviewWebhook.enabled === false) {
    throw new Error("Configured review webhook is disabled in Gitea bootstrap config.");
  }

  const options = {
    command: "serve-gitea-review-webhook",
    host: reviewWebhook.host || DEFAULT_WEBHOOK_HOST,
    port: Number(reviewWebhook.port || DEFAULT_WEBHOOK_PORT),
    route: normalizeConfiguredRoute(reviewWebhook.route, DEFAULT_WEBHOOK_ROUTE),
  };

  if (!options.host || !options.route || !Number.isInteger(options.port) || options.port < 1) {
    throw new Error("Configured review webhook host, port, or route is invalid.");
  }

  return options;
}

function utcNow() {
  return new Date().toISOString();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
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

function parseProposalRef(proposalRef) {
  const match = String(proposalRef || "").match(/^gitea:([^/]+)\/([^/]+)\/([^#]+)#pull\/(\d+)$/u);
  if (!match) {
    throw new Error(`Unsupported Gitea proposal_ref '${proposalRef}'.`);
  }

  return {
    host: match[1],
    owner: match[2],
    repo: match[3],
    index: Number(match[4]),
  };
}

function normalizeWebhookEventType(eventType) {
  return String(eventType || "").trim().toLowerCase();
}

function resolveProposalRefFromEvent(envelope) {
  const eventType = normalizeWebhookEventType(envelope.eventType);
  const payload = envelope.payload || {};
  const pullRequest = payload.pull_request || payload.pullRequest || null;

  if (!["pull_request_review", "pull_request"].includes(eventType)) {
    return {
      status: "ignored",
      message: `Expected 'pull_request_review' or 'pull_request' but received '${envelope.eventType || "unknown"}'.`,
    };
  }

  if (!payload.repository || !pullRequest) {
    throw new Error("The review event payload must include repository and pull_request objects.");
  }

  if (eventType === "pull_request") {
    const action = String(payload.action || "").trim().toLowerCase();
    if (action && !["closed", "reopened"].includes(action)) {
      return {
        status: "ignored",
        message: `Review sync ignores pull_request action '${payload.action}'.`,
      };
    }
  }

  const repositoryFullName = payload.repository.full_name;
  const proposalIndex = pullRequest.number || pullRequest.index || payload.number || null;
  const repositoryHost =
    parseHostFromUrl(payload.repository.html_url) ||
    parseHostFromUrl(payload.repository.clone_url) ||
    parseHostFromUrl(payload.repository.ssh_url) ||
    parseHostFromUrl(pullRequest.html_url) ||
    "localhost";

  if (!repositoryFullName || !proposalIndex) {
    throw new Error("The review event payload must include repository.full_name and pull_request.number.");
  }

  return {
    status: "accepted",
    proposalRef: `gitea:${repositoryHost}/${repositoryFullName}#pull/${proposalIndex}`,
    eventType,
    action: payload.action || null,
    deliveryId: envelope.deliveryId || null,
  };
}

function buildReviewDecisionRef(proposalInfo, reviewId) {
  return `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}#pull/${proposalInfo.index}/review/${reviewId}`;
}

function buildReviewerRef(proposalInfo, login) {
  if (!login) {
    return null;
  }

  return `gitea:${proposalInfo.host}/${login}`;
}

function normalizeReviewState(state) {
  return String(state || "").trim().toUpperCase();
}

function pickLatestDecisionReview(reviews) {
  const filteredReviews = (reviews || []).filter((review) => {
    const state = normalizeReviewState(review.state);
    return !review.dismissed && !review.stale && ["APPROVED", "REQUEST_CHANGES"].includes(state);
  });

  if (filteredReviews.length === 0) {
    return null;
  }

  return filteredReviews
    .slice()
    .sort((left, right) => {
      const leftTime = Date.parse(left.submitted_at || left.updated_at || 0);
      const rightTime = Date.parse(right.submitted_at || right.updated_at || 0);
      return rightTime - leftTime;
    })[0];
}

function deriveReviewOutcome(pullRequest, reviews, proposalInfo) {
  if (pullRequest.merged) {
    return {
      status: "merged",
      decisionOutcome: "merged",
      reviewDecisionRef: `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}#pull/${proposalInfo.index}/merge`,
      reviewerLogin: pullRequest.merged_by && pullRequest.merged_by.login,
      reviewerRef: buildReviewerRef(proposalInfo, pullRequest.merged_by && pullRequest.merged_by.login),
      decidedAt: pullRequest.merged_at || pullRequest.updated_at || utcNow(),
    };
  }

  if (pullRequest.state === "closed") {
    return {
      status: "closed-without-merge",
      decisionOutcome: "closed-without-merge",
      reviewDecisionRef: `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}#pull/${proposalInfo.index}/close`,
      reviewerLogin: null,
      reviewerRef: null,
      decidedAt: pullRequest.closed_at || pullRequest.updated_at || utcNow(),
    };
  }

  const latestDecisionReview = pickLatestDecisionReview(reviews);
  if (!latestDecisionReview) {
    return {
      status: pullRequest.state === "open" ? "awaiting-review-decision" : "awaiting-ci",
      decisionOutcome: null,
      reviewDecisionRef: null,
      reviewerLogin: null,
      reviewerRef: null,
      decidedAt: pullRequest.updated_at || utcNow(),
    };
  }

  const normalizedState = normalizeReviewState(latestDecisionReview.state);
  return {
    status: normalizedState === "APPROVED" ? "approved" : "changes-requested",
    decisionOutcome: normalizedState === "APPROVED" ? "approved" : "changes-requested",
    reviewDecisionRef: buildReviewDecisionRef(proposalInfo, latestDecisionReview.id),
    reviewerLogin: latestDecisionReview.user && latestDecisionReview.user.login,
    reviewerRef: buildReviewerRef(
      proposalInfo,
      latestDecisionReview.user && latestDecisionReview.user.login,
    ),
    decidedAt:
      latestDecisionReview.submitted_at ||
      latestDecisionReview.updated_at ||
      pullRequest.updated_at ||
      utcNow(),
  };
}

function listSessionRecordPaths(statePaths) {
  if (!fs.existsSync(statePaths.agentSessionStateDir)) {
    return [];
  }

  return fs
    .readdirSync(statePaths.agentSessionStateDir)
    .filter((entry) => entry.toLowerCase().endsWith(".json"))
    .map((entry) => path.join(statePaths.agentSessionStateDir, entry));
}

function loadSessionRecords(statePaths) {
  return listSessionRecordPaths(statePaths).map((filePath) => ({
    filePath,
    sessionRecord: readJson(filePath),
  }));
}

function sessionSortKey(sessionRecord) {
  return Date.parse(
    sessionRecord.updated_at ||
      sessionRecord.completed_at ||
      sessionRecord.runtime_completed_at ||
      sessionRecord.created_at ||
      0,
  );
}

function findSessionsByProposalRef(statePaths, proposalRef) {
  return loadSessionRecords(statePaths)
    .filter(({ sessionRecord }) => sessionRecord.proposal_ref === proposalRef)
    .sort((left, right) => sessionSortKey(right.sessionRecord) - sessionSortKey(left.sessionRecord));
}

function dedupePaths(paths) {
  return paths.filter((candidate, index, values) => candidate && values.indexOf(candidate) === index);
}

function collectSessionTraceabilityPaths(repoRoot, sessionEntries) {
  return dedupePaths(
    sessionEntries.flatMap(({ sessionRecord }) => {
      const explicitPaths = [];

      if (sessionRecord.traceability_metadata_ref) {
        explicitPaths.push(path.join(repoRoot, sessionRecord.traceability_metadata_ref));
      }

      const artifactPaths = (sessionRecord.artifact_refs || [])
        .filter((artifactRef) => typeof artifactRef === "string")
        .filter((artifactRef) => /(^|\/)\.agent-sdlc\/traceability\/[^/]+\.json$/u.test(artifactRef))
        .map((artifactRef) => path.join(repoRoot, artifactRef));

      return [...explicitPaths, ...artifactPaths].filter((absolutePath) => fs.existsSync(absolutePath));
    }),
  );
}

function resolveTraceabilityTargets(repoRoot, statePaths, options) {
  const {
    sessionEntries,
    taskRequestId = null,
    proposalRef = null,
    explicitSessionTraceabilityPath = null,
  } = options;
  const uniqueTaskRequestIds = [...new Set(
    sessionEntries.map(({ sessionRecord }) => sessionRecord.task_request_id).filter((value) => value),
  )];

  if (!taskRequestId && uniqueTaskRequestIds.length > 1) {
    throw new Error(
      `Proposal '${proposalRef}' maps to multiple task_request_id values: ${uniqueTaskRequestIds.join(", ")}.`,
    );
  }

  const resolvedTaskRequestId = taskRequestId || uniqueTaskRequestIds[0] || null;
  const stateTraceabilityPath =
    resolvedTaskRequestId && path.join(statePaths.traceabilityDir, `${resolvedTaskRequestId}.json`);
  const sessionTraceabilityPaths = collectSessionTraceabilityPaths(repoRoot, sessionEntries);
  const syncPaths = dedupePaths([
    stateTraceabilityPath,
    explicitSessionTraceabilityPath,
    ...sessionTraceabilityPaths,
  ]);
  const existingPrimaryCandidates = dedupePaths([
    stateTraceabilityPath && fs.existsSync(stateTraceabilityPath) ? stateTraceabilityPath : null,
    explicitSessionTraceabilityPath && fs.existsSync(explicitSessionTraceabilityPath)
      ? explicitSessionTraceabilityPath
      : null,
    ...sessionTraceabilityPaths,
  ]);

  if (existingPrimaryCandidates.length === 0) {
    throw new Error("Traceability metadata file was not found for the requested review sync target.");
  }

  return {
    taskRequestId: resolvedTaskRequestId,
    primaryPath: existingPrimaryCandidates[0],
    syncPaths,
    matchedSessionIds: sessionEntries
      .map(({ sessionRecord }) => sessionRecord.agent_session_id)
      .filter((value) => value),
  };
}

function resolveSyncContextBySession(repoRoot, statePaths, sessionRecordPath) {
  const sessionRecord = readJson(sessionRecordPath);

  if (sessionRecord.proposal_ref) {
    const matchingSessions = findSessionsByProposalRef(statePaths, sessionRecord.proposal_ref);
    if (matchingSessions.length > 0) {
      return {
        proposalRef: sessionRecord.proposal_ref,
        sessionEntries: matchingSessions,
        traceabilityTargets: resolveTraceabilityTargets(repoRoot, statePaths, {
          sessionEntries: matchingSessions,
          proposalRef: sessionRecord.proposal_ref,
        }),
      };
    }
  }

  const singleSessionEntry = [{ filePath: sessionRecordPath, sessionRecord }];
  const explicitSessionTraceabilityPath =
    sessionRecord.traceability_metadata_ref &&
    path.join(repoRoot, sessionRecord.traceability_metadata_ref);

  return {
    proposalRef: sessionRecord.proposal_ref || null,
    sessionEntries: singleSessionEntry,
    traceabilityTargets: resolveTraceabilityTargets(repoRoot, statePaths, {
      sessionEntries: singleSessionEntry,
      taskRequestId: sessionRecord.task_request_id || null,
      proposalRef: sessionRecord.proposal_ref || null,
      explicitSessionTraceabilityPath,
    }),
  };
}

function resolveSyncContextByProposalRef(repoRoot, statePaths, proposalRef) {
  const matchingSessions = findSessionsByProposalRef(statePaths, proposalRef);
  if (matchingSessions.length === 0) {
    throw new Error(`No session record was found for proposal '${proposalRef}'.`);
  }

  return {
    proposalRef,
    sessionEntries: matchingSessions,
    traceabilityTargets: resolveTraceabilityTargets(repoRoot, statePaths, {
      sessionEntries: matchingSessions,
      proposalRef,
    }),
  };
}

function resolveSyncContextByEvent(repoRoot, statePaths, envelope) {
  const eventResolution = resolveProposalRefFromEvent(envelope);
  if (eventResolution.status !== "accepted") {
    return eventResolution;
  }

  const syncContext = resolveSyncContextByProposalRef(repoRoot, statePaths, eventResolution.proposalRef);
  syncContext.eventType = eventResolution.eventType;
  syncContext.eventAction = eventResolution.action;
  syncContext.deliveryId = eventResolution.deliveryId;
  return {
    status: "accepted",
    syncContext,
  };
}

function writeTraceabilityCopies(filePaths, value) {
  filePaths.forEach((filePath) => {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    writeJson(filePath, value);
  });
}

function selectLatestRunForProposal(workflowRuns, proposalInfo) {
  const expectedPathSuffix = `@refs/pull/${proposalInfo.index}/head`;
  const matchingRuns = (workflowRuns || []).filter((run) => {
    return String(run.path || "").endsWith(expectedPathSuffix);
  });

  if (matchingRuns.length === 0) {
    return null;
  }

  return matchingRuns
    .slice()
    .sort((left, right) => {
      const leftOrder = Number(left.run_number || left.id || 0);
      const rightOrder = Number(right.run_number || right.id || 0);
      return rightOrder - leftOrder;
    })[0];
}

function deriveCiStatusFromRun(run) {
  if (!run) {
    return null;
  }

  if (run.status && run.status !== "completed") {
    return "pending";
  }

  switch (String(run.conclusion || "").trim().toLowerCase()) {
    case "success":
      return "success";
    case "cancelled":
      return "cancelled";
    case "failure":
    default:
      return "failure";
  }
}

async function enrichTraceabilityCiFromActions(settings, repositoryRef, proposalInfo, traceability) {
  const runsResponse = await listRepositoryActionRuns(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    repositoryRef,
  );
  const latestRun = selectLatestRunForProposal(runsResponse && runsResponse.workflow_runs, proposalInfo);
  if (!latestRun) {
    return traceability;
  }

  traceability.ci = traceability.ci || {};
  traceability.ci.ci_status = deriveCiStatusFromRun(latestRun) || traceability.ci.ci_status || "pending";
  traceability.ci.ci_run_ref = String(latestRun.run_number || latestRun.id || traceability.ci.ci_run_ref || "");
  traceability.ci.ci_run_url = latestRun.html_url || latestRun.url || traceability.ci.ci_run_url || null;
  traceability.ci.workflow_ref = latestRun.path || traceability.ci.workflow_ref || null;
  traceability.ci.workflow_run_id = latestRun.id || traceability.ci.workflow_run_id || null;
  traceability.ci.workflow_run_number =
    latestRun.run_number || traceability.ci.workflow_run_number || null;
  traceability.ci.completed_at =
    latestRun.completed_at || traceability.ci.completed_at || null;

  if (!traceability.ci.verification_metadata_path) {
    traceability.ci.verification_metadata_path = ".agent-sdlc/ci/verification-metadata.json";
  }

  if (!traceability.review) {
    traceability.review = {};
  }

  return traceability;
}

function hasExplicitReviewDecision(review = {}) {
  const explicitStatuses = new Set([
    "approved",
    "changes-requested",
    "merged",
    "closed-without-merge",
  ]);

  return Boolean(
    review.review_decision_ref ||
      review.decision_outcome ||
      explicitStatuses.has(String(review.status || "").trim()),
  );
}

function mergeProposalTraceabilitySnapshot(traceability, snapshot) {
  if (!snapshot || typeof snapshot !== "object") {
    return traceability;
  }

  if (snapshot.proposal_ref) {
    traceability.proposal_ref = snapshot.proposal_ref;
  }
  if (snapshot.proposal_url) {
    traceability.proposal_url = snapshot.proposal_url;
  }
  if (snapshot.proposal_title) {
    traceability.proposal_title = snapshot.proposal_title;
  }
  if (snapshot.proposal_state) {
    traceability.proposal_state = snapshot.proposal_state;
  }

  if (snapshot.ci && typeof snapshot.ci === "object") {
    traceability.ci = traceability.ci || {};
    for (const [field, value] of Object.entries(snapshot.ci)) {
      if (value !== undefined) {
        traceability.ci[field] = value;
      }
    }
  }

  return traceability;
}

async function syncProposalBody(settings, repositoryRef, proposalInfo, traceability) {
  const currentPullRequest = await getPullRequest(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    repositoryRef,
  );

  if (!currentPullRequest) {
    throw new Error(`Pull request '${traceability.proposal_ref}' was not found for review outcome sync.`);
  }

  const nextBody = replaceTraceabilityBlock(
    currentPullRequest.body || "",
    buildTraceabilityBlock({
      task_request_id: traceability.task_request_id,
      agent_session_id: traceability.agent_session_id,
      source_ref: traceability.issue_ref || traceability.pull_request_ref || traceability.comment_ref || "n/a",
      execution_profile_id: traceability.execution_profile_id,
      runtime_capability_set_id: traceability.runtime_capability_set_id,
      metadata_path: traceability.metadata_path,
      verification_metadata_path:
        (traceability.ci && traceability.ci.verification_metadata_path) ||
        ".agent-sdlc/ci/verification-metadata.json",
      ci: traceability.ci,
      review: traceability.review,
    }),
  );

  if (nextBody === (currentPullRequest.body || "")) {
    return currentPullRequest;
  }

  return updatePullRequest(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    {
      title: currentPullRequest.title,
      body: nextBody,
    },
    repositoryRef,
  );
}

async function syncReviewOutcome(repoRoot, statePaths, syncContext) {
  const { traceabilityTargets, proposalRef } = syncContext;
  const traceabilityPath = traceabilityTargets.primaryPath;
  const traceability = readJson(traceabilityPath);

  if (traceability.proposal_ref && proposalRef && traceability.proposal_ref !== proposalRef) {
    throw new Error(
      `Traceability record proposal_ref '${traceability.proposal_ref}' did not match requested proposal '${proposalRef}'.`,
    );
  }

  if (!traceability.proposal_ref) {
    if (!proposalRef) {
      throw new Error("Traceability record does not include proposal_ref.");
    }

    traceability.proposal_ref = proposalRef;
  }

  const proposalInfo = parseProposalRef(traceability.proposal_ref);
  const repositoryRef = `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}`;
  const settings = loadLocalGiteaSettings(repoRoot);
  const pullRequest = await getPullRequest(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    repositoryRef,
  );

  if (!pullRequest) {
    throw new Error(`Pull request '${traceability.proposal_ref}' was not found.`);
  }

  const reviews = await listPullReviews(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    repositoryRef,
  );
  await enrichTraceabilityCiFromActions(settings, repositoryRef, proposalInfo, traceability);

  const reviewOutcome = deriveReviewOutcome(pullRequest, reviews, proposalInfo);
  const syncedAt = utcNow();

  traceability.proposal_url = pullRequest.html_url || pullRequest.url || traceability.proposal_url || null;
  traceability.proposal_state = pullRequest.merged ? "merged" : pullRequest.state || traceability.proposal_state || "open";
  traceability.review = traceability.review || {};
  traceability.review.status = reviewOutcome.status;
  traceability.review.status_label = labelForReviewStatus(
    reviewOutcome.status,
    traceability.ci && traceability.ci.ci_status,
  );
  traceability.review.review_decision_ref = reviewOutcome.reviewDecisionRef;
  traceability.review.decision_outcome = reviewOutcome.decisionOutcome;
  traceability.review.reviewer_ref = reviewOutcome.reviewerRef;
  traceability.review.reviewer_login = reviewOutcome.reviewerLogin;
  traceability.review.review_synced_at = syncedAt;
  traceability.review.updated_at = reviewOutcome.decidedAt || syncedAt;
  traceability.review.proposal_body_sync_status = "pending";

  writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);

  try {
    const updatedPullRequest = await syncProposalBody(
      settings,
      repositoryRef,
      proposalInfo,
      traceability,
    );
    traceability.proposal_url = updatedPullRequest.html_url || updatedPullRequest.url || traceability.proposal_url || null;
    traceability.proposal_state =
      updatedPullRequest.merged ? "merged" : updatedPullRequest.state || traceability.proposal_state || "open";
    traceability.review.proposal_body_sync_status = "synced";
    traceability.review.proposal_body_synced_at = syncedAt;
    delete traceability.review.proposal_body_sync_error;
  } catch (error) {
    traceability.review.proposal_body_sync_status = "failed";
    traceability.review.proposal_body_sync_error = error.message;
    writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);
    throw error;
  }

  writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);

  return {
    status: "review-outcome-synced",
    task_request_id: traceability.task_request_id,
    proposal_ref: traceability.proposal_ref,
    review_status: traceability.review.status,
    review_decision_ref: traceability.review.review_decision_ref,
    reviewer_login: traceability.review.reviewer_login,
    traceability_metadata_ref: toRepoRelativePath(repoRoot, traceabilityPath),
    matched_session_ids: traceabilityTargets.matchedSessionIds,
    synced_copy_count: traceabilityTargets.syncPaths.length,
  };
}

async function syncProposalTraceability(repoRoot, statePaths, syncContext, snapshot = null) {
  const { traceabilityTargets, proposalRef } = syncContext;
  const traceabilityPath = traceabilityTargets.primaryPath;
  const traceability = readJson(traceabilityPath);

  if (traceability.proposal_ref && proposalRef && traceability.proposal_ref !== proposalRef) {
    throw new Error(
      `Traceability record proposal_ref '${traceability.proposal_ref}' did not match requested proposal '${proposalRef}'.`,
    );
  }

  mergeProposalTraceabilitySnapshot(traceability, snapshot);

  if (!traceability.proposal_ref) {
    if (!proposalRef) {
      throw new Error("Traceability record does not include proposal_ref.");
    }

    traceability.proposal_ref = proposalRef;
  }

  const proposalInfo = parseProposalRef(traceability.proposal_ref);
  const repositoryRef = `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}`;
  const settings = loadLocalGiteaSettings(repoRoot);
  const pullRequest = await getPullRequest(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    repositoryRef,
  );

  if (!pullRequest) {
    throw new Error(`Pull request '${traceability.proposal_ref}' was not found.`);
  }

  const ciNeedsEnrichment =
    !traceability.ci ||
    !traceability.ci.ci_status ||
    traceability.ci.ci_status === "pending" ||
    !traceability.ci.ci_run_ref;

  if (ciNeedsEnrichment) {
    await enrichTraceabilityCiFromActions(settings, repositoryRef, proposalInfo, traceability);
  } else {
    traceability.ci = traceability.ci || {};
    if (!traceability.ci.verification_metadata_path) {
      traceability.ci.verification_metadata_path = ".agent-sdlc/ci/verification-metadata.json";
    }
  }

  const syncedAt = utcNow();
  traceability.proposal_url = pullRequest.html_url || pullRequest.url || traceability.proposal_url || null;
  traceability.proposal_title = pullRequest.title || traceability.proposal_title || null;
  traceability.proposal_state = pullRequest.merged ? "merged" : pullRequest.state || traceability.proposal_state || "open";
  traceability.review = traceability.review || {};

  if (!hasExplicitReviewDecision(traceability.review)) {
    const derivedReviewStatus = deriveReviewStatus(
      (traceability.ci && traceability.ci.ci_status) || "pending",
    );
    traceability.review.status = derivedReviewStatus.id;
    traceability.review.status_label = derivedReviewStatus.label;
    traceability.review.updated_at =
      (traceability.ci && traceability.ci.completed_at) || syncedAt;
  }

  traceability.review.host_traceability_sync_at = syncedAt;
  writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);

  try {
    const updatedPullRequest = await syncProposalBody(
      settings,
      repositoryRef,
      proposalInfo,
      traceability,
    );
    traceability.proposal_url = updatedPullRequest.html_url || updatedPullRequest.url || traceability.proposal_url || null;
    traceability.proposal_state =
      updatedPullRequest.merged ? "merged" : updatedPullRequest.state || traceability.proposal_state || "open";
    traceability.review.proposal_body_sync_status = "synced";
    traceability.review.proposal_body_synced_at = syncedAt;
    delete traceability.review.proposal_body_sync_error;
  } catch (error) {
    traceability.review.proposal_body_sync_status = "failed";
    traceability.review.proposal_body_sync_error = error.message;
    writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);
    throw error;
  }

  writeTraceabilityCopies(traceabilityTargets.syncPaths, traceability);

  return {
    status: "proposal-traceability-synced",
    task_request_id: traceability.task_request_id,
    proposal_ref: traceability.proposal_ref,
    ci_status: traceability.ci && traceability.ci.ci_status,
    review_status: traceability.review && traceability.review.status,
    traceability_metadata_ref: toRepoRelativePath(repoRoot, traceabilityPath),
    matched_session_ids: traceabilityTargets.matchedSessionIds,
    synced_copy_count: traceabilityTargets.syncPaths.length,
  };
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
    const isReviewWebhook = request.method === "POST" && request.url === options.route;
    const isCiTraceabilitySync = request.method === "POST" && request.url === DEFAULT_CI_TRACEABILITY_SYNC_ROUTE;

    if (!isReviewWebhook && !isCiTraceabilitySync) {
      writeJsonResponse(response, request.method === "POST" ? 404 : 405, {
        status: "rejected",
        message: "Only POST requests to the configured review routes are supported.",
      });
      return;
    }

    const chunks = [];
    request.on("data", (chunk) => {
      chunks.push(chunk);
    });

    request.on("end", () => {
      void (async () => {
        try {
          const rawText = Buffer.concat(chunks).toString("utf8");
          const payload = JSON.parse(rawText);
          if (isCiTraceabilitySync) {
            if (!payload.proposal_ref) {
              writeJsonResponse(response, 400, {
                status: "rejected",
                message: "CI traceability sync payload must include 'proposal_ref'.",
              });
              return;
            }

            const syncContext = resolveSyncContextByProposalRef(repoRoot, statePaths, payload.proposal_ref);
            const syncResult = await syncProposalTraceability(repoRoot, statePaths, syncContext, payload);
            writeJsonResponse(response, 202, syncResult);
            return;
          }

          const envelope = buildNormalizedEnvelope({
            rawText,
            payload,
            headers: request.headers,
          });
          const resolution = resolveSyncContextByEvent(repoRoot, statePaths, envelope);

          if (resolution.status !== "accepted") {
            writeJsonResponse(response, 202, resolution);
            return;
          }

          const syncResult = await syncReviewOutcome(repoRoot, statePaths, resolution.syncContext);
          writeJsonResponse(response, 202, {
            ...syncResult,
            source_event_type: resolution.syncContext.eventType,
            source_event_action: resolution.syncContext.eventAction,
            source_event_id: resolution.syncContext.deliveryId,
          });
        } catch (error) {
          writeJsonResponse(response, 500, {
            status: "error",
            message: error.message,
          });
        }
      })();
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
        },
        null,
        2,
      ),
    );
  });
}

async function handleSyncFromEvent(repoRoot, statePaths, eventPath) {
  const envelope = normalizeEventEnvelopeFromFile(eventPath);
  const resolution = resolveSyncContextByEvent(repoRoot, statePaths, envelope);
  if (resolution.status !== "accepted") {
    return resolution;
  }

  const syncResult = await syncReviewOutcome(repoRoot, statePaths, resolution.syncContext);
  return {
    ...syncResult,
    source_event_type: resolution.syncContext.eventType,
    source_event_action: resolution.syncContext.eventAction,
    source_event_id: resolution.syncContext.deliveryId,
  };
}

async function main() {
  const repoRoot = getRepoRoot();
  const statePaths = ensureProjectState(repoRoot);
  const options = parseArguments(process.argv);

  if (options.command === "sync-gitea-pr-review-outcome") {
    const syncContext = options.sessionRecordPath
      ? resolveSyncContextBySession(repoRoot, statePaths, options.sessionRecordPath)
      : resolveSyncContextByProposalRef(repoRoot, statePaths, options.proposalRef);
    const result = await syncReviewOutcome(repoRoot, statePaths, syncContext);
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  if (options.command === "sync-gitea-proposal-traceability") {
    const syncContext = options.sessionRecordPath
      ? resolveSyncContextBySession(repoRoot, statePaths, options.sessionRecordPath)
      : resolveSyncContextByProposalRef(repoRoot, statePaths, options.proposalRef);
    const result = await syncProposalTraceability(repoRoot, statePaths, syncContext);
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  if (options.command === "sync-gitea-pr-review-event") {
    const result = await handleSyncFromEvent(repoRoot, statePaths, options.eventPath);
    console.log(JSON.stringify(result, null, 2));
    process.exit(result.status === "ignored" ? 2 : 0);
    return;
  }

  if (options.command === "serve-configured-gitea-review-webhook") {
    startWebhookServer(repoRoot, resolveConfiguredReviewWebhookOptions(repoRoot));
    return;
  }

  if (options.command === "serve-gitea-review-webhook") {
    startWebhookServer(repoRoot, options);
    return;
  }

  printUsage();
  process.exit(1);
}

main().catch((error) => {
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
});
