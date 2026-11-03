import { Router } from "./r";
export function serve(r: Router, p: string): string {
  return r.route(p);
}
