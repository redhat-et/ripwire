export const encodeBase64Url = (s: string): string => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
export const decodeBase64Url = (s: string): string => atob(s.replace(/-/g, '+').replace(/_/g, '/'))
