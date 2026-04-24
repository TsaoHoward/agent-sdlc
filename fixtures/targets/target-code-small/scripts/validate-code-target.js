const fs = require("fs");
const path = require("path");

function getRepoRoot() {
  return path.resolve(__dirname, "..");
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function assertFileExists(repoRoot, relativePath) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Required file '${relativePath}' was not found.`);
  }

  return absolutePath;
}

function assertMarkdownHasHeading(repoRoot, relativePath) {
  const absolutePath = assertFileExists(repoRoot, relativePath);
  const content = readText(absolutePath);
  if (!/^#\s+/mu.test(content)) {
    throw new Error(`Markdown file '${relativePath}' must contain a top-level heading.`);
  }
}

function main() {
  const repoRoot = getRepoRoot();
  const requiredFiles = [
    ".gitea/workflows/phase1-ci.yml",
    "README.md",
    "src/task-summary.js",
    "src/task-priority.js",
    "scripts/validate-code-target.js",
    "scripts/typecheck-target.js",
    "scripts/ci/collect-verification-metadata.js",
    "scripts/ci/attach-ci-traceability.js",
    "scripts/ci/finalize-ci-traceability.js",
    "scripts/ci/sync-host-traceability.js",
    "scripts/ci/lib/proposal-context.js",
  ];

  requiredFiles.forEach((relativePath) => {
    assertFileExists(repoRoot, relativePath);
  });

  assertMarkdownHasHeading(repoRoot, "README.md");
  const { formatTaskSummary, summarizeStatusCounts } = require(path.join(
    repoRoot,
    "src",
    "task-summary.js",
  ));
  const { normalizePriority, sortTasksByPriority } = require(path.join(
    repoRoot,
    "src",
    "task-priority.js",
  ));

  const formatted = formatTaskSummary({
    id: "TASK-101",
    title: "Refresh webhook contract",
    status: "in-progress",
  });
  if (!formatted.includes("Refresh webhook contract") || !formatted.includes("in-progress")) {
    throw new Error("formatTaskSummary() must include both title and status in the summary string.");
  }

  const summary = summarizeStatusCounts([
    { status: "todo" },
    { status: "in-progress" },
    { status: "in-progress" },
    { status: "done" },
  ]);
  if (summary.total !== 4 || summary.byStatus["in-progress"] !== 2) {
    throw new Error("summarizeStatusCounts() must return total and per-status counts.");
  }

  if (normalizePriority("HIGH") !== "high" || normalizePriority("unknown") !== "medium") {
    throw new Error("normalizePriority() must normalize known values and default unknown values.");
  }

  const sorted = sortTasksByPriority([
    { title: "third", priority: "low" },
    { title: "first", priority: "high" },
    { title: "second", priority: "medium" },
  ]);
  if (sorted[0].title !== "first" || sorted[2].title !== "third") {
    throw new Error("sortTasksByPriority() must order tasks from highest to lowest priority.");
  }

  console.log(
    JSON.stringify(
      {
        status: "passed",
        checked_files: requiredFiles,
        sample_summary: formatted,
        sample_status_totals: summary,
      },
      null,
      2,
    ),
  );
}

main();
