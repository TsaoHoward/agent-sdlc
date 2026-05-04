const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const {
  buildRepositoryUrls,
  loadLocalGiteaSettings,
  parseGiteaRepositoryRef,
  readGiteaBootstrapConfig,
} = require("./gitea-client");
const { toRepoRelativePath, writeJson } = require("./project-state");

const DEFAULT_WORKER_IMAGE = "agent-sdlc-worker-runtime:test";
const DEFAULT_WORKER_GITEA_HOST = "host.docker.internal";

function loadWorkerRuntimeSettings(repoRoot) {
  const { config } = readGiteaBootstrapConfig(repoRoot);
  const configuredRuntime = config.workerRuntime || {};

  return {
    image: process.env.AGENT_SDLC_WORKER_IMAGE || configuredRuntime.image || DEFAULT_WORKER_IMAGE,
    loopbackGiteaHost:
      process.env.AGENT_SDLC_WORKER_GITEA_HOST ||
      configuredRuntime.loopbackGiteaHost ||
      DEFAULT_WORKER_GITEA_HOST,
  };
}

function sanitizeContainerName(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9-]+/gu, "-")
    .replace(/^-+/u, "")
    .replace(/-+$/u, "")
    .slice(0, 63);
}

function utcNow() {
  return new Date().toISOString();
}

function ensureEmptyDirectory(directoryPath) {
  fs.rmSync(directoryPath, { recursive: true, force: true });
  fs.mkdirSync(directoryPath, { recursive: true });
}

function sanitizeDockerArguments(args) {
  return args.map((value) => {
    if (String(value).startsWith("SOURCE_GIT_AUTH_HEADER=")) {
      return "SOURCE_GIT_AUTH_HEADER=[redacted]";
    }

    return value;
  });
}

function isLoopbackHostname(hostname) {
  const normalized = String(hostname || "").trim().toLowerCase();
  return normalized === "localhost" || normalized === "127.0.0.1" || normalized === "::1";
}

function normalizeContainerReachableGitUrl(gitUrl, workerRuntimeSettings) {
  const parsed = new URL(gitUrl);
  if (!isLoopbackHostname(parsed.hostname)) {
    return parsed.toString();
  }

  parsed.hostname = workerRuntimeSettings.loopbackGiteaHost;
  return parsed.toString();
}

function buildRuntimeSourceConfig(repoRoot, taskRequest, workerRuntimeSettings) {
  if (!taskRequest.repository_ref) {
    return {
      cloneMode: "local-source",
      sourceGitUrl: "",
      sourceGitAuthHeader: "",
    };
  }

  try {
    const settings = loadLocalGiteaSettings(repoRoot);
    const repositoryInfo = parseGiteaRepositoryRef(taskRequest.repository_ref);
    const repositoryUrls = buildRepositoryUrls(
      settings,
      repositoryInfo.owner,
      repositoryInfo.repo,
      taskRequest.repository_ref,
    );

    let sourceGitAuthHeader = "";
    if (settings.username && settings.password) {
      const basicAuth = Buffer.from(`${settings.username}:${settings.password}`, "utf8").toString(
        "base64",
      );
      sourceGitAuthHeader = `AUTHORIZATION: Basic ${basicAuth}`;
    } else if (settings.token) {
      sourceGitAuthHeader = `AUTHORIZATION: token ${settings.token}`;
    }

    return {
      cloneMode: "forge-repository",
      sourceGitUrl: normalizeContainerReachableGitUrl(repositoryUrls.gitUrl, workerRuntimeSettings),
      sourceGitAuthHeader,
      repositoryRef: taskRequest.repository_ref,
    };
  } catch (error) {
    return {
      cloneMode: "local-source",
      sourceGitUrl: "",
      sourceGitAuthHeader: "",
      fallbackReason: error.message,
    };
  }
}

function buildRuntimeBootstrapScript() {
  return [
    "set -euo pipefail",
    'if [ -n "${SOURCE_GIT_URL:-}" ]; then',
    '  if [ -n "${SOURCE_GIT_AUTH_HEADER:-}" ]; then',
    '    git -c "http.extraHeader=${SOURCE_GIT_AUTH_HEADER}" clone "${SOURCE_GIT_URL}" /workspace',
    "  else",
    '    git clone "${SOURCE_GIT_URL}" /workspace',
    "  fi",
    "else",
    "  git config --global --add safe.directory /source",
    "  git config --global --add safe.directory /source/.git",
    "  git clone /source /workspace",
    "fi",
    "git config --global --add safe.directory /workspace",
    'if [ -n "${TARGET_BRANCH:-}" ]; then',
    '  git -C /workspace checkout "${TARGET_BRANCH}" || git -C /workspace checkout -B "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}"',
    "fi",
    "mkdir -p /artifacts",
    'printf "workspace prepared for %s\\n" "${AGENT_SESSION_ID}"',
  ].join("\n");
}

