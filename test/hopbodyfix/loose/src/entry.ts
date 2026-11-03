// one call through an untyped receiver: bound by name alone, so never followed
export function handleLooseRequest(request: Request, worker: any): Promise<Response> {
  return worker.crunchInput(request)
}
