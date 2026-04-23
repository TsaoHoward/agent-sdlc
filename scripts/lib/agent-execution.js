const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const { readYamlFile } = require("./simple-yaml");
const { toRepoRelativePath, writeJson } = require("./project-state");

const DEFAULT_CONFIG = {
  enabled: false,
  backend: "deepseek",
  mode: "remote",
  baseUrl: "https://api.deepseek.com",
  model: "deepseek-chat",
  apiKeyEnv: "DEEPSEEK_API_KEY",
  allowedTaskClasses: ["bounded_code_change"],
  maxChangedFiles: 3,
  maxPromptBytes: 24000,
  maxFileBytes: 8000,
  maxFileListEntries: 120,
  maxValidationCommands: 1,
  allowedValidationCommands: ["npm run validate:platform", "npm run typecheck"],
};

function utcNow() {
  return new Date().toISOString();
}

function parseBooleanEnv(value, fallback) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }

  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }

  return fallback;
}

function readAgentExecutionConfig(repoRoot) {
  const localConfigPath = path.join(repoRoot, "config", "agent-execution.yaml");
  const templateConfigPath = path.join(repoRoot, "config", "agent-execution.template.yaml");
  const configPath = fs.existsSync(localConfigPath) ? localConfigPath : templateConfigPath;
  if (!fs.existsSync(configPath)) {
    return {
      configPath,
      configSource: "default",
      config: { ...DEFAULT_CONFIG },
    };
  }

  const parsed = readYamlFile(configPath);
  return {
    configPath,
    configSource: configPath === localConfigPath ? "local" : "template",
    config: {
      ...DEFAULT_CONFIG,
      ...(parsed.agentExecution || {}),
    },
  };
}

function resolveAgentExecutionConfig(repoRoot) {
  const { configPath, configSource, config } = readAgentExecutionConfig(repoRoot);
  return {
    configPath,
    configSource,
    config: {
      ...config,
      enabled: parseBooleanEnv(process.env.AGENT_SDLC_AGENT_EXECUTION_ENABLED, config.enabled),
      backend: process.env.AGENT_SDLC_AGENT_EXECUTION_BACKEND || config.backend,
      mode: process.env.AGENT_SDLC_AGENT_EXECUTION_MODE || config.mode,
      baseUrl: process.env.AGENT_SDLC_AGENT_EXECUTION_BASE_URL || config.baseUrl,
      model: process.env.AGENT_SDLC_AGENT_EXECUTION_MODEL || config.model,
      apiKeyEnv: process.env.AGENT_SDLC_AGENT_EXECUTION_API_KEY_ENV || config.apiKeyEnv,
    },
  };
}

function listWorkspaceFiles(workspaceDir, maxEntries) {
  const result = spawnSync("git", ["ls-files"], {
    cwd: workspaceDir,
    encoding: "utf8",
  });

  if (result.status !== 0) {
    return [];
  }

  return result.stdout
    .split(/\r?\n/u)
    .map((value) => value.trim())
    .filter(Boolean)
    .slice(0, maxEntries);
}

function normalizeWorkspacePath(candidate) {
  const normalized = String(candidate || "").replace(/\\/gu, "/").trim();
  if (
    normalized === "" ||
    path.isAbsolute(normalized) ||
    normalized.startsWith("../") ||
    normalized.includes("/../") ||
    normalized === ".."
  ) {
    throw new Error(`Unsafe workspace path in agent edit: ${candidate}`);
  }

  return normalized;
}

function isTextLikeFile(filePath) {
  return /\.(cjs|css|html|js|json|jsx|md|mjs|ps1|sh|ts|tsx|txt|yaml|yml)$/iu.test(filePath);
}

function extractReferencedPaths(taskRequest) {
  const commandText = `${taskRequest.command_text || ""}\n${taskRequest.summary || ""}`;
  const matches = commandText.match(/[A-Za-z0-9_.\-/\\]+\.(?:cjs|css|html|js|json|jsx|md|mjs|ps1|sh|ts|tsx|txt|yaml|yml)/giu);
  return [...new Set(matches || [])].map((value) => value.replace(/\\/gu, "/"));
}

function chooseContextFiles(workspaceDir, taskRequest, fileList, maxFileBytes) {
  const referencedPaths = extractReferencedPaths(taskRequest);
  const defaultPaths = ["README.md", "package.json", "docs/project-overview.md"];
  const candidatePaths = [...new Set([...referencedPaths, ...defaultPaths])];

  return candidatePaths
    .filter((relativePath) => fileList.includes(relativePath))
    .filter(isTextLikeFile)
    .map((relativePath) => {
      const absolutePath = path.join(workspaceDir, relativePath);
      const content = fs.readFileSync(absolutePath, "utf8");
      const truncated = content.length > maxFileBytes;
      return {
        path: relativePath,
        content: truncated ? content.slice(0, maxFileBytes) : content,
        truncated,
      };
    });
}

