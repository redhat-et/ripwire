// estcalibfix — FROZEN. See ledger.cpp's header; edits invalidate test/estcalib.manifest.

export interface UsageRecord {
  sessionId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

export function totalForRecord(record: UsageRecord): number {
  return (
    record.inputTokens +
    record.outputTokens +
    record.cacheReadTokens +
    record.cacheWriteTokens
  );
}

export function groupBySession(records: UsageRecord[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const record of records) {
    const prior = out.get(record.sessionId) ?? 0;
    out.set(record.sessionId, prior + totalForRecord(record));
  }
  return out;
}

export function dedupe(records: UsageRecord[], keyOf: (r: UsageRecord) => string): UsageRecord[] {
  const seen = new Set<string>();
  const kept: UsageRecord[] = [];
  for (const record of records) {
    const key = keyOf(record);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    kept.push(record);
  }
  return kept;
}

export function isMeasured(record: UsageRecord): boolean {
  return record.inputTokens > 0 || record.outputTokens > 0;
}
