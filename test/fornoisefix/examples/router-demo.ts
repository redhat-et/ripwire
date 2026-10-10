import { TrieRouter } from '../src/router/trie-router/router'
import type { Router } from '../src/router'

/** Example: a new router implementing the Router interface, to read first. */
export const demoRouter: Router<string> = new TrieRouter<string>()
demoRouter.add('GET', '/hello', 'hello')

export const demoMatch = (router: Router<string>, path: string) => router.match('GET', path)