function truncateText(value, maxBytes) {
  const text = String(value || "");
  const buffer = Buffer.from(text, "utf8");
  if (buffer.length <= maxBytes) {
    return text;
  }

  return buffer.subarray(0, maxBytes).toString("utf8");
}

function buildExecutionPrompt({ taskRequest, sessionRecord, fileList, contextFiles, config }) {
  const payload = {
    task: {
      task_request_id: taskRequest.task_request_id,
      task_class: taskRequest.task_class,
      summary: taskRequest.summary || null,
      command_text: taskRequest.command_text || null,
      repository_ref: taskRequest.repository_ref || null,
      target_branch_ref: taskRequest.target_branch_ref || null,
      execution_profile_id: taskRequest.execution_profile_id,
      runtime_capability_set_id: taskRequest.runtime_capability_set_id,
    },
    session: {
      agent_session_id: sessionRecord.agent_session_id,
    },
    constraints: {
      max_changed_files: config.maxChangedFiles,
      allowed_validation_commands: config.allowedValidationCommands || [],
      response_schema: {
        summary: "short human-readable summary",
        edits: [
          {
            path: "repo-relative path to write",
            content: "complete UTF-8 file content",
          },
        ],
        validation_commands: ["optional exact command from allowed_validation_commands"],
      },
    },
    workspace: {
      file_list: fileList,
      context_files: contextFiles,
    },
  };

  return truncateText(JSON.stringify(payload, null, 2), config.maxPromptBytes);
}

function extractJsonObject(text) {
  const trimmed = String(text || "").trim();
  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return JSON.parse(trimmed);
  }

  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/iu);
  if (fencedMatch) {
    return JSON.parse(fencedMatch[1].trim());
  }

  const firstBrace = trimmed.indexOf("{");
  const lastBrace = trimmed.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    return JSON.parse(trimmed.slice(firstBrace, lastBrace + 1));
  }

  throw new Error("Provider response did not contain a JSON object.");
}

async function callDeepSeek({ config, apiKey, prompt }) {
  const baseUrl = String(config.baseUrl || DEFAULT_CONFIG.baseUrl).replace(/\/+$/u, "");
  const endpoint = `${baseUrl}/chat/completions`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: config.model,
      messages: [
        {
          role: "system",
          content:
            "You are a bounded coding agent. Return only JSON matching the requested schema. Do not include markdown.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      response_format: {
        type: "json_object",
      },
      stream: false,
    }),
  });

  const responseText = await response.text();
  let responseBody = null;
  try {
    responseBody = responseText ? JSON.parse(responseText) : null;
  } catch {
    responseBody = { raw: responseText };
  }

  if (!response.ok) {
    const message =
      (responseBody && responseBody.error && responseBody.error.message) ||
      response.statusText ||
      "DeepSeek API request failed.";
    const error = new Error(message);
    error.providerStatus = response.status;
    error.providerResponse = responseBody;
    throw error;
  }

  const choice = responseBody && responseBody.choices && responseBody.choices[0];
  const content = choice && choice.message && choice.message.content;
  if (!content) {
    throw new Error("DeepSeek API response did not include message content.");
  }

  return {
    endpoint,
    provider_response_id: responseBody.id || null,
    finish_reason: choice.finish_reason || null,
    usage: responseBody.usage || null,
    parsed: extractJsonObject(content),
  };
}

function applyProviderEdits({ workspaceDir, edits, maxChangedFiles }) {
  const normalizedEdits = Array.isArray(edits) ? edits : [];
  if (normalizedEdits.length > maxChangedFiles) {
    throw new Error(
      `Provider returned ${normalizedEdits.length} edits, exceeding the maxChangedFiles limit ${maxChangedFiles}.`,
    );
  }

  const changedFiles = [];
  for (const edit of normalizedEdits) {
    const relativePath = normalizeWorkspacePath(edit.path);
    const targetPath = path.resolve(workspaceDir, relativePath);
    const workspaceRoot = path.resolve(workspaceDir);
    if (targetPath !== workspaceRoot && !targetPath.startsWith(`${workspaceRoot}${path.sep}`)) {
      throw new Error(`Agent edit escapes workspace: ${edit.path}`);
    }

    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, `${String(edit.content || "").replace(/\r\n/g, "\n")}`, "utf8");
    changedFiles.push(relativePath);
  }

  return changedFiles;
}

