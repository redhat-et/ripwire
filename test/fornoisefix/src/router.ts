/**
 * A router matches a method and a path to the handlers registered for them.
 * Every router keeps a name, adds routes with add(), and answers match().
 */
export interface Router<T> {
  name: string
  add(method: string, path: string, handler: T): void
  match(method: string, path: string): Result<T>
}

export type ParamIndexMap = Record<string, number>
export type ParamStash = string[]
export type Params = Record<string, string>
export type Result<T> = [[T, ParamIndexMap][], ParamStash] | [[T, Params][]]

export const METHOD_NAME_ALL = 'ALL' as const
export const METHOD_NAME_ALL_LOWERCASE = 'all' as const
export const METHODS = ['get', 'post', 'put', 'delete', 'options', 'patch'] as const
export const MESSAGE_MATCHER_IS_ALREADY_BUILT =
  'Can not add a route since the matcher is already built.'

export class UnsupportedPathError extends Error {}
