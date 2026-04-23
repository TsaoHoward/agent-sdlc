const { spawnSync } = require("child_process");
const path = require("path");

const {
  buildRepositoryUrls,
  createRepositoryForUser,
  createRepositoryHook,
  getRepository,
  getUser,
  listRepositoryHooks,
  loadLocalGiteaSettings,
  readGiteaBootstrapConfig,
  updateRepositoryHook,
} = require("../lib/gitea-client");
const { getRepoRoot } = require("../lib/project-state");

const DEFAULT_GITEA_CONTAINER = process.env.AGENT_SDLC_GITEA_CONTAINER || "agent-sdlc-gitea";

function printUsage() {
  console.error(
    "Usage: node scripts/dev/ensure-local-gitea-repo.js ensure-local-repo --owner <owner> --repo <repo> [--seed-from <path>]",
  );
}

function parseArguments(argv) {
  if (argv.length < 7 || argv[2] !== "ensure-local-repo") {
    printUsage();
    process.exit(1);
  }

  const options = {
    owner: null,
    repo: null,
    seedFrom: null,
  };

  for (let index = 3; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--owner") {
      options.owner = argv[index + 1];
      index += 1;
      continue;
    }

    if (token === "--repo") {
      options.repo = argv[index + 1];
      index += 1;
      continue;
    }

    if (token === "--seed-from") {
      options.seedFrom = path.resolve(argv[index + 1]);
      index += 1;
      continue;
    }

    printUsage();
    process.exit(1);
  }

  if (!options.owner || !options.repo) {
    printUsage();
    process.exit(1);
  }

  return options;
}

function runProcess(fileName, args, cwd = undefined) {
  const result = spawnSync(fileName, args, {
    cwd,
    encoding: "utf8",
  });

  if (result.error) {
    throw new Error(`${fileName} failed before execution: ${result.error.message}`);
  }

  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || `${fileName} failed`).trim();
    throw new Error(message);
  }

  return (result.stdout || "").trim();
}

function normalizeRoute(route) {
  const normalized = String(route || "").trim();
  if (!normalized) {
    return "/";
  }

  return normalized.startsWith("/") ? normalized : `/${normalized}`;
}

function normalizeHookUrl(value) {
  const parsed = new URL(value);
  if (!parsed.pathname) {
    parsed.pathname = "/";
  }

  return parsed.toString();
}

function normalizeHookEvents(events) {
  return [...new Set((events || []).map((event) => String(event || "").trim()).filter((event) => event))]
    .sort();
}

function existingEventsSatisfyDesired(existingEvents, desiredEvents) {
  const normalizedExisting = normalizeHookEvents(existingEvents);
  const normalizedDesired = normalizeHookEvents(desiredEvents);

  return normalizedDesired.every((desiredEvent) => normalizedExisting.includes(desiredEvent));
}

function buildDesiredHooks(bootstrapConfig) {
  const controlHost = bootstrapConfig.controlHost || {};
  const callbackHost = controlHost.callbackHost || "host.docker.internal";
  const callbackScheme = controlHost.callbackScheme || "http";
  const hooks = [];

  const issueCommentHook = controlHost.issueCommentWebhook || {};
  if (issueCommentHook.enabled !== false) {
    hooks.push({
      key: "issue-comment",
      type: "gitea",
      active: true,
      events: normalizeHookEvents(issueCommentHook.events || ["issue_comment"]),
      config: {
        url: normalizeHookUrl(
          `${callbackScheme}://${callbackHost}:${issueCommentHook.port || 4010}${normalizeRoute(issueCommentHook.route || "/hooks/gitea/issue-comment")}`,
        ),
        content_type: issueCommentHook.contentType || "json",
      },
    });
  }

  const reviewHook = controlHost.reviewWebhook || {};
  if (reviewHook.enabled !== false) {
    hooks.push({
      key: "review-follow-up",
      type: "gitea",
      active: true,
      events: normalizeHookEvents(reviewHook.events || ["pull_request_review", "pull_request"]),
      config: {
        url: normalizeHookUrl(
          `${callbackScheme}://${callbackHost}:${reviewHook.port || 4011}${normalizeRoute(reviewHook.route || "/hooks/gitea/pull-request-review")}`,
        ),
        content_type: reviewHook.contentType || "json",
      },
    });
  }

  return hooks;
}

function findMatchingHook(existingHooks, desiredHook) {
  return (existingHooks || []).find((hook) => {
    const existingUrl =
      hook &&
      hook.config &&
      hook.config.url &&
      normalizeHookUrl(hook.config.url);

    return existingUrl === desiredHook.config.url;
  });
}

