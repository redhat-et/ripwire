#ifndef TABLE_H
#define TABLE_H
typedef struct Table_ Table;
struct Table_ { int rows; int (*iterate)(Table*); };
int Table_rowCount(Table* t);
int Table_collectRows(Table* t);
int Table_prepare(Table* t);
int Table_cleanup(Table* t);
int scan(Table* t);
int collect(Table* t);
int catalog(Table* t);
int dialog(Table* t);
#endif
