const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");

const { applyProposalContext, resolveProposalContext } = require("./lib/proposal-context");

const DEFAULT_SYNC_URL = "http://127.0.0.1:4011/hooks/internal/ci-traceability";

function getRepoRoot() {
  return path.resolve(__dirname, "..", "..");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
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

function postJson(urlValue, body) {
  const requestUrl = new URL(urlValue);
  const payload = JSON.stringify(body);
  const transport = requestUrl.protocol === "https:" ? https : http;

  return new Promise((resolve, reject) => {
    const request = transport.request(
      requestUrl,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "content-length": Buffer.byteLength(payload),
        },
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => {
          chunks.push(chunk);
        });
        response.on("end", () => {
          const rawText = Buffer.concat(chunks).toString("utf8");
          const parsedBody = rawText.trim() ? JSON.parse(rawText) : null;

          if (response.statusCode < 200 || response.statusCode >= 300) {
            const error = new Error(
              `Host traceability sync request failed (${response.statusCode}) for ${requestUrl.pathname}.`,
            );
            error.statusCode = response.statusCode;
            error.responseBody = parsedBody;
            reject(error);
            return;
          }

          resolve(parsedBody);
        });
      },
    );

    request.on("error", (error) => {
      reject(error);
    });

    request.write(payload);
    request.end();
  });
}

async function main() {
  const repoRoot = getRepoRoot();
  const traceabilityFiles = findTraceabilityFiles(repoRoot);
  if (traceabilityFiles.length !== 1) {
    throw new Error(
      `Expected exactly one traceability file in '.agent-sdlc/traceability', but found ${traceabilityFiles.length}.`,
    );
  }

  const traceability = readJson(traceabilityFiles[0]);
  const proposalContext = await resolveProposalContext(repoRoot, traceability);
  applyProposalContext(traceability, proposalContext);

  if (!traceability.proposal_ref) {
    throw new Error("Traceability record does not include proposal_ref.");
  }

  const verificationMetadataPath = getVerificationMetadataPath(repoRoot);
  const verificationMetadata = fs.existsSync(verificationMetadataPath)
    ? readJson(verificationMetadataPath)
    : {};

  const payload = {
    proposal_ref: traceability.proposal_ref,
    proposal_url: traceability.proposal_url || verificationMetadata.proposal_url || null,
    proposal_title: traceability.proposal_title || verificationMetadata.proposal_title || null,
    proposal_state: traceability.proposal_state || "open",
    ci: {
      ci_status: firstDefined(
        verificationMetadata.ci_status,
        traceability.ci && traceability.ci.ci_status,
        "pending",
      ),
      ci_run_ref: firstDefined(
        verificationMetadata.ci_run_ref,
        traceability.ci && traceability.ci.ci_run_ref,
        null,
      ),
      ci_run_url: firstDefined(
        verificationMetadata.ci_run_url,
        traceability.ci && traceability.ci.ci_run_url,
        null,
      ),
      workflow_ref: firstDefined(
        verificationMetadata.workflow_ref,
        traceability.ci && traceability.ci.workflow_ref,
        null,
      ),
      workflow_run_id: firstDefined(
        verificationMetadata.workflow_run_id,
        traceability.ci && traceability.ci.workflow_run_id,
        null,
      ),
      workflow_run_number: firstDefined(
        verificationMetadata.workflow_run_number,
        traceability.ci && traceability.ci.workflow_run_number,
        null,
      ),
      verification_metadata_path: firstDefined(
        verificationMetadata.verification_metadata_path,
        traceability.ci && traceability.ci.verification_metadata_path,
        ".agent-sdlc/ci/verification-metadata.json",
      ),
      completed_at: firstDefined(
        verificationMetadata.completed_at,
        traceability.ci && traceability.ci.completed_at,
        null,
      ),
    },
  };

  const syncUrl = process.env.AGENT_SDLC_HOST_TRACEABILITY_SYNC_URL || DEFAULT_SYNC_URL;
  const responseBody = await postJson(syncUrl, payload);
  console.log(JSON.stringify(responseBody, null, 2));
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null && value !== "");
}

main().catch((error) => {
  console.log(
    JSON.stringify(
      {
        status: "error",
        message: error.message,
        response_body: error.responseBody || null,
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
