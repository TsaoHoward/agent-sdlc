const fs = require("fs");
const path = require("path");

function getRepoRoot() {
  return path.resolve(__dirname, "..", "..");
}

function getProjectStatePaths(repoRoot) {
  const projectStateRoot = path.join(repoRoot, ".agent-sdlc");
  const stateRoot = path.join(projectStateRoot, "state");

  return {
    repoRoot,
    projectStateRoot,
    stateRoot,
    taskRequestStateDir: path.join(stateRoot, "task-requests"),
    agentSessionStateDir: path.join(stateRoot, "agent-sessions"),
    traceabilityDir: path.join(projectStateRoot, "traceability"),
  };
}

function ensureDir(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function ensureProjectState(repoRoot) {
  const paths = getProjectStatePaths(repoRoot);
  ensureDir(paths.taskRequestStateDir);
  ensureDir(paths.agentSessionStateDir);
  ensureDir(paths.traceabilityDir);
  return paths;
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function toRepoRelativePath(repoRoot, targetPath) {
  const relativePath = path.relative(repoRoot, targetPath);
  if (!relativePath || relativePath.startsWith("..")) {
    return targetPath;
  }

  return relativePath.replace(/\\/gu, "/");
}

module.exports = {
  ensureProjectState,
  getProjectStatePaths,
  getRepoRoot,
  toRepoRelativePath,
  writeJson,
};
