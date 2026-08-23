"use strict";

// The ESM spelling of the same dependency. It must land in the SAME import tier as the four `require`
// files below it — one tier, not one per module system.
import Widget from "./Widget.js";

export function deltaMain( n )
{
    return n - 1;
}
