// FN-SLOT S2 fix 1 fixture (I* arms): a pointer to an INHERITED or CRTP-base method names the base's definition (F-3).
struct IB { int inh(int x); };
int IB::inh(int x) { return x; }
struct ID : IB { int other(int x); };
int ID::other(int x) { return x; }
typedef int (ID::*IDFn)(int);
struct IT { IDFn f; };
static const IT kIT[] = { { &ID::inh } };
struct IH { const IT* t; };
int go_id(ID& d, int k) { IH h; h.t = &kIT[k]; return (d.*h.t->f)(k); }
template <class D> struct ICB { int crt(int x) { return x; } };
struct ICD : ICB<ICD> { int own(int x) { return x; } };
typedef int (ICD::*ICFn)(int);
struct ICT { ICFn f; };
static const ICT kICT[] = { { &ICD::crt } };
struct ICH { const ICT* t; };
int go_icd(ICD& d, int k) { ICH h; h.t = &kICT[k]; return (d.*h.t->f)(k); }
// the sibling of the inherited store: the derived class's own method, typed beside it
typedef int (ID::*IDFn2)(int);
struct IT2 { IDFn2 f; };
static const IT2 kIT2[] = { { &ID::other } };
struct IH2 { const IT2* t; };
int go_id2(ID& d, int k) { IH2 h; h.t = &kIT2[k]; return (d.*h.t->f)(k); }
// two bases at one level both declare dup: which one `&IMD::dup` names is not proven (C++ itself calls it ambiguous)
struct IM1 { int dup(int x); };
struct IM2 { int dup(int x); };
int IM1::dup(int x) { return x; }
int IM2::dup(int x) { return x + 1; }
struct IMD : IM1, IM2 { int own2(int x); };
int IMD::own2(int x) { return x; }
typedef int (IMD::*IMFn)(int);
struct IMT { IMFn f; };
static const IMT kIMT[] = { { &IMD::dup } };
struct IMH { const IMT* t; };
int go_imd(IMD& d, int k) { IMH h; h.t = &kIMT[k]; return (d.*h.t->f)(k); }
// a base declared outside the tree: the inherited method is not found (no target; a floor, named in the changelog)
struct IE : ext::Unindexed { int ie_own(int x); };
int IE::ie_own(int x) { return x; }
typedef int (IE::*IEFn)(int);
struct IET { IEFn f; };
static const IET kIET[] = { { &IE::from_ext } };
struct IEH { const IET* t; };
int go_ie(IE& d, int k) { IEH h; h.t = &kIET[k]; return (d.*h.t->f)(k); }
// overloads: every overload is a candidate (targets= counts definitions, not stored values)
struct IO { int ov(int x); int ov(double x); };
int IO::ov(int x) { return x; }
int IO::ov(double x) { return 1; }
typedef int (IO::*IOFn)(int);
struct IOT { IOFn f; };
static const IOT kIOT[] = { { &IO::ov } };
struct IOH { const IOT* t; };
int go_io(IO& d, int k) { IOH h; h.t = &kIOT[k]; return (d.*h.t->f)(k); }
