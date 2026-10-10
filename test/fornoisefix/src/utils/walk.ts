export const enumerateProjectFiles = (rootDirectory: string, prune: Set<string>): string[] => {
  const out: string[] = []
  const stack = [rootDirectory]
  while (stack.length > 0) {
    const dir = stack.pop() as string
    for (const entry of readDirSync(dir)) {
      if (prune.has(entry.name)) {
        continue
      }
      if (entry.isDirectory) {
        stack.push(`${dir}/${entry.name}`)
      } else {
        out.push(`${dir}/${entry.name}`)
      }
    }
  }
  return out.sort()
}

interface DirEntry {
  name: string
  isDirectory: boolean
}

const readDirSync = (_dir: string): DirEntry[] => []
