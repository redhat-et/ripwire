// session token types: every class below repeats the question's words (session, token, check) so the lexical
// ranker puts them ABOVE the function the question is about.
export class GatewaySessionTokenInvalid extends Error { constructor(token: string) { super(`session token invalid: ${token}`) } }
export class GatewaySessionTokenExpired extends Error { constructor(token: string) { super(`session token expired: ${token}`) } }
export class GatewaySessionTokenMissing extends Error { constructor(token: string) { super(`session token missing: ${token}`) } }
export class GatewaySessionTokenRevoked extends Error { constructor(token: string) { super(`session token revoked: ${token}`) } }
export class GatewaySessionTokenMalformed extends Error { constructor(token: string) { super(`session token malformed: ${token}`) } }
export class GatewaySessionTokenCheckFailed extends Error { constructor(token: string) { super(`session token check failed: ${token}`) } }
export type GatewaySessionTokenPayload = { session: string; token: string; checked: boolean }
export type GatewaySessionTokenHeader = { session: string; token: string; alg: string }