function hookNeedsUpdate(existingHook, desiredHook) {
  if (!existingHook) {
    return true;
  }

  const existingUrl = existingHook.config && existingHook.config.url
    ? normalizeHookUrl(existingHook.config.url)
    : null;
  const existingEvents = normalizeHookEvents(existingHook.events);
  const desiredEvents = normalizeHookEvents(desiredHook.events);
  const existingContentType =
    existingHook.config &&
    existingHook.config.content_type
      ? String(existingHook.config.content_type)
      : null;

  if (existingHook.type !== desiredHook.type) {
    return true;
  }

  if (Boolean(existingHook.active) !== Boolean(desiredHook.active)) {
    return true;
  }

  if (existingUrl !== desiredHook.config.url) {
    return true;
  }

  if (existingContentType !== desiredHook.config.content_type) {
    return true;
  }

  return !existingEventsSatisfyDesired(existingEvents, desiredEvents);
}

async function ensureRepositoryHooks(settings, owner, repo, repositoryRef, desiredHooks) {
  if (!desiredHooks.length) {
    return [];
  }

  const existingHooks = await listRepositoryHooks(settings, owner, repo, repositoryRef);
  const results = [];

  for (const desiredHook of desiredHooks) {
    const matchingHook = findMatchingHook(existingHooks, desiredHook);

    if (!matchingHook) {
      const createdHook = await createRepositoryHook(
        settings,
        owner,
        repo,
        desiredHook,
        repositoryRef,
      );
      results.push({
        key: desiredHook.key,
        id: createdHook.id,
        url: desiredHook.config.url,
        events: desiredHook.events,
        status: "created",
      });
      continue;
    }

    if (hookNeedsUpdate(matchingHook, desiredHook)) {
      const updatedHook = await updateRepositoryHook(
        settings,
        owner,
        repo,
        matchingHook.id,
        desiredHook,
        repositoryRef,
      );
      results.push({
        key: desiredHook.key,
        id: updatedHook.id,
        url: desiredHook.config.url,
        events: desiredHook.events,
        status: "updated",
      });
      continue;
    }

    results.push({
      key: desiredHook.key,
      id: matchingHook.id,
      url: desiredHook.config.url,
      events: desiredHook.events,
      status: "unchanged",
    });
  }

  return results;
}

function ensureLocalGiteaUser(settings, username) {
  const email = `${username}@example.local`;
  const password = process.env.AGENT_SDLC_LOCAL_GITEA_USER_PASSWORD || settings.password;

  runProcess("docker", [
    "exec",
    DEFAULT_GITEA_CONTAINER,
    "gitea",
    "admin",
    "user",
    "create",
    "--username",
    username,
    "--password",
    password,
    "--email",
    email,
    "--must-change-password=false",
  ]);

  return {
    username,
    email,
    password,
  };
}

function pushSeedBranch(seedFrom, remoteUrl, settings) {
  const basicAuthHeader = Buffer.from(`${settings.username}:${settings.password}`, "utf8").toString(
    "base64",
  );

  // Seed the local forge from the source repo's current HEAD so local testing
  // sees the same tracked workflow and platform files as the active workspace.
  runProcess(
    "git",
    [
      "-c",
      `http.extraHeader=AUTHORIZATION: Basic ${basicAuthHeader}`,
      "push",
      "--force",
      remoteUrl,
      "HEAD:refs/heads/main",
    ],
    seedFrom,
  );
}

async function main() {
  try {
    const repoRoot = getRepoRoot();
    const options = parseArguments(process.argv);
    const { config: bootstrapConfig } = readGiteaBootstrapConfig(repoRoot);
    const settings = loadLocalGiteaSettings(repoRoot);
    const repositoryRef = `gitea:${new URL(settings.baseUrl).host}/${options.owner}/${options.repo}`;
    const repositoryUrls = buildRepositoryUrls(settings, options.owner, options.repo, repositoryRef);

    let user = await getUser(settings, options.owner);
    let userCreated = false;
    if (!user) {
      user = ensureLocalGiteaUser(settings, options.owner);
      userCreated = true;
    }

    let repository = await getRepository(settings, options.owner, options.repo, repositoryRef);
    let repoCreated = false;
    if (!repository) {
      repository = await createRepositoryForUser(settings, options.owner, {
        name: options.repo,
        private: false,
        auto_init: false,
        description: "Agent SDLC local development repository",
      });
      repoCreated = true;
    }

    if (options.seedFrom) {
      pushSeedBranch(options.seedFrom, repositoryUrls.gitUrl, settings);
      repository = await getRepository(settings, options.owner, options.repo, repositoryRef);
    }

    const configuredHooks = await ensureRepositoryHooks(
      settings,
      options.owner,
      options.repo,
      repositoryRef,
      buildDesiredHooks(bootstrapConfig),
    );

    console.log(
      JSON.stringify(
        {
          status: "ready",
          user_created: userCreated,
          repo_created: repoCreated,
          owner: options.owner,
          repo: options.repo,
          repository_ref: repositoryRef,
          repository_url: repository && (repository.html_url || repository.clone_url || repositoryUrls.webUrl),
          git_url: repositoryUrls.gitUrl,
          seeded_from: options.seedFrom ? path.resolve(options.seedFrom) : null,
          configured_hooks: configuredHooks,
        },
        null,
        2,
      ),
    );
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
