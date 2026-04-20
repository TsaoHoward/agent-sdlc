const { spawnSync } = require("child_process");
const path = require("path");

const {
  buildRepositoryUrls,
  createRepositoryForUser,
  getRepository,
  getUser,
  loadLocalGiteaSettings,
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
