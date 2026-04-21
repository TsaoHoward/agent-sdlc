const fs = require("fs");
const path = require("path");

const {
  getPullRequest,
  loadLocalGiteaSettings,
  parseGiteaRepositoryRef,
  updatePullRequest,
} = require("../lib/gitea-client");
const {
  buildTraceabilityBlock,
  deriveReviewStatus,
  replaceTraceabilityBlock,
} = require("../lib/traceability");
const { applyProposalContext, resolveProposalContext } = require("./lib/proposal-context");

function getRepoRoot() {
  return path.resolve(__dirname, "..", "..");
}

function utcNow() {
  return new Date().toISOString();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function findTraceabilityFiles(repoRoot) {
  const traceabilityDir = path.join(repoRoot, ".agent-sdlc", "traceability");
  if (!fs.existsSync(traceabilityDir)) {
    throw new Error("Traceability directory '.agent-sdlc/traceability' was not found in the checked-out proposal branch.");
  }

  return fs
    .readdirSync(traceabilityDir)
    .filter((entry) => entry.endsWith(".json"))
    .map((entry) => path.join(traceabilityDir, entry));
}

function getVerificationMetadataPath(repoRoot) {
  return path.join(repoRoot, ".agent-sdlc", "ci", "verification-metadata.json");
}

function buildCiRunRef() {
  return (
    process.env.GITHUB_RUN_ID ||
    process.env.GITEA_RUN_ID ||
    process.env.GITHUB_RUN_NUMBER ||
    process.env.GITEA_RUN_NUMBER ||
    null
  );
}

function buildCiRunUrl() {
  if (process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID) {
    return `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`;
  }

  if (process.env.GITEA_SERVER_URL && process.env.GITEA_RUN_ID) {
    return `${process.env.GITEA_SERVER_URL}/actions/runs/${process.env.GITEA_RUN_ID}`;
  }

  return null;
}

function describeError(error) {
  if (!error) {
    return "Unknown error.";
  }

  if (typeof error.message === "string" && error.message.trim() !== "") {
    return error.message;
  }

  if (typeof error.code === "string" && error.code.trim() !== "") {
    return `Request failed with code '${error.code}'.`;
  }

  if (typeof error.errno === "number") {
    return `Request failed with errno ${error.errno}.`;
  }

  if (typeof error === "string" && error.trim() !== "") {
    return error;
  }

  try {
    const serialized = JSON.stringify(error);
    if (serialized && serialized !== "{}") {
      return serialized;
    }
  } catch (serializationError) {
    return `Unknown error (${serializationError.message}).`;
  }

  return "Unknown error.";
}

function collectRequiredStepOutcomes() {
  const configuredSteps = [
    ["validate_platform", process.env.AGENT_SDLC_VALIDATE_PLATFORM_OUTCOME],
    ["typecheck", process.env.AGENT_SDLC_TYPECHECK_OUTCOME],
  ];

  return configuredSteps
    .filter(([, outcome]) => outcome)
    .map(([stepId, outcome]) => ({
      step_id: stepId,
      outcome,
    }));
}

function resolveCiStatus(stepOutcomes) {
  if (stepOutcomes.some((step) => step.outcome === "cancelled")) {
    return "cancelled";
  }

  if (stepOutcomes.some((step) => step.outcome !== "success")) {
    return "failure";
  }

  return "success";
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

async function syncProposalBody(traceability, verificationMetadata, reviewStatusLabel) {
  const proposalInfo = parseProposalRef(traceability.proposal_ref);
  const settings = loadLocalGiteaSettings(getRepoRoot());
  const repositoryRef = `gitea:${proposalInfo.host}/${proposalInfo.owner}/${proposalInfo.repo}`;
  const currentPullRequest = await getPullRequest(
    settings,
    proposalInfo.owner,
    proposalInfo.repo,
    proposalInfo.index,
    repositoryRef,
  );

  if (!currentPullRequest) {
    throw new Error(`Pull request '${traceability.proposal_ref}' was not found for traceability sync.`);
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
        verificationMetadata.verification_metadata_path ||
        (traceability.ci && traceability.ci.verification_metadata_path) ||
        ".agent-sdlc/ci/verification-metadata.json",
      ci: traceability.ci,
      review_status: reviewStatusLabel,
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
  const traceabilityFiles = findTraceabilityFiles(repoRoot);
  if (traceabilityFiles.length !== 1) {
    throw new Error(
      `Expected exactly one traceability file in '.agent-sdlc/traceability', but found ${traceabilityFiles.length}.`,
    );
  }

  const verificationMetadataPath = getVerificationMetadataPath(repoRoot);
  if (!fs.existsSync(verificationMetadataPath)) {
    throw new Error("Verification metadata file '.agent-sdlc/ci/verification-metadata.json' was not found.");
  }

  const traceabilityPath = traceabilityFiles[0];
  const traceability = readJson(traceabilityPath);
  const proposalContext = await resolveProposalContext(repoRoot, traceability);
  applyProposalContext(traceability, proposalContext);
  if (!traceability.proposal_ref) {
    throw new Error(
      "Traceability record does not include proposal_ref, and CI could not resolve one from the current workflow context.",
    );
  }
  const verificationMetadata = readJson(verificationMetadataPath);
  const stepOutcomes = collectRequiredStepOutcomes();
  const ciStatus = resolveCiStatus(stepOutcomes);
  const ciRunRef = buildCiRunRef();
  const ciRunUrl = buildCiRunUrl();
  const reviewStatus = deriveReviewStatus(ciStatus);
  const finalizedAt = utcNow();

  traceability.ci = traceability.ci || {};
  traceability.ci.ci_status = ciStatus;
  traceability.ci.ci_run_ref = ciRunRef;
  traceability.ci.ci_run_url = ciRunUrl;
  traceability.ci.workflow_ref = process.env.GITHUB_WORKFLOW || process.env.GITEA_WORKFLOW || traceability.ci.workflow_ref || null;
  traceability.ci.workflow_run_id = process.env.GITHUB_RUN_ID || process.env.GITEA_RUN_ID || traceability.ci.workflow_run_id || null;
  traceability.ci.workflow_run_number =
    process.env.GITHUB_RUN_NUMBER || process.env.GITEA_RUN_NUMBER || traceability.ci.workflow_run_number || null;
  traceability.ci.verification_metadata_path =
    verificationMetadata.verification_metadata_path ||
    traceability.ci.verification_metadata_path ||
    ".agent-sdlc/ci/verification-metadata.json";
  traceability.ci.completed_at = finalizedAt;
  traceability.review = traceability.review || {};
  traceability.review.status = reviewStatus.id;
  traceability.review.updated_at = finalizedAt;
  traceability.review.proposal_body_sync_status = "pending";

  verificationMetadata.ci_status = ciStatus;
  verificationMetadata.ci_run_ref = ciRunRef;
  verificationMetadata.ci_run_url = ciRunUrl;
  verificationMetadata.proposal_ref = traceability.proposal_ref;
  verificationMetadata.proposal_url = traceability.proposal_url || verificationMetadata.proposal_url || null;
  verificationMetadata.proposal_title =
    traceability.proposal_title || verificationMetadata.proposal_title || null;
  verificationMetadata.completed_at = finalizedAt;
  verificationMetadata.review_status = reviewStatus.id;
  verificationMetadata.required_step_outcomes = stepOutcomes;
  verificationMetadata.review_surface_sync_status = "pending";

  writeJson(traceabilityPath, traceability);
  writeJson(verificationMetadataPath, verificationMetadata);

  try {
    const updatedPullRequest = await syncProposalBody(traceability, verificationMetadata, reviewStatus.label);
    traceability.proposal_url = updatedPullRequest.html_url || updatedPullRequest.url || traceability.proposal_url || null;
    traceability.proposal_state = updatedPullRequest.state || traceability.proposal_state || "open";
    traceability.review.proposal_body_sync_status = "synced";
    traceability.review.proposal_body_synced_at = finalizedAt;
    delete traceability.review.proposal_body_sync_error;

    verificationMetadata.proposal_url =
      updatedPullRequest.html_url || updatedPullRequest.url || verificationMetadata.proposal_url || null;
    verificationMetadata.review_surface_sync_status = "synced";
    verificationMetadata.review_surface_synced_at = finalizedAt;
    delete verificationMetadata.review_surface_sync_error;
  } catch (error) {
    traceability.review.proposal_body_sync_status = "failed";
    traceability.review.proposal_body_sync_error = describeError(error);
    verificationMetadata.review_surface_sync_status = "failed";
    verificationMetadata.review_surface_sync_error = describeError(error);
    writeJson(traceabilityPath, traceability);
    writeJson(verificationMetadataPath, verificationMetadata);
    throw error;
  }

  writeJson(traceabilityPath, traceability);
  writeJson(verificationMetadataPath, verificationMetadata);

  console.log(
    JSON.stringify(
      {
        status: ciStatus,
        task_request_id: traceability.task_request_id,
        proposal_ref: traceability.proposal_ref,
        ci_run_ref: ciRunRef,
        review_status: reviewStatus.id,
        verification_metadata_path: verificationMetadata.verification_metadata_path,
      },
      null,
      2,
    ),
  );

  if (ciStatus !== "success") {
    process.exit(1);
  }
}

main().catch((error) => {
  console.log(
    JSON.stringify(
      {
        status: "error",
        message: describeError(error),
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
