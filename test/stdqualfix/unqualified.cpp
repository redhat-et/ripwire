// test/stdqualfix — file 3: the UNQUALIFIED control. `move( x )` under `using namespace std;` carries no
// qualifier, so the std:: guard must not touch it: whatever the resolver did before, it does after. What it
// does is the Phase-5 external-name veto (graph.h ExternalVeto): `move` is in externalnames.h's C-family
// table and no FREE `move` exists anywhere in this corpus (Buf::move is a member), so the site is refused
// and counted in `external=` — on the pre-fix binary and the fixed one alike.

#include <utility>

using namespace std;

int bareMove( int x )
{
    return move( x );
}
