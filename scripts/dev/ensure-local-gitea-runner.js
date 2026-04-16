const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const { getRepoRoot } = require("../lib/project-state");
const { loadLocalGiteaSettings, requestJson } = require("../lib/gitea-client");

const DEFAULT_RUNNER_CONTAINER = process.env.AGENT_SDLC_GITEA_RUNNER_CONTAINER || "agent-sdlc-gitea-runner";
const DEFAULT_RUNNER_IMAGE = process.env.AGENT_SDLC_GITEA_RUNNER_IMAGE || "docker.io/gitea/act_runner:latest";
const DEFAULT_RUNNER_NAME = process.env.AGENT_SDLC_GITEA_RUNNER_NAME || "agent-sdlc-local-runner";
const DEFAULT_RUNNER_LABELS =
  process.env.AGENT_SDLC_GITEA_RUNNER_LABELS ||
  "ubuntu-22.04:docker://node:22-bookworm-slim,ubuntu-latest:docker://node:22-bookworm-slim";
const DEFAULT_GITEA_NETWORK = process.env.AGENT_SDLC_GITEA_RUNNER_NETWORK || "agent-sdlc-gitea-network";
const DEFAULT_DOCKER_INTERNAL_INSTANCE_URL =
  process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL || "http://agent-sdlc-gitea:3000/";

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node scripts/dev/ensure-local-gitea-runner.js ensure-runner",
      "  node scripts/dev/ensure-local-gitea-runner.js status",
      "  node scripts/dev/ensure-local-gitea-runner.js down",
    ].join("\n"),
  );
}

function parseArguments(argv) {
  if (argv.length !== 3) {
    printUsage();
    process.exit(1);
  }

  const command = argv[2];
  if (!["ensure-runner", "status", "down"].includes(command)) {
    printUsage();
    process.exit(1);
  }

  return {
    command,
  };
}

