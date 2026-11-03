export const logMiddleware = (opts) => async (c, next) => { await next() }
