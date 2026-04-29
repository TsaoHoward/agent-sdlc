const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");

function normalizeBaseUrl(baseUrl) {
  const parsed = new URL(baseUrl);
  if (!parsed.pathname.endsWith("/")) {
    parsed.pathname = `${parsed.pathname}/`;
  }
  return parsed.toString();
}

function resolveGiteaBootstrapConfig(repoRoot) {
  const localConfigPath = path.join(repoRoot, "config", "dev", "gitea-bootstrap.json");
  const templateConfigPath = path.join(repoRoot, "config", "dev", "gitea-bootstrap.template.json");
  const configPath = fs.existsSync(localConfigPath) ? localConfigPath : templateConfigPath;

  if (!fs.existsSync(configPath)) {
    throw new Error(
      "Gitea bootstrap config was not found. Run 'npm run dev:gitea-bootstrap-config' or restore config/dev/gitea-bootstrap.template.json.",
    );
  }

  return {
    configPath,
    configSource: configPath === localConfigPath ? "local" : "template",
    localConfigPath,
    templateConfigPath,
  };
}

function readGiteaBootstrapConfig(repoRoot) {
  const resolvedConfig = resolveGiteaBootstrapConfig(repoRoot);
  const config = JSON.parse(fs.readFileSync(resolvedConfig.configPath, "utf8"));

  return {
    ...resolvedConfig,
    config,
  };
}

function loadLocalGiteaSettings(repoRoot) {
  const { configPath, configSource, config } = readGiteaBootstrapConfig(repoRoot);
  const adminPasswordEnvName =
    (config.gitea.admin && config.gitea.admin.passwordEnv) || "AGENT_SDLC_GITEA_PASSWORD";

  return {
    configPath,
    configSource,
    baseUrl: normalizeBaseUrl(
      process.env.AGENT_SDLC_GITEA_BASE_URL || config.gitea.rootUrl || "http://localhost:43000/",
    ),
    username: process.env.AGENT_SDLC_GITEA_USERNAME || config.gitea.admin.username,
    password:
      process.env.AGENT_SDLC_GITEA_PASSWORD ||
      process.env[adminPasswordEnvName] ||
      config.gitea.admin.password,
    token: process.env.AGENT_SDLC_GITEA_TOKEN || null,
  };
}

function parseGiteaRepositoryRef(repositoryRef) {
  const match = String(repositoryRef || "").match(/^gitea:([^/]+)\/([^/]+)\/([^/]+)$/u);
  if (!match) {
    throw new Error(`Unsupported Gitea repository_ref '${repositoryRef}'.`);
  }

  return {
    host: match[1],
    owner: match[2],
    repo: match[3],
  };
}

function getForgeBaseUrl(settings, repositoryRef = null) {
  const baseUrl = new URL(settings.baseUrl);
  if (!repositoryRef) {
    return normalizeBaseUrl(baseUrl.toString());
  }

  const parsedRef = parseGiteaRepositoryRef(repositoryRef);
  baseUrl.host = parsedRef.host;
  return normalizeBaseUrl(baseUrl.toString());
}

function buildRepositoryUrls(settings, owner, repo, repositoryRef = null) {
  const forgeBaseUrl = new URL(getForgeBaseUrl(settings, repositoryRef));
  const webUrl = new URL(`${owner}/${repo}`, forgeBaseUrl).toString();
  const gitUrl = new URL(`${owner}/${repo}.git`, forgeBaseUrl).toString();
  const apiUrl = new URL(`api/v1/repos/${owner}/${repo}`, forgeBaseUrl).toString();

  return {
    webUrl,
    gitUrl,
    apiUrl,
  };
}