function ensureDirectory(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function runProcess(fileName, args, options = {}) {
  const result = spawnSync(fileName, args, {
    cwd: options.cwd,
    encoding: "utf8",
  });

  if (result.error) {
    throw new Error(`${fileName} failed before execution: ${result.error.message}`);
  }

  if (!options.allowFailure && result.status !== 0) {
    const message = (result.stderr || result.stdout || `${fileName} failed`).trim();
    throw new Error(message);
  }

  return {
    status: result.status,
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
  };
}

function getRunnerStateRoot(repoRoot) {
  return path.join(repoRoot, ".agent-sdlc", "dev-env", "gitea-runner");
}

function getRunnerConfigPaths(repoRoot) {
  const root = getRunnerStateRoot(repoRoot);
  const dataDir = path.join(root, "data");
  return {
    root,
    dataDir,
    configFile: path.join(dataDir, "config.yaml"),
  };
}

function yamlQuote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function writeRunnerConfig(configPaths) {
  const containerNetwork = dockerNetworkExists(DEFAULT_GITEA_NETWORK) ? DEFAULT_GITEA_NETWORK : "";
  const lines = [
    "log:",
    "  level: info",
    "container:",
    `  network: ${yamlQuote(containerNetwork)}`,
    "  options:",
  ];

  fs.writeFileSync(configPaths.configFile, `${lines.join("\n")}\n`, "utf8");
}

function getContainerStatus(containerName) {
  const result = runProcess(
    "docker",
    ["container", "inspect", containerName, "--format", "{{.State.Status}}"],
    { allowFailure: true },
  );
  if (result.status !== 0) {
    return null;
  }

  return result.stdout || null;
}

function dockerNetworkExists(networkName) {
  const result = runProcess("docker", ["network", "inspect", networkName], { allowFailure: true });
  return result.status === 0;
}

function generateRegistrationToken() {
  const result = runProcess("docker", [
    "exec",
    "agent-sdlc-gitea",
    "gitea",
    "--config",
    "/etc/gitea/app.ini",
    "actions",
    "generate-runner-token",
  ]);

  return result.stdout;
}

function buildEnsureRunnerResult(containerStatus, runnerState = null) {
  return {
    status: "ready",
    container_name: DEFAULT_RUNNER_CONTAINER,
    container_status: containerStatus,
    runner_name: DEFAULT_RUNNER_NAME,
    runner_labels: DEFAULT_RUNNER_LABELS,
    runner: runnerState,
  };
}

async function findRunner(settings) {
  const runners = await requestJson(settings, {
    method: "GET",
    pathname: "api/v1/admin/actions/runners",
  });

  const entries = (runners && runners.runners) || runners || [];
  return entries.find((runner) => runner.name === DEFAULT_RUNNER_NAME) || null;
}

async function ensureRunner(repoRoot) {
  const configPaths = getRunnerConfigPaths(repoRoot);
  ensureDirectory(configPaths.dataDir);
  writeRunnerConfig(configPaths);

  const existingStatus = getContainerStatus(DEFAULT_RUNNER_CONTAINER);
  if (existingStatus === "running") {
    const settings = loadLocalGiteaSettings(repoRoot);
    return buildEnsureRunnerResult(existingStatus, await findRunner(settings));
  }

  if (existingStatus) {
    runProcess("docker", ["rm", "-f", DEFAULT_RUNNER_CONTAINER], { allowFailure: true });
  }

  const registrationToken = generateRegistrationToken();
  const settings = loadLocalGiteaSettings(repoRoot);
  const instanceUrl = dockerNetworkExists(DEFAULT_GITEA_NETWORK)
    ? DEFAULT_DOCKER_INTERNAL_INSTANCE_URL
    : settings.baseUrl;
  const dockerSocketPath = "//var/run/docker.sock";
  const runnerArgs = [
    "run",
    "-d",
    "--name",
    DEFAULT_RUNNER_CONTAINER,
    "--restart",
    "unless-stopped",
  ];

  if (dockerNetworkExists(DEFAULT_GITEA_NETWORK)) {
    runnerArgs.push("--network", DEFAULT_GITEA_NETWORK);
  }

  runnerArgs.push(
    "-v",
    `${configPaths.dataDir}:/data`,
    "-v",
    `${dockerSocketPath}:/var/run/docker.sock`,
    "-e",
    `GITEA_INSTANCE_URL=${instanceUrl}`,
    "-e",
    "CONFIG_FILE=/data/config.yaml",
    "-e",
    `GITEA_RUNNER_REGISTRATION_TOKEN=${registrationToken}`,
    "-e",
    `GITEA_RUNNER_NAME=${DEFAULT_RUNNER_NAME}`,
    "-e",
    `GITEA_RUNNER_LABELS=${DEFAULT_RUNNER_LABELS}`,
    DEFAULT_RUNNER_IMAGE,
  );
  runProcess("docker", runnerArgs);

  let runnerState = null;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    runnerState = await findRunner(settings);
    if (runnerState) {
      break;
    }
    await new Promise((resolve) => {
      setTimeout(resolve, 2000);
    });
  }

  return buildEnsureRunnerResult(getContainerStatus(DEFAULT_RUNNER_CONTAINER), runnerState);
}

async function showStatus(repoRoot) {
  const settings = loadLocalGiteaSettings(repoRoot);
  return buildEnsureRunnerResult(getContainerStatus(DEFAULT_RUNNER_CONTAINER) || "not-started", await findRunner(settings));
}

async function stopRunner(repoRoot) {
  const settings = loadLocalGiteaSettings(repoRoot);
  const runnerState = await findRunner(settings);
  if (getContainerStatus(DEFAULT_RUNNER_CONTAINER)) {
    runProcess("docker", ["rm", "-f", DEFAULT_RUNNER_CONTAINER], { allowFailure: true });
  }

  return {
    status: "stopped",
    container_name: DEFAULT_RUNNER_CONTAINER,
    runner: runnerState,
  };
}

async function main() {
  try {
    const repoRoot = getRepoRoot();
    const { command } = parseArguments(process.argv);
    let result;

    if (command === "ensure-runner") {
      result = await ensureRunner(repoRoot);
    } else if (command === "status") {
      result = await showStatus(repoRoot);
    } else {
      result = await stopRunner(repoRoot);
    }

    console.log(JSON.stringify(result, null, 2));
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
