#!/usr/bin/env bash
# selfcheckcheck.sh — the self-check vocabulary (src/infra/Diagnostics.h) is used for what each word promises.
#
# DRAFT (macro-vocabulary prep, 2026-09-16). Not registered. Lands in the same commit as the rename (which, by the
# owner's change of 2026-09-16, includes DEGRADED_PATH_ALERT -> DISCLOSE).
#
# WHY. ASSUME hands the optimizer a fact and is not evaluated in release, so its whole value rests on the predicate
# being something THIS code makes true. The owner wants ASSUME / EXPECTS / ENSURES used MUCH more, so this gate is
# built to cost a new invariant check nothing: it bites only on the four shapes that turn a free check into a wrong
# program, and never asks for a reason on a predicate built from comparisons, casts and accessors.
#
#   (P) POPULATION  the scanner saw the vocabulary at all: >= 100 promise-form invocations in src/, >= 1 VALIDATE; and,
#                   when a ripwire binary is available, its tree-sitter --match count over the files it indexes EQUALS
#                   the lexer's count on the same files (a lexer that lost multi-line or raw-string context would
#                   disagree — measured on 30f14a27 with the old names: 156 = 156, the lexer's extra 24 are .inl).
#   (A) OLD NAMES   no VERIFY / VERIFY_TEXT / VERIFY_DEBUG_ONLY(_TEXT) / VERIFY_NOT_REACHED(_TEXT) /
#                   VERIFY_SAME_THREAD(_TEXT) / VERIFY_NO_ALIAS(3|_BUF) / DYNMAP_VERIFY / TODO_IMPLEMENT /
#                   DEGRADED_PATH_ALERT in any tracked text file, identifier-bounded (plus VERIFYs / VERIFYed), outside
#                   the HISTORY list below.
#   (B) SIDE EFFECT no `=`, compound assignment, `++` or `--` inside an ASSUME / EXPECTS / ENSURES / DASSERT /
#                   ASSUME_NO_ALIAS* / DYNMAP_ASSUME argument, after string, char and comment text is blanked, across
#                   lines. Release does not evaluate the argument, so the effect would exist in debug only.
#   (C) PREDICATE   every CALL inside a promise-form argument (ASSUME / EXPECTS / ENSURES / ASSUME_NO_ALIAS* /
#                   DYNMAP_ASSUME) is an accessor or a callee on ALLOW, each with a one-line reason. Keyed by CALLEE,
#                   not by site: the second ASSUME( std::is_sorted( … ) ) costs nothing. DASSERT is exempt (no
#                   promise is made), VALIDATE is exempt (it is evaluated).
#   (D) FALSE       no ASSUME / EXPECTS / ENSURES whose predicate is literally false (false, 0, !true, nullptr):
#                   in release that deletes the code after it (CLAUDE.md non-negotiable #4).
#   (E) VALIDATE    only as a condition: directly under if( / while( / return, or an operand of && / || / ?:.
#   (T) ASSUMED-THEN-TESTED (added 2026-09-18, S2 assume-sweep): no ASSUME/EXPECTS/ENSURES of a bare top-level
#                   equality `LHS == RHS` whose literal negation `LHS != RHS` (either order) is a clause of a
#                   runtime `if( … )` within the next 10 lines of code — that `if` is dead in release the moment
#                   the promise compiles to an optimizer fact, which is exactly the shape found in gitmine.h's
#                   applyCoChangeBoost and mention.h's applyMentionBoost (both since converted to DASSERT). A
#                   compound predicate (top-level && / ||) is not this shape and is not scanned. Off
#                   ASSUMED_THEN_TESTED_ALLOW, keyed by site with a one-line reason — empty today.
#   (R) RATCHET     a one-argument DISCLOSE( msg ) is a debug trace that tells the release user NOTHING (Diagnostics.h
#                   §4b says so). Their count in src/ is pinned below and may only go DOWN: above the pin is a FAIL (a
#                   new sink-less degrade — use DISCLOSE( sink, why[, "msg"] ), which exists), below it is a FAIL too
#                   until the pin is lowered in the same commit (so the ratchet can never slide back up). Sink-form sites
#                   NEVER count. The degrade-disclosure lane drives it to its target, 0.
#   (U) UNCHANGED   every DISCLOSE( Diagnostics::answerUnchanged, "reason"[, "msg"] ) in src/ is LISTED with its reason on
#                   every run — no pin, no allowance, just visible — and a reason that is not a non-empty string literal
#                   is a FAIL. (The compiler already refuses an empty or run-time reason; this arm is what keeps the
#                   judgement readable in the gate log.)
#   (K) CONTRACT    test/selfcheckfix/disclose_contract.cpp is compiled -fsyntax-only with the build's own C++ compiler: as is, in the
#                   plain and the NDEBUG flavour, it must compile WITHOUT A WARNING (its static_asserts pin what does and
#                   does not model Diagnostics::DisclosureSink); and once per RW_NEG_* case, in both flavours, it must
#                   FAIL, with a diagnostic naming the defect. The as-is compile is every negative's contrast.
#   (S) SHIPS       the same TU built as a program (RW_RUN_SINKS) at -O2, NDEBUG and plain: both sink-form sites must RECORD
#                   (truncated=1 unreadable=1, exit 0). The NDEBUG leg is the release expansion a user runs; it is what lets a
#                   plain-flavour-only gate (a non-NDEBUG fault switch) stand for the Release wiring of a converted site.
#   (F) CONTROLS    every arm above runs the SAME scanner over a fixture holding one planted defect per arm plus a
#                   look-alike that must stay clean; each plant must be found by the right arm, the look-alikes by
#                   none, and each plant is re-read from disk before the verdict is trusted.
#
# RED FIRST (measured 2026-09-16 in a scratch worktree, bash, ripwire 0.5.0 for (P)). On origin/main 3bf884e2, before
# the rename: (R) red (no DISCLOSE at all), (P) red three times (0 promise-form invocations, 0 VALIDATE, --match found
# nothing) and (A) red with 806 old-name hits; (B)-(E) green only because (P) already failed — the population guard is
# what makes them non-vacuous. (F) green on both sides, which is its job. After rename_selfcheck.py + the new
# Diagnostics.h + the gitmine.h VALIDATE + `python3 docs/limits_build.py`: 18 PASS, ALL PASS (--match 351 = lexer 351).
# (R) was also observed red on the TREE both ways: one planted sink-less site -> "196 ... pin 195" (UP), one site
# removed -> "194 ... lower the pin" (DOWN). Each fixture arm was driven red by its planted row.
#
# LANDING: set DISCLOSE_SINKLESS_PIN to the count (R) prints on the renamed tree — PRs merged before the rename add
# sites (#236 +3, #44 +5 -2: measured 198 on either merge tree), so 195 is only right for 3bf884e2 itself.
#
# REGISTRATIONS (five): test/regression.sh's loop; python3 docs/gatecount_build.py; test/binoverridecheck.sh — NOT
# exempt, (P) binds RIPWIRE_BIN (without a binary (P)'s cross-check prints SKIP and the arm's lexer half still
# runs); .github/pargates-shard-weights.json (~6 s: 18 -fsyntax-only compiles for (K) + the source scan); and this
# header stays free of absolute paths (test/ripwirepubliccheck.sh arm 2). test/selfcheckfix/disclose_contract.cpp lands with it.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
# (R)'s pin: one-argument DISCLOSE invocations in src/ code. Measured 195 sites in 58 files at f8e6087c (classified
# in the prep report: 106 have an adjacent field, 27 are Tier-1 wrong answers, 32 need vocabulary, 30 cannot change
# the answer). Re-measured at landing on f45087a7: 217 (main gained 25 sites across 13 files since the prep report —
# regexguard.h/lsp.h/resolve.h show none currently — and lost 3 to unrelated fixes in skillscan.h/verbs_for.h; see
# the landing report for the per-site classification of the 25). LOWER THIS NUMBER, never raise it. At landing, set
# it to what (R) prints.
# rv-s2 review LOW-4 (2026-09-19): darkflags.h's collectCMakeFiles root-walk-failure site converted to the sink
# form — CMakeScan now models Diagnostics::DisclosureSink directly (disclose() sets rootWalkFailed itself) —
# retiring its one sink-less DISCLOSE( msg ) site. 217 -> 216.
# Train 6 (2026-09-18): re-measured on the merged 14-member tree — (R) prints 216; no other member adds or retires one.
# lane/disclose-sink-form (2026-09-19): converted the bulk of the sink-less sites to DISCLOSE( sink, why ) — 51 on its tree.
# Train 7 (2026-09-19): re-measured on the merged tree — (R) prints 50: main's darkflags root-walk site (above) was one of
# the lane's 51 and is already in sink form; the lane's mcpedit lock site took main's new wording in its sink form.
# train7-fix1 (2026-09-19): docdrift.h's collectRepoPaths root-walk site converted to the RepoPaths sink (RootWalkFailed),
# the doc-drift twin of the darkflags conversion above. 50 -> 49.
DISCLOSE_SINKLESS_PIN=49
WORK="$( mktemp -d "${TMPDIR:-/tmp}/selfcheck.XXXXXX" )"
trap 'rm -rf "$WORK"' EXIT
T=$'\t'
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skipped=0
skip(){ printf '  SKIP  %s\n' "$*"; skipped=$(( skipped + 1 )); }

