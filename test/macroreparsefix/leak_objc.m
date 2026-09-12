// test/macroreparsecheck.sh fixture — the member-macro leak under the Objective-C grammar (C-syntax structs, as an
// .m file holds them). tree-sitter-objc derails on the same shape tree-sitter-c does.
#define FIELD_TAIL(T) int T##_tail

struct beacon {
  int lumens;
  FIELD_TAIL(beacon)
};

struct lanyard {
  int loops;
  FIELD_TAIL(lanyard)
};

struct compass {
  int bearing;
  FIELD_TAIL(compass)
};

int brightest(int a, int b) {
  if (a > b) {
    return a;
  }
  return b;
}

void zero_bearing(int *bearing) {
  *bearing = 0;
}