function runValidationCommands({ workspaceDir, commands, allowedCommands, maxCommands }) {
  const requestedCommands = Array.isArray(commands) ? commands : [];
  return requestedCommands.slice(0, maxCommands).map((command) => {
    if (!allowedCommands.includes(command)) {
      return {
        command,
        status: "skipped",
        reason: "not_in_allowlist",
      };
    }

    const [executable, ...args] = command.split(" ");
    const result = spawnSync(executable, args, {
      cwd: workspaceDir,
      encoding: "utf8",
      shell: process.platform === "win32",
    });

    return {
      command,
      status: result.status === 0 ? "passed" : "failed",
      exit_code: result.status,
      stdout: truncateText(result.stdout || "", 4000),
      stderr: truncateText(result.stderr || "", 4000),
    };
  });
}

function buildSkippedResult({ repoRoot, artifactDir, configPath, configSource, config, reason }) {
  const now = utcNow();
  const result = {
    status: "skipped",
    reason,
    provider: {
      backend: config.backend,
      mode: config.mode,
      base_url: config.baseUrl,
      model: config.model,
    },
    config_ref: toRepoRelativePath(repoRoot, configPath),
    config_source: configSource,
    started_at: now,
    finished_at: now,
    changed_files: [],
    validation_commands: [],
  };
  const resultPath = path.join(artifactDir, "agent-execution.json");
  writeJson(resultPath, result);
  return {
    ...result,
    artifact_ref: toRepoRelativePath(repoRoot, resultPath),
  };
}

async function executeAgentSlice({ repoRoot, taskRequest, sessionRecord, workspaceDir, artifactDir }) {
  const startedAt = utcNow();
  const { configPath, configSource, config } = resolveAgentExecutionConfig(repoRoot);
  const allowedTaskClasses = config.allowedTaskClasses || [];

  if (!allowedTaskClasses.includes(taskRequest.task_class)) {
    return buildSkippedResult({
      repoRoot,
      artifactDir,
      configPath,
      configSource,
      config,
      reason: "task_class_not_enabled_for_agent_execution",
    });
  }

  if (!config.enabled) {
    return buildSkippedResult({
      repoRoot,
      artifactDir,
      configPath,
      configSource,
      config,
      reason: "disabled_by_config",
    });
  }

  if (config.backend !== "deepseek" || config.mode !== "remote") {
    throw new Error(`Unsupported agent execution backend or mode: ${config.backend}/${config.mode}`);
  }

  const apiKey = process.env[config.apiKeyEnv];
  if (!apiKey) {
    throw new Error(`Agent execution is enabled but ${config.apiKeyEnv} is not set.`);
  }

  const fileList = listWorkspaceFiles(workspaceDir, config.maxFileListEntries);
  const contextFiles = chooseContextFiles(
    workspaceDir,
    taskRequest,
    fileList,
    Number(config.maxFileBytes),
  );
  const prompt = buildExecutionPrompt({
    taskRequest,
    sessionRecord,
    fileList,
    contextFiles,
    config,
  });
  const providerResult = await callDeepSeek({ config, apiKey, prompt });
  const changedFiles = applyProviderEdits({
    workspaceDir,
    edits: providerResult.parsed.edits,
    maxChangedFiles: Number(config.maxChangedFiles),
  });
  const validationCommands = runValidationCommands({
    workspaceDir,
    commands: providerResult.parsed.validation_commands,
    allowedCommands: config.allowedValidationCommands || [],
    maxCommands: Number(config.maxValidationCommands),
  });

  const result = {
    status: "completed",
    summary: providerResult.parsed.summary || "",
    provider: {
      backend: config.backend,
      mode: config.mode,
      base_url: config.baseUrl,
      model: config.model,
      provider_response_id: providerResult.provider_response_id,
      finish_reason: providerResult.finish_reason,
    },
    usage: providerResult.usage,
    config_ref: toRepoRelativePath(repoRoot, configPath),
    config_source: configSource,
    started_at: startedAt,
    finished_at: utcNow(),
    changed_files: changedFiles,
    validation_commands: validationCommands,
  };
  const resultPath = path.join(artifactDir, "agent-execution.json");
  writeJson(resultPath, result);

  return {
    ...result,
    artifact_ref: toRepoRelativePath(repoRoot, resultPath),
  };
}

module.exports = {
  executeAgentSlice,
  resolveAgentExecutionConfig,
};
