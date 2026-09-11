// Exactly 256 leading '$' before an interpolated string — the first count a uint8_t cannot hold.
// Before csharp/001-delimiter-count-cast the dollar_advanced++ at scanner.c:205 truncated and
// aborted the G1 stack. ABORT-ARM ONLY, for the same measured reason as widehash.rs.
class NarrowCounterWrapCsharp
{
    string NarrowCounterWrapDollars()
    {
        return $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$"two hundred and fifty six dollars";
    }
}
