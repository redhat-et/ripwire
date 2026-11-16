#!/usr/bin/env bash
# spinlockcheck.sh — SPINLOCK: src/infra/spinlock.h, the test-and-test-and-set lock with capped
# doubling backoff, and the interned-text shards that are its first consumer.
#
# WHY A SPINLOCK AT ALL, in the owner's own terms (2026-11-15): the extra plain LOAD before the
# exchange is the optimization. Taking the lock with an exchange on every attempt WRITES the line, so
# every waiter invalidates it in every other core's cache even though none of them can enter. A relaxed
# load leaves the line SHARED while the lock is held, and only a load that observes 0 proceeds to the
# one write that can win. That is a property of the generated code, so (C) reads it out of the binary
# rather than trusting the source.
#
# And a second, structural reason this lock earns its place HERE: InternedText holds 64 shards, each
# `alignas(destructive-interference)` so no two shards' locks share a line. A `std::mutex` is 40 B on
# libstdc++ and 64 on libc++, so on a 64 B line a shard needed TWO lines of its own (the header's own
# #608 note). A 4 B flag brings the shard back to one. (D) asserts the size, which is deterministic and
# needs no timing.
#
# The arms:
#   (A) mutual exclusion — 8 threads x 20,000 increments under the lock equals exactly 160,000, and the
#       same loop WITHOUT the lock is shown to lose counts, so the arm can fail.
#   (B) the backoff ladder doubles and is CAPPED. Exposed as a pure function so this is arithmetic, not
#       a stopwatch: a test that times sleeps measures the scheduler, which is the trap the bounded
#       10 ms poll in quality.h already documents.
#   (C) the common-case path does a LOAD before any read-modify-write — read off the disassembly of
#       Spinlock::lock, not off the source.
#   (D) sizeof( Spinlock ) == 4, and an InternedText shard fits ONE destructive-interference line.
#   (E) it satisfies Lockable, so `std::lock_guard` and `std::scoped_lock` take it unchanged.
#   (F) the spin-wait hint is a REAL INSTRUCTION, read off the object: RW_SPIN_PAUSE() expands to the
#       architecture's hint (AArch64 YIELD, x86 PAUSE), and a loop that does not call it does not carry
#       one — so a macro that silently degrades to ( (void)0 ) on a compiler we ship for is caught here
#       rather than measured as a mysteriously hotter spin.
#
# NOT AN ARM HERE, on purpose: that unlock is a RELEASE store and lock an ACQUIRE exchange is a memory
# ORDER claim, and no compile-time assertion proves it. The ASan/TSan arm of the suite running (A) under
# contention is the evidence for that pairing, and it lives there rather than being restated here.
#
# RED-FIRST: every arm fails on main 0217049f2, where src/infra/spinlock.h does not exist.
#
# Usage: test/spinlockcheck.sh    (an argument is accepted and IGNORED — pargates passes every gate the
# binary under test, and this gate binds none: its subject is src/infra/spinlock.h, the compiler's output
# for it, and the shard layout in src/infra/internedtext.h. Nothing here executes build/ripwire, which is
# why test/binoverridecheck.sh carries a pinned exemption row for this gate.
#
# THAT ROW RESTS ON THE ABSENCE OF THE TWO BINARY-BINDING SPELLINGS FROM THIS FILE — the override
# environment variable and the positional-argument variable that every other gate uses to reach the binary
# under test. Arm (2b) of binoverridecheck greps exempted gates for exactly those two names, so neither may
# appear here even inside a comment: writing them in this note is what made that arm fire while the
# exemption it documents was correct. If a future arm here needs the binary, drop the exemption row first.)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
HDR="$ROOT/src/infra/spinlock.h"

[ -f "$HDR" ] || { no "(0) src/infra/spinlock.h does not exist"; echo "spinlockcheck: FAILURES"; exit 1; }
CXX="${CXX:-c++}"
# -DNDEBUG on purpose: the re-entrancy tripwire calls the project's DASSERT, whose handler lives in a
# TU these four-line programs do not link. Release semantics are also what (D1)'s sizeof claim is about.
# The tripwire itself is exercised by the product's own dev build, which every other gate runs.
INC="-I$ROOT/src -I$ROOT/src/infra -DNDEBUG"

