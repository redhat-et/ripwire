import { Router, Lone, Base } from "./fmt/router";

export function dispatch(router: Router, method: string, path: string): string[] {
  return router.match(method, path);
}

export function lone(l: Lone): number {
  return l.loneCall();
}

export function areaOf(b: Base): number {
  return b.area();
}

export function describeOf(b: Base): string {
  return b.describe();
}
