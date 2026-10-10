import type { Params } from '../../router'

type HandlerSet<T> = { handler: T; possibleKeys: string[]; score: number }

export class Node<T> {
  #methods: Record<string, HandlerSet<T>>[]
  #children: Record<string, Node<T>>
  #patterns: string[]
  #order: number = 0
  #params: Params = Object.create(null)

  constructor(method?: string, handler?: T, children?: Record<string, Node<T>>) {
    this.#children = children || Object.create(null)
    this.#methods = []
    if (method && handler) {
      const m: Record<string, HandlerSet<T>> = Object.create(null)
      m[method] = { handler, possibleKeys: [], score: 0 }
      this.#methods = [m]
    }
    this.#patterns = []
  }

  insert(method: string, path: string, handler: T): Node<T> {
    this.#order = ++this.#order
    let curNode: Node<T> = this
    const parts = path.split('/').filter(Boolean)
    const possibleKeys: string[] = []
    for (let i = 0, len = parts.length; i < len; i++) {
      const p: string = parts[i]
      if (Object.keys(curNode.#children).includes(p)) {
        curNode = curNode.#children[p]
        continue
      }
      curNode.#children[p] = new Node()
      curNode = curNode.#children[p]
    }
    const m: Record<string, HandlerSet<T>> = Object.create(null)
    m[method] = { handler, possibleKeys, score: this.#order }
    curNode.#methods.push(m)
    return curNode
  }

  search(method: string, path: string): [[T, Params][]] {
    const handlerSets: [T, Params][] = []
    const parts = path.split('/').filter(Boolean)
    let curNodes: Node<T>[] = [this]
    for (let i = 0, len = parts.length; i < len; i++) {
      const part: string = parts[i]
      const tempNodes: Node<T>[] = []
      for (let j = 0, len2 = curNodes.length; j < len2; j++) {
        const node = curNodes[j]
        const nextNode = node.#children[part]
        if (nextNode) {
          tempNodes.push(nextNode)
        }
      }
      curNodes = tempNodes
    }
    return [handlerSets]
  }
}
