import { LedgerBook } from './book';

// printTotals reconciles the totals of one book and reports them.
export function printTotals(book: LedgerBook, expected: number): string {
  const ok = book.reconcileTotals(expected);
  return ok ? 'totals reconciled' : 'totals differ';
}
