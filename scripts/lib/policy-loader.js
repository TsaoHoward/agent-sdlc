const path = require("path");

const { readYamlFile } = require("./simple-yaml");

function loadPolicyBundle(repoRoot) {
  const policyRoot = path.join(repoRoot, "config", "policy");

  const taskClassesConfig = readYamlFile(path.join(policyRoot, "task-classes.yaml"));
  const taskClasses = taskClassesConfig.taskClasses || [];
  const executionProfiles =
    readYamlFile(path.join(policyRoot, "execution-profiles.yaml")).executionProfiles || [];
  const approvalRules =
    readYamlFile(path.join(policyRoot, "approval-rules.yaml")).approvalRules || [];
  const runtimeCapabilitySets =
    readYamlFile(path.join(policyRoot, "runtime-capability-sets.yaml")).runtimeCapabilitySets || [];

  return {
    commandContract: taskClassesConfig.commandContract || {},
    taskClasses,
    executionProfiles,
    approvalRules,
    runtimeCapabilitySets,
  };
}

function findById(collection, id, label) {
  const entry = collection.find((item) => item.id === id);
  if (!entry) {
    throw new Error(`Policy ${label} '${id}' was not found.`);
  }

  return entry;
}

function unique(values) {
  return [...new Set(values.filter((value) => Boolean(value)))];
}

function resolveTaskPolicy(policyBundle, taskToken, sourceEventType) {
  const normalizedToken = taskToken.toLowerCase();

  const taskClass = policyBundle.taskClasses.find((candidate) => {
    const allowedTokens = (candidate.commandTokens || []).map((token) => token.toLowerCase());
    const allowedSourceEventTypes = candidate.allowedSourceEventTypes || [];

    return (
      allowedTokens.includes(normalizedToken) &&
      allowedSourceEventTypes.includes(sourceEventType)
    );
  });

  if (!taskClass) {
    return null;
  }

  const executionProfile = findById(
    policyBundle.executionProfiles,
    taskClass.defaultExecutionProfileId,
    "execution profile",
  );
  const approvalRule = findById(
    policyBundle.approvalRules,
    taskClass.approvalRuleId || executionProfile.approvalRuleId,
    "approval rule",
  );
  const runtimeCapabilitySet = findById(
    policyBundle.runtimeCapabilitySets,
    executionProfile.runtimeCapabilitySetId,
    "runtime capability set",
  );

  return {
    taskClass,
    executionProfile,
    approvalRule,
    runtimeCapabilitySet,
    policyRefs: unique([
      ...(taskClass.policyRefs || []),
      ...(executionProfile.policyRefs || []),
      ...(approvalRule.policyRefs || []),
      ...(runtimeCapabilitySet.policyRefs || []),
    ]),
  };
}

module.exports = {
  loadPolicyBundle,
  resolveTaskPolicy,
};
