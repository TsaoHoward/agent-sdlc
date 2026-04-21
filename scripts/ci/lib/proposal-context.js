const fs = require("fs");
const path = require("path");

const {
  listPullRequests,
  loadLocalGiteaSettings,
  parseGiteaRepositoryRef,
} = require("../../lib/gitea-client");

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
    proposalRef,
    proposalUrl:
      (pullRequest && (pullRequest.html_url || pullRequest.url)) ||
      (repository && repository.html_url && `${repository.html_url.replace(/\/$/u, "")}/pulls/${proposalIndex}`) ||
      null,
    proposalTitle: (pullRequest && pullRequest.title) || null,
    proposalState: (pullRequest && pullRequest.state) || "open",
    source: "event-payload",
  };
}

function findPullRequestByBranch(pullRequests, owner, branchName) {
  return (pullRequests || []).find((pullRequest) => {
    const headRef = pullRequest.head && pullRequest.head.ref;
    const headLabel = pullRequest.head && pullRequest.head.label;
    return headRef === branchName || headLabel === `${owner}:${branchName}`;
  });
}

async function buildProposalContextFromBranch(repoRoot, traceability) {
  if (!traceability.repository_ref || !traceability.branch_ref) {
    return null;
  }

  const settings = loadLocalGiteaSettings(repoRoot);
  const repositoryInfo = parseGiteaRepositoryRef(traceability.repository_ref);
  const pullRequests = await listPullRequests(
    settings,
    repositoryInfo.owner,
    repositoryInfo.repo,
    traceability.repository_ref,
  );
  const pullRequest = findPullRequestByBranch(
    pullRequests,
    repositoryInfo.owner,
    traceability.branch_ref,
  );

  if (!pullRequest) {
    return null;
  }

  const proposalIndex = pullRequest.number || pullRequest.index;
  return {
    proposalRef: buildProposalRef(
      repositoryInfo.host,
      `${repositoryInfo.owner}/${repositoryInfo.repo}`,
      proposalIndex,
    ),
    proposalUrl: pullRequest.html_url || pullRequest.url || null,
    proposalTitle: pullRequest.title || null,
    proposalState: pullRequest.state || "open",
    source: "branch-lookup",
  };
}

async function resolveProposalContext(repoRoot, traceability) {
  if (traceability.proposal_ref) {
    return {
      proposalRef: traceability.proposal_ref,
      proposalUrl: traceability.proposal_url || null,
      proposalTitle: traceability.proposal_title || null,
      proposalState: traceability.proposal_state || "open",
      source: "traceability",
    };
  }

  const payloadContext = buildProposalContextFromPayload(readEventPayload());
  if (payloadContext) {
    return payloadContext;
  }

  return buildProposalContextFromBranch(repoRoot, traceability);
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

  for (const [field, nextValue] of fieldMap) {
    if (nextValue !== undefined && traceability[field] !== nextValue) {
      traceability[field] = nextValue;
      changed = true;
    }
  }

  return changed;
}

module.exports = {
  applyProposalContext,
  resolveProposalContext,
};
