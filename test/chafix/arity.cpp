// chafix/arity.cpp — gate fixture for B2.2 arity filtering (drop a same-name candidate whose FIXED declared
// arity is provably incompatible with the call site's argument count).
//
// Three same-name overloads of `emit`:
//   * emit(int)                       — a FIXED arity of 1 (arityExact)
//   * emit(int,int,int)               — a FIXED arity of 3 (arityExact)
//   * emit(const char*, ...)          — VARIADIC → NOT a fixed arity (arityExact==0)
//
// The call `emit(1, 2, 3)` supplies 3 positional args. B2.2 drops the arity-1 overload (1 != 3, and its
// arity is fixed → provably wrong), KEEPS the arity-3 overload (3 == 3), and MUST KEEP the variadic overload
// (a variadic accepts any count → never provably wrong). So the caller's resolved targets are {emit/3,
// emit/variadic} — the arity-1 def is excluded, the variadic def is NOT.

void emit( int a ) { (void)a; }                          // arity 1  (line: EMIT1)
void emit( int a, int b, int c ) { (void)a; (void)b; (void)c; }   // arity 3  (line: EMIT3)
void emit( const char* fmt, ... ) { (void)fmt; }         // variadic (line: EMITV)

void caller()
{
    emit( 1, 2, 3 );             // 3 args → excludes emit(int); keeps emit(int,int,int) + emit(const char*,...)
}
