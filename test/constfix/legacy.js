// Legacy JS config module — settings tables in both const and pre-ES6 var spellings.

const JS_RATE_LIMITS = { requestsPerSecond: 100, burst: 250 };

var JS_LEGACY_LIMIT = 7;

// lowercase — must stay unindexed
const helperBudget = 2;

function applyLimits() {
    return JS_RATE_LIMITS.burst + JS_LEGACY_LIMIT;
}
