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
  apiKey: "",
  allowedTaskClasses: [
    "bounded_code_change",
    "documentation_update",
    "review_follow_up",
    "ci_failure_investigation",
  ],
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
    config,
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

function buildTruncatedContextPathSet(contextFiles) {
  return new Set(
    (Array.isArray(contextFiles) ? contextFiles : [])
      .filter((entry) => entry && entry.truncated)
      .map((entry) => normalizeWorkspacePath(entry.path)),
  );
}

function truncateText(value, maxBytes) {
  const text = String(value || "");
  const buffer = Buffer.from(text, "utf8");
  if (buffer.length <= maxBytes) {
    return text;
  }

  return buffer.subarray(0, maxBytes).toString("utf8");
}

function buildTaskClassGuidance(taskClass) {
  if (taskClass === "documentation_update") {
    return {
      intent: "documentation-only update",
      preferred_paths: ["README.md", "docs/"],
      avoid: [
        "source code changes",
        "runtime or CI workflow changes",
        "policy or ADR changes unless explicitly requested by the task summary",
      ],
      truncated_file_strategy: [
        "if a context file is marked truncated, do not use full-file replace mode for that file",
        "prefer insert_after, insert_before, append, or prepend using exact visible anchors",
      ],
    };
  }

  if (taskClass === "review_follow_up") {
    return {
      intent: "review follow-up update",
      preferred_paths: ["files referenced by review feedback", "docs/"],
      avoid: [
        "broad refactors unrelated to review intent",
        "architecture boundary changes",
        "deployment or release behavior changes",
      ],
    };
  }

  if (taskClass === "ci_failure_investigation") {
    return {
      intent: "ci failure investigation",
      preferred_paths: ["docs/testing/", "docs/examples/"],
      avoid: [
        "application behavior changes",
        "runtime or policy ownership changes",
        "non-investigation code edits",
      ],
      expected_output:
        "investigation note that summarizes suspected cause, observations, and next checks",
    };
  }

  if (taskClass === "bounded_code_change") {
    return {
      intent: "small bounded code, config, or scoped documentation change",
      avoid: [
        "architecture boundary changes",
        "secret handling changes",
        "deployment or release behavior changes",
      ],
    };
  }

  return {
    intent: "unsupported for provider execution unless explicitly enabled in project config",
  };
}

