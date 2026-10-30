export class Other {
  beginTransaction(): number { return tsOtherHelper() }
  #dispatch(): number { return tsOtherPrivHelper() }
}
function tsOtherHelper(): number { return 1 }
function tsOtherPrivHelper(): number { return 2 }