function buildDockerArguments({
  repoRoot,
  workspaceDir,
  artifactDir,
  containerName,
  image,
  sessionRecord,
  taskRequest,
  runtimeSource,
}) {
  return [
    "run",
    "--rm",
    "--name",
    containerName,
    "-v",
    `${repoRoot}:/source:ro`,
    "-v",
    `${workspaceDir}:/workspace`,
    "-v",
    `${artifactDir}:/artifacts`,
    "-e",
    `AGENT_SESSION_ID=${sessionRecord.agent_session_id}`,
    "-e",
    `TASK_REQUEST_ID=${taskRequest.task_request_id}`,
    "-e",
    `TARGET_BRANCH=${taskRequest.target_branch_ref || ""}`,
    "-e",
    `SOURCE_GIT_URL=${runtimeSource.sourceGitUrl || ""}`,
    "-e",
    `SOURCE_GIT_AUTH_HEADER=${runtimeSource.sourceGitAuthHeader || ""}`,
    image,
    "bash",
    "-lc",
    buildRuntimeBootstrapScript(),
  ];
}

function writeLaunchArtifacts(repoRoot, artifactDir, launchResult) {
  const runtimeLaunchPath = path.join(artifactDir, "runtime-launch.json");
  const runtimeLogPath = path.join(artifactDir, "runtime-launch.log");
  writeJson(runtimeLaunchPath, launchResult);

  const logOutput = [launchResult.stdout || "", launchResult.stderr || ""]
    .filter((value) => value && value !== "")
    .join("\n");
  fs.writeFileSync(runtimeLogPath, logOutput, "utf8");

  return {
    runtimeLaunchPath,
    runtimeLogPath,
    artifactRefs: [
      toRepoRelativePath(repoRoot, runtimeLaunchPath),
      toRepoRelativePath(repoRoot, runtimeLogPath),
    ],
  };
}

function launchWorkerRuntime({
  repoRoot,
  statePaths,
  sessionRecord,
  taskRequest,
  workerImage = null,
}) {
  const workspaceDir = path.join(statePaths.runtimeWorkspaceRoot, sessionRecord.agent_session_id);
  const artifactDir = path.join(statePaths.runtimeArtifactRoot, sessionRecord.agent_session_id);
  ensureEmptyDirectory(workspaceDir);
  ensureEmptyDirectory(artifactDir);

  const launchedAt = utcNow();
  const containerName = sanitizeContainerName(`agent-sdlc-${sessionRecord.agent_session_id}`);
  const workerRuntimeSettings = loadWorkerRuntimeSettings(repoRoot);
  const resolvedWorkerImage = workerImage || workerRuntimeSettings.image;
  const runtimeSource = buildRuntimeSourceConfig(repoRoot, taskRequest, workerRuntimeSettings);
  const dockerArgs = buildDockerArguments({
    repoRoot,
    workspaceDir,
    artifactDir,
    containerName,
    image: resolvedWorkerImage,
    sessionRecord,
    taskRequest,
    runtimeSource,
  });

  const result = spawnSync("docker", dockerArgs, {
    cwd: repoRoot,
    encoding: "utf8",
  });
  const completedAt = utcNow();

  if (result.error) {
    throw new Error(`Worker runtime launch failed before startup: ${result.error.message}`);
  }

  const launchResult = {
    runner: "docker",
    image: resolvedWorkerImage,
    container_name: containerName,
    launched_at: launchedAt,
    completed_at: completedAt,
    exit_code: result.status,
    workspace_ref: toRepoRelativePath(repoRoot, workspaceDir),
    artifact_dir_ref: toRepoRelativePath(repoRoot, artifactDir),
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    docker_args: sanitizeDockerArguments(dockerArgs),
    prepared_branch_ref: taskRequest.target_branch_ref || null,
    workspace_source: {
      clone_mode: runtimeSource.cloneMode,
      repository_ref: runtimeSource.repositoryRef || taskRequest.repository_ref || null,
      git_url: runtimeSource.sourceGitUrl || null,
      fallback_reason: runtimeSource.fallbackReason || null,
    },
  };

  const artifactOutput = writeLaunchArtifacts(repoRoot, artifactDir, launchResult);

  if (result.status !== 0) {
    const errorMessage = (result.stderr || result.stdout || "docker run failed").trim();
    const runtimeError = new Error(`Worker runtime launch failed: ${errorMessage}`);
    runtimeError.launchResult = launchResult;
    runtimeError.artifactOutput = artifactOutput;
    throw runtimeError;
  }

  return {
    workerImage: resolvedWorkerImage,
    containerName,
    launchedAt,
    completedAt,
    workspaceDir,
    artifactDir,
    artifactRefs: artifactOutput.artifactRefs,
    launchResultPath: artifactOutput.runtimeLaunchPath,
    launchLogPath: artifactOutput.runtimeLogPath,
  };
}

module.exports = {
  DEFAULT_WORKER_IMAGE,
  launchWorkerRuntime,
};
