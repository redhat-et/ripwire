export const corsMiddleware = (opts) => async (c, next) => { await next() }
