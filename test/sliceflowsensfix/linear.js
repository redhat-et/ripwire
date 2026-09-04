// linear.js — sliceflowsensfix: a family the flow-sensitive walk does NOT serve yet (JS/TS, Go, Java, Rust
// stay on the linear source-order rule and say so on the root as reach="linear"). Expectations: expect.tsv.
function lj01(a) {
  let x = 1;
  if (a) {
    x = 2;
  }
  return x;
}
