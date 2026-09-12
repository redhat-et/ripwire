/* test/macroreparsecheck.sh fixture — the member-macro leak in plain C. tree-sitter-c reads a semicolon-less
 * macro invocation as a field declaration too: without the re-parse the three struct bodies nest into each other,
 * sum_rations is swallowed as a field declaration and reset_tally is lost to an ERROR node. */
#define FIELD_TAIL(T) int T##_tail

struct ration {
  int grams;
  FIELD_TAIL(ration)
};

struct satchel {
  int pockets;
  FIELD_TAIL(satchel)
};

struct trailmap {
  int legs;
  FIELD_TAIL(trailmap)
};

int sum_rations(int a, int b, int c) {
  if (a < 0) {
    return b + c;
  }
  return a + b + c;
}

void reset_tally(int *tally) {
  *tally = 0;
}
