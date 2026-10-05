import { fetch } from './client'

// A true edge: a named import of the in-repo fetch.
export function load(url: string): string {
  return fetch(url)
}
