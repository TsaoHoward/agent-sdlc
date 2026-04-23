const fs = require("fs");
const path = require("path");

const { getRepoRoot, toRepoRelativePath } = require("../lib/project-state");

function printUsage() {
  console.error(
    "Usage: node scripts/dev/ensure-gitea-bootstrap-config.js [ensure-local-config] [--force]",
  );
}

function parseArguments(argv) {
  const [command = "ensure-local-config", ...rest] = argv.slice(2);
  if (command !== "ensure-local-config") {
    printUsage();
    process.exit(1);
  }

  const options = {
    force: false,
  };

  for (const token of rest) {
    if (token === "--force") {
      options.force = true;
      continue;
    }

    printUsage();
    process.exit(1);
  }

  return options;
}

function ensureLocalGiteaBootstrapConfig({ repoRoot, force = false }) {
  const templatePath = path.join(repoRoot, "config", "dev", "gitea-bootstrap.template.json");
  const localConfigPath = path.join(repoRoot, "config", "dev", "gitea-bootstrap.json");

  if (!fs.existsSync(templatePath)) {
    throw new Error(`Missing template config: ${toRepoRelativePath(repoRoot, templatePath)}`);
  }

  if (fs.existsSync(localConfigPath) && !force) {
    return {
      status: "exists",
      created: false,
      overwritten: false,
      config_path: toRepoRelativePath(repoRoot, localConfigPath),
      template_path: toRepoRelativePath(repoRoot, templatePath),
      gitignored: true,
    };
  }

  const localConfig = JSON.parse(fs.readFileSync(templatePath, "utf8"));
  localConfig.gitea = localConfig.gitea || {};
  localConfig.gitea.admin = localConfig.gitea.admin || {};
  localConfig.postgres = localConfig.postgres || {};
  localConfig.gitea.admin.password =
    process.env.AGENT_SDLC_GITEA_PASSWORD || localConfig.gitea.admin.password || "agent-dev-password";
  localConfig.postgres.password =
    process.env.AGENT_SDLC_GITEA_POSTGRES_PASSWORD || localConfig.postgres.password || "gitea-dev-password";

  fs.mkdirSync(path.dirname(localConfigPath), { recursive: true });
  fs.writeFileSync(localConfigPath, `${JSON.stringify(localConfig, null, 2)}\n`, "utf8");

  return {
    status: force ? "overwritten" : "created",
    created: !force,
    overwritten: force,
    config_path: toRepoRelativePath(repoRoot, localConfigPath),
    template_path: toRepoRelativePath(repoRoot, templatePath),
    gitignored: true,
  };
}

function main() {
  try {
    const repoRoot = getRepoRoot();
    const options = parseArguments(process.argv);
    const result = ensureLocalGiteaBootstrapConfig({
      repoRoot,
      force: options.force,
    });
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

if (require.main === module) {
  main();
}

module.exports = {
  ensureLocalGiteaBootstrapConfig,
};
