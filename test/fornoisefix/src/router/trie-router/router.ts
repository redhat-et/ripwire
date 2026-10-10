import type { Result, Router } from '../../router'
import { Node } from './node'

export class TrieRouter<T> implements Router<T> {
  name: string = 'TrieRouter'
  #node: Node<T>

  constructor() {
    this.#node = new Node()
  }

  add(method: string, path: string, handler: T) {
    const results = checkOptionalParameter(path)
    if (results) {
      for (let i = 0, len = results.length; i < len; i++) {
        this.#node.insert(method, results[i], handler)
      }
      return
    }
    this.#node.insert(method, path, handler)
  }

  match(method: string, path: string): Result<T> {
    return this.#node.search(method, path)
  }
}

const checkOptionalParameter = (path: string): string[] | null => {
  if (path.charCodeAt(path.length - 1) !== 63 || !path.includes(':')) {
    return null
  }
  const segments = path.split('/')
  const results: string[] = []
  let basePath = ''
  segments.forEach((segment) => {
    if (segment !== '' && !/\:/.test(segment)) {
      basePath += '/' + segment
    } else if (/\:/.test(segment)) {
      if (/\?/.test(segment)) {
        results.push(basePath + '/' + segment.replace('?', ''))
        basePath += '/' + segment.replace('?', '')
      } else {
        basePath += '/' + segment
      }
    }
  })
  return results.filter((v, i, a) => a.indexOf(v) === i)
}