echo "selfcheckcheck: DISCLOSE sink-less pin=$DISCLOSE_SINKLESS_PIN"
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  no python3"; exit 1; }

# ── the scanner: one file, used on the tree AND on the fixture ────────────────────────────────────────────────────
cat > "$WORK/scan.py" <<'PY'
import os, re, subprocess, sys, json

PROMISE = { "ASSUME", "EXPECTS", "ENSURES", "ASSUME_NO_ALIAS", "ASSUME_NO_ALIAS3", "ASSUME_NO_ALIAS_BUF", "DYNMAP_ASSUME" }
NOEFFECT = PROMISE | { "DASSERT" }
FALSEABLE = { "ASSUME", "EXPECTS", "ENSURES" }
OLD = [ "VERIFY", "VERIFY_TEXT", "VERIFY_DEBUG_ONLY", "VERIFY_DEBUG_ONLY_TEXT", "VERIFY_NOT_REACHED", "VERIFY_NOT_REACHED_TEXT",
        "VERIFY_SAME_THREAD", "VERIFY_SAME_THREAD_TEXT", "VERIFY_NO_ALIAS", "VERIFY_NO_ALIAS3", "VERIFY_NO_ALIAS_BUF",
        "DYNMAP_VERIFY", "TODO_IMPLEMENT", "DEGRADED_PATH_ALERT" ]
# `VERIFY-A-CLAIM` / `VERIFY A CLAIM` name the --verify FEATURE, not the macro.
OLD_RE = re.compile( r"(?<![A-Za-z0-9_])(" + "|".join( sorted( OLD, key = len, reverse = True ) ) + r")(?![A-Za-z0-9_])(?!-A-CLAIM| A CLAIM)" )
# Dated records whose text IS the measurement (renaming would falsify them), and release-owned artefacts.
HISTORY_PREFIX = ( "docs/captures/", "bench/capsweep/", "bench/locbench/results/", "bench/recalleval/snapshot.mdpack",
                   "present/", "third_party/" )
HISTORY_EXACT = { "CHANGELOG.md", "docs/EVALS.md", "bench/PROFILE.md", "docs/LINEAGE.md", ".ripwire_quality_acks",
                  "test/selfcheckcheck.sh",
                  "docs/COMMANDS.md" }   # GENERATED from the release capture; the next capture renames it (docscommandscheck owns it)
HISTORY_LINES = [ ( "test/connectjoincheck.sh", "`VERIFY` 27" ),                 # a recorded measurement of join-node names
                  ( "test/showcase_capture.py", "VERIFY a closed claim" ),        # English: the --verify feature's caption
                  ( "test/showcase_capture.py", "VERIFY/VERIFY_TEXT/VERIFY_DEBUG_ONLY/VERIFY_NOT_REACHED/VERIFY_SAME_THREAD/VERIFY_NO_ALIAS*/DYNMAP_VERIFY/DEGRADED_PATH_ALERT renamed to" ),  # the --pack-signatures caption's own before/after name list (provenance of the 2026-09-17 re-derivation), keyed by TEXT not line: see CONTRIBUTING/LIMITS.md's never-pin-a-line rule
                  ( "src/infra/Diagnostics.h", "define ASSERT, VERIFY and ENSURE" ) ]  # the collision note names MFC macros
# The word glued to a suffix is still the old name in prose ("never VERIFYs on hostile input", "VERIFYed here").
INFLECTED_RE = re.compile( r"(?<![A-Za-z0-9_])VERIFY(s|ed)\b" )
ACCESSORS = { "size", "empty", "data", "begin", "end", "cbegin", "cend", "rbegin", "rend", "front", "back", "rows", "cols",
              "std::size", "std::ssize", "std::data", "std::empty", "std::size_t", "std::uint8_t", "std::uint16_t",
              "std::uint32_t", "std::uint64_t", "std::int32_t", "std::int64_t", "std::ptrdiff_t" }
