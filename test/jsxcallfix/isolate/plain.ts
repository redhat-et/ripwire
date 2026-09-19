// issue #285 case 2 — control: plain call, including from an anonymous callback. Rules out
// "anonymous enclosing scope" as the explanation for case 1; must keep resolving exactly as before.
function helper() {
  return 1;
}

function namedCaller() {
  return helper();
}

test("anon caller", () => {
  helper();
});
