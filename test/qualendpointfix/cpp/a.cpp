struct Alpha { int run(int x); };
struct Beta { int run(int x); };
int Alpha::run(int x) { return x + 1; }
int Beta::run(int x) { return x * 2; }
int helper(Beta& b) { return b.run(3); }
int driver() { Alpha a; Beta b; int r = a.run(1); return r + helper(b); }