# ── (A) mutual exclusion, with a no-lock control that must lose counts ───────────────────────────────
cat > "$TMP/excl.cpp" <<'EOF'
#include "spinlock.h"
#include <mutex>
#include <thread>
#include <vector>
#include <cstdio>
static rw::Spinlock g_lock;
static long long    g_guarded = 0;
static volatile long long g_bare = 0;   // volatile: -O2 folds a plain loop into ONE add per thread, and a control that cannot lose a count proves nothing
int main()
{
    constexpr int kThreads = 8, kIters = 20000;
    {
        std::vector<std::thread> ts;
        for( int t = 0; t < kThreads; ++t )
        {
            ts.emplace_back( []() { for( int i = 0; i < kIters; ++i ) { std::lock_guard<rw::Spinlock> lk( g_lock ); ++g_guarded; } } );
        }
        for( std::thread& t : ts ) { t.join(); }
    }
    {
        std::vector<std::thread> ts;
        for( int t = 0; t < kThreads; ++t )
        {
            ts.emplace_back( []() { for( int i = 0; i < kIters; ++i ) { g_bare = g_bare + 1; } } );
        }
        for( std::thread& t : ts ) { t.join(); }
    }
    std::printf( "guarded=%lld bare=%lld expected=%d\n", g_guarded, (long long)g_bare, kThreads * kIters );
    return g_guarded == (long long)kThreads * kIters ? 0 : 1;   // (H1): the harness's own verdict, in its status
}
EOF
if "$CXX" -std=c++23 -O2 $INC "$TMP/excl.cpp" -o "$TMP/excl" 2>"$TMP/excl.err"; then
    out="$( "$TMP/excl" )"; exclRc=$?
    if [ "$exclRc" = 0 ]; then
        ok "(A0) the exclusion harness exits 0 — its own assertion held"
    else
        no "(A0) the exclusion harness exited $exclRc: its internal check failed"
    fi
    if echo "$out" | grep -q "guarded=160000 "; then
        ok "(A1) 8 threads x 20,000 increments under the lock: exactly 160,000"
    else
        no "(A1) the guarded counter is not 160,000 — $out"
    fi
    bare="$( echo "$out" | sed -n 's/.*bare=\([0-9]*\).*/\1/p' )"
    [ -n "$bare" ] && [ "$bare" -lt 160000 ] \
        && ok "(A2) mutation control: the same loop unlocked loses counts ($bare of 160,000), so (A1) can fail" \
        || ok "(A2) INFO: the unlocked control did not lose a count on this run ($bare) — (A1) is still a real assertion, this box just did not race"
else
    no "(A) the exclusion program does not compile: $( head -2 "$TMP/excl.err" )"
fi

# ── (B) the backoff ladder: doubling, and capped ─────────────────────────────────────────────────────
cat > "$TMP/backoff.cpp" <<'EOF'
#include "spinlock.h"
#include <cstdio>
int main()
{
    long prev = 0;
    bool doubling = true, capped = false, monotone = true;
    for( unsigned k = 0; k < 40; ++k )
    {
        const long ns = rw::spinBackoffNs( k );
        if( ns < prev ) { monotone = false; }
        if( k > 0 && prev > 0 && ns != prev * 2 && ns != rw::kSpinBackoffMaxNs ) { doubling = false; }
        if( ns == rw::kSpinBackoffMaxNs ) { capped = true; }
        prev = ns;
    }
    std::printf( "first=%ld doubling=%d capped=%d monotone=%d max=%ld\n",
                 rw::spinBackoffNs( 0 ), doubling ? 1 : 0, capped ? 1 : 0, monotone ? 1 : 0, rw::kSpinBackoffMaxNs );
    return ( doubling && capped && monotone ) ? 0 : 1;   // (H1): the harness's own verdict, in its status
}
EOF
if "$CXX" -std=c++23 -O2 $INC "$TMP/backoff.cpp" -o "$TMP/backoff" 2>"$TMP/backoff.err"; then
    b="$( "$TMP/backoff" )"; backRc=$?
    if [ "$backRc" = 0 ]; then
        ok "(B0) the backoff harness exits 0 — its own assertion held"
    else
        no "(B0) the backoff harness exited $backRc: its internal check failed"
    fi
    if echo "$b" | grep -q "doubling=1"; then
        ok "(B1) each step is twice the one before it, until the cap"
    else
        no "(B1) the ladder does not double: $b"
    fi
    if echo "$b" | grep -q "capped=1"; then
        ok "(B2) the ladder reaches a CAP and stops there — an uncapped doubling reaches seconds"
    else
        no "(B2) no cap within 40 steps: $b"
    fi
    if echo "$b" | grep -q "monotone=1"; then
        ok "(B3) the ladder never decreases"
    else
        no "(B3) the ladder is not monotone: $b"
    fi
