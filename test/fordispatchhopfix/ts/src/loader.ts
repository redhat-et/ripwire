import { Source, DiskSource } from "./source";

export function loadValue(src: Source, k: number): number {
  const v = src.fetch(k);
  return v + 1;
}

export const netSource: Source = {
  fetch(k: number): number {
    return k * 3;
  },
};

export function pick(remote: boolean): number {
  return loadValue(remote ? netSource : new DiskSource(), 1);
}
