import { GatewaySessionTokenInvalid as SessionTokenInvalid, GatewaySessionTokenExpired as SessionTokenExpired, GatewaySessionTokenPayload as SessionTokenPayload } from './types'
// checkSessionToken: decodes a session token and checks its expiry.
export const checkSessionToken = (token: string): SessionTokenPayload => {
  if (!token) throw new SessionTokenInvalid(token)
  const payload = decodeSessionToken(token)
  if (!payload.checked) throw new SessionTokenExpired(token)
  return payload
}
// decodeSessionToken: splits the session token into its parts.
export const decodeSessionToken = (token: string): SessionTokenPayload => {
  const parts = token.split('.')
  return { session: parts[0], token: parts[1], checked: parts.length === 3 }
}
