// alpha.cpp — deliberately reuses the name "dup" also defined in beta.cpp (X9(b) fixture: qualified
// file:name disambiguation for --callers/--callees/--impact). callerA is the ONLY caller of alpha's dup.
int dup() { return 1; }
int callerA() { return dup(); }
