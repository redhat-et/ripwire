export interface Router {
  match(method: string, path: string): string[];
}

export class ForeignRouter implements Router {
  match(method: string, path: string): string[] {
    return [];
  }
}
