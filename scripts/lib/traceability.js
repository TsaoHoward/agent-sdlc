function deriveReviewStatus(ciStatus) {
  switch (ciStatus) {
    case "success":
      return {
        id: "ready-for-human-review",
        label: "ready for human review",
      };
    case "failure":
      return {
        id: "blocked-on-ci",
        label: "blocked on failing CI",
      };
    case "cancelled":
      return {
        id: "ci-cancelled",
        label: "CI cancelled before review",
      };
    case "pending":
    default:
      return {
        id: "awaiting-ci",
        label: "awaiting CI and human review",
      };
  }
}

function labelForReviewStatus(status, ciStatus = "pending") {
  switch (status) {
    case "approved":
      return "approved by reviewer";
    case "changes-requested":
      return "changes requested";
    case "merged":
      return "merged";
    case "closed-without-merge":
      return "closed without merge";
    case "awaiting-review-decision":
      return "awaiting human review decision";
    case "ready-for-human-review":
    case "blocked-on-ci":
    case "ci-cancelled":
    case "awaiting-ci":
      return deriveReviewStatus(ciStatus).label;
    default:
      return deriveReviewStatus(ciStatus).label;
  }
}

function formatCiDisplay(ci = {}) {
  const ciStatus = ci.ci_status || "pending";
  const ciRunRef = ci.ci_run_ref || null;
  const ciRunUrl = ci.ci_run_url || null;

  if (ciRunUrl && ciRunRef) {
    return `\`${ciStatus}\` ([run ${ciRunRef}](${ciRunUrl}))`;
  }

  if (ciRunUrl) {
    return `\`${ciStatus}\` ([run link](${ciRunUrl}))`;
  }

  if (ciRunRef) {
    return `\`${ciStatus}\` (\`${ciRunRef}\`)`;
  }

  return `\`${ciStatus}\``;
}

function buildTraceabilityBlock(details) {
  const sourceRef =
    details.source_ref ||
    details.issue_ref ||
    details.pull_request_ref ||
    details.comment_ref ||
    "n/a";
  const ci = details.ci || {};
  const review = details.review || {};
  const reviewStatus = details.review_status || labelForReviewStatus(review.status, ci.ci_status);
  const lines = [
    "## Agent Traceability",
    `- Task Request: \`${details.task_request_id}\``,
    `- Agent Session: \`${details.agent_session_id}\``,
    `- Source: \`${sourceRef}\``,
    `- Execution Profile: \`${details.execution_profile_id}\``,
    `- Runtime Capability Set: \`${details.runtime_capability_set_id}\``,
    `- Metadata: \`${details.metadata_path}\``,
  ];

  if (details.verification_metadata_path) {
    lines.push(`- Verification Metadata: \`${details.verification_metadata_path}\``);
  }

  lines.push(`- CI: ${formatCiDisplay(ci)}`);
  lines.push(`- Review Status: ${reviewStatus}`);

  if (review.decision_outcome) {
    lines.push(`- Review Decision: \`${review.decision_outcome}\``);
  }

  if (review.reviewer_login || review.reviewer_ref) {
    lines.push(`- Reviewer: \`${review.reviewer_login || review.reviewer_ref}\``);
  }

  return lines.join("\n");
}

function replaceTraceabilityBlock(body, newBlock) {
  const normalizedBody = String(body || "").trimEnd();
  const traceabilityPattern = /## Agent Traceability[\s\S]*?(?=(?:\r?\n## )|$)/u;

  if (traceabilityPattern.test(normalizedBody)) {
    return `${normalizedBody.replace(traceabilityPattern, newBlock).trimEnd()}\n`;
  }

  if (normalizedBody) {
    return `${newBlock}\n\n${normalizedBody}\n`;
  }

  return `${newBlock}\n`;
}

module.exports = {
  buildTraceabilityBlock,
  deriveReviewStatus,
  labelForReviewStatus,
  replaceTraceabilityBlock,
};
