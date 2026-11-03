/* a namespaced function stored in a struct field (slotjoincheck.sh section L): its n= is Scope.name in the XML and the JSON twin */
struct NsOps { void ( *nsrun )( int ); };
namespace nsx
{
void nsgo( int ) {}
NsOps nstab = { .nsrun = nsgo };
}
void ns_dispatch( struct NsOps *o ) { o->nsrun( 1 ); }