BUILTIN_TYPES = { "int", "unsigned", "long", "short", "char", "bool", "float", "double", "size_t", "uint8_t", "uint16_t",
                  "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "ptrdiff_t" }
NOTCALLS = { "static_cast", "const_cast", "reinterpret_cast", "sizeof", "alignof", "decltype", "noexcept", "typeid" }
# Non-accessor callees a promise may use. One line each: why it is a pure function of its arguments.
ALLOW = {
    "fastmath::isFiniteFast": "bit test on the value's representation; its inline-asm barrier makes clang DISCARD the assume, never evaluate it",
    "key_is_finite":          "dynamic_map's finiteness test on a key copy; no state",
    "keyIsSortable":          "radix key classification of a value; no state",
    "std::is_sorted":         "read-only walk of the given range",
    "std::has_single_bit":    "bit arithmetic on an integer",
    "std::isfinite":          "classification of a floating-point value",
    "std::fabs":              "arithmetic on a value",
    "std::strlen":            "read-only walk of a NUL-terminated literal the caller owns",
    "std::min":               "comparison of two values",
    "std::max":               "comparison of two values",
    "std::string_view":       "a non-owning view over storage the caller already holds",
    "rfind":                  "read-only search of a string the caller owns",
}
# (T) ASSUMED-THEN-TESTED allowlist: "site -> reason", one line each. A site lands here only when the equality
# really is a true invariant (the re-test below is dead defensive code that should eventually be deleted, not
# a live degrade path) — never as a way to silence a genuine assumed-then-tested bug. See scan_code's (T) arm.
ASSUMED_THEN_TESTED_ALLOW = {
}

def lex( text ):
    """(kind, start, end) with kind in code/comment/string/char; the same lexer as the rename script that landed with this gate."""
    n = len( text ); i = 0; cs = 0; segs = []; ls = True
    def flush( u ):
        if u > cs: segs.append( ( "code", cs, u ) )
    while i < n:
        c = text[ i ]
        if c == "\n": ls = True; i += 1; continue
        if c in " \t\r\f\v": i += 1; continue
        if ls and c == "#":
            m = re.match( r"#[ \t]*(error|warning)\b", text[ i:i + 40 ] )
            if m:
                j = text.find( "\n", i ); j = n if j < 0 else j
                flush( i + m.end() ); segs.append( ( "string", i + m.end(), j ) ); cs = j; i = j; continue
        ls = False
        if text.startswith( "//", i ):
            flush( i ); j = i
            while True:
                k = text.find( "\n", j )
                if k < 0: k = n; break
                if text[ k - 1 ] == "\\": j = k + 1; continue
                break
            segs.append( ( "comment", i, k ) ); cs = k; i = k; continue
        if text.startswith( "/*", i ):
            flush( i ); k = text.find( "*/", i + 2 ); k = n if k < 0 else k + 2
            segs.append( ( "comment", i, k ) ); cs = k; i = k; continue
        if c.isalpha() or c == "_":
            j = i + 1
            while j < n and ( text[ j ].isalnum() or text[ j ] == "_" ): j += 1
            w = text[ i:j ]
            if j < n and text[ j ] == '"' and w in ( "R", "u8R", "uR", "UR", "LR" ):
                m = re.match( r'"([^()\\ \t\n]{0,16})\(', text[ j:j + 20 ] )
                if m:
                    close = ")" + m.group( 1 ) + '"'; k = text.find( close, j + m.end() )
                    k = n if k < 0 else k + len( close )
                    flush( i ); segs.append( ( "string", i, k ) ); cs = k; i = k; continue
            i = j; continue
        if c.isdigit() or ( c == "." and i + 1 < n and text[ i + 1 ].isdigit() ):
            j = i + 1
            while j < n:
                d = text[ j ]
                if d.isalnum() or d in "_.": j += 1
                elif d == "'" and j + 1 < n and text[ j + 1 ].isalnum(): j += 2
                elif d in "+-" and text[ j - 1 ] in "eEpP": j += 1
                else: break
            i = j; continue
        if c in "\"'":
            flush( i ); j = i + 1
            while j < n and text[ j ] != c:
                if text[ j ] == "\\": j += 2; continue
                if text[ j ] == "\n": break
                j += 1
            k = min( j + 1, n ); segs.append( ( "string", i, k ) ); cs = k; i = k; continue
        i += 1
    flush( n )
    return segs

def blank( text, segs ):
    out = list( text )
    for k, s, e in segs:
        if k != "code":
            for x in range( s, e ):
                if out[ x ] != "\n": out[ x ] = " " if k == "comment" else "_"
    return "".join( out )

def invocations( text, names ):
    """Yield (name, line, argtext, before, after, rawarg) for every CODE invocation, #define bodies excluded, multi-line
    aware. argtext has string/char/comment text blanked (same length); rawarg is the same span of the original text."""
    code = blank( text, lex( text ) )
    for m in re.finditer( r"(?<![A-Za-z0-9_])(" + "|".join( sorted( names, key = len, reverse = True ) ) + r")(?![A-Za-z0-9_])", code ):
        ls = code.rfind( "\n", 0, m.start() ) + 1
        # inside a #define (this line or a backslash-continued one above it)? then it is a definition, not a use
        k = ls; indef = False
        while True:
            if code[ k:m.start() ].lstrip().startswith( "#" ): indef = True; break
            if k == 0 or code[ k - 2:k ] != "\\\n": break
            k = code.rfind( "\n", 0, k - 2 ) + 1
        if indef: continue
        j = m.end()
        while j < len( code ) and code[ j ] in " \t\r\n": j += 1
        if j >= len( code ) or code[ j ] != "(": continue
        depth = 0; e = j
        while e < len( code ):
            if code[ e ] == "(": depth += 1
            elif code[ e ] == ")":
                depth -= 1
                if depth == 0: break
            e += 1
        yield ( m.group( 1 ), text.count( "\n", 0, m.start() ) + 1, code[ j + 1:e ], code[ :m.start() ], code[ e + 1: ], text[ j + 1:e ] )

def raw_args( blanked, raw ):
    """Split RAW argument text at the top-level commas of its BLANKED twin (a comma inside a literal is not a split)."""
    parts = []; d = 0; start = 0
    for i, ch in enumerate( blanked ):
        if ch == "(": d += 1
        elif ch == ")": d -= 1
        elif ch == "," and d == 0: parts.append( raw[ start:i ] ); start = i + 1
    parts.append( raw[ start: ] )
    return parts

LITERAL_REASON = re.compile( r'\s*((?:u8)?"(?:[^"\\\n]|\\.)*"\s*)+' )

def top_args( arg ):
    parts = []; d = 0; cur = ""
    for ch in arg:
        if ch == "(": d += 1
        elif ch == ")": d -= 1
        if ch == "," and d == 0: parts.append( cur ); cur = ""; continue
        cur += ch
    parts.append( cur )
    return parts

EFFECT = re.compile( r"\+\+|--|<<=|>>=|[+\-*/%&|^]=|(?<![=!<>])=(?!=)" )

# CodeRabbit PR #292 finding 4052087952: the (T) arm's `c in win` was raw substring containment, no token
# boundary. `win` is `!=`/`==`-normalized code with ALL whitespace stripped (scan_code's own `re.sub(
# r"\s+", "", ... )`), so a candidate like "a!=b" is not anchored to an operand boundary and can match
# INSIDE an unrelated longer identifier pair: `EXPECTS(a == b)` followed by `if (data != baseline)` builds
# the candidate "a!=b", which IS a substring of the stripped "data!=baseline" (…"dat[a!=b]aseline"…) even
# though no operand there is named `a` or `b`. Internal to a candidate this cannot happen — every character
# inside "a!=b" or "!(a==b)" is contiguous by construction — so only the candidate's OWN two ends need a
# boundary check: the char immediately before its first character, and the char immediately after its
# last, must not ALSO be an identifier character (else the match is a fragment of a longer name). A
# "!(" / ")" -wrapped candidate is already boundary-safe on both ends (its outermost characters are
# punctuation), so this only ever narrows the two bare "lhs OP rhs" forms.
_IDENT_CHAR = re.compile( r"[A-Za-z0-9_]" )
def tokenBoundaryContains( win, candidate ):
    start = 0
    while True:
        idx = win.find( candidate, start )
        if idx < 0:
            return False
        beforeOk = idx == 0 or not _IDENT_CHAR.match( win[ idx - 1 ] )
        afterPos = idx + len( candidate )
        afterOk  = afterPos >= len( win ) or not _IDENT_CHAR.match( win[ afterPos ] )
        if beforeOk and afterOk:
            return True
        start = idx + 1

def scan_code( rel, text, findings, counts, ratchet = True, contract_tu = False ):
    for name, ln, arg, before, after, raw in invocations( text, NOEFFECT | { "VALIDATE", "DISCLOSE" } ):
        where = "%s:%d" % ( rel, ln )
        if name == "DISCLOSE":
            argc = 0 if not arg.strip() else len( [ a for a in top_args( arg ) if a.strip() ] )
            counts[ "disclose_all" ] += 1
            byfile = counts[ "disclose_by_file" ].setdefault( rel, [ 0, 0 ] )
            if ratchet:
                if argc <= 1:
                    counts[ "disclose1" ] += 1; byfile[ 0 ] += 1
                else:
                    counts[ "disclose_sink" ] += 1; byfile[ 1 ] += 1
            if argc >= 2 and ratchet and not contract_tu:
                parts = raw_args( arg, raw )
                sinkName = re.sub( r"\s+", "", parts[ 0 ] ).lstrip( ":" )
                if sinkName in ( "Diagnostics::answerUnchanged", "Diagnostics::answerRefused" ):
                    reason = parts[ 1 ].strip()
                    body = "".join( re.findall( r'"((?:[^"\\\n]|\\.)*)"', reason ) )
                    key = "unchanged" if sinkName.endswith( "answerUnchanged" ) else "refused"
                    if LITERAL_REASON.fullmatch( reason ) and body.strip():
                        counts[ key ].append( [ where, " ".join( reason.split() ) ] )
                    else:
                        findings.append( ( "U", where, "%s reason is not a non-empty string literal: %s" % ( sinkName.split( "::" )[ 1 ], " ".join( reason.split() )[ :80 ] ) ) )
            continue
        if name == "VALIDATE":
            counts[ "validate" ] += 1
            b = re.sub( r"[\s!(]+$", "", before )
            a = re.sub( r"^[\s)]+", "", after )
            okctx = re.search( r"(\bif|\bwhile|\breturn|&&|\|\|)$", b ) or re.match( r"(&&|\|\||\?)", a )
            if not okctx:
                findings.append( ( "E", where, "VALIDATE outside a condition" ) )
            continue
        pred = top_args( arg )
        if name in PROMISE: counts[ "promise" ] += 1
        counts[ "all" ] += 1
        if name in ( "ASSUME", "EXPECTS", "ENSURES", "DASSERT" ) and len( pred ) > 1:
            pred = pred[ :-1 ]          # the trailing message literal
        body = ",".join( pred )
        if EFFECT.search( body.replace( "->", "  " ) ):
            findings.append( ( "B", where, "side effect in %s( %s )" % ( name, " ".join( body.split() )[ :80 ] ) ) )
        if name in FALSEABLE and re.sub( r"[\s()]", "", body ) in ( "false", "0", "!true", "nullptr", "!1", "0u" ):
            findings.append( ( "D", where, "%s( %s ) deletes what follows it in release" % ( name, body.strip() ) ) )
        if name in PROMISE:
            for cm in re.finditer( r"([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*(?:<[^()]*>)?\s*\(", body ):
                callee = cm.group( 1 )
                last = callee.split( "::" )[ -1 ]
                if last in NOTCALLS or last in BUILTIN_TYPES or re.fullmatch( r"[A-Z]", last ): continue   # casts, T( 0 )
                member = body[ :cm.start() ].rstrip().endswith( ( ".", "->" ) )
                key = callee if not member else callee.split( "::" )[ -1 ]
                if key in ACCESSORS or key in ALLOW: continue
                findings.append( ( "C", where, "%s calls %s — not an accessor and not on ALLOW" % ( name, key ) ) )
        # (T) ASSUMED-THEN-TESTED: the promise is a bare top-level `LHS == RHS` or `LHS != RHS` (no other
        # top-level && / || outside parens — a compound predicate is not this shape), and within the next
        # TWINDOW lines of CODE (comments/strings already blanked), BOUNDED TO THE ENCLOSING FUNCTION (rv-s2
        # review LOW-1: the window used to run past the promise's own closing brace into the NEXT function,
        # so a correct ASSUME could be flagged by an unrelated `if` two functions later), a runtime `if( … )`
        # tests the literal negation as one of its clauses: `LHS != RHS` / `RHS != LHS` for an `==` promise
        # (rv-s2 LOW-2 V1/V14), `!( LHS == RHS )` / `!( RHS == LHS )` for the same (V2), or the mirror for a
        # `!=` promise — `LHS == RHS` / `RHS == LHS` / `!( LHS != RHS )` / `!( RHS != LHS )` (V3). Release
        # compiles the promise to an optimizer fact, so that `if` can never be reached on the promise's own
        # predicate being false — the exact shipped-bug shape CONTRIBUTING.md non-negotiable #4 and
        # Diagnostics.h warn about (gitmine.h/mention.h's applyCoChangeBoost/applyMentionBoost, found
        # 2026-09-16 on #286). A whitespace-stripped substring match, not a parser: deliberately loose on
        # WHERE inside the if the clause sits (one clause of an `||` chain still counts, as in the motivating
        # case), deliberately tight on WHAT it must say (the exact operands, both orders) so a coincidental
        # shared identifier is not enough. KNOWN GAPS, listed not chased (rv-s2 LOW-2; the same substring
        # machinery would extend to each, with a different negation table): an ordering promise
        # (`ASSUME( a <= b )` then `if( a > b )`), a bare bool (`ASSUME( ok )` then `if( !ok )`), a
        # null-pointer promise (`ASSUME( p != nullptr )` then `if( !p )`), a loop-bound double guard
        # (`i < a.size() && i < b.size()`, this lane's own abicheck.h shape — not gated, fixed by hand), and a
        # re-test past the TWINDOW/function-bound cutoff.
        if name in FALSEABLE:
            whole = re.sub( r"\s+", "", body )
            d2 = 0; toplevel_bool = False; oppos = -1; opstr = None; k2 = 0
            while k2 < len( whole ):
                c2 = whole[ k2 ]
                if c2 == "(": d2 += 1
                elif c2 == ")": d2 -= 1
                elif d2 == 0 and whole[ k2:k2 + 2 ] in ( "&&", "||" ): toplevel_bool = True; break
                elif d2 == 0 and whole[ k2:k2 + 2 ] == "==" and whole[ k2 - 1:k2 ] not in ( "!", "<", ">", "=" ) and oppos < 0:
                    oppos = k2; opstr = "=="
                elif d2 == 0 and whole[ k2:k2 + 2 ] == "!=" and oppos < 0:
                    oppos = k2; opstr = "!="
                k2 += 1
            if not toplevel_bool and oppos > 0:
                lhs = whole[ :oppos ]; rhs = whole[ oppos + 2: ]
                if lhs and rhs and re.search( r"[A-Za-z_]", lhs ) and re.search( r"[A-Za-z_]", rhs ):
                    TWINDOW = 10
                    win_text = "\n".join( after.split( "\n" )[ :TWINDOW ] )
                    # ASSUMED_THEN_TESTED_FUNCTION_BOUND: stop the window at the first `}` that closes BELOW
                    # the promise's own scope (a balanced nested block — an `if`/`for` that opens and closes
                    # within the window — does not trip this; only a brace that closes an ENCLOSING scope,
                    # i.e. the promise's own function, does). Matches rv-s2's fix shape exactly (LOW-1).
                    fd = 0; cut = len( win_text )
                    for fi, fc in enumerate( win_text ):
                        if fc == "{": fd += 1
                        elif fc == "}":
                            if fd == 0: cut = fi; break
                            fd -= 1
                    win = re.sub( r"\s+", "", win_text[ :cut ] )
                    if opstr == "==":
                        candidates = ( lhs + "!=" + rhs, rhs + "!=" + lhs,
                                       "!(" + lhs + "==" + rhs + ")", "!(" + rhs + "==" + lhs + ")" )
                    else:
                        candidates = ( lhs + "==" + rhs, rhs + "==" + lhs,
                                       "!(" + lhs + "!=" + rhs + ")", "!(" + rhs + "!=" + lhs + ")" )
                    if any( tokenBoundaryContains( win, c ) for c in candidates ) and where not in ASSUMED_THEN_TESTED_ALLOW:
                        findings.append( ( "T", where,
                            "%s( %s %s %s ) then a re-test of it within %d lines of the SAME function — release folds the check away"
                            % ( name, lhs[ :50 ], opstr, rhs[ :50 ], TWINDOW ) ) )

def main():
    root = sys.argv[ 1 ]; mode = sys.argv[ 2 ]
    if mode == "tree":
        files = subprocess.run( [ "git", "-C", root, "ls-files", "-z" ], capture_output = True, check = True ).stdout.decode().split( "\0" )
    else:
        files = sorted( os.path.relpath( os.path.join( d, f ), root ) for d, _, fs in os.walk( root ) for f in fs )
    findings = []; counts = { "promise": 0, "all": 0, "validate": 0, "files": 0, "disclose_all": 0, "disclose1": 0, "disclose_sink": 0,
                              "disclose_by_file": {}, "unchanged": [], "refused": [] }
    perfile = {}
    for rel in files:
        if not rel: continue
        p = os.path.join( root, rel )
        if not os.path.isfile( p ): continue
        try: text = open( p, encoding = "utf-8" ).read()
        except ( UnicodeDecodeError, OSError ): continue
        hist = rel in HISTORY_EXACT or rel.startswith( HISTORY_PREFIX )
        if not hist:
            for i, line in enumerate( text.split( "\n" ) ):
                if any( rel == hp and sub in line for hp, sub in HISTORY_LINES ): continue
                for m in OLD_RE.finditer( line ):
                    findings.append( ( "A", "%s:%d" % ( rel, i + 1 ), "old name %s" % m.group( 1 ) ) )
                for m in INFLECTED_RE.finditer( line ):
                    findings.append( ( "A", "%s:%d" % ( rel, i + 1 ), "old name %s" % m.group( 0 ) ) )
        cpp = rel.endswith( ( ".h", ".hpp", ".inl", ".cpp", ".cc", ".c", ".mm" ) )
        scoped = mode != "tree" or rel.startswith( "src/" ) or ( rel.startswith( ( "test/", "bench/" ) ) and rel.count( "/" ) == 1 )
        if cpp and scoped and not rel.endswith( "infra/Diagnostics.h" ):
            before = counts[ "all" ] + counts[ "disclose_all" ]
            scan_code( rel, text, findings, counts, ratchet = ( mode != "tree" or rel.startswith( "src/" ) ),
                       contract_tu = ( rel == "test/selfcheckfix/disclose_contract.cpp" ) )
            counts[ "files" ] += 1
            after = counts[ "all" ] + counts[ "disclose_all" ]
            if after != before and rel.startswith( "src/" ): perfile[ rel ] = after - before
    json.dump( { "findings": findings, "counts": counts, "perfile": perfile }, sys.stdout )

main()
PY

# ── (F) the fixture: one planted defect per arm, and the look-alikes that must stay clean ─────────────────────────
FX="$WORK/fx"; mkdir -p "$FX/src"
cat > "$FX/src/red_b.h" <<'EOF'
void rb( int i, int& n ) { ASSUME( n = i ); DASSERT( ++n > 0, "count" ); ASSUME_NO_ALIAS( n,
    i += 1 ); }
EOF
cat > "$FX/src/red_c.h" <<'EOF'
bool loadsFromDisk( int );
void rc( int i ) { EXPECTS( loadsFromDisk( i ) ); }
EOF
cat > "$FX/src/red_d.h" <<'EOF'
void rd() { ASSUME( false ); ENSURES( ( 0 ), "never" ); }
EOF
cat > "$FX/src/red_e.h" <<'EOF'
bool re( int i ) { VALIDATE( i > 0 ); const bool ok = VALIDATE( i < 9 ); return ok; }
EOF
cat > "$FX/src/red_a.md" <<'EOF'
Use `VERIFY( cond )` for invariants and VERIFY_NO_ALIAS_BUF for two buffers; the core never VERIFYs input.
EOF
cat > "$FX/src/green.h" <<'EOF'
// VERIFY-A-CLAIM is the --verify feature; "ASSUME( n = 1 )" in a string is not code; verifyCsr() is a function.
const char* kHelp = "VERIFY A CLAIM, ASSUME( false ), i += 1";
bool verifyCsr( int ) noexcept;
struct S { int size() const { return 1; } };
int gr( const S& s, int i, int& out, int other ) {
    ASSUME( s.size() == 1 && i != 0 );
    ASSUME( std::is_sorted( &i, &i + 1 ), "one element" );
    ASSUME( i >= 0 &&
            i <= 9 );                                     // multi-line, comparisons only
    DASSERT( verifyCsr( i ) );                            // a DASSERT may call anything: no promise is made
    ASSUME_NO_ALIAS( out, other );
    EXPECTS( i != 0 ); ENSURES( out == other || out != other );
    if( !VALIDATE( i > 0 ) ) { return 0; }
    while( VALIDATE( i < 9 ) && i ) { --i; }
    return VALIDATE( i >= 0 ) ? i : 0;
}
#define LOCAL_CHECK( x ) ASSUME( x = 1 )                   // a definition, not a use
// (T) look-alikes: a bare equality re-CONFIRMED (not negated) nearby, and one negated far outside the window.
void gt1( const S& a, const S& b, int i ) { ASSUME( a.size() == b.size() ); if( a.size() == b.size() ) { (void)i; } }
void gt2( const S& a, const S& b, int i )
{
    ASSUME( a.size() == b.size() );
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    (void)i;
    if( a.size() != b.size() ) { (void)i; }   // twelve lines below the promise: outside the T window
}
// rv-s2 LOW-1 (2026-09-19): the FUNCTION-BOUND look-alike. gt3 is a correct, tiny ASSUME with nothing wrong
// with it; gt4 is a DIFFERENT function whose first line just happens to negate gt3's predicate. Before the
// function bound, gt3's own ASSUME fell inside gt4's line window and this pair was a false positive that
// would have blocked a legitimate new ASSUME — the one thing the owner wants zero-ceremony.
void gt3( const S& a, const S& b ) { ASSUME( a.size() == b.size() ); }
void gt4( const S& a, const S& b, int i ) { if( a.size() != b.size() ) { (void)i; } }
// CodeRabbit PR #292 finding 4052087952: the OVERLAPPING-IDENTIFIER look-alike. `tokenBoundaryContains`'s
// raw-substring predecessor built the candidate "a!=b" from EXPECTS( a == b )'s own operands and matched
// it INSIDE the unrelated "data!=baseline" text below — "dat[a!=b]aseline" — although no operand in that
// second check is named `a` or `b`. Same shape mirrored for the "!=" -> "==" direction: the candidate
// "x==y" is a substring of "matrix==yellow" — "matri[x==y]ellow" — with no operand named `x` or `y` there.
void gt5( int a, int b, int data, int baseline ) { EXPECTS( a == b ); if( data != baseline ) { (void)a; (void)b; } }
void gt6( int x, int y, int matrix, int yellow ) { EXPECTS( x != y ); if( matrix == yellow ) { (void)x; (void)y; } }
EOF
cat > "$FX/src/red_r.h" <<'EOF'
struct Sink { void disclose( int ) noexcept {} };
// DISCLOSE( "a comment mention is not a site" )
const char* kNote = "DISCLOSE( \"a string literal is not a site\" )";
#define LOCAL_DEGRADE( m ) DISCLOSE( m )                    // a definition, not a use
void rr( Sink& s, const char* m )
{
    DISCLOSE( "one: a sink-less site, with a comma, inside the literal" );
    DISCLOSE( m );
    DISCLOSE( "two " "literals"
              " spanning lines" );
    DISCLOSE( s, 7, "a sink form: not counted as sink-less" );
}
EOF
cat > "$FX/src/red_u.h" <<'EOF'
struct Sink { enum class DisclosureWhy { A }; void disclose( DisclosureWhy ) noexcept {} };
// DISCLOSE( Diagnostics::answerUnchanged, "a comment is not a site" )
void ru( Sink& s, const char* runtime )
{
    DISCLOSE( Diagnostics::answerUnchanged, "listed: the cache write failed, so only the next run is cold, never this one" );
    DISCLOSE( ::Diagnostics::answerUnchanged,
              "listed: a multi-line site " "with a concatenated reason",
              "and a trace message" );
    DISCLOSE( Diagnostics::answerUnchanged, "" );
    DISCLOSE( Diagnostics::answerUnchanged, runtime );
    DISCLOSE( s, Sink::DisclosureWhy::A, "a real sink: never listed, never counted by R" );
}
EOF
cat > "$FX/src/red_t.h" <<'EOF'
struct V { int size() const; };
bool rt( const V& lensRank, const V& symbols, int census )
{
    ASSUME( lensRank.size() == symbols.size() );
    if( census == 0 )
    {
        return false;
    }
    if( symbols.size() != 0 || lensRank.size() != symbols.size() )
    {
        return false;
    }
    return true;
}
// rv-s2 LOW-2 (2026-09-19): V2, `!( a == b )` as the re-test of an `==` promise.
bool rt2( const V& a, const V& b )
{
    ASSUME( a.size() == b.size() );
    if( !( a.size() == b.size() ) )
    {
        return false;
    }
    return true;
}
// rv-s2 LOW-2 (2026-09-19): V3, the mirror — a `!=` promise re-tested by `==`.
bool rt3( const V& a, const V& b )
{
    ASSUME( a.size() != b.size() );
    if( a.size() == b.size() )
    {
        return false;
    }
    return true;
}
EOF
for f in red_b.h red_c.h red_d.h red_e.h red_a.md red_r.h red_u.h red_t.h; do [ -s "$FX/src/$f" ] || no "F: fixture $f did not take"; done
grep -q 'ASSUME( n = i )' "$FX/src/red_b.h" || no "F: the planted (B) defect is not on disk"

python3 "$WORK/scan.py" "$FX" fixture > "$WORK/fx.json" 2> "$WORK/fx.err" || { no "F: the scanner crashed on the fixture"; sed 's/^/    /' "$WORK/fx.err"; }
fxrow(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("\n".join("\t".join(f) for f in d["findings"]))' "$WORK/fx.json"; }
fxrow > "$WORK/fx.tsv" 2>/dev/null
fxcount(){ python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["counts"][sys.argv[2]])' "$WORK/fx.json" "$1" 2>/dev/null; }
fxfile(){ python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["counts"]["disclose_by_file"].get(sys.argv[2],[0,0])[int(sys.argv[3])])' "$WORK/fx.json" "$1" "$2" 2>/dev/null; }
fxunchanged(){ python3 -c 'import json,sys; print(sum(1 for w,r in json.load(open(sys.argv[1]))["counts"]["unchanged"] if w.startswith(sys.argv[2]+":")))' "$WORK/fx.json" "$1" 2>/dev/null; }
want(){ # arm, file, minimum count
    local got; got="$( grep -c "^$1${T}src/$2:" "$WORK/fx.tsv" )"
    if [ "$got" -ge "$3" ]; then ok "F($1): the planted defect in $2 is found ($got finding(s))"
    else no "F($1): the planted defect in $2 was NOT found ($got < $3) — arm $1 cannot fail"; fi
}
want A red_a.md 3
want B red_b.h 3
want C red_c.h 1
want D red_d.h 2
want E red_e.h 2
want T red_t.h 3
want U red_u.h 2
if grep -q "${T}src/green.h:" "$WORK/fx.tsv"; then no "F: look-alikes produced findings:"; grep "${T}src/green.h:" "$WORK/fx.tsv" | sed 's/^/    /'
else ok "F: every look-alike (feature name, literals, comments, a #define body, DASSERT call, multi-line compare, VALIDATE in if/while/?:) stays clean"; fi

# (R) controls: the counter counts exactly the three sink-less uses in red_r.h (literal with commas, variable,
# multi-line) and not the sink form, the comment, the string literal or the #define body; and the ratchet verdict
# function tells all three states apart.
grep -q 'DISCLOSE( m );' "$FX/src/red_r.h" || no "F(R): the planted sink-less site is not on disk"
fx1="$( fxfile src/red_r.h 0 )"; fxs="$( fxfile src/red_r.h 1 )"; fxu1="$( fxfile src/red_u.h 0 )"
[ "$fx1" = 3 ] && ok "F(R): the counter finds exactly the 3 planted sink-less DISCLOSE sites (literal, variable, multi-line)" \
               || no "F(R): the counter found '$fx1' sink-less sites in the fixture, expected 3 — arm R counts the wrong population"
[ "$fxs" = 1 ] && ok "F(R): the sink form is counted apart (1), never as sink-less" \
               || no "F(R): the sink form was counted as '$fxs', expected 1"
[ "$fxu1" = 0 ] && ok "F(R): five sink-form sites in red_u.h add nothing to the sink-less count" \
                || no "F(R): red_u.h's sink forms were counted as $fxu1 sink-less sites"
# (U) controls: two good answerUnchanged sites are LISTED (one multi-line, concatenated), the empty and the run-time
# reasons are REFUSED, and neither the comment mention nor the real sink is listed.
grep -q 'DISCLOSE( Diagnostics::answerUnchanged, "" );' "$FX/src/red_u.h" || no "F(U): the planted empty reason is not on disk"
fxl="$( fxunchanged src/red_u.h )"
[ "$fxl" = 2 ] && ok "F(U): the lister lists exactly the 2 good answerUnchanged sites (single-line, multi-line concatenated)" \
               || no "F(U): the lister listed $fxl sites in red_u.h, expected 2 — arm U reads the wrong population"
ratchetVerdict(){ if [ "$1" -gt "$2" ]; then echo UP; elif [ "$1" -lt "$2" ]; then echo DOWN; else echo HELD; fi; }
[ "$( ratchetVerdict 4 3 )" = UP ] && [ "$( ratchetVerdict 3 3 )" = HELD ] && [ "$( ratchetVerdict 2 3 )" = DOWN ] \
    && ok "F(R): the ratchet verdict distinguishes UP / HELD / DOWN" \
    || no "F(R): the ratchet verdict function cannot tell a rise from a hold from a fall"

# ── (K) the sink contract, compiled with the build's own compiler ─────────────────────────────────────────────────
TU="$ROOT/test/selfcheckfix/disclose_contract.cpp"
CACHE="${RIPWIRE_CMAKE_CACHE:-$ROOT/build/CMakeCache.txt}"
cacheVar(){ [ -f "$CACHE" ] && sed -n "s/^$1:[A-Z]*=//p" "$CACHE" | head -1; return 0; }
KCXX="${CXX:-$( cacheVar CMAKE_CXX_COMPILER )}"; KCXX="${KCXX:-c++}"
if [ ! -f "$TU" ]; then
    no "K: $TU is missing — the DISCLOSE sink contract has no compiled statement"
elif ! command -v "$KCXX" >/dev/null 2>&1; then
    skip "K: no C++ compiler at '$KCXX' — the sink contract was not compiled"
else
    . "$ROOT/scripts/cxxstd.sh"
    KSTD="$( ripwire_cxx_std_flag "$KCXX" )"
    cat > "$WORK/negs.txt" <<'NEGS'
NOT_A_SINK does not model Diagnostics::DisclosureSink
NOT_NOEXCEPT does not model Diagnostics::DisclosureSink
RUNTIME_WHY constant expression
WRONG_WHY_TYPE DisclosureWhy
EMPTY_REASON needs a non-empty literal reason
RUNTIME_REASON DisclosureWhy
NONLITERAL_MSG expected
NO_ARGS DISCLOSE needs a sink and a reason
NEGS
    negN=0
    while read -r neg want; do
        negN=$(( negN + 1 ))
        grep -q "defined( RW_NEG_$neg )" "$TU" || no "K: presence guard — $TU has no RW_NEG_$neg case (the negative would compile the positive file)"
    done < "$WORK/negs.txt"
    for flav in plain NDEBUG; do
        fl=(); [ "$flav" = NDEBUG ] && fl=( -DNDEBUG )
        if "$KCXX" "$KSTD" -fsyntax-only -Wall -Wextra ${fl[@]+"${fl[@]}"} -I"$ROOT/src" "$TU" > "$WORK/k_pos_$flav.log" 2>&1; then
            if grep -q 'warning:' "$WORK/k_pos_$flav.log"; then
                no "K($flav): the contract compiles but WARNS:"; grep 'warning:' "$WORK/k_pos_$flav.log" | head -5 | sed 's/^/    /'
            else
                ok "K($flav): the contract compiles clean with $KCXX — the DisclosureSink static_asserts hold and the four DISCLOSE spellings build"
            fi
        else
            no "K($flav): the contract does not compile — every negative below is now unproven:"; grep -m5 'error' "$WORK/k_pos_$flav.log" | sed 's/^/    /'
        fi
        refused=0
        while read -r neg want; do
            log="$WORK/k_${neg}_$flav.log"
            # the negative's own DISCLOSE line: the first one after its #elif — the diagnostic must point THERE, so a
            # failure anywhere else in the file (or in the header) cannot pass as this refusal
            site="$( awk -v tag="defined( RW_NEG_$neg )" 'index( $0, tag ) { armed = 1; next } armed && /DISCLOSE\(/ { print NR; exit }' "$TU" )"
            if [ -z "$site" ]; then
                no "K($flav): could not locate RW_NEG_$neg's DISCLOSE line in $TU"
            elif "$KCXX" "$KSTD" -fsyntax-only ${fl[@]+"${fl[@]}"} -DRW_NEG_"$neg" -I"$ROOT/src" "$TU" > "$log" 2>&1; then
                no "K($flav): RW_NEG_$neg COMPILED — the contract no longer refuses it"
            elif grep -qF -- "$want" "$log" && grep -qE "disclose_contract\.cpp:$site:" "$log"; then
                refused=$(( refused + 1 ))
            else
                no "K($flav): RW_NEG_$neg failed to compile, but not at line $site with '$want' — refused for another reason?"; grep -m3 'error' "$log" | sed 's/^/    /'
            fi
        done < "$WORK/negs.txt"
        [ "$refused" = "$negN" ] && ok "K($flav): all $negN negative cases refused, each naming its defect"
    done
fi

# ── (S) SHIPS: the sink form records in the flavour a user runs ────────────────────────────────────────────────────
# (K) proves the contract COMPILES; this proves it RUNS where it matters. The same TU, built as a program (RW_RUN_SINKS)
# at -O2, once with -DNDEBUG (the release expansion, where the one-argument trace is `do { } while( 0 )`) and once plain
# (the trace linked from src/infra/diagnostics.cpp): both must print truncated=1 unreadable=1 — the two sink-form sites
# recorded their reasons — and exit 0. This is the flavour-independence every converted site in src/ rests on: a gate
# that can only drive a degrade on the plain build (a non-NDEBUG fault switch) still proves the Release wiring, because
# the sink call is this same expansion in both. Red on a header whose sink form were compiled out under NDEBUG.
if [ ! -f "$TU" ] || ! command -v "$KCXX" >/dev/null 2>&1; then
    skip "S: no contract TU or no C++ compiler — the shipped sink form was not run"
else
    for flav in NDEBUG plain; do
        fl=( -O2 -DRW_RUN_SINKS ); src=( "$TU" )
        if [ "$flav" = NDEBUG ]; then fl+=( -DNDEBUG ); else src+=( "$ROOT/src/infra/diagnostics.cpp" ); fi
        if "$KCXX" "$KSTD" "${fl[@]}" -I"$ROOT/src" "${src[@]}" -o "$WORK/sinks_$flav" > "$WORK/s_$flav.log" 2>&1; then
            out="$( "$WORK/sinks_$flav" 2>"$WORK/s_$flav.err" )"; rc=$?
            if [ "$rc" = 0 ] && [ "$out" = "truncated=1 unreadable=1" ]; then
                ok "S($flav): DISCLOSE( sink, why ) recorded both reasons in an -O2 $flav program ($out)"
            else
                no "S($flav): the sink form did not record (rc=$rc, printed '$out') — a converted site would disclose nothing in this flavour"
            fi
            if [ "$flav" = NDEBUG ] && [ -s "$WORK/s_$flav.err" ]; then
                no "S(NDEBUG): the release-flavour program wrote a trace to stderr — is NDEBUG really in force? $( head -c 160 "$WORK/s_$flav.err" )"
            fi
        else
            no "S($flav): the contract TU does not build as a program:"; grep -m5 'error' "$WORK/s_$flav.log" | sed 's/^/    /'
        fi
    done
fi

# ── the tree ──────────────────────────────────────────────────────────────────────────────────────────────────────
python3 "$WORK/scan.py" "$ROOT" tree > "$WORK/tree.json" 2> "$WORK/tree.err" || { no "the scanner crashed on the tree"; sed 's/^/    /' "$WORK/tree.err"; }
python3 - "$WORK/tree.json" > "$WORK/tree.tsv" <<'PY'
import json, sys
d = json.load( open( sys.argv[ 1 ] ) )
c = d[ "counts" ]
print( "COUNT\t%d\t%d\t%d\t%d" % ( c[ "promise" ], c[ "all" ], c[ "validate" ], c[ "files" ] ) )
print( "DISC\t%d\t%d\t%d" % ( c[ "disclose1" ], c[ "disclose_sink" ], c[ "disclose_all" ] ) )
for where, reason in c[ "unchanged" ]: print( "UNCH\t%s\t%s" % ( where, reason ) )
for where, reason in c.get( "refused", [] ): print( "REFU\t%s\t%s" % ( where, reason ) )
for rel, n in sorted( d[ "perfile" ].items() ): print( "FILE\t%s\t%d" % ( rel, n ) )
for arm, where, what in d[ "findings" ]: print( "HIT\t%s\t%s\t%s" % ( arm, where, what ) )
PY
grep '^COUNT' "$WORK/tree.tsv" | tr '\t' ' ' > "$WORK/count.txt"
read -r _ promiseN allN validateN filesN < "$WORK/count.txt"
promiseN="${promiseN:-0}"; allN="${allN:-0}"; validateN="${validateN:-0}"; filesN="${filesN:-0}"

# (R) the ratchet on the tree
grep '^DISC' "$WORK/tree.tsv" | tr '\t' ' ' > "$WORK/disc.txt"
read -r _ disc1 discSink discAll < "$WORK/disc.txt"
disc1="${disc1:-0}"; discSink="${discSink:-0}"
if [ "${discAll:-0}" = 0 ]; then
    no "R: no DISCLOSE invocation found at all — wrong population, or the rename has not landed"
else
    case "$( ratchetVerdict "$disc1" "$DISCLOSE_SINKLESS_PIN" )" in
        HELD ) ok "R: $disc1 sink-less DISCLOSE( msg ) sites = the pin ($DISCLOSE_SINKLESS_PIN); $discSink sink-form sites. Target 0" ;;
        UP )   no "R: $disc1 sink-less DISCLOSE( msg ) sites, pin $DISCLOSE_SINKLESS_PIN — a NEW degrade tells the release user nothing; pass a sink (Diagnostics.h §4b)" ;;
        DOWN ) no "R: $disc1 sink-less DISCLOSE( msg ) sites, below the pin $DISCLOSE_SINKLESS_PIN — good; now lower DISCLOSE_SINKLESS_PIN to $disc1 in this commit so it cannot slide back" ;;
    esac
