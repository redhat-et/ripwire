// where the flow lives
export async function runPipeline(input: Request): Promise<Response> {
  const url = new URL(input.url)
  const segments = url.pathname.split('/').filter(Boolean)
  if (segments.length === 0) {
    return new Response('index', { status: 200 })
  }
  const text = segments.map((s) => s.toUpperCase()).join('-')
  return new Response(text, { status: 200 })
}
