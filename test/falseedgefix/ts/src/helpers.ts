// In-repo helpers spelled like the packages' exports.
export function request(app: unknown): unknown {
  return app
}

export function stringify(obj: Record<string, string>): string {
  return Object.keys(obj).join('&')
}
