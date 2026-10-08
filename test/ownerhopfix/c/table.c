#include "table.h"
int Table_rowCount(Table* t) { return t->rows; }
int Table_collectRows(Table* t) { return t->rows; }
int Table_prepare(Table* t) { return t->rows; }
int Table_cleanup(Table* t) { return t->rows; }

/* scan: one refresh of the tables (the function the question is about) */
int scan(Table* t) {
    Table_prepare(t);
    int n = Table_rowCount(t);
    Table_cleanup(t);
    return n;
}

/* collect: only an indirect call through the table's own iterate pointer (no resolvable callee) */
int collect(Table* t) {
    return t->iterate(t);
}

/* catalog and dialog: names that CONTAIN a question word ("log") without being it */
int catalog(Table* t) { return Table_rowCount(t); }
int dialog(Table* t) { return Table_rowCount(t); }
