import type { Context } from './context'
export type Next = () => Promise<void>
export type MiddlewareHandler = (c: Context, next: Next) => Promise<Response | void>
