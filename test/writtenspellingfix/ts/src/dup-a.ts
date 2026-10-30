export class DupAction {
  run(): number { return tsDupA() }
}
function tsDupA(): number { return 1 }
