#include "row.h"
static void Linux_writeField(const void* r, int f) { (void)r; (void)f; }
static void Other_writeField(const void* r, int f) { (void)r; (void)f; }
static int Linux_compare(int x) { return x; }
const ProcessClass LinuxProcess_class = {
   .super = {
      .name = "linux",
      .writeField = Linux_writeField
   },
   .compare = Linux_compare
};
const OtherClass Other_class = { .writeField = Other_writeField };
