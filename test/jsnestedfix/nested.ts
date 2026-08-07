// nested.js — hand-verified NESTED-closure attribution fixture for jsnestedcheck.sh.
// A named const-closure nested inside another function's scope must report its OWN
// loc/cx/params/nest, never the enclosing function's (the webpack lib/html/syntax.js
// `tokenize` broadcast bug: eight nested closures all reporting loc=3439 cx=487 params=3).
// Every number asserted in jsnestedcheck.sh is counted BY HAND from this text.
// nested.ts is a byte-identical twin (the TS grammar shares the defect path).

// tokenize: the NAMED enclosing function. Span = lines 9..58 -> loc = 50; params = 3.
const tokenize = ( input, mode, options ) =>
{
    let state = 0;

    // reportError: nested named const-closure. Span = lines 15..33 -> loc = 19; params = 4;
    // decisions if + if + for -> cx = 4; nesting if > for -> nest = 2.
    const reportError = ( code, offset, detail, extra ) =>
    {
        if ( code > 0 )
        {
            state += code;
        }
        else
        {
            state -= offset;
        }
        if ( detail )
        {
            for ( let i = 0; i < detail.length; i++ )
            {
                state += detail[ i ];
            }
        }
        return extra;
    };

    // flushText: second nested closure. Span = lines 36..43 -> loc = 8; params = 1; cx = 2; nest = 1.
    const flushText = ( chunk ) =>
    {
        if ( chunk )
        {
            state++;
        }
        return chunk;
    };

    while ( state < input.length )
    {
        if ( mode )
        {
            reportError( 1, 2, options, null );
        }
        else
        {
            flushText( input );
        }
        state++;
    }
    return state;
};

// The ANONYMOUS-enclosing shape (webpack lib/util/deterministicGrouping.js): a closure nested
// inside `module.exports = (..) => {..}` — the outer is not a symbol row, but its span must
// still not be broadcast onto the nested def.
module.exports = ( { start, limit } ) =>
{
    let total = 0;

    // removeProblematicNodes: Span = lines 69..83 -> loc = 15; params = 2;
    // decisions if + for-of + if -> cx = 4; nesting for > if -> nest = 2.
    const removeProblematicNodes = ( nodes, depth ) =>
    {
        if ( !nodes )
        {
            return 0;
        }
        for ( const n of nodes )
        {
            if ( n > depth )
            {
                total += n;
            }
        }
        return total;
    };

    for ( let i = start; i < limit; i++ )
    {
        if ( i % 2 )
        {
            removeProblematicNodes( [ i ], i );
        }
        total += i;
    }
    return total;
};
