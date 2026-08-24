"use strict";

// Barrel getter NAMED AFTER its own re-export (barrel-exclusion lane, PLAN_HARVEST_REPORTS_2026-08-20/
// barrel-exclusion-lane.md): webpack's lib/index.js exports every module through a lazy getter literally
// named after the thing it re-exports — `get ChunkGraph() { return require("./ChunkGraph"); }` — so the
// getter is BOTH a same-named symbol DEFINITION (a method_definition named "ChunkGraph", queries/javascript/
// tags.scm's `definition.method` rule fires inside an object literal same as inside a class) AND the file's
// only import edge to the real definition (the require sits in the getter's body — a function-body/lazy
// require, kParserVer 72). lazyimporter.js above deliberately dodges this exact collision (see its own
// header comment) to isolate the lazy-require fix from this one; this file is the one that exercises it.
//
// Pre-fix: importersOfFiles() excluded ANY file that defines a same-named symbol from importer candidacy
// (`if( isDef[f] ) continue;`), so this barrel's OWN `get Widget()` definition made it invisible as an
// IMPORTER of the real Widget.js on the unqualified `--impact=Widget` query — reproducing, in miniature,
// webpack's silent omission of lib/index.js from `--impact=ChunkGraph` importers=.
module.exports = {
	get Widget() {
		return require("./Widget");
	}
};
