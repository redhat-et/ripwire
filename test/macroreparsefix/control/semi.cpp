// test/macroreparsecheck.sh fixture — the member-macro scope leak, inside an anonymous namespace. Each of the four
// structs below ends with a function-like macro invocation and NO semicolon, as the last member of its body.
// tree-sitter-cpp reads that as a field declaration missing its `;`, dissolves the earlier structs into an ERROR
// region, and lets the LAST struct's body run on to the namespace's closing brace — so, without the member-macro
// re-parse, the free functions below come out as `method` rows filed under KeelFault::. The re-parse blanks the four
// invocations (bytes -> spaces, newlines kept), re-parses, and adopts that tree because it holds fewer error bytes.
// test/macroreparsefix/control/semi.cpp is this file with the semicolons added.
#define NAME_OF(T) static const char* kindName() { return #T; }

namespace {

struct HarborFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(HarborFault);
};

struct InletFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(InletFault);
};

struct JettyFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(JettyFault);
};

struct KeelFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(KeelFault);
};

int tallyCargo(const int *crates, int count) {
  int total = 0;
  for (int i = 0; i < count; ++i) {
    if (crates[i] > 0) {
      total += crates[i];
    }
  }
  return total;
}

bool berthIsFree(int berth, int occupied) {
  if (berth < 0) {
    return false;
  }
  return berth != occupied;
}

void clearManifest(int &lines) {
  while (lines > 0) {
    --lines;
  }
}

}  // namespace
