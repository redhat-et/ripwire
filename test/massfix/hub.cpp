// hub.cpp -- a small (2-member) but heavily relied-upon cluster: validateCore is called from TWELVE
// separate module clusters (module_a..module_l.cpp) plus checkHelper is its only internal callee. That
// concentrated cross-cluster fan-in gives this cluster's summed PageRank (mass) more weight than
// leaf.cpp's raw member count despite leaf.cpp having 3x the members -- exactly the ordering
// test/communitylabelcheck.sh's "mass" arm asserts, and exactly what --communities/--zoom got wrong
// before V6 (raw members.size() as the sole sort key: 2 < 6, so hub sorted LAST under the old rule).
//
// Both names are recognized verbs (verbtable.h) on purpose, so this fixture doubles as the verb-histogram
// suffix's exact-output arm: this community's label must end " [check,validate]" (both verbs occur exactly
// once each -- checkHelper and validateCore are the community's only two members -- so the tie-break is
// first-seen NodeId order, and checkHelper is declared first).

int checkHelper()  { return 1; }
int validateCore() { return checkHelper(); }