fi

# (U) every answerUnchanged site, listed with its reason
unchN="$( grep -c '^UNCH' "$WORK/tree.tsv" )"
if [ "$unchN" = 0 ]; then
    ok "U: 0 DISCLOSE( Diagnostics::answerUnchanged, … ) sites in src/ — each one the degrade-disclosure lane adds is listed here"
else
    grep '^UNCH' "$WORK/tree.tsv" | cut -f2,3 | sed 's/^/  INFO  U: /; s/\t/  /'
    ok "U: $unchN answerUnchanged site(s) listed above, each with a non-empty literal reason"
fi
refuN="$( grep -c '^REFU' "$WORK/tree.tsv" )"
if [ "$refuN" != 0 ]; then
    grep '^REFU' "$WORK/tree.tsv" | cut -f2,3 | sed 's/^/  INFO  U(refused): /; s/\t/  /'
    ok "U: $refuN answerRefused site(s) listed above, each with a non-empty literal reason (the refusal is the disclosure)"
fi

# (P) population
if [ "$promiseN" -ge 100 ]; then ok "P: $promiseN promise-form invocations ($allN with DASSERT) across $filesN C/C++ files"
else no "P: only $promiseN promise-form invocations — the scanner is looking at the wrong population (or the rename has not landed)"; fi
if [ "$validateN" -ge 1 ]; then ok "P: $validateN VALIDATE site(s)"
else no "P: no VALIDATE site — src/gitmine.h's baseline-sha check is the first one"; fi
if [ -x "$BIN" ]; then
    "$BIN" "$ROOT/src" --no-cache --limit=100000 \
        --match='(call_expression function: (identifier) @m (#match? @m "^(ASSUME|EXPECTS|ENSURES|DASSERT|ASSUME_NO_ALIAS|ASSUME_NO_ALIAS3|ASSUME_NO_ALIAS_BUF|DYNMAP_ASSUME|DISCLOSE)$"))' \
        > "$WORK/match.xml" 2> "$WORK/match.err"
    mrc=$?
    if [ "$mrc" = 0 ] && grep -q 'hits_capped="0"' "$WORK/match.xml"; then
        python3 - "$WORK/match.xml" "$WORK/tree.tsv" > "$WORK/pop.txt" <<'PY'
