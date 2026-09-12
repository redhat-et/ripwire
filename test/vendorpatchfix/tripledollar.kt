package vendorpatchfix

// kotlin/002-triple-dollar-escape fixture: an escaped `$` immediately before a triple-quoted
// string's closing delimiter used to consume only the FIRST of the three closing quotes as
// STRING_END, corrupting everything that followed. If the patch regresses, this file either
// degrades (ERROR/MISSING nodes — see vendorpatchcheck.sh arm J) or afterTripleDollarEscape below
// silently fails to extract as its own symbol.
fun tripleDollarEscape(): String = """a\$"""

fun afterTripleDollarEscape(n: Int): Int = n + 1
