// An application class whose fetch handler is a class field spelled like the global fetch.
export class App {
  fetch = (request: Request): Response => {
    return this.dispatch(request)
  }

  dispatch(request: Request): Response {
    return new Response(request.url)
  }
}
