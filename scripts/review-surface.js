const fs = require("fs");
const path = require("path");

const {
  getPullRequest,
  listPullReviews,
  loadLocalGiteaSettings,
  updatePullRequest,
} = require("./lib/gitea-client");
const { ensureProjectState, getRepoRoot, toRepoRelativePath, writeJson } = require("./lib/project-state");
const { buildTraceabilityBlock, labelForReviewStatus, replaceTraceabilityBlock } = require("./lib/traceability");

function printUsage() {
  console.error(
    "Usage: node scripts/review-surface.js sync-gitea-pr-review-outcome --session <agent-session-json-path>",
  );
}

function parseArguments(argv) {
  if (
    argv.length !== 5 ||
    argv[2] !== "sync-gitea-pr-review-outcome" ||
    argv[3] !== "--session" ||
    !argv[4]
  ) {
    printUsage();
    process.exit(1);
  }

  return {
    sessionRecordPath: path.resolve(argv[4]),
  };
}

function utcNow() {
  return new Date().toISOString();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
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

function resolveTraceabilityTargets(repoRoot, statePaths, sessionRecord) {
  const stateTraceabilityPath =
    sessionRecord.task_request_id &&
    path.join(statePaths.traceabilityDir, `${sessionRecord.task_request_id}.json`);
  const sessionTraceabilityPath =
    sessionRecord.traceability_metadata_ref &&
    path.join(repoRoot, sessionRecord.traceability_metadata_ref);

  const syncPaths = [stateTraceabilityPath, sessionTraceabilityPath].filter((candidate, index, values) => {
    return candidate && fs.existsSync(candidate) && values.indexOf(candidate) === index;
  });

  if (syncPaths.length === 0) {
    throw new Error("Traceability metadata file was not found for the provided session record.");
  }

  return {
    primaryPath:
      stateTraceabilityPath && fs.existsSync(stateTraceabilityPath)
        ? stateTraceabilityPath
        : sessionTraceabilityPath,
    syncPaths,
  };
}

function writeTraceabilityCopies(filePaths, value) {
  filePaths.forEach((filePath) => {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    writeJson(filePath, value);
  });
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

async function main() {
  const repoRoot = getRepoRoot();
  const statePaths = ensureProjectState(repoRoot);
  const { sessionRecordPath } = parseArguments(process.argv);
  const sessionRecord = readJson(sessionRecordPath);
  const traceabilityTargets = resolveTraceabilityTargets(repoRoot, statePaths, sessionRecord);
  const traceabilityPath = traceabilityTargets.primaryPath;
  const traceability = readJson(traceabilityPath);

  if (!traceability.proposal_ref) {
    throw new Error("Traceability record does not include proposal_ref.");
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

  console.log(
    JSON.stringify(
      {
        status: "review-outcome-synced",
        task_request_id: traceability.task_request_id,
        proposal_ref: traceability.proposal_ref,
        review_status: traceability.review.status,
        review_decision_ref: traceability.review.review_decision_ref,
        reviewer_login: traceability.review.reviewer_login,
        traceability_metadata_ref: toRepoRelativePath(repoRoot, traceabilityPath),
      },
      null,
      2,
    ),
  );
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
