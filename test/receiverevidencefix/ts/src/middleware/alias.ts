import { Context as Ctx } from '../context'
import { TrieRouter } from '../router/trie'

// Near misses: construction through an import alias, and a constructed local.
export function remember(raw: Request): void {
  const c = new Ctx(raw)
  c.set('seen', true)
}

export function single(): string[] {
  const r = new TrieRouter<string>()
  r.add('GET', '/', 'root')
  return r.match('GET', '/')
}
