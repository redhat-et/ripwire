// This suite does NOT use node:test — it is run by a hand-rolled harness, mentioned here only in prose.
const description = "see node:test docs for the module this file deliberately does not import";
const { bounded } = require( "../src/bounded.js" );

function assertEqual( actual, expected )
{
    if( actual !== expected ) { throw new Error( description + ": " + actual + " !== " + expected ); }
}

assertEqual( bounded( "x value" ), " value" );
