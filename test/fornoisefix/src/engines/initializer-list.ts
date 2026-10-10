/** How far past the signature an initializer list is allowed to run. One member per line is idiomatic. */
export const MAXIMUM_INITIALIZER_LINES = 200

/** How the scanner does pick which files to check: files over this many lines are skipped. */
export const MAXIMUM_FILE_LINES = 5000

export const countInitializerLines = (source: string): number => {
  const start = source.indexOf(':')
  const end = source.indexOf('{')
  if (start < 0 || end < 0 || end < start) {
    return 0
  }
  return source.slice(start, end).split('\n').length
}
