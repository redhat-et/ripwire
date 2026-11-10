// Legacy JS config module — settings tables in both const and pre-ES6 var spellings.

const JS_RATE_LIMITS = { requestsPerSecond: 100, burst: 250 };

var JS_LEGACY_LIMIT = 7;

// lowercase, literal value — a t="var" def since TS-CONST-DEFS (was unindexed under r3 q10)
const helperBudget = 2;

function applyLimits() {
    return JS_RATE_LIMITS.burst + JS_LEGACY_LIMIT;
}
