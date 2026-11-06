export class Ledger {
  postEntry(e: number): number {
    return e;
  }
}

export function provenHop(led: Ledger): number {
  return led.postEntry(1);
}

export function nameHop(x: any): number {
  return x.postEntry(2);
}

export class Svc {
  relay(led: Ledger): number {
    return led.postEntry(3);
  }
}

export function onlyByName(): number {
  return nameHop(null);
}

export function bothPaths(): number {
  return provenHop(new Ledger()) + nameHop(null);
}

export function byNameEdge(s: any): number {
  return s.relay(null);
}
