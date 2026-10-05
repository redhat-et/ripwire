// checkSig calls the Web Crypto verify through the global crypto object, not the token verify.
export const checkSig = async (key: CryptoKey, sig: Uint8Array, data: Uint8Array): Promise<boolean> => {
  return await crypto.subtle.verify('HMAC', key, sig, data)
}
