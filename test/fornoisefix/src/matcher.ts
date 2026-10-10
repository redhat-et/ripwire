/** The matcher matches a route against the registered patterns and returns the first hit. */
export const sourceMatcher = (route: string, patterns: string[]): string | undefined => {
  for (const pattern of patterns) {
    if (route === pattern || pattern === '*') {
      return pattern
    }
  }
  return undefined
}
