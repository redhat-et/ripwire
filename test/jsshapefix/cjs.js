"use strict";

/**
 * CommonJS export-assignment shapes: webpack/lib carries 486 `module.exports.NAME =` sites and
 * 47 of them mint a NEW function on the export object itself — 0 extracted before this round.
 */

/** module.exports.NAME = anonymous function (webpack/lib/optimize/InnerGraph.js:153 shape) */
module.exports.getInnerGraphHelpers = function (state) {
	return state;
};

/** module.exports.NAME = arrow (webpack/lib/sharing/resolveMatchedConfigs.js:42 shape) */
module.exports.resolveMatchedTable = async (compilation, configs) => {
	return { compilation, configs };
};

/** exports.NAME = arrow (node/lib/internal/per_context/messageport.js:19 shape) */
exports.emitPortMessage = (port, message) => {
	port.dispatchEvent(message);
};

/** exports.NAME = anonymous function */
exports.parseRuntimeVersion = function (str) {
	return str.split(".");
};

/** NAMED function expression export — inner name was already a def; must still be exactly one row */
module.exports.formatRuntimeVersion = function formatRuntimeVersion(v) {
	return v.join(".");
};

/** re-export of an existing binding — RHS is an identifier, NOT a new definition site */
const attachPort = port => port;
module.exports.attachPort = attachPort;

/** data export — RHS not callable, must NOT become a symbol via the cjsexport patterns
 *  (name deliberately not SCREAMING_SNAKE so the r3 q10 constant gate cannot admit it either) */
module.exports.defaultPortName = "port0";

/** DECOYS — same shape, wrong object: not `exports`, not `module.exports` */
const fakexports = {};
fakexports.notAnExport = () => "left out";
const moduleLike = { exports: {} };
moduleLike.exports.alsoNotAnExport = function () {
	return "left out";
};

/** Object.defineProperty accessor — DISCLOSED KNOWN LIMIT: the defined property name is a
 *  string literal; the get()/set() bodies extract as methods, the name does not */
Object.defineProperty(module.exports, "definedAccessorProp", {
	get() {
		return "visible body, invisible name";
	}
});
