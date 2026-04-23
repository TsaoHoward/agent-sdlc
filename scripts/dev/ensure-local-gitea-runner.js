const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const { getRepoRoot } = require("../lib/project-state");
const { loadLocalGiteaSettings, readGiteaBootstrapConfig, requestJson } = require("../lib/gitea-client");

const DEFAULT_RUNNER_SETTINGS = {
  giteaContainer: "agent-sdlc-gitea",
  container: "agent-sdlc-gitea-runner",
  image: "docker.io/gitea/act_runner:latest",
  name: "agent-sdlc-local-runner",
  labels: "ubuntu-22.04:docker://node:22-bookworm-slim,ubuntu-latest:docker://node:22-bookworm-slim",
  network: "agent-sdlc-gitea-network",
  containerNetwork: null,
  jobNetwork: null,
  dockerInternalInstanceUrl: "http://agent-sdlc-gitea:3000/",
};

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

function firstNonEmpty(...values) {
  return values.find((value) => value !== undefined && value !== null && value !== "");
}

function loadRunnerSettings(repoRoot) {
  const { config } = readGiteaBootstrapConfig(repoRoot);
  const configuredRunner = config.giteaActionsRunner || {};

  return {
    giteaContainer: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_CONTAINER,
      configuredRunner.giteaContainer,
      DEFAULT_RUNNER_SETTINGS.giteaContainer,
    ),
    container: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_CONTAINER,
      configuredRunner.container,
      DEFAULT_RUNNER_SETTINGS.container,
    ),
    image: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_IMAGE,
      configuredRunner.image,
      DEFAULT_RUNNER_SETTINGS.image,
    ),
    name: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_NAME,
      configuredRunner.name,
      DEFAULT_RUNNER_SETTINGS.name,
    ),
    labels: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_LABELS,
      configuredRunner.labels,
      DEFAULT_RUNNER_SETTINGS.labels,
    ),
    network: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_NETWORK,
      configuredRunner.network,
      DEFAULT_RUNNER_SETTINGS.network,
    ),
    containerNetwork: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_CONTAINER_NETWORK,
      configuredRunner.containerNetwork,
      DEFAULT_RUNNER_SETTINGS.containerNetwork,
    ),
    jobNetwork: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_JOB_NETWORK,
      configuredRunner.jobNetwork,
      DEFAULT_RUNNER_SETTINGS.jobNetwork,
    ),
    dockerInternalInstanceUrl: firstNonEmpty(
      process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL,
      configuredRunner.dockerInternalInstanceUrl,
      DEFAULT_RUNNER_SETTINGS.dockerInternalInstanceUrl,
    ),
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

function resolveJobContainerNetwork(settings, runnerSettings) {
  if (runnerSettings.jobNetwork) {
    return runnerSettings.jobNetwork;
  }

  const hostname = new URL(settings.baseUrl).hostname;
  if (isLoopbackHostname(hostname)) {
    return "host";
  }

  return dockerNetworkExists(runnerSettings.network) ? runnerSettings.network : "";
}

function resolveRunnerContainerNetwork(settings, runnerSettings) {
  if (runnerSettings.containerNetwork) {
    return runnerSettings.containerNetwork;
  }

  const hostname = new URL(settings.baseUrl).hostname;
  if (isLoopbackHostname(hostname)) {
    return "host";
  }

  return dockerNetworkExists(runnerSettings.network) ? runnerSettings.network : "";
}

