import { Source } from "../src/source";

export class FakeSource implements Source {
  fetch(k: number): number {
    return k;
  }
}