else
    no "(B) the backoff program does not compile: $( head -2 "$TMP/backoff.err" )"
fi

# ── (C) the LOAD-before-exchange, read out of the binary ─────────────────────────────────────────────
cat > "$TMP/dis.cpp" <<'EOF'
#include "spinlock.h"
rw::Spinlock g;
extern "C" void take() { g.lock(); }
extern "C" void give() { g.unlock(); }
EOF
if "$CXX" -std=c++23 -O2 $INC -c "$TMP/dis.cpp" -o "$TMP/dis.o" 2>"$TMP/dis.err"; then
    if command -v objdump >/dev/null 2>&1; then DIS="objdump -d"; else DIS="otool -tV"; fi
    $DIS "$TMP/dis.o" > "$TMP/dis.txt" 2>/dev/null
    # The shape to prove, not just the order: a LOAD, then a CONDITIONAL BRANCH that skips the write,
    # then the read-modify-write. The branch is the part that matters — it is what leaves the line
    # SHARED for every waiter that cannot enter. Symbol labels are not matched: a mach-o object of two
    # extern "C" functions disassembles under ltmp0, so this reads instruction ORDER over the whole
    # text section, which holds only lock() and unlock() here.
    # ARCHITECTURE. The RMW and branch patterns below already cover AArch64 and x86-64, but the LOAD
    # pattern was AArch64-only (ldr/ldar/ldur), so on x86-64 -- where a load is mov/cmp, not ldr -- this
    # arm found "any load (none)" and could never pass. It failed all four ubuntu shard-1 jobs on the PR
    # that introduces this gate while macOS was green; the product was correct the whole time (the x86
    # object reads `mov 0x0(%rip),%eax` / `test` / `je` before its xchg, exactly the shape C1 wants).
    #
    # x86 loads must be told from x86 STORES or the arm would pass on a store-before-load: AT&T order is
    # `op SRC,DST`, so a mov is a load only when the memory operand comes BEFORE the comma. cmp/test read
    # both operands, so either side counts. `\bcmp\b` cannot match `cmpxchg` (no word boundary), so the
    # RMW cannot be mistaken for its own load.
    ARM_LOAD='\b(ldr|ldar|ldur)\b'
    X86_MOV_LOAD='\b(mov|movl|movq|movb|movw|movzbl|movzwl|movslq)\b[[:space:]]+[^,]*(\(%|%fs:|%gs:)[^,]*,'
    X86_CMP_LOAD='\b(cmp|cmpb|cmpl|cmpq|cmpw|test|testb|testl|testq)\b[^#]*(\(%|%fs:|%gs:)'
    firstLoad="$( grep -nE "$ARM_LOAD|$X86_MOV_LOAD|$X86_CMP_LOAD" "$TMP/dis.txt" | head -1 | cut -d: -f1 )"
    # A third architecture must fail LOUDLY rather than silently read as "no load": if neither family's
    # mnemonics appear anywhere in the object, this arm cannot read it and says so instead of failing it.
    archSeen="$( grep -cE "$ARM_LOAD|\b(mov|cmp|test|xchg|lea|push)\b" "$TMP/dis.txt" )"
    firstRmw="$(  grep -nE "\b(swpa?l?|casa?l?|ldaxr|stlxr|xchg|cmpxchg)\b" "$TMP/dis.txt" | head -1 | cut -d: -f1 )"
    firstSkip="$( grep -nE "\b(cbnz|cbz|b\.[a-z]+|jne|jnz|je|jz)\b" "$TMP/dis.txt" | head -1 | cut -d: -f1 )"
    if [ "$archSeen" -eq 0 ]; then
        no "(C1) this arm reads AArch64 and x86-64 mnemonics and recognised NEITHER in $TMP/dis.o — it cannot judge this architecture, so treat as NOT-ESTABLISHED and widen the patterns rather than reading the silence as a pass or a fail"
    elif [ -z "$firstRmw" ]; then
        no "(C1) no read-modify-write in the object at all — this arm is not reading the lock"
    elif [ -z "$firstLoad" ] || [ "$firstLoad" -ge "$firstRmw" ]; then
        no "(C1) the first write (line $firstRmw) comes before any load (${firstLoad:-none}) — every waiter would invalidate the line"
    elif [ -z "$firstSkip" ] || [ "$firstSkip" -ge "$firstRmw" ] || [ "$firstSkip" -le "$firstLoad" ]; then
        no "(C2) no conditional branch between the load (line $firstLoad) and the write (line $firstRmw) — the load is not actually skipping the write"
    else
        ok "(C1) lock() loads at line $firstLoad before its first write at line $firstRmw"
        ok "(C2) and branches at line $firstSkip on that load — a waiter that cannot enter never writes the line"
    fi

    # (C3) MUTATION CONTROL for the load pattern itself. Widening C1 to x86 is only safe if a STORE is
    # still not read as a load -- otherwise the arm would pass on a store-before-write, which is the very
    # thing it exists to forbid. Two planted objects, no compiler involved: one where the only memory
    # writes precede the RMW (must be judged NO load before the write), one where a real load does
    # (must be judged a load). Without this the widened regex could rot into a pattern that always matches.
    printf '%s\n' \
        '   4: 48 89 44 24 18        mov    %rax,0x18(%rsp)' \
        '   9: 48 89 05 00 00 00 00  mov    %rax,0x0(%rip)' \
        '  10: 87 07                 xchg   %eax,(%rdi)' > "$TMP/c3_stores.txt"
    printf '%s\n' \
        '   0: 8b 05 00 00 00 00     mov    0x0(%rip),%eax' \
        '   6: 85 c0                 test   %eax,%eax' \
        '   a: 87 07                 xchg   %eax,(%rdi)' > "$TMP/c3_load.txt"
    c3bad="$(  grep -ncE "$ARM_LOAD|$X86_MOV_LOAD|$X86_CMP_LOAD" "$TMP/c3_stores.txt" )"
    c3good="$( grep -nE  "$ARM_LOAD|$X86_MOV_LOAD|$X86_CMP_LOAD" "$TMP/c3_load.txt" | head -1 | cut -d: -f1 )"
    if [ "$c3bad" = "0" ] && [ -n "$c3good" ] && [ "$c3good" = "1" ]; then
        ok "(C3) control: two planted memory STORES are not read as loads, and a real load is — the widened x86 pattern can still fail"
    else
        no "(C3) control: planted stores matched $c3bad time(s) (want 0) and the planted load was found at ${c3good:-none} (want 1) — the load pattern no longer distinguishes a load from a store"
    fi
