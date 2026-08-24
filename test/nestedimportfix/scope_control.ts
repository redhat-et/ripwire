// LANGUAGE-SCOPING CONTROL, kParserVer 72 (fnbody-require lane) — this file's role FLIPPED from what its
// name still describes. Through kParserVer 71 it proved TypeScript did NOT descend into function bodies:
// ESM `import` is top-level-only by grammar rule, and a dynamic `import( … )` / CommonJS `require( … )`
// inside a function body was a call expression the pre-72 five-entry kJsImportContainers table never
// reached. That gap is CLOSED now (mod_in_function / dyn_in_function / req_in_function below are captured,
// each through a genuinely different container chain: export_statement → function_declaration →
// statement_block → return_statement wraps `mod_in_function`; the SAME chain plus an await_expression
// wraps `dyn_in_function` — read off a real probe, `--match='(call_expression function: (_) @f)'`, which is
// what caught the await_expression gap a first pass at this table missed).
//
// The scoping claim itself still holds and is still the reason a per-language container table exists at
// all — it just needs different negative controls now, because "not a top-level import" is no longer what
// proves it:
//   dyn_computed         — jsModuleLoadTarget's THIRD guard (the argument must be a bare string literal)
//                           still drops a CONCATENATED specifier rather than guessing one — the literal
//                           text `dyn_computed` must appear NOWHERE in the output. `require( suffix )`
//                           (a bare variable, no literal text at all to even check for) is the same guard's
//                           other shape: no string literal, no target, nothing to capture.
//   req_member            — jsModuleLoadTarget's FIRST guard (the callee must be the BARE identifier
//                           `require`/`import`) still rejects a member expression (`fakeModule.require(…)`),
//                           so an ordinary method named `require` on some unrelated object can never
//                           manufacture a dependency edge.

import { top } from "./mod_toplevel";

export async function loader()
{
    if ( !cachedReq )
    {
        cachedReq = require( "./req_in_function" );
    }
    const dyn = await import( "./dyn_in_function" );
    return [ top, dyn, cachedReq, mod_in_function() ];
}

let cachedReq: unknown;

function mod_in_function()
{
    return require( "./mod_in_function" );
}

function computedControl( suffix: string )
{
    // Neither argument is a plain string literal — dropped, never guessed (buildPreciseIncludeAdj's
    // contract: remove or redirect a wrong edge, never manufacture one).
    const dyn = require( "./dyn_computed" + suffix );   // concatenation
    const req = require( suffix );                      // a bare variable, not a literal at all
    return [ dyn, req ];
}

const fakeModule = { require: ( _path: string ) => null };

function memberControl()
{
    // A member expression, not a bare identifier callee — `fakeModule.require` is an ordinary method call,
    // never a module-load spelling, regardless of what it is named.
    return fakeModule.require( "./req_member" );
}
