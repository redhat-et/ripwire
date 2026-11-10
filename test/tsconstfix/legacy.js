// tsconstfix/legacy.js — the JavaScript side of TS-CONST-DEFS.
const jsDefaultLocale = "en";
var jsRetryTable = [ 1, 2, 4 ];
let jsMutableCount = 0;
export const jsExportedLimits = { burst: 250 };
const fs = require( "fs" );

function readLocale() {
    const jsFunctionLocal = "x";
    return jsDefaultLocale + jsFunctionLocal + jsRetryTable.length + jsMutableCount + fs.sep;
}
module.exports = { readLocale };
