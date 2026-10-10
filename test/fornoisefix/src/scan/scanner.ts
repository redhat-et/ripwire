import { listProjectFiles, filterFiles } from '../utils/source-file-selection'

/** The scanner picks which files to check from the project file list. */
export const SCANNER_NOTE = 1

export const SAMPLE_QUESTIONS = [
  'how does the scanner pick which files to check',
  'how does authentication work',
  'how is the database accessed',
]

export interface ScanOptions {
  rootDirectory: string
  include: string[]
  exclude: string[]
}

export const runScan = async (options: ScanOptions): Promise<string[]> => {
  const candidates = listProjectFiles(options.rootDirectory)
  const selected = filterFiles(candidates, { include: options.include, exclude: options.exclude })
  const results: string[] = []
  for (const file of selected) {
    results.push(file)
  }
  return results
}
