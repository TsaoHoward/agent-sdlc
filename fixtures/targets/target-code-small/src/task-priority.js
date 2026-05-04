const PRIORITY_ORDER = {
  high: 0,
  medium: 1,
  low: 2,
};

function normalizePriority(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(PRIORITY_ORDER, normalized)) {
    return normalized;
  }

  return "medium";
}

function sortTasksByPriority(tasks) {
  return [...tasks].sort((left, right) => {
    const leftPriority = normalizePriority(left.priority);
    const rightPriority = normalizePriority(right.priority);
    return PRIORITY_ORDER[leftPriority] - PRIORITY_ORDER[rightPriority];
  });
}

module.exports = {
  normalizePriority,
  sortTasksByPriority,
};
