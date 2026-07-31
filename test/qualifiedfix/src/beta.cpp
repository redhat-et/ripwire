// beta.cpp — the second "dup" (see alpha.cpp). callerB is the ONLY caller of beta's dup.
int dup() { return 2; }
int callerB() { return dup(); }
