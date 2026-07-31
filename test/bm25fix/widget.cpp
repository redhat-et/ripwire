// widget.cpp — the ONE function with the distinctive terms "frobnicate" + "widget" in both its name and
// its doc-comment. bm25check.sh queries for these terms and expects this symbol to rank first.

// widget frobnication entrypoint — normalizes a widget's internal state before dispatch.
int frobnicate_widget( int state )
{
    int normalized = state;
    if( normalized < 0 ) normalized = 0;
    return normalized;
}

// module helper: computes a running tally for this module.
int compute_tally( int a, int b )
{
    return a + b;
}
