export interface Router {
  route(path: string): string;
}
export class HttpRouter implements Router {
  route(path: string): string { return "http" + path; }
}