import re, sys, collections
xml = open( sys.argv[ 1 ] ).read()
m = collections.Counter( "src/" + p for p in re.findall( r'<m p="([^"]+?)(?::\d+)?"', xml ) )
lx = { l.split( "\t" )[ 1 ]: int( l.split( "\t" )[ 2 ] ) for l in open( sys.argv[ 2 ] ) if l.startswith( "FILE\t" ) }
lx = { f: n for f, n in lx.items() if not f.endswith( ".inl" ) }   # ripwire does not index .inl
bad = sorted( f for f in set( m ) | set( lx ) if m.get( f, 0 ) != lx.get( f, 0 ) )
print( "%d %d %d" % ( sum( m.values() ), sum( lx.values() ), len( bad ) ) )
for f in bad[ :10 ]: print( "  %s match=%d lexer=%d" % ( f, m.get( f, 0 ), lx.get( f, 0 ) ) )
PY
        read -r mN lN badN < "$WORK/pop.txt"
        if [ "${mN:-0}" = 0 ]; then no "P: --match found no self-check invocation at all — nothing to cross-check (wrong root, or the rename has not landed)"
        elif [ "${badN:-1}" = 0 ]; then ok "P: tree-sitter --match and the lexer agree file by file ($mN invocations in indexed files)"
        else no "P: --match ($mN) and the lexer ($lN) disagree in $badN file(s):"; tail -n +2 "$WORK/pop.txt"; fi
    else
        no "P: --match did not run cleanly (rc=$mrc) or its engine cap was reached"; head -3 "$WORK/match.err"
    fi
