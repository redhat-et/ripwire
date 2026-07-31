// rangedemo.cpp — fixture for --expand=SYM:START-END gate (test/expandrangecheck.sh).
// bigFunction has a KNOWN, stable line layout (relative to its own first line) so the gate
// can assert an EXACT slice. A UTF-8 comment line is included so the gate can also assert
// that a range slice never corrupts a multi-byte codepoint at a slice boundary.

int helperOne( int x )
{
    return x + 1;
}

int bigFunction( int a, int b )
{
    int line2 = a + b;
    int line3 = a - b;
    int line4 = a * b;
    int line5 = helperOne( a );
    // café — UTF-8 comment on line6 (é is a 2-byte codepoint straddling nothing here,
    int line7 = b - a;
    int line8 = line2 + line3 + line4 + line5 + line7;
    return line8;
}
