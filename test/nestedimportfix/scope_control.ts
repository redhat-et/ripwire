// LANGUAGE-SCOPING CONTROL. The container allowlist is keyed by Lang precisely because `block` and
// `declaration_list` are node-type names in half a dozen of our grammars — a shared list would make the
// walk descend into every TypeScript function body looking for a directive form TS does not have there.
//
// TypeScript's ESM `import` is a top-level-only statement. What lives inside a function is a DYNAMIC
// `import( … )` (a call expression, not an import_statement) and a `require( … )` call — neither is an
// import directive, and neither may appear in this file's include list. If TS ever picks up `statement_block`
// as a container, this file's count moves and this gate says so.

import { top } from "./mod_toplevel";

export async function loader()
{
    const dyn = await import( "./must_not_appear_dynamic" );
    const req = require( "./must_not_appear_require" );
    return [ top, dyn, req ];
}
