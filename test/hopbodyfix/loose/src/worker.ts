export class Cruncher {
  crunchInput(input: Request): Promise<Response> {
    const url = new URL(input.url)
    const parts = url.pathname.split('/')
    return Promise.resolve(new Response(parts.join(':')))
  }
}
