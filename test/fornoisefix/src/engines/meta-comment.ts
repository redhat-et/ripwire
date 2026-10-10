/** Narration of how the code changed: before/after state that belongs in a PR diff, not source. */
export const BEFORE_AFTER_RES: RegExp[] = [
  /\bpreviously[,:]?\s+(?:this|we|it|the)\b/i,
  /\bused\s+to\s+(?:be|use|call|return|do|have|rely)\b/i,
  /\bchanged\s+(?:\w+\s+)?(?:to|from)\b/i,
]

/** Which plan the comment references: the scanner does not pick these files to check. */
export const PLAN_REFERENCE_RES: RegExp[] = [/\bstep\s+\d+\b/i, /\bphase\s+\d+\b/i]

export const detectMetaComments = (text: string): number => {
  let hits = 0
  for (const re of BEFORE_AFTER_RES) {
    if (re.test(text)) {
      hits++
    }
  }
  for (const re of PLAN_REFERENCE_RES) {
    if (re.test(text)) {
      hits++
    }
  }
  return hits
}
