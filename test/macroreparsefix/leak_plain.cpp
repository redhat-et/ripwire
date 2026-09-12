// test/macroreparsecheck.sh fixture — the member-macro scope leak with NO enclosing namespace. Three structs end with
// a semicolon-less function-like macro invocation; without the re-parse the later struct bodies swallow the free
// functions that follow them.
#define TAG_KIND(T) static int kindTag() { return sizeof(T); }

struct LanternRecord : public store::Record {
  int id = 0;
  TAG_KIND(LanternRecord)
};

struct MooringRecord : public store::Record {
  int id = 0;
  TAG_KIND(MooringRecord)
};

struct NavigatorRecord : public store::Record {
  int id = 0;
  TAG_KIND(NavigatorRecord)
};

int countMoorings(int requested, int limit) {
  if (requested > limit) {
    return limit;
  }
  return requested;
}

long sumDraft(const long *drafts, int n) {
  long total = 0;
  for (int i = 0; i < n; ++i) {
    total += drafts[i];
  }
  return total;
}