else
    skip "P: no ripwire binary at $BIN — the tree-sitter cross-check did not run (the lexer arms still did)"
fi

# (A)-(E),(T) on the tree
for arm in A B C D E T U; do
    n="$( grep -c "^HIT${T}$arm${T}" "$WORK/tree.tsv" )"
    case "$arm" in
        A ) label="old self-check names outside the history list" ;;
        B ) label="side effects inside a self-check argument" ;;
        C ) label="non-accessor calls in a promise, off ALLOW" ;;
        D ) label="ASSUME/EXPECTS/ENSURES of a literal false" ;;
        E ) label="VALIDATE outside a condition" ;;
        T ) label="assumed-then-tested: an equality ASSUME/EXPECTS/ENSURES whose negation is re-tested nearby, off ASSUMED_THEN_TESTED_ALLOW" ;;
        U ) label="answerUnchanged sites without a non-empty literal reason" ;;
    esac
    if [ "$n" = 0 ]; then ok "$arm: zero $label"
    else no "$arm: $n $label:"; grep "^HIT${T}$arm${T}" "$WORK/tree.tsv" | cut -f3,4 | head -25 | sed 's/^/    /'; fi
done

if [ "$fail" != 0 ]; then echo "FAILURES ABOVE"
elif [ "$skipped" != 0 ]; then echo "PASS WITH $skipped ARM(S) SKIPPED — the skipped arm asserted nothing"
else echo "ALL PASS"; fi
exit "$fail"
