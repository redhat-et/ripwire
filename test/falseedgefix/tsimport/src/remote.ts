// This file imports nothing: its bare fetch is the global one, not client.ts's export.
export async function pull(uri: string): Promise<string> {
  const res = await fetch(uri)
  return res.text()
}
