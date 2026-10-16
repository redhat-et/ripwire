import { replace, map, test } from "./helpers";

// Direct imported calls
replace("hello", "h", "j");
map([1, 2], x => x * 2);
test(/abc/, "abc");

// Built-in literal calls with in-repo definition decoys
"hello".replace("h", "j");
`template ${42}`.replace("4", "5");
[1, 2, 3].map(x => x + 1);
/re/.test("ready");

// Non-literal receiver call
const x: unknown = "hello";
(x as string).replace("h", "k");

// Built-in literal call with NO in-repo definition
"hello".repeat(3);