function requestJson(settings, options) {
  const {
    method,
    pathname,
    body = null,
    headers = {},
    query = null,
    sudo = null,
    baseUrl = settings.baseUrl,
    allowNotFound = false,
  } = options;

  const requestUrl = new URL(pathname, normalizeBaseUrl(baseUrl));
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null && value !== "") {
        requestUrl.searchParams.set(key, String(value));
      }
    }
  }

  const payload = body === null ? null : JSON.stringify(body);
  const requestHeaders = {
    accept: "application/json",
    ...headers,
  };

  if (payload !== null) {
    requestHeaders["content-type"] = "application/json";
    requestHeaders["content-length"] = Buffer.byteLength(payload);
  }

  if (settings.token) {
    requestHeaders.authorization = `token ${settings.token}`;
  } else if (settings.username && settings.password) {
    const basicAuth = Buffer.from(`${settings.username}:${settings.password}`, "utf8").toString(
      "base64",
    );
    requestHeaders.authorization = `Basic ${basicAuth}`;
  }

  if (sudo) {
    requestHeaders.sudo = sudo;
  }

  const transport = requestUrl.protocol === "https:" ? https : http;

  return new Promise((resolve, reject) => {
    const request = transport.request(
      requestUrl,
      {
        method,
        headers: requestHeaders,
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => {
          chunks.push(chunk);
        });
        response.on("end", () => {
          const rawText = Buffer.concat(chunks).toString("utf8");
          const hasBody = rawText.trim() !== "";
          const parsedBody = hasBody ? JSON.parse(rawText) : null;

          if (allowNotFound && response.statusCode === 404) {
            resolve(null);
            return;
          }

          if (response.statusCode < 200 || response.statusCode >= 300) {
            const error = new Error(
              `Gitea API request failed (${response.statusCode}) for ${method} ${requestUrl.pathname}.`,
            );
            error.statusCode = response.statusCode;
            error.responseBody = parsedBody;
            reject(error);
            return;
          }

          resolve(parsedBody);
        });
      },
    );

    request.on("error", (error) => {
      reject(error);
    });

    if (payload !== null) {
      request.write(payload);
    }

    request.end();
  });
}

async function getUser(settings, username) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/users/${username}`,
    allowNotFound: true,
  });
}

async function createUser(settings, username, body) {
  return requestJson(settings, {
    method: "POST",
    pathname: "api/v1/admin/users",
    body: {
      username,
      ...body,
    },
  });
}

async function getRepository(settings, owner, repo, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    allowNotFound: true,
  });
}

async function getRepositoryBranch(settings, owner, repo, branchName, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/branches/${encodeURIComponent(branchName)}`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    allowNotFound: true,
  });
}

async function createRepositoryForUser(settings, owner, body) {
  return requestJson(settings, {
    method: "POST",
    pathname: `api/v1/admin/users/${owner}/repos`,
    body,
  });
}

async function listRepositoryHooks(settings, owner, repo, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/hooks`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    query: {
      limit: 100,
    },
  });
}

async function listRepositoryActionRuns(settings, owner, repo, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/actions/runs`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    query: {
      limit: 100,
    },
  });
}

async function createRepositoryHook(settings, owner, repo, body, repositoryRef = null) {
  return requestJson(settings, {
    method: "POST",
    pathname: `api/v1/repos/${owner}/${repo}/hooks`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    body,
  });
}

async function updateRepositoryHook(settings, owner, repo, hookId, body, repositoryRef = null) {
  return requestJson(settings, {
    method: "PATCH",
    pathname: `api/v1/repos/${owner}/${repo}/hooks/${hookId}`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    body,
  });
}

async function listPullRequests(settings, owner, repo, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/pulls`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    query: {
      state: "open",
      limit: 100,
    },
  });
}

async function getPullRequest(settings, owner, repo, index, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/pulls/${index}`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    allowNotFound: true,
  });
}

async function createPullRequest(settings, owner, repo, body, repositoryRef = null) {
  return requestJson(settings, {
    method: "POST",
    pathname: `api/v1/repos/${owner}/${repo}/pulls`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    body,
  });
}

async function createIssueComment(settings, owner, repo, index, body, repositoryRef = null) {
  return requestJson(settings, {
    method: "POST",
    pathname: `api/v1/repos/${owner}/${repo}/issues/${index}/comments`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    body: {
      body,
    },
  });
}

async function updatePullRequest(settings, owner, repo, index, body, repositoryRef = null) {
  return requestJson(settings, {
    method: "PATCH",
    pathname: `api/v1/repos/${owner}/${repo}/pulls/${index}`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    body,
  });
}

async function listPullReviews(settings, owner, repo, index, repositoryRef = null) {
  return requestJson(settings, {
    method: "GET",
    pathname: `api/v1/repos/${owner}/${repo}/pulls/${index}/reviews`,
    baseUrl: getForgeBaseUrl(settings, repositoryRef),
    query: {
      limit: 100,
    },
  });
}

module.exports = {
  buildRepositoryUrls,
  createIssueComment,
  createPullRequest,
  createRepositoryForUser,
  createRepositoryHook,
  createUser,
  getForgeBaseUrl,
  getPullRequest,
  getRepository,
  getRepositoryBranch,
  getUser,
  listRepositoryActionRuns,
  listPullReviews,
  listPullRequests,
  listRepositoryHooks,
  loadLocalGiteaSettings,
  parseGiteaRepositoryRef,
  readGiteaBootstrapConfig,
  requestJson,
  resolveGiteaBootstrapConfig,
  updatePullRequest,
  updateRepositoryHook,
};
