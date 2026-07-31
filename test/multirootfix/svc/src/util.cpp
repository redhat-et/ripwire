// util.cpp — deliberately the SAME root-relative path as cli/src/util.cpp: the per-root git isolation
// gate (G-git) asserts each repo's history/ownership lands on ITS OWN util.cpp, never the other root's
// (the suffix-match trap a merged file list would otherwise fall into).
int svc_util_tick()
{
    return 7;
}
