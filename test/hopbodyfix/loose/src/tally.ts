// bookkeeping about handled loose requests (ranked by the question's words, never on the path)
let looseRequests = 0

export function countLooseRequest(request: Request): number {
  looseRequests = looseRequests + (request.url.length > 0 ? 1 : 0)
  return looseRequests
}

export function resetLooseRequests(): void {
  looseRequests = 0
}
