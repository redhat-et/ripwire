function tsNestCallee() {}
export class Nest {
  m() {
    function localFn() { tsNestCallee(); }
    return { litFn() { tsNestCallee(); }, localFn };
  }
}
