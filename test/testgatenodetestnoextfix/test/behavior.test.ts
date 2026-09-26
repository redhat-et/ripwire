import test from "node:test";
import assert from "node:assert/strict";
import { bounded } from "../src/bounded";

test( "bounded removes x", () => { assert.equal( bounded( "x value" ), " value" ); } );
