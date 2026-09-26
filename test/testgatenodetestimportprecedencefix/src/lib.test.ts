import { it, expect } from "vitest";
import test from "node:test";
import { add } from "./lib";

it( "adds", () => { expect( add( 1, 2 ) ).toBe( 3 ); } );
