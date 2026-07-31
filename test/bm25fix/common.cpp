// common.cpp — the file where the term "module" appears in EVERY function's doc-comment (a ubiquitous
// term, for the IDF sanity check: a query on a term present in ALL docs should NOT outrank a query on the
// distinctive term "frobnicate widget" for the frobnicate_widget() symbol).

// module helper: logs a module startup event.
int module_startup_log( int code )
{
    return code;
}

// module helper: logs a module shutdown event.
int module_shutdown_log( int code )
{
    return code;
}

// module helper: validates a module handle.
int module_validate_handle( int handle )
{
    return handle != 0;
}
