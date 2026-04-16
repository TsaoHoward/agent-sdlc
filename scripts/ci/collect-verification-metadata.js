const fs = require("fs");
const path = require("path");

function getRepoRoot() {
  return path.resolve(__dirname, "..", "..");
}

function utcNow() {
  return new Date().toISOString();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensureDirectory(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
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

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function setGithubOutput(name, value) {
  if (!process.env.GITHUB_OUTPUT) {
    return;
  }

  fs.appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`, "utf8");
}

function appendStepSummary(metadata) {
  if (!process.env.GITHUB_STEP_SUMMARY) {
    return;
  }

  const lines = [
    "## Verification Traceability",
    `- Task Request: \`${metadata.task_request_id}\``,
    `- Proposal Ref: \`${metadata.proposal_ref}\``,
    `- Proposal URL: ${metadata.proposal_url || "n/a"}`,
    `- CI Run: \`${metadata.ci_run_ref || "n/a"}\``,
    `- Source Event: \`${metadata.source_event_id}\``,
    `- Verification Metadata: \`${metadata.verification_metadata_path}\``,
  ];

  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`, "utf8");
}

function main() {
  const repoRoot = getRepoRoot();
  const traceabilityFiles = findTraceabilityFiles(repoRoot);

  if (traceabilityFiles.length !== 1) {
    throw new Error(
      `Expected exactly one traceability file in '.agent-sdlc/traceability', but found ${traceabilityFiles.length}.`,
    );
  }

  const traceability = readJson(traceabilityFiles[0]);
  const outputDir = path.join(repoRoot, ".agent-sdlc", "ci");
  ensureDirectory(outputDir);

  const eventPayloadPath = process.env.GITHUB_EVENT_PATH || process.env.GITEA_EVENT_PATH || null;
  const verificationMetadataPath = path.join(outputDir, "verification-metadata.json");
  const ciRunRef = process.env.GITHUB_RUN_ID || process.env.GITEA_RUN_ID || process.env.GITHUB_RUN_NUMBER || process.env.GITEA_RUN_NUMBER || null;
  const ciRunUrl = process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null;
  const verificationMetadata = {
    verification_version: 1,
    created_at: utcNow(),
    task_request_id: traceability.task_request_id,
    agent_session_id: traceability.agent_session_id,
    proposal_ref: traceability.proposal_ref,
    proposal_url: traceability.proposal_url || null,
    proposal_title: traceability.proposal_title || null,
    repository_ref: traceability.repository_ref,
    branch_ref: traceability.branch_ref,
    execution_profile_id: traceability.execution_profile_id,
    runtime_capability_set_id: traceability.runtime_capability_set_id,
    source_event_id: traceability.source_event_id,
    source_event_type: traceability.source_event_type,
    traceability_metadata_path: ".agent-sdlc/traceability/" + path.basename(traceabilityFiles[0]),
    verification_metadata_path: ".agent-sdlc/ci/verification-metadata.json",
    workflow_ref: process.env.GITHUB_WORKFLOW || process.env.GITEA_WORKFLOW || "phase1-ci",
    workflow_run_number: process.env.GITHUB_RUN_NUMBER || process.env.GITEA_RUN_NUMBER || null,
    workflow_run_id: process.env.GITHUB_RUN_ID || process.env.GITEA_RUN_ID || null,
    ci_run_ref: ciRunRef,
    ci_run_url: ciRunUrl,
    event_name: process.env.GITHUB_EVENT_NAME || process.env.GITEA_EVENT_NAME || null,
    event_payload_path: eventPayloadPath,
    ci_status: "pending",
  };

  writeJson(verificationMetadataPath, verificationMetadata);
  setGithubOutput("task_request_id", verificationMetadata.task_request_id);
  setGithubOutput("proposal_ref", verificationMetadata.proposal_ref);
  setGithubOutput("verification_metadata_path", verificationMetadata.verification_metadata_path);
  appendStepSummary(verificationMetadata);

  console.log(JSON.stringify(verificationMetadata, null, 2));
}

try {
  main();
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
