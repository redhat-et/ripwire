/* a.c — C ingest fixture for §P11.9 (--external-surface lang= split): calls the external printf()
   from a C-family file, distinct from b.sh's Bash-builtin printf call below. */
#include <stdio.h>
int main(void) { printf("hi\n"); return 0; }
