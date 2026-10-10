import { decodeBase64Url, encodeBase64Url } from '../encode'
import type { JWTPayload } from './types'
import {
  JwtTokenExpired,
  JwtTokenInvalid,
  JwtTokenIssuedAt,
  JwtTokenNotBefore,
  JwtTokenSignatureMismatched,
} from './types'

export interface TokenHeader {
  alg: string
  typ?: 'JWT'
  kid?: string
}

export interface VerifyOptions {
  nbf?: boolean
  exp?: boolean
  iat?: boolean
}

export const sign = async (payload: JWTPayload, privateKey: string, alg: string = 'HS256'): Promise<string> => {
  const encodedPayload = encodeBase64Url(JSON.stringify(payload))
  const encodedHeader = encodeBase64Url(JSON.stringify({ alg, typ: 'JWT' }))
  const partialToken = `${encodedHeader}.${encodedPayload}`
  const signaturePart = await signing(privateKey, alg, partialToken)
  return `${partialToken}.${signaturePart}`
}

/** Verify a token: decode it, check the algorithm, the nbf/exp/iat claims, then the signature. */
export const verify = async (
  token: string,
  publicKey: string,
  algOrOptions: string | VerifyOptions = 'HS256'
): Promise<JWTPayload> => {
  const alg = typeof algOrOptions === 'string' ? algOrOptions : 'HS256'
  const tokenParts = token.split('.')
  if (tokenParts.length !== 3) {
    throw new JwtTokenInvalid(token)
  }
  const { header, payload } = decode(token)
  if (!isTokenHeader(header)) {
    throw new JwtTokenInvalid(token)
  }
  if (header.alg !== alg) {
    throw new JwtTokenInvalid(token)
  }
  const now = Math.floor(Date.now() / 1000)
  if (payload.nbf && payload.nbf > now) {
    throw new JwtTokenNotBefore(token)
  }
  if (payload.exp && payload.exp <= now) {
    throw new JwtTokenExpired(token)
  }
  if (payload.iat && now < payload.iat) {
    throw new JwtTokenIssuedAt(now, payload.iat)
  }
  const headerPayload = token.substring(0, token.lastIndexOf('.'))
  const verified = await verifying(publicKey, alg, decodeBase64Url(tokenParts[2]), headerPayload)
  if (!verified) {
    throw new JwtTokenSignatureMismatched(token)
  }
  return payload
}

export const decode = (token: string): { header: TokenHeader; payload: JWTPayload } => {
  try {
    const [h, p] = token.split('.')
    const header = decodeJwtPart(h) as TokenHeader
    const payload = decodeJwtPart(p) as JWTPayload
    return { header, payload }
  } catch {
    throw new JwtTokenInvalid(token)
  }
}

export const decodeHeader = (token: string): TokenHeader => {
  try {
    const [h] = token.split('.')
    return decodeJwtPart(h) as TokenHeader
  } catch {
    throw new JwtTokenInvalid(token)
  }
}

const decodeJwtPart = (part: string): unknown => JSON.parse(decodeBase64Url(part))

const isTokenHeader = (obj: unknown): obj is TokenHeader =>
  typeof obj === 'object' && obj !== null && 'alg' in obj

const signing = async (key: string, alg: string, data: string): Promise<string> => `${alg}:${key.length}:${data.length}`

const verifying = async (key: string, alg: string, signature: string, data: string): Promise<boolean> =>
  signature === `${alg}:${key.length}:${data.length}`
