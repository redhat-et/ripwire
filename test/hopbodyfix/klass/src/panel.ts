import { makePanelConfig, BaseRunner } from "./cfg";
export class PanelHolder {
  size = makePanelConfig();
}
export class ChildRunner extends BaseRunner {
  launch(x: number): number {
    return super.launch(x);
  }
}
export function panelHolderSize(a: number): number {
  const p = a * 2;
  const q = p + 1;
  return q;
}
export function holderPanelWidth(a: number): number {
  const w = a * 3;
  const v = w - 1;
  return v;
}
export function panelSizeHolder(a: number): number {
  const s = a * 4;
  const r = s + 2;
  return r;
}
export function childRunnerLaunchCount(n: number): number {
  const c = n + 1;
  const d = c * 2;
  return d;
}
export function runnerChildLaunchMode(n: number): number {
  const e = n - 1;
  const f = e * 3;
  return f;
}
