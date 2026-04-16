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
const DEFAULT_GITEA_CONTAINER = process.env.AGENT_SDLC_GITEA_CONTAINER || "agent-sdlc-gitea";
const DEFAULT_GITEA_NETWORK = process.env.AGENT_SDLC_GITEA_RUNNER_NETWORK || "agent-sdlc-gitea-network";
const DEFAULT_RUNNER_CONTAINER_NETWORK =
  process.env.AGENT_SDLC_GITEA_RUNNER_CONTAINER_NETWORK || null;
const DEFAULT_JOB_CONTAINER_NETWORK = process.env.AGENT_SDLC_GITEA_RUNNER_JOB_NETWORK || null;
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
    runnerFile: path.join(dataDir, ".runner"),
  };
}

function yamlQuote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function isLoopbackHostname(hostname) {
  const normalized = String(hostname || "").trim().toLowerCase();
  return normalized === "localhost" || normalized === "127.0.0.1" || normalized === "::1";
}

function resolveJobContainerNetwork(settings) {
  if (DEFAULT_JOB_CONTAINER_NETWORK) {
    return DEFAULT_JOB_CONTAINER_NETWORK;
  }

  const hostname = new URL(settings.baseUrl).hostname;
  if (isLoopbackHostname(hostname)) {
    return "host";
  }

  return dockerNetworkExists(DEFAULT_GITEA_NETWORK) ? DEFAULT_GITEA_NETWORK : "";
}

function resolveRunnerContainerNetwork(settings) {
  if (DEFAULT_RUNNER_CONTAINER_NETWORK) {
    return DEFAULT_RUNNER_CONTAINER_NETWORK;
  }

  const hostname = new URL(settings.baseUrl).hostname;
  if (isLoopbackHostname(hostname)) {
    return "host";
  }

  return dockerNetworkExists(DEFAULT_GITEA_NETWORK) ? DEFAULT_GITEA_NETWORK : "";
}

function resolveRunnerInstanceUrl(settings, runnerContainerNetwork) {
  if (process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL) {
    return process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL;
  }

  if (runnerContainerNetwork === "host") {
    return settings.baseUrl;
  }

  return dockerNetworkExists(DEFAULT_GITEA_NETWORK) ? DEFAULT_DOCKER_INTERNAL_INSTANCE_URL : settings.baseUrl;
}

function getContainerNetworkMap(containerName) {
  const result = runProcess(
    "docker",
    ["container", "inspect", containerName, "--format", "{{json .NetworkSettings.Networks}}"],
    { allowFailure: true },
  );
  if (result.status !== 0 || !result.stdout) {
    return null;
  }

  return JSON.parse(result.stdout);
}

function getContainerIp(containerName, preferredNetworkName = null) {
  const networkMap = getContainerNetworkMap(containerName);
  if (!networkMap) {
    return null;
  }

  if (
    preferredNetworkName &&
    networkMap[preferredNetworkName] &&
    networkMap[preferredNetworkName].IPAddress
  ) {
    return networkMap[preferredNetworkName].IPAddress;
  }

  const firstNetwork = Object.values(networkMap).find((network) => network && network.IPAddress);
  return firstNetwork ? firstNetwork.IPAddress : null;
}

function resolveJobContainerOptions(settings) {
  if (resolveJobContainerNetwork(settings) !== "host") {
    return "";
  }

  const giteaContainerIp = getContainerIp(DEFAULT_GITEA_CONTAINER, DEFAULT_GITEA_NETWORK);
  if (!giteaContainerIp) {
    return "";
  }

  return `--add-host=agent-sdlc-gitea:${giteaContainerIp}`;
}

