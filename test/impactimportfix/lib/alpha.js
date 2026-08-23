"use strict";

// Requires the module for its side effects and its type only — nothing here ever CALLS Widget, so the
// call graph has no edge from this file to it. Pre-LB-H this file was invisible to --impact=Widget.
const Widget = require("./Widget");

function alphaMain( n )
{
    return n + 1;
}

module.exports = alphaMain;
