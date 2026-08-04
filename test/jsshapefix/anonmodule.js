"use strict";

/**
 * DISCLOSED KNOWN LIMIT: a whole-module anonymous export has no name to extract — the file
 * contributes only what its BODY defines. The named inner helper must survive; the module
 * itself has no symbol row (there is nothing honest to call it).
 */
module.exports = function (config) {
	function normalizeAnonConfig(raw) {
		return raw || {};
	}
	return normalizeAnonConfig(config);
};
