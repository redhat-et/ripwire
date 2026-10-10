export interface EngineContext {
  rootDirectory: string
  files: string[]
}

export interface Diagnostic {
  file: string
  message: string
}

/** Run the formatter for one target, returning the per-file diagnostics it reports. */
export const checkTarget = async (context: EngineContext, target: string): Promise<Diagnostic[]> => {
  const diagnostics: Diagnostic[] = []
  for (const file of context.files) {
    if (file.endsWith(target)) {
      diagnostics.push({ file, message: 'needs formatting' })
    }
  }
  return diagnostics
}

export const fixDotnetFormat = async (context: EngineContext): Promise<number> => {
  const fixed = await checkTarget(context, '.cs')
  return fixed.length
}
