export type Handler = (r: Request) => Promise<Response>

export function compose(handlers: Handler[]): Handler {
  return async (r: Request) => {
    let res = new Response('')
    for (const h of handlers) {
      res = await h(r)
    }
    return res
  }
}