function writeRunnerConfig(configPaths, settings) {
  const containerNetwork = resolveJobContainerNetwork(settings);
  const containerOptions = resolveJobContainerOptions(settings);
  const lines = [
    "log:",
    "  level: info",
    "container:",
    `  network: ${yamlQuote(containerNetwork)}`,
    `  options: ${yamlQuote(containerOptions)}`,
  ];

  const nextContent = `${lines.join("\n")}\n`;
  const previousContent = fs.existsSync(configPaths.configFile)
    ? fs.readFileSync(configPaths.configFile, "utf8")
    : null;

  fs.writeFileSync(configPaths.configFile, nextContent, "utf8");

  return {
    changed: previousContent !== nextContent,
    containerNetwork,
  };
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

function getContainerNetworkMode(containerName) {
  const result = runProcess(
    "docker",
    ["container", "inspect", containerName, "--format", "{{.HostConfig.NetworkMode}}"],
    { allowFailure: true },
  );
  if (result.status !== 0) {
    return null;
  }

  return result.stdout || null;
}

function getContainerEnvValue(containerName, envName) {
  const result = runProcess("docker", ["container", "inspect", containerName, "--format", "{{json .Config.Env}}"], {
    allowFailure: true,
  });
  if (result.status !== 0 || !result.stdout) {
    return null;
  }

  const entries = JSON.parse(result.stdout);
  const prefix = `${envName}=`;
  const match = entries.find((entry) => entry.startsWith(prefix));
  return match ? match.slice(prefix.length) : null;
}

function readRunnerRegistrationState(configPaths) {
  if (!fs.existsSync(configPaths.runnerFile)) {
    return null;
  }

  return JSON.parse(fs.readFileSync(configPaths.runnerFile, "utf8"));
}

function syncRunnerRegistrationState(configPaths, instanceUrl) {
  const state = readRunnerRegistrationState(configPaths);
  if (!state || state.address === instanceUrl) {
    return {
      changed: false,
      address: state ? state.address : null,
    };
  }

  state.address = instanceUrl;
  fs.writeFileSync(configPaths.runnerFile, `${JSON.stringify(state, null, 2)}\n`, "utf8");
  return {
    changed: true,
    address: state.address,
  };
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

function buildEnsureRunnerResult(
  containerStatus,
  runnerState = null,
  jobContainerNetwork = null,
  runnerContainerNetwork = null,
  instanceUrl = null,
) {
  return {
    status: "ready",
    container_name: DEFAULT_RUNNER_CONTAINER,
    container_status: containerStatus,
    runner_name: DEFAULT_RUNNER_NAME,
    runner_labels: DEFAULT_RUNNER_LABELS,
    job_container_network: jobContainerNetwork,
    runner_container_network: runnerContainerNetwork,
    instance_url: instanceUrl,
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
  const settings = loadLocalGiteaSettings(repoRoot);
  ensureDirectory(configPaths.dataDir);
  const runnerConfigState = writeRunnerConfig(configPaths, settings);
  const runnerContainerNetwork = resolveRunnerContainerNetwork(settings);
  const instanceUrl = resolveRunnerInstanceUrl(settings, runnerContainerNetwork);
  const runnerRegistrationState = syncRunnerRegistrationState(configPaths, instanceUrl);

  const existingStatus = getContainerStatus(DEFAULT_RUNNER_CONTAINER);
  if (existingStatus === "running") {
    const currentNetworkMode = getContainerNetworkMode(DEFAULT_RUNNER_CONTAINER);
    const currentInstanceUrl = getContainerEnvValue(DEFAULT_RUNNER_CONTAINER, "GITEA_INSTANCE_URL");
    if (
      !runnerConfigState.changed &&
      !runnerRegistrationState.changed &&
      currentNetworkMode === runnerContainerNetwork &&
      currentInstanceUrl === instanceUrl
    ) {
      return buildEnsureRunnerResult(
        existingStatus,
        await findRunner(settings),
        runnerConfigState.containerNetwork,
        runnerContainerNetwork,
        instanceUrl,
      );
    }

    runProcess("docker", ["rm", "-f", DEFAULT_RUNNER_CONTAINER], { allowFailure: true });
  }

  if (existingStatus) {
    runProcess("docker", ["rm", "-f", DEFAULT_RUNNER_CONTAINER], { allowFailure: true });
  }

  const registrationToken = generateRegistrationToken();
  const dockerSocketPath = "//var/run/docker.sock";
  const runnerArgs = [
    "run",
    "-d",
    "--name",
    DEFAULT_RUNNER_CONTAINER,
    "--restart",
    "unless-stopped",
  ];

  if (runnerContainerNetwork) {
    runnerArgs.push("--network", runnerContainerNetwork);
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

  return buildEnsureRunnerResult(
    getContainerStatus(DEFAULT_RUNNER_CONTAINER),
    runnerState,
    runnerConfigState.containerNetwork,
    runnerContainerNetwork,
    instanceUrl,
  );
}

async function showStatus(repoRoot) {
  const settings = loadLocalGiteaSettings(repoRoot);
  const runnerContainerNetwork = resolveRunnerContainerNetwork(settings);
  const instanceUrl = resolveRunnerInstanceUrl(settings, runnerContainerNetwork);
  return buildEnsureRunnerResult(
    getContainerStatus(DEFAULT_RUNNER_CONTAINER) || "not-started",
    await findRunner(settings),
    resolveJobContainerNetwork(settings),
    runnerContainerNetwork,
    instanceUrl,
  );
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
