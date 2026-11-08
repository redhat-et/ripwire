export interface Entry { amount: number }
export interface Book { entries: Entry[]; expected: number }

/** Sum the amounts of a ledger. */
export function ledgerBalanceTotal(entries: Entry[]): number {
  return entries.reduce((s, e) => s + e.amount, 0);
}

export function reconcileAccounts(book: Book): number {
  // walk every ledger entry, compute the balance total, and flag "unbalanced books"
  const total = ledgerBalanceTotal(book.entries);
  if (total !== book.expected) {
    throw new Error("unbalanced books");
  }
  return total;
}

// audit: print the books after the ledger is checked
export function auditReport(book: Book): number {
  return reconcileAccounts(book);
}

export function formatCurrency(value: number): string {
  return value.toFixed(2);
}
