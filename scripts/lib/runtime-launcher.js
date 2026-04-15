const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const { toRepoRelativePath, writeJson } = require("./project-state");

const DEFAULT_WORKER_IMAGE = process.env.AGENT_SDLC_WORKER_IMAGE || "agent-sdlc-worker-runtime:test";

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

function buildRuntimeBootstrapScript() {
  return [
    "set -euo pipefail",
    "git config --global --add safe.directory /source",
    "git config --global --add safe.directory /source/.git",
    "git clone /source /workspace",
    "git config --global --add safe.directory /workspace",
    'if [ -n "${TARGET_BRANCH:-}" ]; then',
    '  git -C /workspace checkout "${TARGET_BRANCH}"',
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
  workerImage = DEFAULT_WORKER_IMAGE,
}) {
  const workspaceDir = path.join(statePaths.runtimeWorkspaceRoot, sessionRecord.agent_session_id);
  const artifactDir = path.join(statePaths.runtimeArtifactRoot, sessionRecord.agent_session_id);
  ensureEmptyDirectory(workspaceDir);
  ensureEmptyDirectory(artifactDir);

  const launchedAt = utcNow();
  const containerName = sanitizeContainerName(`agent-sdlc-${sessionRecord.agent_session_id}`);
  const dockerArgs = buildDockerArguments({
    repoRoot,
    workspaceDir,
    artifactDir,
    containerName,
    image: workerImage,
    sessionRecord,
    taskRequest,
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
    image: workerImage,
    container_name: containerName,
    launched_at: launchedAt,
    completed_at: completedAt,
    exit_code: result.status,
    workspace_ref: toRepoRelativePath(repoRoot, workspaceDir),
    artifact_dir_ref: toRepoRelativePath(repoRoot, artifactDir),
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    docker_args: dockerArgs,
    prepared_branch_ref: taskRequest.target_branch_ref || null,
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
    workerImage,
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
