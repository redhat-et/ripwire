export class DupAction {
  run(): number { return tsDupB() }
}
function tsDupB(): number { return 2 }
