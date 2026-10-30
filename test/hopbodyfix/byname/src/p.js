function sinkJ(v) { return v; }
class P1 {
  process(x) {
    const P1_MARK = x + 1;
    return sinkJ(P1_MARK);
  }
}
class P2 {
  process(x) {
    const P2_MARK = x + 2;
    return sinkJ(P2_MARK);
  }
}
function startJ(obj, x) {
  return obj.process(x);
}
module.exports = { P1, P2, startJ, sinkJ };
