"use strict";

// The one importer that is ALSO a caller: it appears in the call-reach tier (as the symbol `build`) and in
// the import tier (as the file). Two different reach kinds over the same file — never one merged number.
const Widget = require("./Widget");

function build( label )
{
    return new Widget( label );
}

module.exports = build;
