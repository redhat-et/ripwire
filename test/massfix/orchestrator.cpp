// orchestrator.cpp -- calls the leaf cluster's entry point plus each of twelve independent module clusters,
// whose own entry points each place a single bridge edge into the hub cluster (hub.cpp). This gives the
// hub concentrated fan-in from TWELVE distinct communities while the hub cluster itself stays 2 members --
// the "small load-bearing hub" ripwire's mass-based --communities/--zoom ordering (V6) is meant to surface
// above a much larger but purely-peripheral leaf cluster (leaf.cpp) of much lower external fan-in.

int leafRun();
int moduleARun();
int moduleBRun();
int moduleCRun();
int moduleDRun();
int moduleERun();
int moduleFRun();
int moduleGRun();
int moduleHRun();
int moduleIRun();
int moduleJRun();
int moduleKRun();
int moduleLRun();

int orchestratorMain()
{
    return leafRun() + moduleARun() + moduleBRun() + moduleCRun() + moduleDRun()
         + moduleERun() + moduleFRun() + moduleGRun() + moduleHRun()
         + moduleIRun() + moduleJRun() + moduleKRun() + moduleLRun();
}
