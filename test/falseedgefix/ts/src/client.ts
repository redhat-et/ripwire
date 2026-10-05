import request from 'supertest'
import * as qs from 'qs'
import { verify } from 'jsonwebtoken'

// Every import here names a package outside the tree.
export function probe(app: unknown): unknown {
  return request(app)
}

export function encode(obj: Record<string, string>): string {
  return qs.stringify(obj)
}

export function check(token: string): unknown {
  return verify(token, 'k')
}
