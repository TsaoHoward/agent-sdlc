const path = require("path");
const { spawnSync } = require("child_process");

const { getRepoRoot, toRepoRelativePath } = require("../lib/project-state");

const TARGET_DEFINITIONS = {
  "target-code-small": {
    owner: "eval",
    repo: "target-code-small",
    fixturePath: path.join("fixtures", "targets", "target-code-small"),
    recommendedTaskToken: "code",
    summary:
      "Controlled bounded-code external target with a minimal target-side CI integration kit.",
  },
  "target-docs": {
    owner: "eval",
    repo: "target-docs",
    fixturePath: path.join("fixtures", "targets", "target-docs"),
    recommendedTaskToken: "docs",
    summary:
      "Controlled docs-only external target with a minimal target-side CI integration kit.",
  },
};

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node scripts/dev/manage-external-target-repo.js list-targets",
      "  node scripts/dev/manage-external-target-repo.js provision-target --target <target-id>",
      "  node scripts/dev/manage-external-target-repo.js reset-target --target <target-id>",
    ].join("\n"),
  );
}

function parseArguments(argv) {
  if (argv.length < 3) {
    printUsage();
    process.exit(1);
  }

  const command = argv[2];
  if (command === "list-targets") {
    if (argv.length !== 3) {
      printUsage();
      process.exit(1);
    }

    return {
      command,
      targetId: null,
    };
  }

  if (!["provision-target", "reset-target"].includes(command)) {
    printUsage();
    process.exit(1);
  }

  let targetId = null;
  for (let index = 3; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--target") {
      targetId = argv[index + 1];
      index += 1;
      continue;
    }

    printUsage();
    process.exit(1);
  }

  if (!targetId) {
    printUsage();
    process.exit(1);
  }

  return {
    command,
    targetId,
  };
}

function resolveTargetDefinition(repoRoot, targetId) {
  const definition = TARGET_DEFINITIONS[targetId];
  if (!definition) {
    throw new Error(`Unknown external target '${targetId}'.`);
  }

  return {
    ...definition,
    targetId,
    absoluteFixturePath: path.resolve(repoRoot, definition.fixturePath),
  };
}

function runNodeScript(scriptPath, args) {
  const result = spawnSync(process.execPath, [scriptPath, ...args], {
    encoding: "utf8",
  });

  if (result.error) {
    throw new Error(`Node script failed before execution: ${result.error.message}`);
  }

  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || "External target repo helper failed.").trim();
    throw new Error(message);
  }

  const stdout = (result.stdout || "").trim();
  if (!stdout) {
    return null;
  }

  try {
    return JSON.parse(stdout);
  } catch {
    return {
      raw_output: stdout,
    };
  }
}

function buildTargetSummary(repoRoot, definition) {
  return {
    target_id: definition.targetId,
    owner: definition.owner,
    repo: definition.repo,
    fixture_path: toRepoRelativePath(repoRoot, definition.absoluteFixturePath),
    recommended_task_token: definition.recommendedTaskToken,
    summary: definition.summary,
  };
}

function listTargets(repoRoot) {
  const targets = Object.keys(TARGET_DEFINITIONS)
    .sort()
    .map((targetId) => buildTargetSummary(repoRoot, resolveTargetDefinition(repoRoot, targetId)));

  console.log(
    JSON.stringify(
      {
        status: "listed",
        targets,
      },
      null,
      2,
    ),
  );
}

function ensureSeedPathExists(definition) {
  const fs = require("fs");

  if (!fs.existsSync(definition.absoluteFixturePath)) {
    throw new Error(
      `External target fixture '${definition.targetId}' was not found at ${definition.absoluteFixturePath}.`,
    );
  }
}

function provisionOrResetTarget(repoRoot, definition, action) {
  ensureSeedPathExists(definition);
  const ensureScriptPath = path.join(repoRoot, "scripts", "dev", "ensure-local-gitea-repo.js");
  const result = runNodeScript(ensureScriptPath, [
    "ensure-local-repo",
    "--owner",
    definition.owner,
    "--repo",
    definition.repo,
    "--seed-from",
    definition.absoluteFixturePath,
  ]);

  console.log(
    JSON.stringify(
      {
        status: "ready",
        action,
        ...buildTargetSummary(repoRoot, definition),
        ensure_local_repo: result,
      },
      null,
      2,
    ),
  );
}

function main() {
  try {
    const repoRoot = getRepoRoot();
    const options = parseArguments(process.argv);

    if (options.command === "list-targets") {
      listTargets(repoRoot);
      return;
    }

    const definition = resolveTargetDefinition(repoRoot, options.targetId);
    if (options.command === "provision-target") {
      provisionOrResetTarget(repoRoot, definition, "provision-target");
      return;
    }

    if (options.command === "reset-target") {
      provisionOrResetTarget(repoRoot, definition, "reset-target");
      return;
    }

    printUsage();
    process.exit(1);
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
}

main();
