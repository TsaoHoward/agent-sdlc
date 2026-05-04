const fs = require("fs");
const path = require("path");
const { deriveReviewStatus } = require("../lib/traceability");
const { applyProposalContext, resolveProposalContext } = require("./lib/proposal-context");

function getRepoRoot() {
  return path.resolve(__dirname, "..", "..");
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

async function main() {
  const repoRoot = getRepoRoot();
  const traceabilityFiles = findTraceabilityFiles(repoRoot);

  if (traceabilityFiles.length !== 1) {
    throw new Error(
      `Expected exactly one traceability file in '.agent-sdlc/traceability', but found ${traceabilityFiles.length}.`,
    );
  }

  const traceabilityPath = traceabilityFiles[0];
  const traceability = readJson(traceabilityPath);
  const proposalContext = await resolveProposalContext(repoRoot, traceability);
  applyProposalContext(traceability, proposalContext);
  const ciRunRef = buildCiRunRef();
  const ciRunUrl = buildCiRunUrl();

  traceability.ci = traceability.ci || {};
  traceability.ci.ci_run_ref = ciRunRef;
  traceability.ci.ci_run_url = ciRunUrl;
  traceability.ci.workflow_ref = process.env.GITHUB_WORKFLOW || process.env.GITEA_WORKFLOW || traceability.ci.workflow_ref || null;
  traceability.ci.workflow_run_id = process.env.GITHUB_RUN_ID || process.env.GITEA_RUN_ID || traceability.ci.workflow_run_id || null;
  traceability.ci.workflow_run_number = process.env.GITHUB_RUN_NUMBER || process.env.GITEA_RUN_NUMBER || traceability.ci.workflow_run_number || null;
  traceability.ci.ci_status = "pending";
  traceability.ci.verification_metadata_path =
    traceability.ci.verification_metadata_path || ".agent-sdlc/ci/verification-metadata.json";
  traceability.review = traceability.review || {};
  traceability.review.status = deriveReviewStatus("pending").id;
  traceability.review.proposal_body_sync_status =
    traceability.review.proposal_body_sync_status || "pending";

  writeJson(traceabilityPath, traceability);
  console.log(JSON.stringify(traceability, null, 2));
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
