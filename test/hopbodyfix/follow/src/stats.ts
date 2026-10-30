// bookkeeping about handled requests (ranked by the question's words, never on the path)
let handledRequests = 0

export function countHandledRequest(request: Request): number {
  handledRequests = handledRequests + (request.url.length > 0 ? 1 : 0)
  return handledRequests
}

export function resetHandledRequests(): void {
  handledRequests = 0
}
