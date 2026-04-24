const fs = require("fs");
const path = require("path");

function parseHostFromUrl(urlValue) {
  if (!urlValue) {
    return null;
  }

  try {
    return new URL(urlValue).host;
  } catch {
    return null;
  }
}

function normalizeNullableString(value) {
  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value !== "string") {
    return value;
  }

  const normalized = value.trim();
  if (!normalized) {
    return null;
  }

  if (["null", "undefined"].includes(normalized.toLowerCase())) {
    return null;
  }

  return normalized;
}

function isSupportedProposalRef(proposalRef) {
  return /^gitea:[^/]+\/[^/]+\/[^#]+#pull\/\d+$/u.test(String(proposalRef || ""));
}

function readEventPayload() {
  const eventPayloadPath = process.env.GITHUB_EVENT_PATH || process.env.GITEA_EVENT_PATH || null;
  if (!eventPayloadPath) {
    return null;
  }

  const absolutePath = path.resolve(eventPayloadPath);
  if (!fs.existsSync(absolutePath)) {
    return null;
  }

  const rawText = fs.readFileSync(absolutePath, "utf8").replace(/^\uFEFF/u, "");
  return JSON.parse(rawText);
}

function buildProposalRef(host, fullName, index) {
  if (!host || !fullName || !index) {
    return null;
  }

  return `gitea:${host}/${fullName}#pull/${index}`;
}

function buildProposalContextFromPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  const pullRequest = payload.pull_request || payload.pullRequest || null;
  const repository = payload.repository || null;
  const repositoryFullName =
    (repository && repository.full_name) || process.env.GITHUB_REPOSITORY || null;
  const proposalIndex =
    (pullRequest && (pullRequest.number || pullRequest.index)) || payload.number || null;
  const host =
    parseHostFromUrl(repository && (repository.html_url || repository.clone_url || repository.ssh_url)) ||
    parseHostFromUrl(pullRequest && pullRequest.html_url) ||
    parseHostFromUrl(process.env.GITHUB_SERVER_URL || process.env.GITEA_SERVER_URL || null);

  const proposalRef = buildProposalRef(host, repositoryFullName, proposalIndex);
  if (!proposalRef) {
    return null;
  }

  return {
    proposalRef: normalizeNullableString(proposalRef),
    proposalUrl: normalizeNullableString(
      (pullRequest && (pullRequest.html_url || pullRequest.url)) ||
        (repository &&
          repository.html_url &&
          `${repository.html_url.replace(/\/$/u, "")}/pulls/${proposalIndex}`) ||
        null,
    ),
    proposalTitle: normalizeNullableString((pullRequest && pullRequest.title) || null),
    proposalState: normalizeNullableString((pullRequest && pullRequest.state) || "open"),
    source: "event-payload",
  };
}

async function resolveProposalContext(_repoRoot, traceability) {
  const traceabilityProposalRef = normalizeNullableString(traceability.proposal_ref);
  if (traceabilityProposalRef && isSupportedProposalRef(traceabilityProposalRef)) {
    return {
      proposalRef: traceabilityProposalRef,
      proposalUrl: normalizeNullableString(traceability.proposal_url || null),
      proposalTitle: normalizeNullableString(traceability.proposal_title || null),
      proposalState: normalizeNullableString(traceability.proposal_state || "open"),
      source: "traceability",
    };
  }

  const payloadContext = buildProposalContextFromPayload(readEventPayload());
  if (payloadContext && payloadContext.proposalRef && isSupportedProposalRef(payloadContext.proposalRef)) {
    return payloadContext;
  }

  return {
    proposalRef: null,
    proposalUrl: normalizeNullableString(traceability.proposal_url || null),
    proposalTitle: normalizeNullableString(traceability.proposal_title || null),
    proposalState: normalizeNullableString(traceability.proposal_state || "open"),
    source: "unresolved",
  };
}

function applyProposalContext(traceability, proposalContext) {
  if (!proposalContext) {
    return false;
  }

  let changed = false;
  const fieldMap = [
    ["proposal_ref", proposalContext.proposalRef],
    ["proposal_url", proposalContext.proposalUrl],
    ["proposal_title", proposalContext.proposalTitle],
    ["proposal_state", proposalContext.proposalState || "open"],
  ];

  fieldMap.forEach(([field, nextValue]) => {
    if (nextValue !== undefined && nextValue !== null && traceability[field] !== nextValue) {
      traceability[field] = nextValue;
      changed = true;
    }
  });

  return changed;
}

module.exports = {
  applyProposalContext,
  resolveProposalContext,
};