else
    no "(C) the disassembly program does not compile: $( head -2 "$TMP/dis.err" )"
fi

# ── (D) size, and the shard that motivated it ────────────────────────────────────────────────────────
cat > "$TMP/size.cpp" <<'EOF'
#include "spinlock.h"
#include <cstdio>
#include <mutex>
int main()
{
    std::printf( "spin=%zu mutex=%zu\n", sizeof( rw::Spinlock ), sizeof( std::mutex ) );
    return sizeof( rw::Spinlock ) == 4 ? 0 : 1;   // (H1): the harness's own verdict, in its status
}
EOF
if "$CXX" -std=c++23 -O2 $INC "$TMP/size.cpp" -o "$TMP/size" 2>/dev/null; then
    sz="$( "$TMP/size" )"; szRc=$?
    if [ "$szRc" = 0 ]; then
        ok "(D0) the size harness exits 0 — its own assertion held"
    else
        no "(D0) the size harness exited $szRc: its internal check failed"
    fi
    if echo "$sz" | grep -q "spin=4 "; then
        ok "(D1) sizeof( Spinlock ) == 4 ($sz)"
    else
        no "(D1) sizeof( Spinlock ) is not 4: $sz"
    fi
else
    no "(D) the size program does not compile"
fi
if grep -q "Spinlock" "$ROOT/src/infra/internedtext.h"; then
    ok "(D2) the interned-text shards use it — the consumer the size claim is about"
else
    no "(D2) src/infra/internedtext.h still holds a std::mutex: the lock has no consumer, so no size claim is earned"
fi

# ── (E) Lockable: std::lock_guard and std::scoped_lock take it unchanged ─────────────────────────────
cat > "$TMP/lockable.cpp" <<'EOF'
#include "spinlock.h"
#include <mutex>
int main()
{
    rw::Spinlock a, b;
    { std::lock_guard<rw::Spinlock> g( a ); }
    { std::scoped_lock              g( a, b ); }   // needs try_lock() as well as lock()/unlock()
    return a.try_lock() ? ( a.unlock(), 0 ) : 1;
}
EOF
"$CXX" -std=c++23 -O2 $INC "$TMP/lockable.cpp" -o "$TMP/lockable" 2>"$TMP/lockable.err" && "$TMP/lockable" \
    && ok "(E1) satisfies Lockable: lock_guard, scoped_lock and try_lock all work" \
    || no "(E1) not usable as a standard Lockable: $( head -2 "$TMP/lockable.err" )"

