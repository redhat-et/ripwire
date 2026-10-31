// FN-SLOT S2 fix 1 fixture (test/fnslotcheck.sh V* arms): a pointer to a VIRTUAL method is a candidate SET (F-1).
struct VBase {
  typedef int (VBase::*VFn)(int);
  virtual int Act(int x);
  virtual int Pure(int x) = 0;
  int Plain(int x);
};
int VBase::Act(int x) { return x; }
int VBase::Plain(int x) { return x; }
struct VDerived : VBase {
  int Act(int x) override;
  int Pure(int x) override;
};
int VDerived::Act(int x) { return x + 1; }
int VDerived::Pure(int x) { return 2; }
struct VDeeper : VDerived {
  int Act(int x) override;
};
int VDeeper::Act(int x) { return x + 2; }
struct VEnt { const char* n; VBase::VFn fn; };
static const VEnt kVEnts[] = { { "act", &VBase::Act }, { "pure", &VBase::Pure }, { "plain", &VBase::Plain } };
struct VHolder { const VEnt* e; };
int dispatch_v(VBase& r, int k) {
  VHolder h;
  h.e = &kVEnts[k];
  return (r.*h.e->fn)(k);
}
// an abstract method nobody overrides in the tree, and a method a derived class HIDES (non-virtual): the hedge lists both classes
struct HBase { int sh(int x); };
int HBase::sh(int x) { return x; }
struct HDer : HBase { int sh(int x); };
int HDer::sh(int x) { return x + 1; }
typedef int (HBase::*HFn)(int);
typedef int (HDer::*HDFn)(int);
struct HEnt { HFn f; };
struct HDEnt { HDFn f; };
static const HEnt kHEnt[] = { { &HBase::sh } };
static const HDEnt kHDEnt[] = { { &HDer::sh } };
struct HHold { const HEnt* e; };
struct HDHold { const HDEnt* e; };
int go_hbase(HBase& b, int k) { HHold h; h.e = &kHEnt[k]; return (b.*h.e->f)(k); }
int go_hder(HDer& d, int k) { HDHold h; h.e = &kHDEnt[k]; return (d.*h.e->f)(k); }
// V6: the override is only DECLARED in the tree (its body lives in an unindexed unit) and the base method is pure: the pointer's
// candidate is the override's declaration, never the base's bodyless (pure) one
struct PB { virtual int pv(int x) = 0; };
struct PD : PB { int pv(int x) override; };
typedef int (PB::*PFn)(int);
struct PEnt { PFn f; };
static const PEnt kPEnt[] = { { &PB::pv } };
struct PHold { const PEnt* e; };
int go_pv(PB& b, int k) { PHold h; h.e = &kPEnt[k]; return (b.*h.e->f)(k); }
