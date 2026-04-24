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

function listMarkdownFiles(repoRoot, relativeDirectory) {
  const directoryPath = path.join(repoRoot, relativeDirectory);
  if (!fs.existsSync(directoryPath)) {
    throw new Error(`Directory '${relativeDirectory}' was not found.`);
  }

  return fs
    .readdirSync(directoryPath)
    .filter((entry) => entry.toLowerCase().endsWith(".md"))
    .sort();
}

function main() {
  const repoRoot = getRepoRoot();
  const requiredFiles = [
    ".gitea/workflows/phase1-ci.yml",
    "README.md",
    "docs/overview.md",
    "docs/faq.md",
    "scripts/validate-docs-target.js",
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
  assertMarkdownHasHeading(repoRoot, "docs/overview.md");
  assertMarkdownHasHeading(repoRoot, "docs/faq.md");

  const docsFiles = listMarkdownFiles(repoRoot, "docs");
  if (docsFiles.length < 2) {
    throw new Error("The docs directory must contain at least two markdown files.");
  }

  console.log(
    JSON.stringify(
      {
        status: "passed",
        checked_files: requiredFiles,
        docs_files: docsFiles,
      },
      null,
      2,
    ),
  );
}

main();
