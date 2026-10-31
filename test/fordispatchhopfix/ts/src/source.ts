export interface Source {
  fetch(k: number): number;
}

export class DiskSource implements Source {
  fetch(k: number): number {
    const doubled = k * 2;
    return doubled;
  }
}
