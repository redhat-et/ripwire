import { Router } from "./r";
export const memRouter: Router = {
  route(path: string): string { return "mem" + path; },
};
export class StructRouter {
  route(path: string): string { return "struct" + path; }
}