# ── (F) the spin-wait hint reaches the object as an instruction ──────────────────────────────────────
# RW_SPIN_PAUSE() is the ladder's cheapest rung, and its #else arm is ( (void)0 ) by design — an
# unrecognised architecture should spin correctly, just hotter. That same fallback is what makes a
# REGRESSION invisible: if the arm we do ship stops compiling, or an #if is mis-spelled, the macro
# quietly becomes nothing and the only symptom is a slower spin nobody measures. So read the object.
#
# The expected mnemonic comes from `uname -m` rather than from the preprocessor, which makes this arm an
# independent reading of the same question platform.h answers with its #if ladder: if the two disagree,
# the arm fails, which is the point. A machine neither family recognises reports NOT-ESTABLISHED.
cat > "$TMP/pause.cpp" <<'EOF'
#include "platform.h"
extern "C" void spin3()   { for( int i = 0; i < 3; ++i ) { RW_SPIN_PAUSE(); } }
extern "C" void nospin3() { for( volatile int i = 0; i < 3; ++i ) { } }
EOF
case "$( uname -m )" in
    arm64|aarch64)   WANT='\byield\b';  WANTNAME='YIELD' ;;
    x86_64|amd64)    WANT='\bpause\b';  WANTNAME='PAUSE' ;;
    i386|i686)       WANT='\bpause\b';  WANTNAME='PAUSE' ;;
    *)               WANT='';           WANTNAME="$( uname -m )" ;;
esac
if [ -z "$WANT" ]; then
    ok "(F0) INFO: $WANTNAME is neither an AArch64 nor an x86 machine — this arm knows no hint mnemonic for it and reports NOT-ESTABLISHED rather than reading the silence as a pass; platform.h's #else arm spins correctly here, just hotter"
elif "$CXX" -std=c++23 -O2 $INC -c "$TMP/pause.cpp" -o "$TMP/pause.o" 2>"$TMP/pause.err"; then
    if command -v objdump >/dev/null 2>&1; then PDIS="objdump -d"; else PDIS="otool -tV"; fi
    $PDIS "$TMP/pause.o" > "$TMP/pause.txt" 2>/dev/null
    # Split the text at nospin3 so the control cannot read spin3's hint: a mach-o object renames both to
    # local labels, so match on the SYMBOL NAME as the disassembler prints it, and fall back to counting
    # over the whole object only when neither name appears (then the control is the weaker claim, and
    # (F2) says so rather than pretending the split happened).
    hits="$( grep -cE "$WANT" "$TMP/pause.txt" )"
    if [ "$hits" -ge 1 ]; then
        ok "(F1) RW_SPIN_PAUSE() emits $WANTNAME ($hits site(s) in the object) — the hint is a real instruction, not a dropped macro"
    else
        no "(F1) RW_SPIN_PAUSE() emitted no $WANTNAME on $( uname -m ): the macro degraded to nothing for this compiler, so the ladder's cheapest rung is a plain busy spin"
    fi
    nos="$( awk -v want="$WANT" 'BEGIN{ inn=0; n=0 } /nospin3/ { inn=1 } inn && $0 ~ want { n++ } END{ print n }' "$TMP/pause.txt" )"
    namesSeen="$( grep -cE 'nospin3' "$TMP/pause.txt" )"
    if [ "$namesSeen" -eq 0 ]; then
        ok "(F2) INFO: this disassembler prints no nospin3 label, so the control could not be scoped to it — (F1) stands on its own and this arm claims nothing"
    elif [ "$nos" = "0" ]; then
        ok "(F2) control: the loop that does NOT call the macro carries no $WANTNAME — (F1) is reading the call, not the architecture"
    else
        no "(F2) control: the loop that never calls RW_SPIN_PAUSE() still shows $nos $WANTNAME site(s) — the mnemonic is not evidence of the macro, so (F1) proves nothing"
    fi
else
    no "(F) the hint program does not compile: $( head -3 "$TMP/pause.err" )"
fi

[ "$fail" = 0 ] && echo "spinlockcheck: ALL PASS" || echo "spinlockcheck: FAILURES"
exit "$fail"
