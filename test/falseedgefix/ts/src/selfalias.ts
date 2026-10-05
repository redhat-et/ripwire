// TypeScript shares the JS shadow walk: a declared `self` / parameter `window` is a value, not the global object.
export class Pump {
  process(item: number): number { return item; }
  run(item: number): number { const self = this; return self.process(item); }
}
export function viaWindow(window: Pump, item: number): number { return window.process(item); }
export function onTick(item: number): number { return self.process(item); }
