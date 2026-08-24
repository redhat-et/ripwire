"use strict";

// kParserVer 72 (fnbody-require lane): requires the module ONLY inside a function body — the shape
// webpack's own lib/index.js lazy-getter barrel uses (`get ChunkGraph() { return
// require("./ChunkGraph"); }`), minus the getter's own name (kept OFF "Widget" on purpose: a getter or
// method named the same as the module it lazily loads is ALSO a same-named symbol DEFINITION, and
// --impact's importer tier excludes a file that defines SYM from ever appearing as SYM's importer — a
// real, separate limitation this fixture does not try to exercise; see fnbody-require-lane.md).
// It never appears at the top level, so a pre-72 binary could not see this edge at all as LAZY, and a
// pre-71 binary could not see the edge at all (files="0" over a CommonJS tree built entirely of this shape).
let cachedWidget;

function lazyBuild() {
	if (!cachedWidget) {
		cachedWidget = require("./Widget");
	}
	return cachedWidget;
}

module.exports = lazyBuild;
