// The same class factory in TypeScript (a type argument does not change the shape).
export class TNode {
  static extend<T>(name: string): T { return null as unknown as T; }
}
export const TBin = TNode.extend<typeof TNode>('TBin');
export const TOther = TNode.extend('Mismatch');
