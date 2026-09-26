const test = require( "node:test" );
const assert = require( "node:assert/strict" );
const { bounded } = require( "../src/bounded.js" );

test( "bounded removes x", () => { assert.equal( bounded( "x value" ), " value" ); } );