function resolveRunnerInstanceUrl(settings, runnerContainerNetwork, runnerSettings) {
  if (process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL) {
    return process.env.AGENT_SDLC_GITEA_RUNNER_INSTANCE_URL;
  }

  if (runnerContainerNetwork === "host") {
    return settings.baseUrl;
  }

  return dockerNetworkExists(runnerSettings.network) ? runnerSettings.dockerInternalInstanceUrl : settings.baseUrl;
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

function resolveJobContainerOptions(settings, runnerSettings) {
  if (resolveJobContainerNetwork(settings, runnerSettings) !== "host") {
    return "";
  }

  const giteaContainerIp = getContainerIp(runnerSettings.giteaContainer, runnerSettings.network);
  if (!giteaContainerIp) {
    return "";
  }

  return `--add-host=agent-sdlc-gitea:${giteaContainerIp}`;
}

function writeRunnerConfig(configPaths, settings, runnerSettings) {
  const containerNetwork = resolveJobContainerNetwork(settings, runnerSettings);
  const containerOptions = resolveJobContainerOptions(settings, runnerSettings);
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

function generateRegistrationToken(runnerSettings) {
  const result = runProcess("docker", [
    "exec",
    runnerSettings.giteaContainer,
    "gitea",
    "--config",
    "/etc/gitea/app.ini",
    "actions",
    "generate-runner-token",
  ]);

  return result.stdout;
}

function buildEnsureRunnerResult(
  runnerSettings,
  containerStatus,
  runnerState = null,
  jobContainerNetwork = null,
  runnerContainerNetwork = null,
  instanceUrl = null,
) {
  return {
    status: "ready",
    container_name: runnerSettings.container,
    container_status: containerStatus,
    runner_name: runnerSettings.name,
    runner_labels: runnerSettings.labels,
    job_container_network: jobContainerNetwork,
    runner_container_network: runnerContainerNetwork,
    instance_url: instanceUrl,
    runner: runnerState,
  };
}

function isRunnerOnline(runnerState) {
  return !!runnerState && String(runnerState.status || "").toLowerCase() === "online";
}

async function findRunner(settings, runnerSettings) {
  const runners = await requestJson(settings, {
    method: "GET",
    pathname: "api/v1/admin/actions/runners",
  });

  const entries = (runners && runners.runners) || runners || [];
  return entries.find((runner) => runner.name === runnerSettings.name) || null;
}

async function ensureRunner(repoRoot) {
  const configPaths = getRunnerConfigPaths(repoRoot);
  const settings = loadLocalGiteaSettings(repoRoot);
  const runnerSettings = loadRunnerSettings(repoRoot);
  ensureDirectory(configPaths.dataDir);
  const runnerConfigState = writeRunnerConfig(configPaths, settings, runnerSettings);
  const runnerContainerNetwork = resolveRunnerContainerNetwork(settings, runnerSettings);
  const instanceUrl = resolveRunnerInstanceUrl(settings, runnerContainerNetwork, runnerSettings);
  const runnerRegistrationState = syncRunnerRegistrationState(configPaths, instanceUrl);

  const existingStatus = getContainerStatus(runnerSettings.container);
  if (existingStatus === "running") {
    const currentNetworkMode = getContainerNetworkMode(runnerSettings.container);
    const currentInstanceUrl = getContainerEnvValue(runnerSettings.container, "GITEA_INSTANCE_URL");
    const currentRunnerState = await findRunner(settings, runnerSettings);
    if (
      !runnerConfigState.changed &&
      !runnerRegistrationState.changed &&
      currentNetworkMode === runnerContainerNetwork &&
      currentInstanceUrl === instanceUrl &&
      isRunnerOnline(currentRunnerState)
    ) {
      return buildEnsureRunnerResult(
        runnerSettings,
        existingStatus,
        currentRunnerState,
        runnerConfigState.containerNetwork,
        runnerContainerNetwork,
        instanceUrl,
      );
    }

    runProcess("docker", ["rm", "-f", runnerSettings.container], { allowFailure: true });
  }

  if (existingStatus) {
    runProcess("docker", ["rm", "-f", runnerSettings.container], { allowFailure: true });
  }

  const registrationToken = generateRegistrationToken(runnerSettings);
  const dockerSocketPath = "//var/run/docker.sock";
  const runnerArgs = [
    "run",
    "-d",
    "--name",
    runnerSettings.container,
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
    `GITEA_RUNNER_NAME=${runnerSettings.name}`,
    "-e",
    `GITEA_RUNNER_LABELS=${runnerSettings.labels}`,
    runnerSettings.image,
  );
  runProcess("docker", runnerArgs);

  let runnerState = null;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    runnerState = await findRunner(settings, runnerSettings);
    if (isRunnerOnline(runnerState)) {
      break;
    }
    await new Promise((resolve) => {
      setTimeout(resolve, 2000);
    });
  }

  return buildEnsureRunnerResult(
    runnerSettings,
    getContainerStatus(runnerSettings.container),
    runnerState,
    runnerConfigState.containerNetwork,
    runnerContainerNetwork,
    instanceUrl,
  );
}

async function showStatus(repoRoot) {
  const settings = loadLocalGiteaSettings(repoRoot);
  const runnerSettings = loadRunnerSettings(repoRoot);
  const runnerContainerNetwork = resolveRunnerContainerNetwork(settings, runnerSettings);
  const instanceUrl = resolveRunnerInstanceUrl(settings, runnerContainerNetwork, runnerSettings);
  return buildEnsureRunnerResult(
    runnerSettings,
    getContainerStatus(runnerSettings.container) || "not-started",
    await findRunner(settings, runnerSettings),
    resolveJobContainerNetwork(settings, runnerSettings),
    runnerContainerNetwork,
    instanceUrl,
  );
}

async function stopRunner(repoRoot) {
  const settings = loadLocalGiteaSettings(repoRoot);
  const runnerSettings = loadRunnerSettings(repoRoot);
  const runnerState = await findRunner(settings, runnerSettings);
  if (getContainerStatus(runnerSettings.container)) {
    runProcess("docker", ["rm", "-f", runnerSettings.container], { allowFailure: true });
  }

  return {
    status: "stopped",
    container_name: runnerSettings.container,
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
