// compress_demo.cpp — fixture for --compress gate (test/compresscheck.sh).
// Contains real comments, blank-line runs, AND string literals that mimic
// comment syntax — the literal content MUST survive --compress unmodified.

#include <string>

/* This is a block comment at file scope.
   It spans multiple lines.
   It should be stripped by --compress. */

// A line comment that should also be stripped.

double computeArea( double width, double height )
{
    /* block comment inside function — must be stripped */
    // line comment inside function — must be stripped

    double area = width * height;



    // Three or more consecutive blank lines above should collapse to one blank line.

    // URL in a string literal — the // must NOT be treated as a comment:
    const char* url = "http://example.com // not a comment inside a string";

    /* tricky string: mimics a block comment */
    const char* p = "/* not a comment */";

    // Another line comment between statements.
    return area;
}

int helperValue( int x )
{
    // Leading comment in helperValue
    return x * 2; // trailing comment on the return
}
