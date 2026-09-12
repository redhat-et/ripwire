// test/macroreparsecheck.sh control — a first parse WITH an error the re-parse cannot reduce. The member-macro
// invocation in Signal is followed by another member, which tree-sitter-cpp recovers with a zero-width MISSING `;`
// (no error BYTES), while the unclosed parenthesis in relayDelay is a real ERROR span. Blanking the invocation leaves
// the error bytes exactly where they were (measured: 7 before, 7 after), so the re-parse must NOT be adopted: the
// first tree is kept, and every output stays byte-identical to the pre-change binary. Adopting it anyway would drop
// err= from 2 to 1 on --skipped and add the per-file blank count — which is how this control catches an "adopt
// regardless" mutation. (No comment in a control spells the new disclosure's names: the gate greps every output
// of a control for them, and --expand prints this file's text.)
#define NAME_OF(T) static const char* kindName() { return #T; }

struct Signal
{
  NAME_OF(Signal)
  int strength = 0;
};

int relayDelay(int hops) {
  return (hops + ;
}

int relayCount(int hops) {
  if (hops > 8) {
    return 8;
  }
  return hops;
}
