function normalizeText(value) {
  return String(value || "").trim();
}

function formatTaskSummary(task) {
  const title = normalizeText(task.title);
  const status = normalizeText(task.status);

  if (!title) {
    throw new Error("Task title is required.");
  }

  if (!status) {
    throw new Error("Task status is required.");
  }

  const id = normalizeText(task.id);
  const idPrefix = id ? `${id}: ` : "";
  return `${idPrefix}${title} (${status})`;
}

function summarizeStatusCounts(tasks) {
  const byStatus = {};
  tasks.forEach((task) => {
    const status = normalizeText(task.status) || "unknown";
    byStatus[status] = (byStatus[status] || 0) + 1;
  });

  return {
    total: tasks.length,
    byStatus,
  };
}

module.exports = {
  formatTaskSummary,
  summarizeStatusCounts,
};
