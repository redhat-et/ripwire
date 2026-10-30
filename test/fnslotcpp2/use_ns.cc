// namespace shapes (E* / N* arms): one single-field table per spelling, so every positional index is exact
#include "scope.h"
typedef int (outer::inner::Deep::*F_nfull)(int);
struct E_nfull { F_nfull f; };
static const E_nfull k_nfull[] = { { &outer::inner::Deep::run } };
struct H_nfull { const E_nfull* e; };
int go_nfull(outer::inner::Deep& s, int k) { H_nfull h; h.e = &k_nfull[k]; return (s.*h.e->f)(k); }
typedef int (outer::inner::Deep::*F_nsuf)(int);
struct E_nsuf { F_nsuf f; };
static const E_nsuf k_nsuf[] = { { &inner::Deep::run } };
struct H_nsuf { const E_nsuf* e; };
int go_nsuf(outer::inner::Deep& s, int k) { H_nsuf h; h.e = &k_nsuf[k]; return (s.*h.e->f)(k); }
typedef int (Anon::*F_anon)(int);
struct E_anon { F_anon f; };
static const E_anon k_anon[] = { { &Anon::go } };
struct H_anon { const E_anon* e; };
int go_anon(Anon& s, int k) { H_anon h; h.e = &k_anon[k]; return (s.*h.e->f)(k); }
typedef int (c1::c2::Pair::*F_pfull)(int);
struct E_pfull { F_pfull f; };
static const E_pfull k_pfull[] = { { &c1::c2::Pair::f } };
struct H_pfull { const E_pfull* e; };
int go_pfull(c1::c2::Pair& s, int k) { H_pfull h; h.e = &k_pfull[k]; return (s.*h.e->f)(k); }
typedef int (c1::c2::Pair::*F_psuf)(int);
struct E_psuf { F_psuf f; };
static const E_psuf k_psuf[] = { { &c2::Pair::f } };
struct H_psuf { const E_psuf* e; };
int go_psuf(c1::c2::Pair& s, int k) { H_psuf h; h.e = &k_psuf[k]; return (s.*h.e->f)(k); }
typedef int (v0::Ver::*F_inl)(int);
struct E_inl { F_inl f; };
static const E_inl k_inl[] = { { &v0::Ver::vf } };
struct H_inl { const E_inl* e; };
int go_inl(v0::Ver& s, int k) { H_inl h; h.e = &k_inl[k]; return (s.*h.e->f)(k); }
typedef int (mine::Server::*F_ofull)(int);
struct E_ofull { F_ofull f; };
static const E_ofull k_ofull[] = { { &::mine::Server::start } };
struct H_ofull { const E_ofull* e; };
int go_ofull(mine::Server& s, int k) { H_ofull h; h.e = &k_ofull[k]; return (s.*h.e->f)(k); }
typedef int (other::inner::Deep::*F_oext)(int);
struct E_oext { F_oext f; };
static const E_oext k_oext[] = { { &other::inner::Deep::run } };
struct H_oext { const E_oext* e; };
int go_oext(other::inner::Deep& s, int k) { H_oext h; h.e = &k_oext[k]; return (s.*h.e->f)(k); }
typedef int (mine::Server::*F_gwrong)(int);
struct E_gwrong { F_gwrong f; };
static const E_gwrong k_gwrong[] = { { &::Server::stop } };
struct H_gwrong { const E_gwrong* e; };
int go_gwrong(mine::Server& s, int k) { H_gwrong h; h.e = &k_gwrong[k]; return (s.*h.e->f)(k); }
// a bare spelling inside the class's own namespace
namespace mine {
typedef int (Server::*BFn)(int);
struct BEnt { BFn f; };
static const BEnt kBEnts[] = { { &Server::stop } };
struct BHold { const BEnt* e; };
int go_inside(Server& s, int k) { BHold h; h.e = &kBEnts[k]; return (s.*h.e->f)(k); }
}
