#include "hdr.h"
int Hdr::Run(int x) { return x; }
struct Slot { const char* name; HdrFn fn; };
static const Slot kSlots[] = { { "run", &Hdr::Run }, { "stop", &Hdr::Stop } };
struct Box { Hdr hdr; const Slot* slot; };
int go_hdr(int k) {
  Box box;
  box.slot = &kSlots[k];
  return (box.hdr.*box.slot->fn)(k);
}
