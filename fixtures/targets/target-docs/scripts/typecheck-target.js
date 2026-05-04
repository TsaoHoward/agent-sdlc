const path = require("path");
const { spawnSync } = require("child_process");

function getRepoRoot() {
  return path.resolve(__dirname, "..");
}

function main() {
  const repoRoot = getRepoRoot();
  const scriptPaths = [
    "scripts/validate-docs-target.js",
    "scripts/typecheck-target.js",
    "scripts/ci/collect-verification-metadata.js",
    "scripts/ci/attach-ci-traceability.js",
    "scripts/ci/finalize-ci-traceability.js",
    "scripts/ci/sync-host-traceability.js",
    "scripts/ci/lib/proposal-context.js",
  ];

  const failures = [];
  scriptPaths.forEach((relativePath) => {
    const absolutePath = path.join(repoRoot, relativePath);
    const result = spawnSync(process.execPath, ["--check", absolutePath], {
      encoding: "utf8",
    });

    if (result.status !== 0) {
      failures.push({
        path: relativePath,
        stderr: (result.stderr || result.stdout || "").trim(),
      });
    }
  });

  if (failures.length > 0) {
    throw new Error(
      `Target script syntax check failed for: ${failures.map((failure) => failure.path).join(", ")}`,
    );
  }

  console.log(
    JSON.stringify(
      {
        status: "passed",
        checked_scripts: scriptPaths,
      },
      null,
      2,
    ),
  );
}

main();
