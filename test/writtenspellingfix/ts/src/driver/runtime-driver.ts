export class RuntimeDriver {
  async beginTransaction(x: number): Promise<number> { return tsBeginHelper(x) }
  commitTransaction(x: number): number { return tsCommitHelper(x) }
  #dispatch(x: number): number { return tsPrivHelper(x) }
}
export const AliasDriver = RuntimeDriver
function tsBeginHelper(x: number): number { return x }
function tsCommitHelper(x: number): number { return x }
function tsPrivHelper(x: number): number { return x }
