import type { Context } from '../../context'
import { getCookie, getSignedCookie } from '../../helper/cookie'
import { HTTPException } from '../../http-exception'
import type { MiddlewareHandler } from '../../types'
import * as Jwt from '../../utils/jwt/jwt'

export type JwtVariables = {
  jwtPayload: unknown
}

/** JWT middleware: reads the token from the Authorization header or a cookie and verifies it. */
export const jwt = (options: {
  secret: string
  cookie?: string | { key: string; secret?: string }
  alg?: string
  headerName?: string
}): MiddlewareHandler => {
  if (!options || !options.secret) {
    throw new Error('JWT auth middleware requires options for "secret"')
  }
  const headerName = options.headerName || 'Authorization'
  return async function jwt(ctx, next) {
    const headerToken = ctx.req.header(headerName)
    let token
    if (headerToken) {
      const parts = headerToken.split(/\s+/)
      if (parts.length !== 2) {
        const errDescription = 'invalid credentials structure'
        throw new HTTPException(401, {
          message: errDescription,
          res: unauthorizedResponse({ ctx, error: 'invalid_request', errDescription }),
        })
      }
      token = parts[1]
    } else if (options.cookie) {
      if (typeof options.cookie == 'string') {
        token = getCookie(ctx, options.cookie)
      } else if (options.cookie.secret) {
        token = await getSignedCookie(ctx, options.cookie.secret, options.cookie.key)
      } else {
        token = getCookie(ctx, options.cookie.key)
      }
    }
    if (!token) {
      const errDescription = 'no authorization included in request'
      throw new HTTPException(401, {
        message: errDescription,
        res: unauthorizedResponse({ ctx, error: 'invalid_request', errDescription }),
      })
    }
    let payload
    let cause
    try {
      payload = await Jwt.verify(token, options.secret, options.alg || 'HS256')
    } catch (e) {
      cause = e
    }
    if (!payload) {
      throw new HTTPException(401, {
        message: 'Unauthorized',
        res: unauthorizedResponse({ ctx, error: 'invalid_token', statusText: 'Unauthorized', errDescription: 'token verification failure' }),
        cause,
      })
    }
    ctx.set('jwtPayload', payload)
    await next()
  }
}

function unauthorizedResponse(opts: { ctx: Context; error: string; errDescription: string; statusText?: string }) {
  return new Response('Unauthorized', {
    status: 401,
    statusText: opts.statusText,
    headers: {
      'WWW-Authenticate': `Bearer realm="${opts.ctx.req.url}",error="${opts.error}",error_description="${opts.errDescription}"`,
    },
  })
}
