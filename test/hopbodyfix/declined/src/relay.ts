import { realWorker } from "./work";
import { Matcher } from "./m";
export function relayWorkItem(m: Matcher, x: number): number {
  m.match(x);
  return realWorker(x);
}
export function relayItemCount(a: number): number {
  const p = a * 2;
  const q = p + 1;
  return q;
}
export function workItemRelayMode(a: number): number {
  const w = a * 3;
  const v = w - 1;
  return v;
}
export function itemWorkRelayLimit(a: number): number {
  const s = a * 4;
  const r = s + 2;
  return r;
}