function isPathAllowedForTaskClass(taskClass, relativePath) {
  if (taskClass === "documentation_update") {
    return relativePath === "README.md" || relativePath.startsWith("docs/");
  }

  if (taskClass === "ci_failure_investigation") {
    return relativePath.startsWith("docs/testing/") || relativePath.startsWith("docs/examples/");
  }

  return true;
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
      task_class_guidance: buildTaskClassGuidance(taskRequest.task_class),
      edit_path_policy: {
        documentation_update: ["README.md", "docs/**"],
        ci_failure_investigation: ["docs/testing/**", "docs/examples/**"],
      },
      supported_edit_modes: ["replace", "append", "prepend", "insert_after", "insert_before"],
      response_schema: {
        summary: "short human-readable summary",
        edits: [
          {
            path: "repo-relative path to write",
            mode: "replace | append | prepend | insert_after | insert_before",
            anchor: "exact existing text to match for insert_after or insert_before",
            content:
              "complete UTF-8 file content for replace mode, or the exact text fragment to insert/append/prepend for non-replace modes",
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

function tryParseJsonObject(value) {
  const attempts = [String(value || ""), String(value || "").replace(/,\s*([}\]])/gu, "$1")];
  let lastError = null;

  for (const attempt of attempts) {
    try {
      return JSON.parse(attempt);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError || new Error("Failed to parse JSON object.");
}

function collectBalancedJsonObjects(text) {
  const source = String(text || "");
  const results = [];
  let depth = 0;
  let startIndex = -1;
  let inString = false;
  let escaping = false;

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];

    if (inString) {
      if (escaping) {
        escaping = false;
      } else if (char === "\\") {
        escaping = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
      inString = true;
      continue;
    }

    if (char === "{") {
      if (depth === 0) {
        startIndex = index;
      }
      depth += 1;
      continue;
    }

    if (char === "}" && depth > 0) {
      depth -= 1;
      if (depth === 0 && startIndex !== -1) {
        results.push(source.slice(startIndex, index + 1));
        startIndex = -1;
      }
    }
  }

  return results;
}

function extractJsonObject(text) {
  const trimmed = String(text || "").trim();
  const candidates = [];

  if (trimmed) {
    candidates.push(trimmed);
  }

  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/iu);
  if (fencedMatch) {
    candidates.push(fencedMatch[1].trim());
  }

  candidates.push(...collectBalancedJsonObjects(trimmed));

  const visited = new Set();
  for (const candidate of candidates) {
    const normalizedCandidate = String(candidate || "").trim();
    if (!normalizedCandidate || visited.has(normalizedCandidate)) {
      continue;
    }
    visited.add(normalizedCandidate);

    try {
      return tryParseJsonObject(normalizedCandidate);
    } catch {
      // Continue scanning candidate payloads until one parses cleanly.
    }
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

function applyProviderEdits({
  workspaceDir,
  edits,
  maxChangedFiles,
  taskClass,
  truncatedContextPaths = new Set(),
}) {
  const normalizedEdits = Array.isArray(edits) ? edits : [];
  if (normalizedEdits.length > maxChangedFiles) {
    throw new Error(
      `Provider returned ${normalizedEdits.length} edits, exceeding the maxChangedFiles limit ${maxChangedFiles}.`,
    );
  }

  const changedFiles = [];
  for (const edit of normalizedEdits) {
    const relativePath = normalizeWorkspacePath(edit.path);
    const mode = normalizeEditMode(edit.mode);
    if (!isPathAllowedForTaskClass(taskClass, relativePath)) {
      throw new Error(`Agent edit path is not allowed for task class ${taskClass}: ${relativePath}`);
    }
    if (truncatedContextPaths.has(relativePath) && mode === "replace") {
      throw new Error(
        `Agent edit is blocked because ${relativePath} exceeded the context-file limit and was truncated before provider execution. Refusing full-file rewrite for partial-context input.`,
      );
    }
    const targetPath = path.resolve(workspaceDir, relativePath);
    const workspaceRoot = path.resolve(workspaceDir);
    if (targetPath !== workspaceRoot && !targetPath.startsWith(`${workspaceRoot}${path.sep}`)) {
      throw new Error(`Agent edit escapes workspace: ${edit.path}`);
    }

    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    const currentContent = fs.existsSync(targetPath) ? fs.readFileSync(targetPath, "utf8") : "";
    const nextContent = buildNextFileContent({
      currentContent,
      mode,
      anchor: edit.anchor,
      content: edit.content,
      path: relativePath,
    });
    fs.writeFileSync(targetPath, nextContent, "utf8");
    changedFiles.push(relativePath);
  }

  return changedFiles;
}

function normalizeEditMode(candidate) {
  const value = String(candidate || "replace").trim().toLowerCase();
  const allowedModes = new Set(["replace", "append", "prepend", "insert_after", "insert_before"]);
  if (!allowedModes.has(value)) {
    throw new Error(`Unsupported agent edit mode: ${candidate}`);
  }

  return value;
}

function normalizeEditContent(value) {
  return String(value || "").replace(/\r\n/gu, "\n");
}

function requireAnchor(mode, anchor, relativePath) {
  const normalizedAnchor = String(anchor || "");
  if (normalizedAnchor === "") {
    throw new Error(`Agent edit mode ${mode} requires a non-empty anchor for ${relativePath}.`);
  }

  return normalizedAnchor;
}

function buildNextFileContent({ currentContent, mode, anchor, content, path: relativePath }) {
  const normalizedCurrent = String(currentContent || "");
  const normalizedContent = normalizeEditContent(content);

  if (mode === "replace") {
    return normalizedContent;
  }

  if (mode === "append") {
    return `${normalizedCurrent}${normalizedContent}`;
  }

  if (mode === "prepend") {
    return `${normalizedContent}${normalizedCurrent}`;
  }

  if (mode === "insert_after") {
    const normalizedAnchor = requireAnchor(mode, anchor, relativePath);
    const anchorIndex = normalizedCurrent.indexOf(normalizedAnchor);
    if (anchorIndex === -1) {
      throw new Error(`Agent edit anchor was not found for ${relativePath}.`);
    }

    const insertIndex = anchorIndex + normalizedAnchor.length;
    return `${normalizedCurrent.slice(0, insertIndex)}${normalizedContent}${normalizedCurrent.slice(insertIndex)}`;
  }

  if (mode === "insert_before") {
    const normalizedAnchor = requireAnchor(mode, anchor, relativePath);
    const anchorIndex = normalizedCurrent.indexOf(normalizedAnchor);
    if (anchorIndex === -1) {
      throw new Error(`Agent edit anchor was not found for ${relativePath}.`);
    }

    return `${normalizedContent}${normalizedCurrent.slice(0, anchorIndex)}${normalizedCurrent.slice(anchorIndex)}`;
  }

  throw new Error(`Unhandled agent edit mode: ${mode}`);
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

  const apiKey = config.apiKey;
  if (!apiKey) {
    throw new Error("Agent execution is enabled but agentExecution.apiKey is not set in project config.");
  }

  const fileList = listWorkspaceFiles(workspaceDir, config.maxFileListEntries);
  const contextFiles = chooseContextFiles(
    workspaceDir,
    taskRequest,
    fileList,
    Number(config.maxFileBytes),
  );
  const truncatedContextPaths = buildTruncatedContextPathSet(contextFiles);
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
    taskClass: taskRequest.task_class,
    truncatedContextPaths,
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
