import { enumerateProjectFiles } from './walk'

const WALK_PRUNE_DIRECTORIES = new Set(['node_modules', '.git', 'dist', 'build'])
const MAX_GLOB_PATTERN_LENGTH = 512

/** Every file of the project the scanner may pick, pruned of generated and dependency directories. */
export const listProjectFiles = (rootDirectory: string): string[] =>
  enumerateProjectFiles(rootDirectory, WALK_PRUNE_DIRECTORIES)

export interface FileFilterOptions {
  readonly include: string[]
  readonly exclude: string[]
}

const normalizeIncludePatterns = (patterns: string[]): string[] =>
  patterns.flatMap((pattern) => {
    const normalized = pattern.trim().replace(/^\.\//, '').replace(/\/$/, '')
    if (normalized === '' || normalized === '.') {
      return ['**']
    }
    if (normalized.length > MAX_GLOB_PATTERN_LENGTH) {
      return []
    }
    return [normalized, `${normalized}/**`]
  })

const matchesAny = (patterns: string[], filePath: string): boolean =>
  patterns.some((pattern) => pattern === '**' || filePath.startsWith(pattern.replace('/**', '')))

/** The files the scanner picks to check: those matching an include pattern and no exclude pattern. */
export const filterFiles = (files: string[], options: FileFilterOptions): string[] => {
  const include = normalizeIncludePatterns(options.include)
  const exclude = normalizeIncludePatterns(options.exclude)
  return files.filter((file) => matchesAny(include, file) && !matchesAny(exclude, file))
}
