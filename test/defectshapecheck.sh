#!/usr/bin/env bash
# defectshapecheck.sh — gate for the twelfth --quality-delta kind, defect-shape: four shapes of a REAL defect
# that review keeps finding by hand and that a deterministic syntactic check finds at write time. Each row is
# <r kind="defect-shape" ... defect="FACET" ...>, one kind with four facets so the kind list grows once and
# --ack-only=FACET selects one shape:
#   format-arity   — a literal std::format-family / rw::emitTo / rw::formatTo / fmt:: format string, or a Python
#                    "literal".format(...), whose replacement fields do not match its arguments. GATES (a dropped
#                    argument is a defect, not debt — so it gates whatever the origin; see §1 freshbad).
#                    std::format_string rejects too FEW arguments at compile time and accepts too MANY silently;
#                    Python raises on too few at run time and ignores too many.
#   utf8-cut       — C++: a byte cap on display text (a cut plus an appended ellipsis) with no UTF-8 boundary
#                    back-off, or an ellipsis appended at a byte cap reached by pushing bytes. REPORT-ONLY.
#   dedup-first    — C++: std::unique / std::ranges::unique with a predicate over a type that carries a
#                    severity-like field, where neither the predicate nor the sort before it reads that field,
#                    so the FIRST row of a run survives, not the most severe. REPORT-ONLY.
#   vacuous-assert — Bash, test-script paths only: an assertion that PASSES on an empty text (an absence grep,
#                    [ -z ], a cmp/diff/= parity of two texts) read off a run whose failure is never checked —
#                    through a capture, a pipe without pipefail, a file it redirected into or a wrapper whose
#                    status is dropped — so a crash reads as PASS; and three status shapes: a FAIL reporter
#                    called inside $( ) (its flag dies with the subshell), an rc=$? no test reads, and a
#                    `| head || fallback` (the || reads head's status). REPORT-ONLY.
# Like every kind, a row fires only on what THIS change introduced, never on pre-existing debt: a site is new
# when its normalized text occurs more often than among the baseline's sites of that facet (repo-wide), so an untouched,
# MOVED or RENAMED mismatch gives no row and a swap (one fixed, one added in the same function) still does.
# was/now count the anchor's offending sites. Each facet has near-miss negatives the new code could plausibly
# mis-handle.
#
# format-arity is the ONE exception to "new-symbol rows never gate": new-symbol rows never gate, except
# defect-shape format-arity (§1 freshbad, §5 legend/help/MCP/skill/docs arms). Every surface that applies the
# exit predicate (XML gating=, --json and MCP "gating", --ack-only=gating) must agree on it (§1 ackgating, §5).
#
# Stated floors (no row is not a verdict on these): Python %-formatting and f-strings; a format held in a
# named constant, a macro, a pack expansion or a runtime/vformat wrapper; an argument that may be a macro (this file's
# #defines, a FUNCTION-LIKE macro the tree defines, an ALL_CAPS name called — an object-like macro defined only in another
# file is not seen), a call with a directive inside it or under a literal #if 0 (#if false / #if (0) / #if 0 && … / the
# #else of #if 1 read as live), an escape that spells a brace (§1d); an unqualified format()/print();
# the std::print ostream overload; a dedup whose sort reads severity in the MILD-first direction, or whose
# predicate/comparator is a named function (skipped, never guessed); a utf8 cut with no ellipsis; a
# vacuous-assert comparison of COUNTS (a failed run counts 0 rows), a text read off stderr, or a sentinel a helper
# prints on failure (§4b). And the
# utf8/dedup fixtures cannot see an exit-only bug on their own (their clone near-misses gate duplication) —
# §4 vac and §5 both carry the exit judgment for the report-only facets.
#
# Every absence assertion in this gate is read off a delta run that SUCCEEDED (rc 0 or 2 and a
# <quality-delta root) — the very shape §4 detects. Operates in temp dirs; the repo is never touched.
#
# Usage:  bash test/defectshapecheck.sh "$PWD/build/ripwire"
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  defectshapecheck (git not available)"; exit 0; }

WORK="$( mktemp -d )" || { echo "  FAIL  defectshapecheck: mktemp -d failed"; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "  FAIL  defectshapecheck: no temp dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
echo "defectshapecheck: BIN=$BIN  (temp corpora)"

# ── harness ─────────────────────────────────────────────────────────────────────────────────────────────
fx_init(){   # NAME → a fresh git repo at $WORK/NAME
    local d="$WORK/$1"
    mkdir -p "$d" && ( cd "$d" && git init -q && git config user.email t@t && git config user.name t ) \
        || { no "$1: fixture repo could not be created"; return 1; }
}
fx_commit(){ ( cd "$WORK/$1" && git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 ) || no "$1: baseline commit failed"; }
QD_OUT=""; QD_RC=99; QD_OK=0
fx_run(){    # NAME [extra args] → QD_OUT, QD_RC, QD_OK (1 only when the run succeeded and produced its root)
    local d="$WORK/$1"; shift
    QD_OUT="$( cd "$d" && "$BIN" . --quality-delta --no-cache "$@" 2>/dev/null )"
    QD_RC=$?
    QD_OK=0
    if { [ "$QD_RC" = 0 ] || [ "$QD_RC" = 2 ]; } && printf '%s' "$QD_OUT" | grep -q '<quality-delta '; then
        QD_OK=1
    else
        no "$( basename "$d" ): the delta run failed (rc=$QD_RC) — no assertion below reads an absence off it"
    fi
}
fx_run_ref(){  # NAME RANGE [extra args] → the same as fx_run, in ref-pair mode (--quality-delta=A..B)
    local d="$WORK/$1" range="$2"; shift 2
    QD_OUT="$( cd "$d" && "$BIN" . --quality-delta="$range" --no-cache "$@" 2>/dev/null )"
    QD_RC=$?
    QD_OK=0
    if { [ "$QD_RC" = 0 ] || [ "$QD_RC" = 2 ]; } && printf '%s' "$QD_OUT" | grep -q '<quality-delta '; then
        QD_OK=1
    else
        no "$( basename "$d" ) $range: the delta run failed (rc=$QD_RC) — no assertion below reads an absence off it"
    fi
}
fx_copy(){   # SRC DST → a fresh copy of a fixture (its working-tree edit included), so an ack run cannot leak into later arms
    rm -rf "$WORK/$2" && cp -R "$WORK/$1" "$WORK/$2" || no "$2: fixture copy failed"
}
ds_rows(){ printf '%s' "$QD_OUT" | tr '>' '\n' | grep '<r kind="defect-shape" '; }                       # every defect-shape row
ds_row(){  ds_rows | grep "defect=\"$1\"" | grep " sym=\"$2\""; }                                           # FACET SYM
ds_row_p(){ ds_rows | grep "defect=\"$1\"" | grep " p=\"$2:"; }                                             # FACET PATH (a file-anchored row)
ds_any_sym(){ ds_rows | grep " sym=\"$1\""; }
ds_any_p(){ ds_rows | grep " p=\"$1:"; }
ds_judge(){  # LABEL ROW WANT
    local label="$1" row="$2"
    case "$3" in
        gating)     printf '%s' "$row" | grep -q 'gating="1"' && ! printf '%s' "$row" | grep -q 'sev="minor"' \
                        && ! printf '%s' "$row" | grep -q 'origin="new-symbol"' \
                        && ok "$label: gating (preexisting)" || no "$label: should gate as preexisting-worse: $row" ;;
        gating-new) printf '%s' "$row" | grep -q 'gating="1"' && printf '%s' "$row" | grep -q 'origin="new-symbol"' \
                        && ok "$label: origin=new-symbol AND gating (a defect, not debt)" || no "$label: a new-symbol format-arity row should still gate: $row" ;;
        minor)      printf '%s' "$row" | grep -q 'sev="minor"' && ! printf '%s' "$row" | grep -q 'gating=' \
                        && ! printf '%s' "$row" | grep -q 'origin="new-symbol"' \
                        && ok "$label: sev=minor (report-only)" || no "$label: should be report-only sev=minor: $row" ;;
        new-symbol) printf '%s' "$row" | grep -q 'origin="new-symbol"' && ! printf '%s' "$row" | grep -q 'gating=' \
                        && ok "$label: origin=new-symbol, never gating" || no "$label: should be new-symbol and non-gating: $row" ;;
        *)          no "$label: harness: unknown WANT '$3'" ;;
    esac
}
ds_has(){    # LABEL FACET SYM WANT
    local row; row="$( ds_row "$2" "$3" )"
    if [ -z "$row" ]; then no "$1: no defect=\"$2\" row on $3"; ds_rows | head -20; return; fi
    [ "$( printf '%s\n' "$row" | wc -l | tr -d ' ' )" = 1 ] || { no "$1: more than one defect=\"$2\" row on $3: $row"; return; }
    ds_judge "$1: defect=\"$2\" on $3" "$row" "$4"
}
ds_has_p(){  # LABEL FACET PATH WANT
    local row; row="$( ds_row_p "$2" "$3" )"
    if [ -z "$row" ]; then no "$1: no defect=\"$2\" row anchored in $3"; ds_rows | head -20; return; fi
    [ "$( printf '%s\n' "$row" | wc -l | tr -d ' ' )" = 1 ] || { no "$1: more than one defect=\"$2\" row in $3: $row"; return; }
    ds_judge "$1: defect=\"$2\" in $3" "$row" "$4"
}
ds_none(){   # LABEL SYM WHY — no defect-shape row of ANY facet on SYM
    [ "$QD_OK" = 1 ] || { no "$1: cannot read an absence on $2 off a failed run"; return; }
    local row; row="$( ds_any_sym "$2" )"
    if [ -z "$row" ]; then ok "$1: no defect-shape row on $2 ($3)"; else no "$1: false positive on $2 ($3): $row"; fi
}
ds_none_p(){ # LABEL PATH WHY — no defect-shape row anchored in PATH
    [ "$QD_OK" = 1 ] || { no "$1: cannot read an absence in $2 off a failed run"; return; }
    local row; row="$( ds_any_p "$2" )"
    if [ -z "$row" ]; then ok "$1: no defect-shape row in $2 ($3)"; else no "$1: false positive in $2 ($3): $row"; fi
}
ds_wasnow(){ # LABEL FACET SYM WAS NOW — the count is distinct offending sites, not a double count
    local row; row="$( ds_row "$2" "$3" )"
    printf '%s' "$row" | grep -q "was=\"$4\"" && printf '%s' "$row" | grep -q "now=\"$5\"" \
        && ok "$1: $3 counts was=$4 now=$5" || no "$1: $3 should count was=$4 now=$5: ${row:-<no row>}"
}
hdr_attr(){ printf '%s' "$QD_OUT" | tr '>' '\n' | grep '<quality-delta ' | head -1 | grep -o " $1=\"[0-9]*\"" | grep -o '[0-9][0-9]*'; }
gating_split(){  # LABEL MIN_FORMAT_ARITY_GATING — who gates. The near-miss functions are clones of each other on purpose, so the
                 # duplication kind gates in these fixtures too; the exit is judged by attribution, not by a bare 0/2:
                 # header gating= equals the gating rows, no REPORT-ONLY facet carries gating=, format-arity carries >= MIN,
                 # and the exit is 2 exactly when some row gates.
    [ "$QD_OK" = 1 ] || { no "$1: cannot judge gating off a failed run"; return; }
    local hg all fa other
    hg="$( hdr_attr gating )"
    case "$hg" in ''|*[!0-9]*) no "$1: header gating= is missing or not numeric ('$hg')"; return ;; esac
    all="$( printf '%s' "$QD_OUT" | tr '>' '\n' | grep '<r ' | grep -c 'gating="1"' )"
    fa="$( ds_rows | grep 'defect="format-arity"' | grep -c 'gating="1"' )"
    other="$( ds_rows | grep 'gating=' | grep -vc 'defect="format-arity"' )"
    if [ "$hg" = "$all" ]; then ok "$1: header gating=$hg counts every gating row"; else no "$1: header gating=$hg but $all rows carry gating=\"1\""; fi
    [ "$other" = 0 ] && ok "$1: no report-only facet (utf8-cut, dedup-first, vacuous-assert) carries gating=" \
        || no "$1: $other report-only defect-shape rows carry gating=: $( ds_rows | grep 'gating=' | grep -v 'defect="format-arity"' | head -3 )"
    if [ "$fa" -ge "$2" ]; then ok "$1: $fa format-arity rows gate (want >= $2)"; else no "$1: $fa format-arity rows gate, want >= $2"; fi
    if [ "$all" -gt 0 ]; then
        if [ "$QD_RC" = 2 ]; then ok "$1: exit 2 with $all gating rows"; else no "$1: $all gating rows but exit $QD_RC"; fi
    else
        if [ "$QD_RC" = 0 ]; then ok "$1: exit 0 with no gating row"; else no "$1: no gating row but exit $QD_RC"; fi
    fi
}

# ── 1) FORMAT-ARITY, C++ ────────────────────────────────────────────────────────────────────────────────
#   Every function exists at the baseline with a CORRECT call. The edit turns some into a mismatch (the
#   positives) and the rest into correct-but-tricky spellings the counter must get right (the near-misses):
#   {{ }} escapes, format specs, positional {0}, nested dynamic width {:>{}} (it consumes an argument), a
#   non-literal or macro format (skipped, never guessed), a "{}" inside an ARGUMENT, a raw string, a wide
#   literal, a member function that happens to be called format, a commented-out call, a char argument '{'.
fx_init fmt_cpp
mkdir -p "$WORK/fmt_cpp/src"
FMT_HDR='#include <chrono>
#include <cinttypes>
#include <cstdio>
#include <format>
#include <iostream>
#include <iterator>
#include <locale>
#include <print>
#include <string>
#include <utility>
#include <fmt/format.h>

namespace rw
{
template<class... A> void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a );
template<class... A> std::size_t formatTo( char* buf, std::size_t cap, std::format_string<A...> f, A&&... a );
template<class S> void emitRaw( std::FILE* stream, const S& text );
}

#define FMT_PAIR "{} {}"
#define PAIR a, b
constexpr const char* kFmt = "{} and {}";
std::string format( const char* f, int a );

struct Log
{
    std::string format( const char* f, int a ) const;
};
'
{ printf '%s' "$FMT_HDR"; cat <<'EOF'
std::string extra( int a, int b ) { return std::format( "a={} b={}", a, b ); }
std::string fewer( int a, int b ) { return std::format( "a={} b={}", a, b ); }
void concat( int a, int b )
{
    rw::emitTo( stdout, "<legend a=\"{}\" "
                        "b=\"{}\"/>\n",
                a, b );
}
std::size_t formatto( int a, int b ) { char buf[64]; return rw::formatTo( buf, sizeof( buf ), "<x a=\"{}\" b=\"{}\"/>", a, b ); }
std::string formattostd( int a, int b ) { std::string out; std::format_to( std::back_inserter( out ), "{}-{}", a, b ); return out; }
std::string positional( int a, int b ) { return std::format( "{0} {1}", a, b ); }
std::string dynwidthbad( const std::string& s, int w ) { return std::format( "{:>{}}", s, w ); }
void printstream( int a, int b ) { std::print( stderr, "{} {}\n", a, b ); }
std::string fmtns( int a, int b ) { return fmt::format( "{} {}", a, b ); }
std::string escaped( int a ) { return std::format( "{}", a ); }
std::string spec( int a, double d, int b, std::chrono::sys_days t, const std::string& s ) { return std::format( "{} {} {} {} {}", a, d, b, t, s ); }
std::string posok( int a, int b ) { return std::format( "{} {}", a, b ); }
std::string dynwidth( const std::string& s, int w, double d, int p ) { return std::format( "{} {} {} {}", s, w, d, p ); }
std::string nonliteral( int a, int b ) { return std::format( "{} {}", a, b ); }
std::string fmtconstarg( int a ) { return std::format( "{}", a ); }
std::string macro( int a, int b ) { return std::format( "{} {}", a, b ); }
std::string inarg( int a ) { return std::format( "{}", a ); }
std::string rawstr( int a ) { return std::format( "{}", a ); }
std::wstring wide( int a, int b ) { return std::format( L"{}", a + b ); }
std::string member( const Log& log, int a ) { return log.format( "{}", a ); }
std::string commented( int a ) { return std::format( "{}", a ); }
std::string charlit( int a ) { return std::format( "{}", a ); }
void printok( int a ) { std::println( "{}", a ); }
void raw() { rw::emitRaw( stdout, "plain" ); }
std::string localebad( int a, int b ) { return std::format( std::locale( "C" ), "{} {}", a, b ); }
std::string unrefpos( int a, int b ) { return std::format( "{0} {1}", a, b ); }
template<class... A> std::string packexp( A&&... a ) { return std::format( "{}", std::forward<A>( a )... ); }
std::string runtimefmt( int a ) { return std::format( std::runtime_format( "{}" ), a ) + fmt::format( fmt::runtime( "{}" ), a ); }
std::string pairmacro( int a, int b ) { return std::format( "{}", a + b ); }
std::string pricat( std::uint64_t a ) { return std::format( "{}", a ); }
std::string unqualified( int a ) { return format( "{}", a ); }
void ostreamprint( int a ) { std::print( std::cout, "{}", a ); }
std::string formattonok( int a, int b ) { char out[16]; std::format_to_n( out, 10, "{}", a + b ); return out; }
std::string posnested( const std::string& s, int w ) { return std::format( "{}", s ); }
std::string swapped( int a, int b ) { return std::format( "{} {}", a, b, b ) + std::format( "{}", a ); }
std::string moved( int a ) { return std::format( "m={}", a, a ); }
std::string cmpinarg( int a, int b ) { return std::format( "{}", a > b ); }
std::string tmplarg( int a, int b ) { return std::format( "{}", b ); }
std::string legacy( int a ) { return std::format( "{} {}", a, a, a ); }
int drive() { return 0; }
EOF
} >"$WORK/fmt_cpp/src/fmt.cpp"
printf '#include <format>\n#define LOGF( ... ) std::format( "{}", __VA_ARGS__ )\n' >"$WORK/fmt_cpp/src/vamacro.h"
fx_commit fmt_cpp
{ printf '%s' "$FMT_HDR"; cat <<'EOF'
std::string extra( int a, int b ) { return std::format( "a={} b={}", a, b, a + b ); }
std::string fewer( int a, int b ) { return std::format( "a={} b={} c={}", a, b ); }
void concat( int a, int b )
{
    rw::emitTo( stdout, "<legend a=\"{}\" "
                        "b=\"{}\" c=\"{}\"/>\n",
                a, b, a, b );
}
std::size_t formatto( int a, int b ) { char buf[64]; return rw::formatTo( buf, sizeof( buf ), "<x a=\"{}\"/>", a, b ); }
std::string formattostd( int a, int b ) { std::string out; std::format_to( std::back_inserter( out ), "{}-{}", a, b, a ); return out; }
std::string positional( int a, int b ) { return std::format( "{0} {1}", a, b, a ); }
std::string dynwidthbad( const std::string& s, int w ) { return std::format( "{:>{}}", s ); }
void printstream( int a, int b ) { std::print( stderr, "{} {}\n", a ); }
std::string fmtns( int a, int b ) { return fmt::format( "{} {}", a ); }
std::string escaped( int a ) { return std::format( "{{literal}} {} }}{{", a ); }
std::string spec( int a, double d, int b, std::chrono::sys_days t, const std::string& s ) { return std::format( "{:>8} {:.2f} {:#x} {:%Y-%m-%d} {:*^10}", a, d, b, t, s ); }
std::string posok( int a, int b ) { return std::format( "{0} and {0} and {1}", a, b ); }
std::string dynwidth( const std::string& s, int w, double d, int p ) { return std::format( "{:>{}} {:{}.{}f}", s, w, d, w, p ); }
std::string nonliteral( int a, int b ) { return std::format( kFmt, a, b, a ) + std::vformat( kFmt, std::make_format_args( a, b, a ) ); }
std::string fmtconstarg( int a ) { return std::format( kFmt, "{}" ); }
std::string macro( int a, int b ) { return std::format( FMT_PAIR, a, b, a ); }
std::string inarg( int a ) { return std::format( "{}", "{} {}" ); }
std::string rawstr( int a ) { return std::format( R"x(<a x="{}" y="{{}}" q=")"/>)x", a ); }
std::wstring wide( int a, int b ) { return std::format( L"{} {}", a, b ); }
std::string member( const Log& log, int a ) { return log.format( "{} {} {}", a ); }
std::string commented( int a )
{
    // return std::format( "{} {}", a );
    return std::format( "{}", a );
}
std::string charlit( int a ) { return std::format( "{}{}", '{', a ); }
void printok( int a ) { std::println( "{} {}", a, a ); }
void raw() { rw::emitRaw( stdout, "{} {} {}" ); }
std::string localebad( int a, int b ) { return std::format( std::locale( "C" ), "{} {}", a, b, a ); }
std::string unrefpos( int a, int b ) { return std::format( "{1}", a, b ); }
template<class... A> std::string packexp( A&&... a ) { return std::format( "{} {}", std::forward<A>( a )... ); }
std::string runtimefmt( int a ) { return std::format( std::runtime_format( "{} {}" ), a ) + fmt::format( fmt::runtime( "{} {}" ), a ); }
std::string pairmacro( int a, int b ) { return std::format( "{} {}", PAIR ); }
std::string pricat( std::uint64_t a ) { return std::format( "{} " PRIu64, a ); }
std::string unqualified( int a ) { return format( "{} {}", a ); }
void ostreamprint( int a ) { std::print( std::cout, "{} {}", a ); }
std::string formattonok( int a, int b ) { char out[16]; std::format_to_n( out, 10, "{} {}", a, b ); return out; }
std::string posnested( const std::string& s, int w ) { return std::format( "{0:>{1}}", s, w ); }
std::string swapped( int a, int b ) { return std::format( "{} {}", a, b ) + std::format( "{}", a, b ); }
std::string cmpinarg( int a, int b ) { return std::format( "{}", a > b, a ); }
std::string tmplarg( int a, int b ) { return std::format( "{} {}", std::pair<int, int>{ a, b }.first, b ); }
std::string legacy( int a ) { return std::format( "{} {}", a, a, a ); }
std::string freshbad( int a ) { return std::format( "{}", a, a ); }
std::string freshok( int a ) { return std::format( "{} {}", a, a ); }
int drive() { return 1; }
EOF
} >"$WORK/fmt_cpp/src/fmt.cpp"
printf '#include <format>\n#define LOGF( ... ) std::format( "{} {}", __VA_ARGS__ )\n' >"$WORK/fmt_cpp/src/vamacro.h"
printf '#include <format>\n#include <string>\nstd::string movedRenamed( int a ) { return std::format( "m={}", a, a ); }\n' >"$WORK/fmt_cpp/src/moved.cpp"
fx_run fmt_cpp
L="format-arity (c++)"
ds_has  "$L" format-arity extra       gating
ds_has  "$L" format-arity fewer       gating
ds_has  "$L" format-arity concat      gating
ds_has  "$L" format-arity formatto    gating
ds_has  "$L" format-arity formattostd gating
ds_has  "$L" format-arity positional  gating
ds_has  "$L" format-arity dynwidthbad gating
ds_has  "$L" format-arity printstream gating
ds_has  "$L" format-arity fmtns       gating
ds_has  "$L" format-arity localebad   gating
ds_has  "$L" format-arity unrefpos    gating
ds_has  "$L" format-arity swapped     gating
ds_has  "$L" format-arity cmpinarg    gating
ds_has  "$L" format-arity freshbad    gating-new
ds_wasnow "$L" format-arity extra 0 1
ds_wasnow "$L" format-arity concat 0 1
ds_wasnow "$L" format-arity swapped 1 1
ds_none "$L" escaped     "{{ and }} are escapes, not fields"
ds_none "$L" spec        "a format spec is part of its field"
ds_none "$L" posok       "{0} twice and {1} need two arguments"
ds_none "$L" dynwidth    "a nested {} width/precision consumes an argument"
ds_none "$L" nonliteral  "a named format constant or vformat is skipped, never guessed"
ds_none "$L" fmtconstarg "the literal is an ARGUMENT, not the format"
ds_none "$L" macro       "a macro format is skipped, never guessed"
ds_none "$L" inarg       "a {} inside an argument string is not a field"
ds_none "$L" rawstr      "a raw string with a custom delimiter and a )\" inside, one field"
ds_none "$L" wide        "an L-prefixed literal counts like any other"
ds_none "$L" member      "Log::format is not the format family"
ds_none "$L" commented   "a commented-out call is not code"
ds_none "$L" charlit     "a '{' char argument is an argument"
ds_none "$L" printok     "std::println with matching arguments"
ds_none "$L" raw         "emitRaw prints bytes, it does not format"
ds_none "$L" legacy      "a mismatch the change did not introduce (untouched function)"
ds_none "$L" freshok     "a new function with a matching call"
ds_none "$L" packexp     "a pack expansion makes the argument count unknowable (skipped)"
ds_none "$L" runtimefmt  "std::runtime_format / fmt::runtime wrap a non-literal format (skipped)"
ds_none "$L" pairmacro   "an object-like macro argument may expand to a comma list (skipped)"
ds_none "$L" pricat      "an adjacent-literal concat with a macro piece is not a whole literal (skipped)"
ds_none "$L" unqualified "an unqualified in-repo format() is not the format family"
ds_none "$L" ostreamprint "the std::print ostream overload is skipped, never guessed (stated floor)"
ds_none "$L" formattonok "std::format_to_n puts the format at index 2: two fields, two arguments"
ds_none "$L" posnested   "a positional nested width {0:>{1}} references both arguments"
ds_none "$L" tmplarg     "a template argument list (std::pair<int, int>) the comma split would cut makes the count unknowable (skipped)"
ds_none_p "$L" src/vamacro.h "a format inside a macro body (__VA_ARGS__) is skipped"
ds_none "$L" moved        "a mismatch moved out of this file is not new"
ds_none "$L" movedRenamed "a mismatch moved to a new file and renamed is not new (its call text was already in the baseline)"
ds_none_p "$L" src/moved.cpp "the moved mismatch's new file carries no row"
gating_split "$L" 14
OFMT="$QD_OUT"
fx_run fmt_cpp
if [ "$QD_OK" = 1 ] && [ "$OFMT" = "$QD_OUT" ]; then ok "$L: delta byte-identical run-to-run"; else no "$L: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OFMT" | xmllint --noout - 2>/dev/null; then ok "$L: xml well-formed"; else no "$L: xml malformed"; fi
else
    echo "  SKIP  $L: xml well-formedness (xmllint not installed)"
fi
#   The exit predicate's own ack token: --ack-only=gating selects whatever would exit 2, and a new-symbol
#   format-arity row (freshbad) DOES exit 2, so the ack must take it too — the ack token and the XML gating=
#   must read one predicate. On a fresh copy, so the later arms see the unacked fixture.
L="format-arity ack gating"
if printf '%s' "$OFMT" | tr '>' '\n' | grep '<r kind="defect-shape" ' | grep 'defect="format-arity"' | grep -q ' sym="freshbad"'; then
    fx_copy fmt_cpp fmt_ackg
    ( cd "$WORK/fmt_ackg" && "$BIN" . --quality-delta --no-cache --ack-only=gating --quality-ack="ack every gating row in this fixture" >/dev/null 2>&1 )
    ARC=$?
    if [ "$ARC" = 0 ]; then ok "$L: --ack-only=gating wrote its acks (exit 0)"; else no "$L: --ack-only=gating exited $ARC"; fi
    fx_run fmt_ackg
    if [ "$QD_OK" = 1 ]; then
        left="$( ds_rows | grep -c 'defect="format-arity"' )"
        if [ "$left" = 0 ]; then ok "$L: no format-arity row survives --ack-only=gating (freshbad included)"
        else no "$L: $left format-arity rows survived --ack-only=gating: $( ds_rows | grep 'defect="format-arity"' | head -3 )"; fi
        gating_split "$L" 0
    fi
else
    no "$L: premise: the unacked fixture has no format-arity row on freshbad, so there is nothing for the ack to select"
fi

# ── 1c) FORMAT-ARITY across a CLEAN MERGE (ref-pair mode) — the train-25 incident ───────────────────────
#   Each side adds the same field literal and one argument; git merges the two cleanly into 5 fields and 6
#   arguments, which compiles. Each side alone matches. --quality-delta=BASE..HEAD takes the ref-pair snapshot
#   path, which no other arm here exercises.
fx_init merge
mkdir -p "$WORK/merge/src"
MERGE_BASE_SRC='#include <cstdio>
namespace rw { template<class... A> void emitTo( std::FILE* stream, const char* f, A&&... a ); }
void legend( int a, int b, int c, int d, int e, int f )
{
    rw::emitTo( stdout, "<l a=\"{}\" "
                        "x=\"\" "
                        "e=\"{}\" f=\"{}\" d=\"{}\"/>\n",
                a,
                e,
                f,
                d );
}
int drive() { return 0; }
'
printf '%s' "$MERGE_BASE_SRC" >"$WORK/merge/src/legend.cpp"
fx_commit merge
MB="$( cd "$WORK/merge" && git rev-parse HEAD )"
( cd "$WORK/merge" && git checkout -q -b side_x \
    && sed -i.bak -e 's|^                        "x=\\"\\" "$|&\
                        "n=\\"{}\\" "|' -e 's|^                a,$|&\
                b,|' src/legend.cpp && rm -f src/legend.cpp.bak && git commit -qam x \
    && git checkout -q "$MB" && git checkout -q -b side_y \
    && sed -i.bak -e 's|^                        "x=\\"\\" "$|&\
                        "n=\\"{}\\" "|' -e 's|^                f,$|&\
                c,|' src/legend.cpp && rm -f src/legend.cpp.bak && git commit -qam y \
    && git checkout -q -b merged side_x && git merge -q --no-edit side_y >/dev/null 2>&1 ) \
    || no "merge: building the two sides and their clean merge failed"
MF="$( grep -c '{}' "$WORK/merge/src/legend.cpp" )"
MA="$( grep -cE '^                [a-f],$|^                d \);$' "$WORK/merge/src/legend.cpp" )"
if [ "$MF" = 3 ] && [ "$MA" = 6 ]; then ok "merge: the clean merge holds the duplicated literal once and both arguments (premise)"
else no "merge: premise: expected 3 field lines and 6 argument lines after the merge, got $MF / $MA"; cat "$WORK/merge/src/legend.cpp"; fi
L="format-arity (merge, ref-pair)"
fx_run_ref merge "$MB..HEAD"
ds_has "$L" format-arity legend gating
gating_split "$L" 1
fx_run_ref merge "$MB..side_x"
ds_none "$L side x" legend "one side alone: five fields, five arguments"
fx_run_ref merge "$MB..side_y"
ds_none "$L side y" legend "the other side alone: five fields, five arguments"

# ── 1b) FORMAT-ARITY, Python "literal".format(...) ──────────────────────────────────────────────────────
#   Too few raises IndexError/KeyError at run time; too many is ignored silently. Named fields count against
#   keyword arguments, auto/positional fields against positional ones; *args / **kwargs make the count
#   unknowable (skipped). f-strings, %-formatting and a non-literal receiver are out of the shape. An explicit
#   keyword the format never names is ignored silently (a row); a raw r"" literal and an unparenthesised
#   implicit concat ("a" "b".format) are one literal like any other.
fx_init fmt_py
printf 'VERSION = "1"\nBANNER = "v{}".format(VERSION)\n' >"$WORK/fmt_py/banner.py"
cat >"$WORK/fmt_py/fmt.py" <<'EOF'


def extra(a, b):
    return "a={} b={}".format(a, b)


def fewer(a, b):
    return "a={} b={}".format(a, b)


def namedmissing(x, y):
    return "{x} {y}".format(x=x, y=y)


def concat(a, b):
    return ("a={} " "b={}").format(a, b)


def escaped(a):
    return "{}".format(a)


def star(pair):
    return "{} {}".format(pair[0], pair[1])


def kwstar(d):
    return "{a} {b}".format(a=d["a"], b=d["b"])


def attr(f):
    return "{}".format(f.name)


def index(d):
    return "{}".format(d["k"])


def nested(a):
    return "{}".format(a)


def mixed(a, b):
    return "{} {}".format(a, b)


def fstring(a, b):
    return "{} {}".format(a, b)


def nonliteral(tmpl, a, b):
    return tmpl.format(a, b)


def percent(a):
    return "%s" % (a,)


def triple(a, b):
    return """{} {}""".format(a, b)


def kwunused(x, y):
    return "{x}".format(x=x)


def rawbad(a):
    return r"{}".format(a)


def concatbare(a, b):
    return "a={} " "b={}".format(a, b)


def nestedauto(s, w):
    return "{}".format(s)


def fmtmap(d):
    return "{a}".format_map(d)


def legacy(a):
    return "{} {}".format(a, a, a)
EOF
fx_commit fmt_py
printf 'VERSION = "1"\nBANNER = "v{} build {}".format(VERSION)\n' >"$WORK/fmt_py/banner.py"
cat >"$WORK/fmt_py/fmt.py" <<'EOF'


def extra(a, b):
    return "a={} b={}".format(a, b, a + b)


def fewer(a, b):
    return "a={} b={} c={}".format(a, b)


def namedmissing(x, y):
    return "{x} {y}".format(x=x)


def concat(a, b):
    return ("a={} " "b={} " "c={}").format(a, b)


def escaped(a):
    return "{{}} {} {{x}}".format(a)


def star(pair):
    return "{} {} {}".format(*pair)


def kwstar(d):
    return "{a} {b} {c}".format(**d)


def attr(f):
    return "{0.name} {0.size}".format(f)


def index(d):
    return "{0[k]} {0[j]}".format(d)


def nested(a):
    return "{!r:>{w}}".format(a, w=3)


def mixed(a, b):
    return "{0} {name}".format(a, name=b)


def fstring(a, b):
    return f"{a} {b} {{}}"


def nonliteral(tmpl, a, b):
    return tmpl.format(a, b, a)


def percent(a):
    return "%s %s" % (a,)


def triple(a, b):
    return """{}
{}""".format(a, b)


def kwunused(x, y):
    return "{x}".format(x=x, y=y)


def rawbad(a):
    return r"{} {}".format(a)


def concatbare(a, b):
    return "a={} " "b={}".format(a)


def nestedauto(s, w):
    return "{:>{}}".format(s, w)


def fmtmap(d):
    return "{a} {b}".format_map(d)


def legacy(a):
    return "{} {}".format(a, a, a)


def freshbad(a):
    return "{}".format(a, a)
EOF
fx_run fmt_py
L="format-arity (python)"
ds_has   "$L" format-arity extra        gating
ds_has   "$L" format-arity fewer        gating
ds_has   "$L" format-arity namedmissing gating
ds_has   "$L" format-arity concat       gating
ds_has   "$L" format-arity freshbad     gating-new
ds_has_p "$L" format-arity banner.py    gating
ds_has   "$L" format-arity kwunused     gating
ds_has   "$L" format-arity rawbad       gating
ds_has   "$L" format-arity concatbare   gating
ds_none  "$L" escaped    "{{ }} are escapes"
ds_none  "$L" star       "*args makes the count unknowable"
ds_none  "$L" kwstar     "**kwargs makes the names unknowable"
ds_none  "$L" attr       "{0.name} {0.size} need one positional argument"
ds_none  "$L" index      "{0[k]} {0[j]} need one positional argument"
ds_none  "$L" nested     "a nested named width {w} is a keyword argument"
ds_none  "$L" mixed      "one positional, one named, both given"
ds_none  "$L" fstring    "an f-string has no argument list"
ds_none  "$L" nonliteral "a non-literal receiver is skipped, never guessed"
ds_none  "$L" percent    "%-formatting is not this shape"
ds_none  "$L" triple     "a triple-quoted literal with two fields and two arguments"
ds_none  "$L" legacy     "a mismatch the change did not introduce"
ds_none  "$L" nestedauto "an auto nested width {:>{}} consumes a positional argument"
ds_none  "$L" fmtmap     ".format_map takes a mapping, not an argument list (skipped)"
gating_split "$L" 9

# ── 1d) FORMAT-ARITY precision: macros, directives, dead code (rv-cr-qd-kinds-068 §1b F1/F2/F3) ─────────
#   The rule that lets format-arity gate: when the argument count cannot be known, SKIP, never guess. The
#   reviewer's adversarial shapes (fixtures p2/fp/repo, repo2) as negatives, each beside a near-miss POSITIVE the
#   skip must not swallow:
#   F1 an argument that may be a macro expanding to an argument list: an identifier this file or the tree
#      #defines (SRC_LOC(), a lower-case pq( p ) here, xy( p ) defined in ANOTHER file), or an ALL_CAPS name
#      followed by '(' whose definition is not visible (PAIR_OF( a ), and OUT_IT( s ) BEFORE the format, which
#      may shift its index). A real function call (twice( a )) and a qualified Foo::BAR( 1 ) are still counted.
#   F2 a preprocessor directive inside the call's parentheses (#ifdef arms in the argument list, or around the
#      format itself): every arm's tokens would be concatenated. A directive OUTSIDE the call does not skip it.
#   F3 a call inside #if 0 … #endif (nested conditionals inside it too) is dead code; the #else arm is live.
#   And the low-realism edges: other::std::format is not the family (::std::format is); "\x7b\x7d" spells "{}"
#   by escapes (skipped), "\x1b[1m{}" does not (counted).
fx_init fmt_pp
mkdir -p "$WORK/fmt_pp/src"
printf '#pragma once\n#define xy( p ) p.x, p.y\n#define INNER2() a, b\n' >"$WORK/fmt_pp/src/macros.h"
printf '#include "macros.h"\nint drive() { return 0; }\n' >"$WORK/fmt_pp/src/pp.cpp"
fx_commit fmt_pp
cat >"$WORK/fmt_pp/src/pp.cpp" <<'EOF'
#include <format>
#include <print>
#include <string>
#include "macros.h"
#define SRC_LOC() __FILE__, __LINE__
#define VEC3( v ) ( v ).x, ( v ).y, ( v ).z
#define pq( p ) p.first, p.second
#define ARGS( ... ) __VA_ARGS__
#define LOGV( fmt, ... ) std::print( fmt, __VA_ARGS__ )
#define FMTOF( x ) "{} " x
#define outer2() INNER2()
struct Foo { static int BAR( int x ); };
int twice( int a );
std::string n_srcloc( const char* m ) { return std::format( "{}:{} {}", SRC_LOC(), m ); }
std::string n_vec3( auto v ) { return std::format( "({}, {}, {})", VEC3( v ) ); }
std::string n_lowersame( auto p ) { return std::format( "{} {}", pq( p ) ); }
std::string n_lowertree( auto p ) { return std::format( "{} {}", xy( p ) ); }
std::string n_capsundef( int a ) { return std::format( "{} {}", PAIR_OF( a ) ); }
std::string n_beforefmt( std::string& s, int a, int b ) { std::format_to( OUT_IT( s ), "{}", a, b ); return s; }
std::string n_variadic( int a, int b ) { return std::format( "{} {}", ARGS( a, b ) ); }
void n_vawrapper( int a ) { LOGV( "{} {}\n", a ); }
std::string n_fmtmacro( int a ) { return std::format( FMTOF( "{}" ), a ); }
std::string n_nested( int a, int b ) { return std::format( "{} {}", outer2() ); }
std::string n_ifdefargs( int a, int b, int c )
{
    return std::format( "{} {}", a
#ifdef _WIN32
                        , b
#else
                        , c
#endif
    );
}
void n_ifdeffmt( int a, int b, int c )
{
    std::print(
#ifdef VERBOSE
        "{} {} {}\n", a, b, c
#else
        "{}\n", a
#endif
    );
}
std::string n_ifzero( int a )
{
#if 0
    return std::format( "{} {}", a );
#ifdef NESTED
    return std::format( "{}", a, a );
#endif
    return std::format( "{} {} {}", a );
#endif
    return {};
}
std::string n_qualified( int a, int b ) { return other::std::format( "{}", a, b ); }
std::string n_hexesc( int a ) { return std::format( "\x7b\x7d", a ); }
std::string p_lowerfn( int a ) { return std::format( "{} {}", twice( a ) ); }
std::string p_qualcaps( int a ) { return std::format( "{}", a, Foo::BAR( 1 ) ); }
#ifdef OUTSIDE
int outsideDirective = 1;
#endif
std::string p_afterdirective( int a ) { return std::format( "{}", a, a ); }
std::string p_ifzeroelse( int a )
{
#if 0
    return {};
#else
    return std::format( "{}", a, a );
#endif
}
std::string p_globalns( int a ) { return ::std::format( "{}", a, a ); }
std::string p_hexother( int a ) { return std::format( "\x1b[1m{}\x1b[0m", a, a ); }
int drive() { return 1; }
EOF
fx_run fmt_pp
L="format-arity precision (c++)"
for f in n_srcloc n_vec3 n_lowersame n_lowertree n_capsundef n_beforefmt n_variadic n_vawrapper n_fmtmacro n_nested; do
    ds_none "$L" "$f" "F1: a macro that may expand to an argument list makes the count unknowable (skipped)"
done
ds_none "$L" n_ifdefargs "F2: #ifdef arms inside the argument list (skipped)"
ds_none "$L" n_ifdeffmt  "F2: #ifdef arms around the format itself (skipped)"
ds_none "$L" n_ifzero    "F3: calls inside #if 0 … #endif, nested conditionals included, are dead code"
ds_none "$L" n_qualified "other::std::format is not the format family"
ds_none "$L" n_hexesc    "a literal whose escapes spell a brace is skipped, never guessed"
ds_none_p "$L" src/macros.h "a macro definition is not a call"
ds_has "$L" format-arity p_lowerfn        gating-new
ds_has "$L" format-arity p_qualcaps       gating-new
ds_has "$L" format-arity p_afterdirective gating-new
ds_has "$L" format-arity p_ifzeroelse     gating-new
ds_has "$L" format-arity p_globalns       gating-new
ds_has "$L" format-arity p_hexother       gating-new
FA="$( ds_rows | grep -c 'defect="format-arity"' )"
if [ "$QD_OK" = 1 ] && [ "$FA" = 6 ]; then ok "$L: exactly the 6 near-miss positives carry a format-arity row"
else no "$L: $FA format-arity rows, want exactly the 6 positives: $( ds_rows | grep 'defect="format-arity"' | head -10 )"; fi

#   Python: a raw literal has no escapes (r"\N{a}" holds the field {a}); "\x7b\x7d" spells "{}" (skipped); a
#   newline outside brackets ends a statement, so X = "a {}" and a next-line "{}".format( 1 ) are not one concat.
fx_init fmt_py2
printf 'def drive():\n    return 0\n' >"$WORK/fmt_py2/p.py"
fx_commit fmt_py2
cat >"$WORK/fmt_py2/p.py" <<'EOF'
def n_rawN(a):
    return r"\N{a}".format(a=a)


def n_hexesc(a):
    return "\x7b\x7d".format(a)


def n_namedesc(a):
    return "\N{LEFT CURLY BRACKET}\N{RIGHT CURLY BRACKET}".format(a)


def p_rawextra(a, b):
    return r"\d {}".format(a, b)


def p_escother(a, b):
    return "\x1b[1m{}".format(a, b)


def drive():
    return 1
EOF
printf 'X = "a {}"\n"{}".format(1)\n' >"$WORK/fmt_py2/m.py"
printf 'Y = 1\n"{} {}".format(1)\n' >"$WORK/fmt_py2/q.py"
fx_run fmt_py2
L="format-arity precision (python)"
ds_none   "$L" n_rawN    "a raw literal's \\N is a backslash and an N; {a} is a field and a=a gives it"
ds_none   "$L" n_hexesc  "a literal whose escapes spell a brace is skipped, never guessed"
ds_none   "$L" n_namedesc "\\N{LEFT CURLY BRACKET} spells a brace: skipped"
ds_none_p "$L" m.py      "a module-level statement's literal is not concatenated with the next line's receiver"
ds_has    "$L" format-arity p_rawextra gating-new
ds_has    "$L" format-arity p_escother gating-new
ds_has_p  "$L" format-arity q.py       gating-new
#   next= hands a gating row's body to open; a FILE-anchored row has no symbol to expand (rv N2), a function's row does
if [ "$QD_OK" = 1 ]; then
    if ds_row_p format-arity q.py | grep -q ' next='; then no "$L: the file-anchored q.py row carries a next= that matches no symbol: $( ds_row_p format-arity q.py )"
    else ok "$L: the file-anchored q.py row carries no next="; fi
    if ds_row format-arity p_rawextra | grep -q ' next="--expand=p.py:p_rawextra"'; then ok "$L: a function-anchored row keeps next=--expand=FILE:NAME"
    else no "$L: the p_rawextra row lost its next=: $( ds_row format-arity p_rawextra )"; fi
fi

# ── 2) UTF8-CUT, C++ (report-only) ──────────────────────────────────────────────────────────────────────
#   The corpus shapes: a cut (resize / substr(0,N) / erase(N)) plus an appended ellipsis on the SAME string
#   with no UTF-8 back-off in the function, and an ellipsis appended once a byte-pushing loop reaches the
#   cap (the cut lands mid-sequence and the ellipsis can fire with nothing dropped). Near-misses: a
#   continuation-byte back-off (0xC0/0x80), a utf8-named helper, a cut with no ellipsis (a buffer, not text —
#   a stated floor), an ellipsis on a different variable, an ellipsis that replaces the value, a u32string,
#   a cut at a parsed delimiter (the cut length must be the bound of a size comparison on the same string, or
#   a cap-named constant/parameter), and a loop that appends whole words. A back-off guard anywhere in the
#   function exempts it: a precision choice, stated in the legend.
fx_init utf8
mkdir -p "$WORK/utf8/src"
U8_HDR='#include <string>
#include <string_view>
#include <vector>

constexpr std::size_t kCap = 80;
std::string truncateUtf8WithEllipsis( std::string_view s, std::size_t cap );
'
{ printf '%s' "$U8_HDR"; cat <<'EOF'
std::string excerpt( std::string s ) { return s; }
std::string clip( const std::string& s, std::size_t n ) { return s; }
std::string build( std::string_view s )
{
    std::string out;
    for( char c : s )
    {
        out.push_back( c );
    }
    return out;
}
std::string erasecut( std::string s, std::size_t n ) { return s; }
std::string guarded( std::string s ) { return s; }
std::string helper( const std::string& s ) { return s; }
std::string noellipsis( std::string s, std::size_t n ) { return s; }
std::string othervar( std::string buf, std::string label, std::size_t n ) { return buf + label; }
std::string replaced( const std::string& s, std::size_t n ) { return s; }
std::string packname( const std::string& text, bool pack ) { return text; }
std::string wordloop( const std::vector<std::string>& words ) { std::string out; return out; }
std::string capminus( std::string s ) { return s; }
std::string guardanywhere( std::string s ) { return s; }
std::u32string wide( std::u32string s, std::size_t n ) { return s; }
std::string legacy( std::string s ) { if( s.size() > 40 ) { s.resize( 40 ); s += "..."; } return s; }
int drive() { return 0; }
EOF
} >"$WORK/utf8/src/text.cpp"
fx_commit utf8
{ printf '%s' "$U8_HDR"; cat <<'EOF'
std::string excerpt( std::string s )
{
    if( s.size() > 117 )
    {
        s.resize( 117 );
        s += "...";
    }
    return s;
}
std::string clip( const std::string& s, std::size_t n ) { return s.size() > n ? s.substr( 0, n ) + "\xE2\x80\xA6" : s; }
std::string build( std::string_view s )
{
    std::string out;
    for( char c : s )
    {
        out.push_back( c );
        if( out.size() >= kCap )
        {
            out += "\xE2\x80\xA6";
            break;
        }
    }
    return out;
}
std::string erasecut( std::string s, std::size_t n )
{
    if( s.size() > n )
    {
        s.erase( n );
        s.append( "..." );
    }
    return s;
}
std::string guarded( std::string s )
{
    if( s.size() > 117 )
    {
        std::size_t n = 117;
        while( n > 0 && ( static_cast<unsigned char>( s[n] ) & 0xC0 ) == 0x80 )
        {
            --n;
        }
        s.resize( n );
        s += "...";
    }
    return s;
}
std::string helper( const std::string& s ) { return truncateUtf8WithEllipsis( s, 117 ); }
std::string noellipsis( std::string s, std::size_t n )
{
    if( s.size() > n )
    {
        s.resize( n );
    }
    return s;
}
std::string othervar( std::string buf, std::string label, std::size_t n )
{
    buf.resize( n );
    label += "...";
    return buf + label;
}
std::string replaced( const std::string& s, std::size_t n ) { return s.size() > n ? std::string( "..." ) : s; }
std::string packname( const std::string& text, bool pack )
{
    std::string n = text.substr( 0, text.find( '=' ) );
    if( pack )
    {
        n += "...";
    }
    return n;
}
std::string wordloop( const std::vector<std::string>& words )
{
    std::string out;
    for( const std::string& w : words )
    {
        out += w;
        if( out.size() >= kCap )
        {
            out += "\xE2\x80\xA6";
            break;
        }
    }
    return out;
}
std::u32string wide( std::u32string s, std::size_t n )
{
    if( s.size() > n )
    {
        s.resize( n );
        s += U"…";
    }
    return s;
}
std::string guardanywhere( std::string s )
{
    if( s.size() > 117 )
    {
        std::size_t n = 117;
        while( n > 0 && ( static_cast<unsigned char>( s[n] ) & 0xC0 ) == 0x80 )
        {
            --n;
        }
        s.resize( 117 );
        s += "...";
    }
    return s;
}
std::string capminus( std::string s )
{
    if( s.size() > 120 )
    {
        s.resize( 117 );
        s += "...";
    }
    return s;
}
std::string legacy( std::string s ) { if( s.size() > 40 ) { s.resize( 40 ); s += "..."; } return s; }
std::string freshcut( std::string s ) { if( s.size() > 60 ) { s = s.substr( 0, 60 ) + "..."; } return s; }
int drive() { return 1; }
EOF
} >"$WORK/utf8/src/text.cpp"
fx_run utf8
L="utf8-cut (c++)"
ds_has  "$L" utf8-cut excerpt  minor
ds_has  "$L" utf8-cut clip     minor
ds_has  "$L" utf8-cut build    minor
ds_has  "$L" utf8-cut erasecut minor
ds_has  "$L" utf8-cut capminus minor
ds_has  "$L" utf8-cut freshcut new-symbol
ds_wasnow "$L" utf8-cut excerpt 0 1
ds_none "$L" guarded    "the cut backs off continuation bytes (0xC0/0x80)"
ds_none "$L" helper     "a utf8 truncation helper does the cut"
ds_none "$L" guardanywhere "a back-off anywhere in the function exempts it, even one that does not cover the cut (a precision choice, stated in the legend)"
ds_none "$L" noellipsis "a cut with no ellipsis is not judged display text (stated floor)"
ds_none "$L" othervar   "the ellipsis goes on a different string than the one cut"
ds_none "$L" replaced   "the ellipsis replaces the value, nothing is cut"
ds_none "$L" packname   "the cut is at a parsed ASCII delimiter, not a size cap, and ... is pack syntax (src/ingest_names.h cppTemplateParameterName)"
ds_none "$L" wordloop   "whole strings are appended, so no byte sequence is split (the byte-push rule needs a single-char push)"
ds_none "$L" wide       "a u32string holds code points, a cut cannot split one"
ds_none "$L" legacy     "a cut the change did not introduce"
gating_split "$L" 0

# ── 3) DEDUP-FIRST, C++ (report-only) ───────────────────────────────────────────────────────────────────
#   The corpus shape (a two-pass merge, sorted on (line, rule), uniqued keeping the first) plus its ranges and
#   unsorted siblings. Near-misses: the sort orders on severity (worst first), the predicate compares severity,
#   a type with no severity-like field, a field whose name only CONTAINS a severity word (indentLevel — a
#   bounded token match), a predicate-less unique, a unique over ints, a heading level (bare level is not a
#   severity token: severity-like = sev / severity / priority / prio), and a NAMED predicate (skipped).
#   Stated floor: a sort that reads severity in the mild-first direction is not caught.
fx_init dedup
mkdir -p "$WORK/dedup/src"
DD_HDR='#include <algorithm>
#include <string>
#include <vector>

enum class Severity { Info, Warn, Critical };
struct Finding
{
    int line = 0;
    std::string rule;
    Severity sev = Severity::Info;
};
struct Row
{
    int line = 0;
    std::string rule;
    std::string text;
};
struct Node
{
    int line = 0;
    std::string rule;
    int indentLevel = 0;
};
struct Heading
{
    int line = 0;
    int level = 0;
};
bool sameLineSev( const Finding& a, const Finding& b );
'
{ printf '%s' "$DD_HDR"; cat <<'EOF'
void mergeFirst( std::vector<Finding>& v ) { (void)v; }
void rangesFirst( std::vector<Finding>& v ) { (void)v; }
void unsortedFirst( std::vector<Finding>& v ) { (void)v; }
void worstFirst( std::vector<Finding>& v ) { (void)v; }
void predSev( std::vector<Finding>& v ) { (void)v; }
void noSev( std::vector<Row>& v ) { (void)v; }
void indent( std::vector<Node>& v ) { (void)v; }
void defaultEq( std::vector<int>& v ) { (void)v; }
void ints( std::vector<int>& v ) { (void)v; }
void headings( std::vector<Heading>& v ) { (void)v; }
void namedPred( std::vector<Finding>& v ) { (void)v; }
void legacy( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b ) { return a.line == b.line; } ), v.end() );
}
int drive() { return 0; }
EOF
} >"$WORK/dedup/src/merge.cpp"
fx_commit dedup
{ printf '%s' "$DD_HDR"; cat <<'EOF'
void mergeFirst( std::vector<Finding>& v )
{
    std::stable_sort( v.begin(), v.end(), []( const Finding& a, const Finding& b )
                      { return a.line != b.line ? a.line < b.line : a.rule < b.rule; } );
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b )
                          { return a.line == b.line && a.rule == b.rule; } ),
             v.end() );
}
void rangesFirst( std::vector<Finding>& v )
{
    std::ranges::sort( v, []( const Finding& a, const Finding& b ) { return a.line < b.line; } );
    v.erase( std::ranges::unique( v, []( const Finding& a, const Finding& b ) { return a.line == b.line; } ).begin(), v.end() );
}
void unsortedFirst( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b ) { return a.rule == b.rule; } ), v.end() );
}
void worstFirst( std::vector<Finding>& v )
{
    std::stable_sort( v.begin(), v.end(), []( const Finding& a, const Finding& b )
                      { return a.line != b.line ? a.line < b.line : a.sev > b.sev; } );
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b ) { return a.line == b.line; } ), v.end() );
}
void predSev( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b )
                          { return a.line == b.line && a.sev == b.sev; } ),
             v.end() );
}
void noSev( std::vector<Row>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Row& a, const Row& b ) { return a.line == b.line; } ), v.end() );
}
void indent( std::vector<Node>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Node& a, const Node& b ) { return a.line == b.line; } ), v.end() );
}
void defaultEq( std::vector<int>& v )
{
    std::sort( v.begin(), v.end() );
    v.erase( std::unique( v.begin(), v.end() ), v.end() );
}
void ints( std::vector<int>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( int a, int b ) { return a / 10 == b / 10; } ), v.end() );
}
void headings( std::vector<Heading>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Heading& a, const Heading& b ) { return a.line == b.line; } ), v.end() );
}
bool sameLineSev( const Finding& a, const Finding& b ) { return a.line == b.line && a.sev == b.sev; }
void namedPred( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), sameLineSev ), v.end() );
}
void legacy( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b ) { return a.line == b.line; } ), v.end() );
}
void freshFirst( std::vector<Finding>& v )
{
    v.erase( std::unique( v.begin(), v.end(), []( const Finding& a, const Finding& b ) { return a.line == b.line; } ), v.end() );
}
int drive() { return 1; }
EOF
} >"$WORK/dedup/src/merge.cpp"
fx_run dedup
L="dedup-first (c++)"
ds_has  "$L" dedup-first mergeFirst    minor
ds_has  "$L" dedup-first rangesFirst   minor
ds_has  "$L" dedup-first unsortedFirst minor
ds_has  "$L" dedup-first freshFirst    new-symbol
ds_none "$L" worstFirst "the sort before the unique orders on severity, worst first"
ds_none "$L" predSev    "the predicate keeps rows of different severity apart"
ds_none "$L" noSev      "the element type has no severity-like field"
ds_none "$L" indent     "indentLevel only contains a severity word (bounded token match)"
ds_none "$L" defaultEq  "a predicate-less unique compares whole values"
ds_none "$L" ints       "a unique over ints carries no severity"
ds_none "$L" headings   "a heading/nesting level is not a severity (bare level, risk and grade are not severity tokens)"
ds_none "$L" namedPred  "a named predicate function is skipped, never guessed"
ds_none "$L" legacy     "a keep-first the change did not introduce"
gating_split "$L" 0

# ── 4) VACUOUS-ASSERT, Bash gate scripts (report-only) ──────────────────────────────────────────────────
#   One script per arm (top-level code has no enclosing symbol, so its row anchors on the file and a file
#   per arm keeps the arms apart). Baseline: each script has its reporters and one sound assertion; the edit
#   appends the arm. Positives: an absence assertion read off an unchecked $( ) capture, off a direct pipe
#   (with or without pipefail — under pipefail a crash makes the pipeline false, which takes the same PASS
#   branch), the if/else spelling, backslash continuations, the !-negated pass spelling, other reporter
#   names, inside a function, and a brand-new script; under set -e a `local x="$( )"` capture (local masks the
#   rc) and a direct pipe (left of &&, where errexit is suspended) stay positive. Near-misses: the capture's rc
#   checked, `|| no` on the capture, a presence check, a positive assertion on the same output before OR after
#   the absence, an enclosing if/case that requires content of the same capture, a plain capture under set -e
#   (errexit aborts on its failure), the match-is-pass polarity, a literal producer, a commented-out shape, a
#   pre-existing vacuous line, a sound if, a new function with a handled capture, the same shape in a script
#   outside a test path, a presence test on a variable derived from the capture, a requirement inside a
#   { …; } group, and an elif chain. A capture
#   derived from another capture (TAG="$( printf '%s' "$OUT" | grep -o … )") is followed back to its run.
fx_init vac
mkdir -p "$WORK/vac/test" "$WORK/vac/scripts"
VHDR="$( cat <<'EOF'
#!/usr/bin/env bash
BIN="${1:?}"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
V0="$( "$BIN" --version 2>&1 )"; RC0=$?
[ "$RC0" = 0 ] && ok "version runs" || no "version failed: $V0"
EOF
)"
VHDR="$VHDR
"
for f in t_var t_pipe t_pipefail t_if t_cont t_neg t_names t_fn t_setelocal t_setepipe t_derived n_rc n_orno n_presence n_positive n_polarity n_literal n_comment n_legacy n_ifok n_posafter n_nestif n_case n_casealone n_sete n_seteuo t_filepipe t_wrapper n_derivedguard n_bracegroup n_elif n_ifand n_elifpos n_helper t_fileredirect t_orcond t_undefhelper t_reassign; do
    printf '%s' "$VHDR" >"$WORK/vac/test/$f.sh"
done
for f in t_setepipe n_sete; do printf 'set -e\n' >>"$WORK/vac/test/$f.sh"; done
printf 'set -euo pipefail\n' >>"$WORK/vac/test/n_seteuo.sh"
cat >>"$WORK/vac/test/t_setelocal.sh" <<'EOF'
set -e
chk_local(){
    ok "placeholder"
}
chk_local
EOF
printf '%s' "$VHDR" >"$WORK/vac/scripts/build.sh"
cat >>"$WORK/vac/test/n_legacy.sh" <<'EOF'
OLD="$( "$BIN" --old 2>/dev/null )"
printf '%s' "$OLD" | grep -q 'stale' && no "stale present" || ok "stale absent"
EOF
cat >"$WORK/vac/test/t_names.sh" <<'EOF'
#!/usr/bin/env bash
BIN="${1:?}"
status=0
report_pass(){ echo "PASS $*"; }
report_fail(){ echo "FAIL $*"; status=1; }
"$BIN" --version >/dev/null 2>&1 && report_pass "runs" || report_fail "does not run"
EOF
cat >>"$WORK/vac/test/t_fn.sh" <<'EOF'
absent(){
    local out
    out="$( "$BIN" --version 2>&1 )" || { no "version failed"; return; }
    printf '%s' "$out" | grep -q "$1" && no "$1 present" || ok "$1 absent"
}
absent zzz
EOF
fx_commit vac
cat >>"$WORK/vac/test/t_var.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_pipe.sh" <<'EOF'
"$BIN" --list 2>/dev/null | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
{ printf 'set -o pipefail\n'; cat <<'EOF'
"$BIN" --list 2>/dev/null | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
} >>"$WORK/vac/test/t_pipefail.sh"
cat >>"$WORK/vac/test/t_if.sh" <<'EOF'
OUT2="$( "$BIN" --list 2>/dev/null )"
if printf '%s' "$OUT2" | grep -q 'bad'; then
    no "bad present"
else
    ok "bad absent"
fi
EOF
cat >>"$WORK/vac/test/t_cont.sh" <<'EOF'
MAP="$( "$BIN" --map 2>/dev/null )"
printf '%s' "$MAP" | grep -q 'suspect=' \
    && no "(f) a clean file carries suspect=" \
    || ok "(f) no suspect= on the clean file"
EOF
cat >>"$WORK/vac/test/t_neg.sh" <<'EOF'
NOUT="$( "$BIN" --list 2>/dev/null )"
! printf '%s' "$NOUT" | grep -q 'bad' && ok "bad absent" || no "bad present"
EOF
cat >>"$WORK/vac/test/t_names.sh" <<'EOF'
R="$( "$BIN" --list 2>/dev/null )"
echo "$R" | grep -q 'bad' && report_fail "bad present" || report_pass "bad absent"
EOF
cat >>"$WORK/vac/test/t_fn.sh" <<'EOF'
absent_unchecked(){
    local out
    out="$( "$BIN" --list 2>/dev/null )"
    printf '%s' "$out" | grep -q "$1" && no "$1 present" || ok "$1 absent"
}
absent_unchecked yyy
EOF
{ printf '%s' "$VHDR"; cat <<'EOF'
FRESH="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$FRESH" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
} >"$WORK/vac/test/t_new.sh"
cat >>"$WORK/vac/test/n_rc.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"; RC=$?
[ "$RC" = 0 ] || no "the list run failed (rc=$RC)"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_orno.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )" || no "the list run failed"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_presence.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
[ -n "$OUT" ] || no "the list run printed nothing"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_positive.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q '<list ' && ok "the list root is there" || no "no list root"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_polarity.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q 'good' && ok "good present" || no "good missing"
EOF
cat >>"$WORK/vac/test/n_literal.sh" <<'EOF'
X="fixed text"
printf '%s' "$X" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_comment.sh" <<'EOF'
# OUT="$( "$BIN" --list 2>/dev/null )"
# printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
echo done
EOF
cat >>"$WORK/vac/test/n_legacy.sh" <<'EOF'
echo "an unrelated line after the pre-existing assertion"
EOF
cat >>"$WORK/vac/test/n_ifok.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"; RC=$?
if [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q 'bad'; then ok "bad absent"; else no "bad present or the run failed (rc=$RC)"; fi
EOF
cat >>"$WORK/vac/scripts/build.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_fn.sh" <<'EOF'
absent_checked(){
    local out
    out="$( "$BIN" --list 2>/dev/null )" || { no "the list run failed"; return; }
    printf '%s' "$out" | grep -q "$1" && no "$1 present" || ok "$1 absent"
}
absent_checked xxx
EOF
{ printf '%s' "$VHDR"; cat <<'EOF'
set -e
chk_local(){
    local x="$( "$BIN" --list 2>/dev/null )"
    printf '%s' "$x" | grep -q 'bad' && no "bad present" || ok "bad absent"
}
chk_local
EOF
} >"$WORK/vac/test/t_setelocal.sh"
cat >>"$WORK/vac/test/t_setepipe.sh" <<'EOF'
"$BIN" --list 2>/dev/null | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_posafter.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
printf '%s' "$OUT" | grep -q '<list ' && ok "the list root is there" || no "no list root"
EOF
cat >>"$WORK/vac/test/n_nestif.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
if printf '%s' "$OUT" | grep -q '<list '; then
    if printf '%s' "$OUT" | grep -q 'bad'; then
        no "bad present"
    else
        ok "bad absent"
    fi
else
    no "no list root"
fi
EOF
cat >>"$WORK/vac/test/n_case.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
case "$OUT" in
    '<list '*) printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent" ;;
    *) no "no list root" ;;
esac
EOF
cat >>"$WORK/vac/test/n_casealone.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
case "$OUT" in
    '<list '*)
        printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent" ;;
    *)
        no "no list root" ;;
esac
EOF
for f in n_sete n_seteuo; do
    cat >>"$WORK/vac/test/$f.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
done
cat >>"$WORK/vac/test/t_derived.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
TAG="$( printf '%s' "$OUT" | grep -o '<list[^>]*>' )"
printf '%s' "$TAG" | grep -q 'bad=' && no "bad= present" || ok "bad= absent"
EOF
cat >>"$WORK/vac/test/t_filepipe.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/out.txt" 2>/dev/null
grep -v '^#' "$TMPDIR/out.txt" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_wrapper.sh" <<'EOF'
runit(){ "$BIN" "$@" 2>/dev/null; }
W="$( runit --list )"
printf '%s' "$W" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_derivedguard.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
ROWS="$( printf '%s' "$OUT" | grep -o '<r [^>]*>' )"
[ -n "$ROWS" ] || no "the list has no rows"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_bracegroup.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
{ printf '%s' "$OUT" | grep -q '<list ' && printf '%s' "$OUT" | grep -q '</list>'; } && ok "the list is whole" || no "the list is cut"
printf '%s' "$OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/n_elif.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"
if printf '%s' "$OUT" | grep -q 'bad'; then
    no "bad present"
elif printf '%s' "$OUT" | grep -q '<list '; then
    ok "bad absent and the list is there"
else
    no "no list root"
fi
EOF
#   Fix round 1 (rv-cr-qd-kinds-068 §1c): a positive on the SAME capture guards the absence beside it, also when it is
#   spelled as an if condition of &&-joined greps (wrapverbscheck:266), as an elif condition (ensemblecheck:366) or
#   through a function the script defines (qddialscheck:320). Near-miss positives: a || condition (a crash can take
#   the other branch's pass), a helper the script does not define, and a positive on an EARLIER capture of a
#   reassigned variable.
cat >>"$WORK/vac/test/n_ifand.sh" <<'EOF'
C_OUT="$( "$BIN" --list 2>/dev/null )"
if echo "$C_OUT" | grep -q '<list ' && echo "$C_OUT" | grep -qF '</list>'; then
    ok "the list is whole"
else
    no "the list is cut"
fi
if echo "$C_OUT" | grep -q 'bad'; then
    no "bad present"
else
    ok "bad absent"
fi
EOF
cat >>"$WORK/vac/test/n_elifpos.sh" <<'EOF'
page="$( "$BIN" --list 2>/dev/null | head -1 )"
rows="$( "$BIN" --list 2>/dev/null | grep -c '<r ' )"
if [ "$rows" != "1" ]; then
    no "want one row"
elif printf '%s' "$page" | grep -q 'total="1"'; then
    ok "one row disclosed"
else
    no "no total"
fi
if printf '%s' "$page" | grep -qE ' shown="'; then
    no "a bare shown="
else
    ok "no bare shown="
fi
EOF
cat >>"$WORK/vac/test/n_helper.sh" <<'EOF'
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r ' ; }
ODP2="$( "$BIN" --list 2>/dev/null )"
rows "$ODP2" | grep 'kind="dup"' | grep -q 'alpha' \
    && ok "the unrelated group survives" \
    || no "the unrelated group is gone"
printf '%s' "$ODP2" | grep -q 'config-warnings=' && no "a config warning" || ok "no config warning"
EOF
cat >>"$WORK/vac/test/t_orcond.sh" <<'EOF'
OR_OUT="$( "$BIN" --list 2>/dev/null )"
if echo "$OR_OUT" | grep -q '<list ' || echo "$OR_OUT" | grep -q '<empty'; then
    ok "a root"
fi
printf '%s' "$OR_OUT" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_undefhelper.sh" <<'EOF'
UH="$( "$BIN" --list 2>/dev/null )"
rowsx "$UH" | grep -q 'alpha' && ok "alpha" || no "no alpha"
printf '%s' "$UH" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_reassign.sh" <<'EOF'
RA="$( "$BIN" --list 2>/dev/null )"
if echo "$RA" | grep -q '<list ' && echo "$RA" | grep -q '</list>'; then
    ok "the first list is whole"
fi
RA="$( "$BIN" --list --other 2>/dev/null )"
printf '%s' "$RA" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vac/test/t_fileredirect.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/exp.xml" 2>/dev/null
grep -q 'secret' "$TMPDIR/exp.xml" && no "the secret leaked" || ok "no secret"
EOF
fx_run vac
L="vacuous-assert (bash)"
for f in t_var t_pipe t_pipefail t_if t_cont t_neg t_names t_setepipe t_derived; do
    ds_has_p "$L" vacuous-assert "test/$f.sh" minor
done
ds_has   "$L" vacuous-assert chk_local minor
ds_has   "$L" vacuous-assert absent_unchecked new-symbol
ds_has_p "$L" vacuous-assert test/t_new.sh new-symbol
ds_none  "$L" absent "the capture's failure is handled (|| { no; return; }) — and the function is untouched"
ds_none_p "$L" test/n_rc.sh       "the capture's rc is checked before the absence"
ds_none_p "$L" test/n_orno.sh     "|| no on the capture"
ds_none_p "$L" test/n_presence.sh "a presence check before the absence"
ds_none_p "$L" test/n_positive.sh "a positive assertion on the same output first"
ds_none_p "$L" test/n_polarity.sh "a match is the PASS branch: a crash fails"
ds_none_p "$L" test/n_literal.sh  "the producer is a literal, not a command"
ds_none_p "$L" test/n_comment.sh  "a commented-out shape is not code"
ds_none_p "$L" test/n_legacy.sh   "a vacuous line the change did not introduce"
ds_none_p "$L" test/n_ifok.sh     "the if checks the rc in its condition"
ds_none_p "$L" scripts/build.sh   "not a test-script path: the kind is scoped to gate scripts"
ds_none  "$L" absent_checked      "a NEW function whose capture failure is handled (|| { no; return; })"
ds_none_p "$L" test/n_posafter.sh "a positive assertion on the same capture AFTER the absence fails on a crash"
ds_none_p "$L" test/n_nestif.sh   "the absence is nested in an if that requires content of the same capture"
ds_none_p "$L" test/n_case.sh     "the absence is nested in a case arm that requires content of the same capture"
ds_none_p "$L" test/n_casealone.sh "a case pattern alone on its line (the scanner must not read past it), the absence on the next line"
ds_none_p "$L" test/n_sete.sh     "set -e: a failed plain capture aborts the script"
ds_none_p "$L" test/n_seteuo.sh   "set -euo pipefail: a failed plain capture aborts the script"
ds_none_p "$L" test/n_derivedguard.sh "a presence test on a variable DERIVED from the capture requires the capture's text"
ds_none_p "$L" test/n_bracegroup.sh "a requirement inside a { …; } group on the same capture"
ds_none_p "$L" test/n_elif.sh     "an elif chain: a crash takes the final else (a failure), not a pass"
ds_none_p "$L" test/n_ifand.sh    "a positive on the same capture in an if condition of &&-joined greps guards it (rv §1c, wrapverbscheck:271)"
ds_none_p "$L" test/n_elifpos.sh  "a positive on the same capture in an elif condition guards it (rv §1c, ensemblecheck:371)"
ds_none_p "$L" test/n_helper.sh   "a positive on the same capture through a script-defined function guards it (rv §1c, qddialscheck:323)"
#   QD-VA-FORMS (2026-11-19): the three former floors are positives now — a filter over a file the run wrote
#   (t_filepipe), a capture through a script-defined wrapper (t_wrapper), an absence read off a FILE a run
#   redirected into (t_fileredirect; redactcheck:81 was the shape).
for f in t_orcond t_undefhelper t_reassign t_filepipe t_wrapper t_fileredirect; do
    ds_has_p "$L" vacuous-assert "test/$f.sh" minor
done
gating_split "$L" 0

# ── 4b) VACUOUS-ASSERT FORMS (QD-VA-FORMS): the status-dataflow walk on the B43 matcher's port ──────────────────
#   One status model (src/shstatus.h = test/lib/exitstatus.py, held equal by gateexitcheck H4): a run whose status
#   nothing reads may fail silently, and its text is then EMPTY. Positives, one per form: an absence read off a file
#   the run redirected into; `|| no` after a pipe without pipefail (it reads the last stage); a wrapper whose status
#   is dropped; a cmp parity of two failed runs' files; a FAIL reporter inside $( ) (the flag dies with the
#   subshell); rc=$? only echoed; `| head -1 || fallback`; a text kept in a loop; a capture of a wrapper call. Each
#   negative is a positive twin with the status read or the text guarded; the twin's row is the premise that the
#   form is read, so the arm counts its pairs and fails short of all. The last five are census false positives
#   fixed in this lane (the site in parentheses).
fx_init vaf
mkdir -p "$WORK/vaf/test"
for f in t_redir t_nopipefail t_wrapdrop t_parity t_lostflag t_rcunread t_headfallback t_ungated t_callnorc n_pipefail n_redirrc n_redirorfail n_wrapchecked n_parityguard n_rcread n_rccondreassign n_rcbranches n_headtrue n_presencegated n_callrc n_sqsub; do
    printf '%s' "$VHDR" >"$WORK/vaf/test/$f.sh"
done
fx_commit vaf
cat >>"$WORK/vaf/test/t_redir.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/o.txt" 2>/dev/null
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/t_nopipefail.sh" <<'EOF'
"$BIN" --list 2>/dev/null | sed 's/x/y/' >"$TMPDIR/o.txt" || no "the list run failed"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/t_wrapdrop.sh" <<'EOF'
runit(){ "$BIN" "$@" 2>/dev/null; }
runit --list >"$TMPDIR/o.txt"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/t_parity.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/a.txt" 2>/dev/null
"$BIN" --list >"$TMPDIR/b.txt" 2>/dev/null
cmp -s "$TMPDIR/a.txt" "$TMPDIR/b.txt" && ok "deterministic" || no "nondeterministic"
EOF
cat >>"$WORK/vaf/test/t_lostflag.sh" <<'EOF'
ask(){ local o; o="$( "$BIN" --list 2>/dev/null )" || { no "the list run failed"; return 0; }; printf '%s' "$o"; }
A="$( ask )"
printf '%s' "$A" | grep -q 'bad' && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/t_rcunread.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"; rc=$?
echo "the list run exited $rc"
printf '%s' "$OUT" | grep -q '<list' && ok "a list" || no "no list"
EOF
cat >>"$WORK/vaf/test/t_headfallback.sh" <<'EOF'
FIRST="$( "$BIN" --list 2>/dev/null | head -1 || echo 'no output' )"
case "$FIRST" in '<list'*) ok "a list first" ;; *) no "first line: $FIRST" ;; esac
EOF
cat >>"$WORK/vaf/test/t_ungated.sh" <<'EOF'
KEEP=""; HIT=""
for n in 1 2 3; do
    o="$( "$BIN" --list --n=$n 2>/dev/null )"
    HIT="$n"; KEEP="$o"
done
if [ -z "$HIT" ]; then
    no "no run"
else
    printf '%s' "$KEEP" | grep -q 'bad' && no "bad present" || ok "bad absent"
fi
EOF
cat >>"$WORK/vaf/test/t_callnorc.sh" <<'EOF'
run_hook(){ printf '%s' "$1" | bash "$HOOK"; }
OUT="$( run_hook '{}' )"
if [ -z "$OUT" ]; then ok "silent"; else no "fired: $OUT"; fi
EOF
cat >>"$WORK/vaf/test/n_pipefail.sh" <<'EOF'
set -o pipefail
"$BIN" --list 2>/dev/null | sed 's/x/y/' >"$TMPDIR/o.txt" || no "the list run failed"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/n_redirrc.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/o.txt" 2>/dev/null; rc=$?
[ "$rc" = 0 ] || no "the list run failed (rc=$rc)"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/n_redirorfail.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/o.txt" 2>/dev/null || no "the list run failed"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/n_wrapchecked.sh" <<'EOF'
runit(){ "$BIN" "$@" 2>/dev/null; }
runit --list >"$TMPDIR/o.txt" || no "the list run failed"
grep -q 'bad' "$TMPDIR/o.txt" && no "bad present" || ok "bad absent"
EOF
cat >>"$WORK/vaf/test/n_parityguard.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/a.txt" 2>/dev/null
"$BIN" --list >"$TMPDIR/b.txt" 2>/dev/null
[ -s "$TMPDIR/a.txt" ] && [ -s "$TMPDIR/b.txt" ] || no "a run printed nothing"
cmp -s "$TMPDIR/a.txt" "$TMPDIR/b.txt" && ok "deterministic" || no "nondeterministic"
EOF
cat >>"$WORK/vaf/test/n_rcread.sh" <<'EOF'
OUT="$( "$BIN" --list 2>/dev/null )"; rc=$?
[ "$rc" = 0 ] || no "the list run exited $rc"
printf '%s' "$OUT" | grep -q '<list' && ok "a list" || no "no list"
EOF
cat >>"$WORK/vaf/test/n_rccondreassign.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/v" 2>&1; prc=$?
"$BIN" --other >>"$TMPDIR/v" 2>&1 || prc=1
[ "$prc" = 0 ] && ok "both ran" || no "a run failed"
EOF
cat >>"$WORK/vaf/test/n_rcbranches.sh" <<'EOF'
if [ -n "${WIDE:-}" ]; then
    OUT="$( "$BIN" --list --wide 2>/dev/null )"; rc=$?
else
    OUT="$( "$BIN" --list 2>/dev/null )"; rc=$?
fi
[ "$rc" = 0 ] && printf '%s' "$OUT" | grep -q '<list' && ok "a list" || no "rc=$rc or no list"
EOF
cat >>"$WORK/vaf/test/n_headtrue.sh" <<'EOF'
FIRST="$( "$BIN" --list 2>/dev/null | head -1 || true )"
case "$FIRST" in '<list'*) ok "a list first" ;; *) no "first line: $FIRST" ;; esac
EOF
cat >>"$WORK/vaf/test/n_presencegated.sh" <<'EOF'
KEEP=""; HIT=""
for n in 1 2 3; do
    o="$( "$BIN" --list --n=$n 2>/dev/null )"
    if printf '%s' "$o" | grep -q '<list'; then HIT="$n"; KEEP="$o"; break; fi
done
if [ -z "$HIT" ]; then
    no "no run printed a list"
else
    printf '%s' "$KEEP" | grep -q 'bad' && no "bad present" || ok "bad absent"
fi
EOF
cat >>"$WORK/vaf/test/n_callrc.sh" <<'EOF'
run_hook(){ printf '%s' "$1" | bash "$HOOK"; }
OUT="$( run_hook '{}' )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exit 0"; else no "exit was $RC"; fi
if [ -z "$OUT" ]; then ok "silent"; else no "fired: $OUT"; fi
EOF
cat >>"$WORK/vaf/test/n_sqsub.sh" <<'EOF'
"$BIN" --list >"$TMPDIR/u.xml" 2>/dev/null
OFF="$( grep -bo '<r ' "$TMPDIR/u.xml" | head -1 | cut -d: -f1 )"
if [ -z "$OFF" ]; then no "no row"; fi
grep -q 'note=' "$TMPDIR/u.xml" && no "note present" || ok "no note"
EOF
fx_run vaf
L="vacuous-assert forms"
for f in t_redir t_nopipefail t_wrapdrop t_parity t_lostflag t_rcunread t_headfallback t_ungated t_callnorc; do
    ds_has_p "$L" vacuous-assert "test/$f.sh" minor
done
vpairs=0
vpair(){  # NEG TWIN WHY — the negative prints no row, and its positive twin's row proves the form was read
    [ "$QD_OK" = 1 ] || { no "$L: cannot read an absence in $1 off a failed run"; return; }
    if [ -z "$( ds_any_p "test/$2.sh" )" ]; then no "$L: $1: the premise twin $2 printed no row, so its absence proves nothing"; return; fi
    ds_none_p "$L" "test/$1.sh" "$3; twin $2 fires"
    [ -z "$( ds_any_p "test/$1.sh" )" ] && vpairs=$(( vpairs + 1 ))
}
vpair n_pipefail t_nopipefail "set -o pipefail: the || after the pipe reads the run's status"
vpair n_redirrc t_redir "rc=\$? after the redirected run is compared"
vpair n_redirorfail t_redir "|| no on the redirected run"
vpair n_wrapchecked t_wrapdrop "the wrapper call's status is read (|| no)"
vpair n_parityguard t_parity "[ -s ] on both files guards the parity"
vpair n_rcread t_rcunread "the captured rc is compared"
vpair n_rccondreassign t_rcunread "a conditional \`|| prc=1\` keeps the capture live until its test (pincensuscheck:414)"
vpair n_rcbranches t_rcunread "rc=\$? captured in both arms of an if, tested after fi: the else arm never overwrites the then arm (qualitycheck:231)"
vpair n_headtrue t_headfallback "\`|| true\` is no fallback"
vpair n_presencegated t_ungated "the text is assigned only behind a presence check on it (prcontextcheck:226)"
vpair n_callrc t_callnorc "rc=\$? of the wrapper call is compared (hookcheck:345)"
vpair n_sqsub t_redir "a single-quoted pattern inside \"\$( )\" is a word, not a < redirect (expandbodyfirstcheck:122)"
[ "$vpairs" = 12 ] && ok "$L: all $vpairs negative arms print 0 rows beside a firing twin" \
    || no "$L: $vpairs of 12 negative arms passed beside a firing twin (want all; zero means nothing was judged)"
gating_split "$L" 0

# ── 4c) UNCHECKED-STATUS (QD-UNCHECKED-STATUS): a dropped I/O or child status, C/C++ and Python ─────────────────
#   A call whose return IS the status (pclose, rename, write, system, fflush; fclose / close of a stream or descriptor
#   the function wrote; waitpid with the child's status dropped too; Python subprocess.run with no check=,
#   subprocess.call, os.system) made where the value reaches nothing. Every function exists at the baseline with an
#   empty body and the edit adds the call, so a row is preexisting-worse and must STILL be sev="minor" (report-only).
#   p= is the SITE's line (not the definition's) and call= names the call. Each negative is a positive's twin with
#   the status read, cast to (void), returned, tested, or the stream/descriptor not written; the arm counts the twins
#   whose positive fired and fails short of all of them (an arm whose premise did not fire proves nothing).
fx_init ucs
UC_FNS_C="p_pclose p_rename p_write p_system p_fflush p_fclose p_close p_waitpid p_label p_append n_void n_assign n_return n_cond n_fclose_read n_close_unwritten n_waitpid_read n_fflush_stderr n_member n_helper n_fclose_failed n_fflush_stdout"
UC_FNS_PY="p_run p_call p_system p_stdout p_bound p_bare p_alias n_check n_check_false n_rc n_return n_cond n_kwargs n_underscore n_rc_attr n_bound_returned"
{ printf '#include <stdio.h>\n'; for f in $UC_FNS_C; do printf 'void %s( int fd, FILE* p ) { }\n' "$f"; done; } >"$WORK/ucs/a.c"
{ printf 'import os\nimport subprocess\n'; for f in $UC_FNS_PY; do printf 'def %s(cmd):\n    return None\n' "$f"; done; } >"$WORK/ucs/t.py"
printf 'void cpp_base( int fd ) { }\nvoid cpp_os( int fd ) { }\nvoid cpp_multi( int fd ) { }\n' >"$WORK/ucs/b.cpp"
fx_commit ucs
cat >"$WORK/ucs/a.c" <<'EOF'
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
void p_pclose( int fd, FILE* p ) { pclose( p ); }
void p_rename( int fd, FILE* p ) { rename( "a", "b" ); }
void p_write( int fd, FILE* p ) { write( fd, "x", 1 ); }
void p_system( int fd, FILE* p ) { if( fd ) system( "ls" ); }
void p_fflush( int fd, FILE* p ) { fflush( p ); }
void p_fclose( int fd, FILE* p ) { FILE* f = fopen( "o", "w" ); fputs( "x", f ); fclose( f ); }
void p_close( int fd, FILE* p ) { if( write( fd, "x", 1 ) < 0 ) { return; } close( fd ); }
void p_waitpid( int fd, FILE* p ) { waitpid( fd, NULL, 0 ); }
void p_label( int fd, FILE* p ) { if( !p ) goto out; out: pclose( p ); }
void p_append( int fd, FILE* p ) { FILE* f = fopen( "o", "a" ); fclose( f ); }
void n_void( int fd, FILE* p ) { (void)pclose( p ); }
void n_assign( int fd, FILE* p ) { int rc = rename( "a", "b" ); if( rc ) { return; } }
int n_return( int fd, FILE* p ) { return write( fd, "x", 1 ); }
void n_cond( int fd, FILE* p ) { if( system( "ls" ) != 0 ) { return; } }
void n_fclose_read( int fd, FILE* p ) { FILE* f = fopen( "o", "r" ); fclose( f ); }
void n_close_unwritten( int fd, FILE* p ) { int w = open( "/dev/null", O_RDWR ); close( w ); }
void n_waitpid_read( int fd, FILE* p ) { int st; waitpid( fd, &st, 0 ); if( WIFEXITED( st ) ) { return; } }
void n_fflush_stderr( int fd, FILE* p ) { fflush( stderr ); }
void n_member( int fd, FILE* p ) { struct { void ( *pclose )( FILE* ); } s; s.pclose( p ); }
static int xclose( FILE* p ) { return pclose( p ); }
void n_helper( int fd, FILE* p ) { if( xclose( p ) ) { return; } }
void n_fclose_failed( int fd, FILE* p ) { if( fwrite( "x", 1, 1, p ) != 1 ) { fclose( p ); return; } if( fclose( p ) ) { return; } }
void n_fflush_stdout( int fd, FILE* p ) { fflush( stdout ); }
EOF
cat >"$WORK/ucs/b.cpp" <<'EOF'
#include <cstdio>
#include <cstdlib>
namespace pool { int close( int ); }
void cpp_base( int fd ) { std::system( "ls" ); }
void cpp_ns( int fd ) { pool::close( fd ); }
void cpp_cast( int fd ) { static_cast<void>( std::system( "ls" ) ); }
namespace rw::os { int pclose( FILE* ); }
void cpp_os( int fd ) { rw::os::pclose( nullptr ); }
void cpp_multi( int fd )
{
    std::system( "a" );
    std::system( "b" );
    std::system( "c" );
    std::system( "d" );
}
EOF
cat >"$WORK/ucs/t.py" <<'EOF'
import os
import subprocess
import subprocess as sp
from subprocess import call as pcall
def p_run(cmd):
    subprocess.run(cmd)
def p_call(cmd):
    subprocess.call(cmd)
def p_system(cmd):
    os.system(cmd)
def p_stdout(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout
def p_bound(cmd):
    r = subprocess.run(cmd, capture_output=True)
    print(r.stdout)
def p_bare(cmd):
    pcall(cmd)
def p_alias(cmd):
    if cmd: sp.run(cmd)
def n_check(cmd):
    subprocess.run(cmd, check=True)
def n_check_false(cmd):
    subprocess.run(cmd, check=False)
def n_rc(cmd):
    r = subprocess.run(cmd)
    if r.returncode != 0:
        raise SystemExit(1)
def n_return(cmd):
    return subprocess.run(cmd)
def n_cond(cmd):
    if subprocess.call(cmd) != 0:
        raise SystemExit(1)
def n_kwargs(cmd, **kw):
    subprocess.run(cmd, **kw)
def n_underscore(cmd):
    _ = os.system(cmd)
def n_rc_attr(cmd):
    return subprocess.run(cmd).returncode
def n_bound_returned(cmd):
    r = subprocess.run(cmd, capture_output=True)
    print(r.stdout)
    return r
EOF
L="unchecked-status"
fx_run ucs
uc_row(){ ds_rows | grep 'defect="unchecked-status"' | grep " sym=\"$1\"" | grep " p=\"$2:"; }   # SYM PATH
uc_has(){    # SYM PATH LINE CALL — one minor row, p= at the SITE's line, call= the call
    local row; row="$( uc_row "$1" "$2" )"
    if [ -z "$row" ]; then no "$L: no unchecked-status row on $1 ($2)"; return 1; fi
    [ "$( printf '%s\n' "$row" | wc -l | tr -d ' ' )" = 1 ] || { no "$L: more than one unchecked-status row on $1 ($2): $row"; return 1; }
    ds_judge "$L: $1 ($2)" "$row" minor
    if printf '%s' "$row" | grep -q " p=\"$2:$3\""; then ok "$L: $1 p=$2:$3 (the site's line)"; else no "$L: $1 p= should be the site $2:$3: $row"; fi
    if printf '%s' "$row" | grep -q " call=\"$4\""; then ok "$L: $1 call=$4"; else no "$L: $1 call= should be $4: $row"; fi
    return 0
}
uc_none(){   # SYM PATH WHY
    [ "$QD_OK" = 1 ] || { no "$L: cannot read an absence on $1 off a failed run"; return; }
    local row; row="$( uc_row "$1" "$2" )"
    if [ -z "$row" ]; then ok "$L: no unchecked-status row on $1 ($3)"; else no "$L: false positive on $1 ($3): $row"; fi
}
if [ "$QD_OK" = 1 ]; then
    uc_has p_pclose a.c 5 pclose; uc_has p_rename a.c 6 rename; uc_has p_write a.c 7 write; uc_has p_system a.c 8 system
    uc_has p_fflush a.c 9 fflush; uc_has p_fclose a.c 10 fclose; uc_has p_close a.c 11 close; uc_has p_waitpid a.c 12 waitpid
    uc_has p_label a.c 13 pclose; uc_has p_append a.c 14 fclose; uc_has cpp_base b.cpp 4 system; uc_has cpp_os b.cpp 8 pclose
    uc_has cpp_multi b.cpp 11 system   # four sites: p= is the EARLIEST line, not the first in site-identity order
    ds_wasnow "$L" unchecked-status cpp_multi 0 4
    uc_has p_run t.py 6 subprocess.run; uc_has p_call t.py 8 subprocess.call; uc_has p_system t.py 10 os.system
    uc_has p_stdout t.py 12 subprocess.run; uc_has p_bound t.py 14 subprocess.run; uc_has p_bare t.py 17 subprocess.call
    uc_has p_alias t.py 19 subprocess.run
    #   the twins: NEGATIVE [premise POSITIVE] — the positive's row above is what makes the negative's silence mean something
    seen=0; pairs=0
    for pair in "n_void:p_pclose:a.c:(void) is a stated decision" "n_assign:p_rename:a.c:assigned and compared" \
                "n_return:p_write:a.c:the value is returned" "n_cond:p_system:a.c:used in a condition" \
                "n_fclose_read:p_fclose:a.c:a read stream's close loses nothing" "n_close_unwritten:p_close:a.c:opened for writing (/dev/null), never written" \
                "n_fclose_failed:p_fclose:a.c:the cleanup close in a failed-write branch" "n_fflush_stdout:p_fflush:a.c:a flush of stdout is not judged" \
                "n_waitpid_read:p_waitpid:a.c:the child's status is read" "n_fflush_stderr:p_fflush:a.c:a failed flush of stderr has nowhere to go" \
                "n_member:p_pclose:a.c:a member named pclose is not libc's" "xclose:p_pclose:a.c:a helper that returns the status" \
                "n_helper:p_pclose:a.c:a helper call whose status is read" \
                "cpp_ns:cpp_base:b.cpp:another namespace's close" "cpp_cast:cpp_base:b.cpp:static_cast<void> is a stated decision" \
                "n_check:p_run:t.py:check=True" "n_check_false:p_run:t.py:check=False is a stated decision" \
                "n_rc:p_bound:t.py:returncode is read" "n_return:p_run:t.py:the result is returned" \
                "n_cond:p_call:t.py:used in a condition" "n_kwargs:p_run:t.py:**kwargs may carry check=" \
                "n_underscore:p_system:t.py:bound to _" "n_rc_attr:p_stdout:t.py:.returncode read off the call" \
                "n_bound_returned:p_bound:t.py:the bound result is returned"; do
        neg="${pair%%:*}"; rest="${pair#*:}"; pos="${rest%%:*}"; rest="${rest#*:}"; path="${rest%%:*}"; why="${rest#*:}"
        pairs=$(( pairs + 1 ))
        [ -n "$( uc_row "$pos" "$path" )" ] && seen=$(( seen + 1 ))
        uc_none "$neg" "$path" "$why"
    done
    if [ "$seen" = "$pairs" ] && [ "$pairs" -gt 0 ]; then ok "$L: every negative's positive twin fired ($seen/$pairs): each silence is read off a shape the scanner sees"
    else no "$L: only $seen/$pairs negatives' positive twins fired — a silent negative proves nothing without its twin"; fi
    #   never gating: the report-only facet carries no gating= even on a preexisting symbol
    if ds_rows | grep 'defect="unchecked-status"' | grep -q 'gating='; then no "$L: an unchecked-status row gates: $( ds_rows | grep 'defect="unchecked-status"' | grep 'gating=' | head -1 )"
    else ok "$L: no unchecked-status row gates ($( ds_rows | grep -c 'defect="unchecked-status"' ) rows)"; fi
fi
#   the legend: unchecked-status and call= are defined on an answer that carries the row, and only there
ULEG="$( cd "$WORK/ucs" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; xrc=$?   # 0 or 2: the run completed
if [ "$xrc" -le 2 ] && printf '%s' "$ULEG" | grep -q 'unchecked-status: a call whose return' && printf '%s' "$ULEG" | grep -q 'call= the call'; then ok "$L: the full legend defines unchecked-status and call="
else no "$L: the full legend does not define unchecked-status / call="; fi
UCLEG="$( cd "$WORK/ucs" && "$BIN" . --quality-delta --no-cache --legend=compact 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$UCLEG" | grep -q 'r call=: the call an unchecked-status row'; then ok "$L: the compact legend defines r call="; else no "$L: the compact legend does not define r call="; fi
FLEG="$( cd "$WORK/fmt_cpp" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$FLEG" | grep -q '<quality-delta ' && ! printf '%s' "$FLEG" | grep -q 'unchecked-status: a call whose return'; then ok "$L: an answer with no unchecked-status row carries no unchecked-status legend"
else no "$L: the unchecked-status legend rides on an answer without the row (or the run failed)"; fi
#   the JSON twin carries call= too
UJ="$( cd "$WORK/ucs" && "$BIN" . --quality-delta --no-cache --json 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$UJ" | grep -q '"defect":"unchecked-status"' && printf '%s' "$UJ" | grep -q '"call":"pclose"'; then ok "$L: --json rows carry defect=unchecked-status and call"
else no "$L: --json rows do not carry the unchecked-status facet and call"; fi
#   recall replay, reversed: a fix that checked the status, read backwards (FIX..FIX^), adds the discard back
fx_init ucfix
printf '#include <stdio.h>\nint run( FILE* p ) { return pclose( p ) != 0; }\n' >"$WORK/ucfix/r.c"
printf 'import subprocess\ndef run(cmd):\n    subprocess.run(cmd, check=True)\n' >"$WORK/ucfix/r.py"
fx_commit ucfix
( cd "$WORK/ucfix" && printf '#include <stdio.h>\nint run( FILE* p ) { pclose( p ); return 0; }\n' >r.c \
  && printf 'import subprocess\ndef run(cmd):\n    subprocess.run(cmd)\n' >r.py && git add -A >/dev/null 2>&1 && git commit -qm "drop the checks" >/dev/null 2>&1 ) || no "$L: the recall fixture's second commit failed"
fx_run_ref ucfix HEAD^..HEAD
if [ "$QD_OK" = 1 ]; then
    n="$( ds_rows | grep 'defect="unchecked-status"' | grep -c ' sym="run"' )"
    if [ "$n" = 2 ]; then ok "$L: the range that dropped both checks prints both rows (C and Python)"; else no "$L: the range that dropped both checks printed $n unchecked-status rows, want 2"; fi
fi
fx_run_ref ucfix HEAD..HEAD^
if [ "$QD_OK" = 1 ]; then
    n="$( ds_rows | grep -c 'defect="unchecked-status"' )"
    if [ "$n" = 0 ]; then ok "$L: the fixing direction prints no unchecked-status row"; else no "$L: the fixing direction printed $n unchecked-status rows"; fi
fi

# ── 4d) UNHANDLED-ARM (QD-UNHANDLED-ARM): a classifier over a closed set with no outcome for a value it does not name ──
#   C/C++: a switch with no default: over an in-tree enum that decides a value and leaves an owed enumerator out (the
#   enum lives in a header the switch's file does not define); shell: a case with no *) arm ending its function with
#   return/echo arms, or setting one name read after esac; Python: an if/elif chain or a match ending a value-returning
#   function with no else. Every function exists at the baseline with an empty body and the edit adds the classifier,
#   so a row is preexisting-worse and must STILL be sev="minor". p= is the SITE's line, why= what is left out. Each
#   negative is a positive's twin with a default / *) / else, full coverage, a stated omission, nothing decided, an
#   undecidable set (an int switch, an #if, a foreign enum) or generated code; the arm counts the twins whose positive
#   fired and fails short of all of them.
fx_init uas
mkdir -p "$WORK/uas/tools"
cat >"$WORK/uas/k.h" <<'EOF'
#pragma once
enum class Kind : unsigned char { Fn, Var, Type, Macro, kKindCount };
enum Color { RED, GREEN, BLUE, COLOR_DEFAULT = BLUE };
typedef enum { M_A, M_B, M_C } Mode;
enum class Cond {
    A,
#ifdef X
    B,
#endif
    C };
EOF
UA_CPP="p_missing p_assign p_full_alias n_default n_full n_void n_comment n_named n_int n_cond n_ifdef"
{ printf '#include "k.h"\nvoid f(); void g();\n'; for f in $UA_CPP; do printf 'int %s( int k ) { return 0; }\n' "$f"; done; } >"$WORK/uas/a.cpp"
printf '#include "k.h"\nint p_typedef( int m ) { return 0; }\n' >"$WORK/uas/m.c"
printf '// Code generated by mkswitch. DO NOT EDIT.\n#include "k.h"\nint n_generated( int k ) { return 0; }\n' >"$WORK/uas/gen.cpp"
UA_PY="p_literal p_enum p_match p_in n_else n_wild n_trailing n_full_enum n_none n_optional n_void n_mixed n_foreign"
{ printf 'import enum\nfrom typing import Optional\nclass Shade(enum.Enum):\n    LIGHT = 1\n    DARK = 2\n    DIM = 3\n    GLOOM = DARK\n'
  for f in $UA_PY; do printf 'def %s(kind, other=None):\n    return 0\n' "$f"; done; } >"$WORK/uas/t.py"
UA_SH="p_ret p_echo p_assign n_star n_trailing n_default n_unread n_dispatch"
{ printf '#!/bin/bash\n'; for f in $UA_SH; do printf '%s() {\n    :\n}\n' "$f"; done; } >"$WORK/uas/tools/s.sh"
fx_commit uas
cat >"$WORK/uas/a.cpp" <<'EOF'
#include "k.h"
void f(); void g();
const char* p_missing( Kind k ) { switch( k ) { case Kind::Fn: return "fn"; case Kind::Var: return "var"; } return "?"; }
int p_assign( Color c ) { int v = 0; switch( c ) { case RED: v = 1; break; case GREEN: v = 2; break; } return v; }
int p_full_alias( Color c ) { switch( c ) { case RED: return 1; case GREEN: return 2; } return 0; }
const char* n_default( Kind k ) { switch( k ) { case Kind::Fn: return "fn"; case Kind::Var: return "var"; default: return "?"; } }
const char* n_full( Kind k ) { switch( k ) { case Kind::Fn: return "a"; case Kind::Var: return "b"; case Kind::Type: return "c"; case Kind::Macro: return "d"; } return "?"; }
void n_void( Kind k ) { switch( k ) { case Kind::Fn: f(); break; case Kind::Var: g(); break; } }
const char* n_comment( Kind k ) { switch( k ) { case Kind::Fn: return "fn"; case Kind::Var: return "var"; /* the rest fall through to the generic tag */ } return "?"; }
const char* n_named( Kind k ) { switch( k ) { case Kind::Fn: return "fn"; case Kind::Var: return "var"; // Type and Macro carry no tag
  } return "?"; }
int n_int( int x ) { switch( x ) { case 1: return 2; case 3: return 4; } return 0; }
int n_cond( Cond c ) { switch( c ) { case Cond::A: return 1; } return 0; }
int n_ifdef( Kind k ) { switch( k ) { case Kind::Fn: return 1;
#ifdef Y
  case Kind::Var: return 2;
#endif
  } return 0; }
EOF
# p_full_alias names RED and GREEN only: BLUE is owed (COLOR_DEFAULT is an alias of it); its twin n_alias below covers BLUE
cat >>"$WORK/uas/a.cpp" <<'EOF'
int n_alias( Color c ) { switch( c ) { case RED: return 1; case GREEN: return 2; case BLUE: return 3; } return 0; }
EOF
printf '#include "k.h"\nint p_typedef( Mode m ) { switch( m ) { case M_A: return 1; case M_B: return 2; } return 0; }\n' >"$WORK/uas/m.c"
printf '// Code generated by mkswitch. DO NOT EDIT.\n#include "k.h"\nconst char* n_generated( Kind k ) { switch( k ) { case Kind::Fn: return "fn"; case Kind::Var: return "var"; } return "?"; }\n' >"$WORK/uas/gen.cpp"
cat >"$WORK/uas/t.py" <<'EOF'
import enum
from typing import Optional
class Shade(enum.Enum):
    LIGHT = 1
    DARK = 2
    DIM = 3
    GLOOM = DARK
def p_literal(kind, other=None):
    if kind == "a":
        return 1
    elif kind == "b":
        return 2
def p_enum(kind, other=None):
    if kind == Shade.LIGHT:
        return "l"
    elif kind is Shade.DARK:
        return "d"
def p_match(kind, other=None):
    match kind:
        case "x" | "y":
            return 1
        case "z":
            return 2
def p_in(kind, other=None):
    if kind in ("a", "b"):
        return 1
    elif kind == "c": return 2
def n_else(kind, other=None):
    if kind == "a":
        return 1
    elif kind == "b":
        return 2
    else:
        return 3
def n_wild(kind, other=None):
    match kind:
        case "x":
            return 1
        case "y":
            return 2
        case _:
            return 3
def n_trailing(kind, other=None):
    if kind == "a":
        return 1
    elif kind == "b":
        return 2
    return 0
def n_full_enum(kind, other=None):
    if kind == Shade.LIGHT:
        return "l"
    elif kind == Shade.DARK:
        return "d"
    elif kind == Shade.DIM:
        return "m"
def n_none(kind, other=None):
    if kind == "x":
        return None
    if kind == "a":
        return 1
    elif kind == "b":
        return 2
def n_optional(kind, other=None) -> Optional[int]:
    if kind == "a":
        return 1
    elif kind == "b":
        return 2
def n_void(kind, other=None):
    if kind == "a":
        print(1)
    elif kind == "b":
        print(2)
def n_mixed(kind, other=None):
    if kind == "a":
        return 1
    elif other == "b":
        return 2
def n_foreign(kind, other=None):
    if kind == Other.A:
        return 1
    elif kind == Other.B:
        return 2
EOF
cat >"$WORK/uas/tools/s.sh" <<'EOF'
#!/bin/bash
p_ret() {
    case "$1" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
    esac
}
p_echo() {
    case "$1" in
        a) echo alpha ;;
        b) echo beta ;;
    esac
}
p_assign() {
    case "$1" in
        a) mode=fast ;;
        b) mode=slow ;;
    esac
    run "$mode"
}
n_star() {
    case "$1" in
        y) return 0 ;;
        *) return 1 ;;
    esac
}
n_trailing() {
    case "$1" in
        y) return 0 ;;
        n) return 1 ;;
    esac
    return 2
}
n_default() {
    level=info
    case "$1" in
        -v) level=debug ;;
        -q) level=warn ;;
    esac
    echo "$level"
}
n_unread() {
    case "$1" in
        a) tmpx=1 ;;
        b) tmpx=2 ;;
    esac
}
n_dispatch() {
    case "$1" in
        start) do_start ;;
        stop) do_stop ;;
    esac
}
EOF
L="unhandled-arm"
fx_run uas
ua_row(){ ds_rows | grep 'defect="unhandled-arm"' | grep " sym=\"$1\"" | grep " p=\"$2:"; }   # SYM PATH
ua_has(){    # SYM PATH LINE WHY-SUBSTRING — one minor row, p= at the SITE's line, why= naming what is left out
    local row; row="$( ua_row "$1" "$2" )"
    if [ -z "$row" ]; then no "$L: no unhandled-arm row on $1 ($2)"; return 1; fi
    [ "$( printf '%s\n' "$row" | wc -l | tr -d ' ' )" = 1 ] || { no "$L: more than one unhandled-arm row on $1 ($2): $row"; return 1; }
    ds_judge "$L: $1 ($2)" "$row" minor
    if printf '%s' "$row" | grep -q " p=\"$2:$3\""; then ok "$L: $1 p=$2:$3 (the site's line)"; else no "$L: $1 p= should be the site $2:$3: $row"; fi
    if printf '%s' "$row" | grep -qF " why=\"$4"; then ok "$L: $1 why=$4…"; else no "$L: $1 why= should start '$4': $row"; fi
    return 0
}
ua_none(){   # SYM PATH WHY
    [ "$QD_OK" = 1 ] || { no "$L: cannot read an absence on $1 off a failed run"; return; }
    local row; row="$( ua_row "$1" "$2" )"
    if [ -z "$row" ]; then ok "$L: no unhandled-arm row on $1 ($3)"; else no "$L: false positive on $1 ($3): $row"; fi
}
if [ "$QD_OK" = 1 ]; then
    ua_has p_missing a.cpp 3 'no default: Kind::Macro, Kind::Type not handled'
    ua_has p_assign a.cpp 4 'no default: BLUE not handled'
    ua_has p_full_alias a.cpp 5 'no default: BLUE not handled'
    ua_has p_typedef m.c 2 'no default: M_C not handled'
    ua_has p_literal t.py 9 'no else: returns None for a value other than &quot;a&quot;, &quot;b&quot;'
    ua_has p_enum t.py 14 'no else: returns None for Shade.DIM'
    ua_has p_match t.py 19 'no else: returns None for a value other than &quot;x&quot;, &quot;y&quot;, &quot;z&quot;'
    ua_has p_in t.py 25 'no else: returns None for a value other than &quot;a&quot;, &quot;b&quot;, &quot;c&quot;'
    ua_has p_ret tools/s.sh 3 'no *) arm: an unmatched &quot;$1&quot; returns 0 and prints nothing'
    ua_has p_echo tools/s.sh 9 'no *) arm: an unmatched &quot;$1&quot; returns 0'
    ua_has p_assign tools/s.sh 15 'no *) arm: an unmatched &quot;$1&quot; leaves mode unset'
    #   the twins: NEGATIVE [premise POSITIVE] — the positive's row above is what makes the negative's silence mean something
    seen=0; pairs=0
    for pair in "n_default:p_missing:a.cpp:a default: arm" "n_full:p_missing:a.cpp:every owed enumerator has an arm (kKindCount is a sentinel)" \
                "n_void:p_missing:a.cpp:a void dispatcher decides nothing" "n_comment:p_missing:a.cpp:a comment states the omission" \
                "n_named:p_missing:a.cpp:a comment names the omitted enumerators" "n_int:p_missing:a.cpp:an int switch is no closed set" \
                "n_cond:p_missing:a.cpp:an enum under #ifdef: its enumerators depend on the build" \
                "n_ifdef:p_missing:a.cpp:an #if inside the switch" "n_alias:p_full_alias:a.cpp:COLOR_DEFAULT is an alias, owed no arm" \
                "n_generated:p_missing:gen.cpp:generated code" \
                "n_else:p_literal:t.py:an else" "n_wild:p_match:t.py:case _" "n_trailing:p_literal:t.py:a trailing return" \
                "n_full_enum:p_enum:t.py:every member has an arm (GLOOM is an alias)" "n_none:p_literal:t.py:return None elsewhere states None" \
                "n_optional:p_literal:t.py:an Optional annotation" "n_void:p_literal:t.py:no arm returns a value" \
                "n_mixed:p_literal:t.py:two subjects: no closed set" "n_foreign:p_enum:t.py:an enum this file does not define" \
                "n_star:p_ret:tools/s.sh:a *) arm" "n_trailing:p_ret:tools/s.sh:a command after esac" \
                "n_default:p_assign:tools/s.sh:the name has a default before the case" "n_unread:p_assign:tools/s.sh:nothing reads the name" \
                "n_dispatch:p_echo:tools/s.sh:the arms run commands: no result"; do
        neg="${pair%%:*}"; rest="${pair#*:}"; pos="${rest%%:*}"; rest="${rest#*:}"; path="${rest%%:*}"; why="${rest#*:}"
        pairs=$(( pairs + 1 ))
        twin_path="$path"; [ "$path" = gen.cpp ] && twin_path=a.cpp   # the generated negative's twin is the hand-written a.cpp
        [ -n "$( ua_row "$pos" "$twin_path" )" ] && seen=$(( seen + 1 ))
        ua_none "$neg" "$path" "$why"
    done
    if [ "$seen" = "$pairs" ] && [ "$pairs" -gt 0 ]; then ok "$L: every negative's positive twin fired ($seen/$pairs): each silence is read off a shape the scanner sees"
    else no "$L: only $seen/$pairs negatives' positive twins fired — a silent negative proves nothing without its twin"; fi
    if ds_rows | grep 'defect="unhandled-arm"' | grep -q 'gating='; then no "$L: an unhandled-arm row gates: $( ds_rows | grep 'defect="unhandled-arm"' | grep 'gating=' | head -1 )"
    else ok "$L: no unhandled-arm row gates ($( ds_rows | grep -c 'defect="unhandled-arm"' ) rows)"; fi
fi
#   the legend: unhandled-arm and why= are defined on an answer that carries the row, and only there
ULEG="$( cd "$WORK/uas" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$ULEG" | grep -q 'unhandled-arm: a classifier over a closed set' && printf '%s' "$ULEG" | grep -q 'why= what is left without an outcome'; then ok "$L: the full legend defines unhandled-arm and why="
else no "$L: the full legend does not define unhandled-arm / why="; fi
UCLEG="$( cd "$WORK/uas" && "$BIN" . --quality-delta --no-cache --legend=compact 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$UCLEG" | grep -q "an unhandled-arm row's values with no outcome"; then ok "$L: the compact legend defines r why="; else no "$L: the compact legend does not define r why="; fi
FLEG="$( cd "$WORK/fmt_cpp" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$FLEG" | grep -q '<quality-delta ' && ! printf '%s' "$FLEG" | grep -q 'unhandled-arm: a classifier'; then ok "$L: an answer with no unhandled-arm row carries no unhandled-arm legend"
else no "$L: the unhandled-arm legend rides on an answer without the row (or the run failed)"; fi
UJ="$( cd "$WORK/uas" && "$BIN" . --quality-delta --no-cache --json 2>/dev/null )"; xrc=$?
if [ "$xrc" -le 2 ] && printf '%s' "$UJ" | grep -q '"defect":"unhandled-arm"' && printf '%s' "$UJ" | grep -q '"why":"no default: Kind::Macro, Kind::Type not handled"'; then ok "$L: --json rows carry defect=unhandled-arm and why"
else no "$L: --json rows do not carry the unhandled-arm facet and why"; fi
#   appending an enumerator: the header edit alone makes an untouched, once-complete switch incomplete — that switch gets the
#   row (its site text names the missing enumerator, so it is a new site); a twin switch with a default: does not
fx_init uaenum
printf 'enum class Tok { A, B };\n' >"$WORK/uaenum/t.h"
printf '#include "t.h"\nint full( Tok t ) { switch( t ) { case Tok::A: return 1; case Tok::B: return 2; } return 0; }\nint dflt( Tok t ) { switch( t ) { case Tok::A: return 1; default: return 2; } }\n' >"$WORK/uaenum/u.cpp"
fx_commit uaenum
printf 'enum class Tok { A, B, C };\n' >"$WORK/uaenum/t.h"
fx_run uaenum
if [ "$QD_OK" = 1 ]; then
    row="$( ds_rows | grep 'defect="unhandled-arm"' | grep ' sym="full"' )"
    if printf '%s' "$row" | grep -q 'why="no default: Tok::C not handled"' && printf '%s' "$row" | grep -q ' p="u.cpp:2"'; then ok "$L: an appended enumerator gives the untouched switch its row (p=u.cpp:2, why= Tok::C)"
    else no "$L: the switch the appended enumerator left incomplete has no row: ${row:-<none>}"; fi
    if [ -n "$row" ] && [ -z "$( ds_rows | grep 'defect="unhandled-arm"' | grep ' sym="dflt"' )" ]; then ok "$L: its twin with a default: has none"; else no "$L: dflt (default:) has a row, or its premise did not fire"; fi
fi
#   recall replay, reversed: a fix that added the arm / else / *), read backwards (FIX..FIX^), takes it away again
fx_init uafix
printf 'enum class E { X, Y, Z };\n' >"$WORK/uafix/e.h"
printf '#include "e.h"\nint cls( E e ) { switch( e ) { case E::X: return 1; case E::Y: return 2; case E::Z: return 3; } return 0; }\n' >"$WORK/uafix/c.cpp"
printf 'def cls(k):\n    if k == "x":\n        return 1\n    elif k == "y":\n        return 2\n    else:\n        raise ValueError(k)\n' >"$WORK/uafix/c.py"
printf 'cls() {\n    case "$1" in\n        x) return 0 ;;\n        y) return 1 ;;\n        *) return 2 ;;\n    esac\n}\n' >"$WORK/uafix/c.sh"
fx_commit uafix
( cd "$WORK/uafix" && printf '#include "e.h"\nint cls( E e ) { switch( e ) { case E::X: return 1; case E::Y: return 2; } return 0; }\n' >c.cpp \
  && printf 'def cls(k):\n    if k == "x":\n        return 1\n    elif k == "y":\n        return 2\n' >c.py \
  && printf 'cls() {\n    case "$1" in\n        x) return 0 ;;\n        y) return 1 ;;\n    esac\n}\n' >c.sh && git add -A >/dev/null 2>&1 && git commit -qm "drop the arms" >/dev/null 2>&1 ) || no "$L: the recall fixture's second commit failed"
fx_run_ref uafix HEAD^..HEAD
if [ "$QD_OK" = 1 ]; then
    n="$( ds_rows | grep 'defect="unhandled-arm"' | grep -c ' sym="cls"' )"
    if [ "$n" = 3 ]; then ok "$L: the range that dropped the three arms prints three rows (C++, Python, shell)"; else no "$L: the range that dropped the arms printed $n unhandled-arm rows, want 3"; fi
fi
fx_run_ref uafix HEAD..HEAD^
if [ "$QD_OK" = 1 ]; then
    n="$( ds_rows | grep -c 'defect="unhandled-arm"' )"
    if [ "$n" = 0 ]; then ok "$L: the fixing direction prints no unhandled-arm row"; else no "$L: the fixing direction printed $n unhandled-arm rows"; fi
fi

# ── 5) SURFACES: legend, help, MCP, skill and docs; JSON twin; MCP; the ack identity of a facet ───────────
#   D2: format-arity is the one exception to "new-symbol rows never gate", and every surface that states the
#   rule states the exception in ONE fixed phrase (PHRASE below), so no surface still reads unqualified.
L="surfaces"
PHRASE='new-symbol rows never gate, except defect-shape format-arity'
#   QD-ENTRY-CEILING (2026-11-13) adds the second exception, a NEW function at 4x the bar, and TANGLE-GATE-B (2026-11-21)
#   the third, a new function at tangle 6 or more: every statement of the rule names both, in the long form (legend,
#   help, MCP, docs) or the compact legend's ceiling= row and tangle row.
CEILX='(, a new function at the ceiling[^.;]* (and a tangled new (function|one)|and a new one at tangle 6 or more)|, a ceiling= row or a tangle row)'
phrase_ok(){  # LABEL TEXT — the text states the exception, and every "new-symbol rows never gate" in it carries it
    local all qual flat   # whitespace-normalized first: a sentence may wrap anywhere in a document
    flat="$( printf '%s' "$2" | tr '\n' ' ' | tr -s ' ' )"
    all="$( printf '%s' "$flat" | grep -o 'new-symbol rows never gate' | wc -l | tr -d ' ' )"
    qual="$( printf '%s' "$flat" | grep -oE "$PHRASE$CEILX" | wc -l | tr -d ' ' )"
    if [ "$qual" -ge 1 ] && [ "$all" = "$qual" ]; then ok "$1: states '$PHRASE' + the ceiling exception ($qual), no unqualified 'new-symbol rows never gate'"
    else no "$1: '$PHRASE' + the ceiling exception x$qual, 'new-symbol rows never gate' x$all — an exception is missing or a sentence still reads unqualified"; fi
}
LEG="$( cd "$WORK/fmt_cpp" && "$BIN" . --quality-delta --no-cache --legend=full 2>/dev/null )"
if printf '%s' "$LEG" | grep -q '<quality-delta '; then
    miss=""
    for w in defect-shape format-arity utf8-cut dedup-first vacuous-assert 'defect='; do
        printf '%s' "$LEG" | grep -q -- "$w" || miss="$miss $w"
    done
    if [ -z "$miss" ]; then ok "$L: the full legend names defect-shape, its four facets and the defect= facet attribute"; else no "$L: the full legend does not name:$miss"; fi
    if printf '%s' "$LEG" | grep -q 'ELEVEN KINDS'; then no "$L: the legend still says ELEVEN KINDS (stale count)"; else ok "$L: the legend's kind count is not the stale ELEVEN"; fi
    phrase_ok "$L full legend" "$LEG"
    EX="$( printf '%s' "$LEG" | grep -o 'EXIT 2 fires only on[^.]*' )"
    if [ -n "$EX" ] && ! printf '%s\n' "$EX" | grep -vq 'format-arity'; then ok "$L: every 'EXIT 2 fires only on' sentence names the format-arity exception"
    else no "$L: an 'EXIT 2 fires only on' sentence omits format-arity (or none found): ${EX:-<none>}"; fi
    if printf '%s' "$LEG" | grep -q 'report-only by facet, not by size'; then ok "$L: the legend says the report-only facets are sev=minor by facet, not by size (D3)"
    else no "$L: the legend does not say 'report-only by facet, not by size' — sev=minor is otherwise defined as a small numeric delta"; fi
    if printf '%s' "$LEG" | grep -q 'f-strings are not checked'; then ok "$L: the legend names the Python formats it does not check"
    else no "$L: the legend does not say '%-formatting and f-strings are not checked' (no row is not a verdict on them)"; fi
else
    no "$L: the --legend=full delta run produced no <quality-delta root"
fi
CLEG="$( cd "$WORK/fmt_cpp" && "$BIN" . --quality-delta --no-cache --legend=compact 2>/dev/null )"
if printf '%s' "$CLEG" | grep -q '<quality-delta '; then
    phrase_ok "$L compact legend" "$CLEG"
    if printf '%s' "$CLEG" | grep -q -e 'NEW code; never gate' -e 'NEW code, never gating'; then no "$L: the compact legend still says new-symbol rows never gate, unqualified"
    else ok "$L: the compact legend has no unqualified new-symbol never-gate entry"; fi
else
    no "$L: the --legend=compact delta run produced no <quality-delta root"
fi
#   --help prints each flag's first line (the kind count); --help=quality-delta prints the flag's whole text.
HELP="$( "$BIN" --help 2>&1 )"; HRC=$?
if [ "$HRC" = 0 ] && printf '%s' "$HELP" | grep -q -- '--quality-delta'; then
    if printf '%s' "$HELP" | grep -qE '(across )?11[ -]kind'; then no "$L: --help still says 11 kinds: $( printf '%s' "$HELP" | grep -E '11[ -]kind' | head -2 )"; else ok "$L: --help no longer says 11 kinds"; fi
else
    no "$L: --help failed (rc=$HRC) or does not list --quality-delta"
fi
HELPQ="$( "$BIN" --help=quality-delta 2>&1 )"; HQRC=$?
if [ "$HQRC" = 0 ] && printf '%s' "$HELPQ" | grep -q -- '--quality-delta'; then
    if printf '%s' "$HELPQ" | grep -q 'defect-shape'; then ok "$L: --help=quality-delta names defect-shape"; else no "$L: --help=quality-delta does not name defect-shape"; fi
    phrase_ok "$L --help=quality-delta" "$HELPQ"
else
    no "$L: --help=quality-delta failed (rc=$HQRC) or does not print the flag"
fi
if command -v python3 >/dev/null 2>&1; then
    TL="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 )"
    QDD="$( printf '%s' "$TL" | python3 -c '
import json, sys
try: r = json.load(sys.stdin)
except Exception as e: print("BROKEN %s" % e); raise SystemExit
d = [t.get("description", "") for t in r.get("result", {}).get("tools", []) if t.get("name") == "quality_delta"]
print(d[0] if d else "MISSING")' )"
    case "$QDD" in
        BROKEN*|MISSING) no "$L: MCP tools/list has no quality_delta description: $QDD" ;;
        *)  if printf '%s' "$QDD" | grep -q '11 measured failure modes'; then no "$L: the MCP quality_delta description still says '11 measured failure modes'"
            else ok "$L: the MCP quality_delta description has no stale kind count"; fi
            if printf '%s' "$QDD" | grep -q 'defect-shape'; then ok "$L: the MCP quality_delta description names defect-shape"; else no "$L: the MCP quality_delta description does not name defect-shape"; fi
            phrase_ok "$L MCP description" "$QDD" ;;
    esac
else
    echo "  SKIP  $L: MCP tools/list description (python3 not installed)"
fi
#   docs/COMMANDS.md is generated from --help plus a DATED showcase capture: its ``` sample blocks are the recorded
#   output of the binary that made the capture and change only when the capture is re-recorded (a train step),
#   so the arms read the generated prose and skip the sample blocks.
SKILL="$ROOT/skills/ripwire-quality-bar/SKILL.md"
for doc in "$SKILL" "$ROOT/docs/COMMANDS.md" "$ROOT/README.md"; do
    rel="${doc#"$ROOT"/}"
    if [ ! -f "$doc" ]; then no "$L: $rel is missing"; continue; fi
    if [ "$rel" = docs/COMMANDS.md ]; then DTEXT="$( awk '/^```/ { f = !f; next } !f' "$doc" )"; else DTEXT="$( cat "$doc" )"; fi
    if [ -z "$DTEXT" ]; then no "$L: $rel read empty"; continue; fi
    if printf '%s' "$DTEXT" | grep -qiE '(^|[^0-9])11 kinds|eleven kinds|eleven quality kinds|ELEVEN KINDS'; then
        no "$L: $rel still says 11/eleven kinds: $( printf '%s' "$DTEXT" | grep -iE '(^|[^0-9])11 kinds|eleven kinds|eleven quality kinds' | head -2 | cut -c1-160 )"
    else ok "$L: $rel has no stale 11/eleven-kinds count"; fi
    phrase_ok "$L $rel" "$DTEXT"
done
if [ -f "$SKILL" ]; then
    FM="$( awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$SKILL" )"
    if printf '%s' "$FM" | tr '\n' ' ' | tr -s ' ' | grep -q "$PHRASE"; then ok "$L: the quality-bar skill's trigger text states the format-arity exception"
    else no "$L: the quality-bar skill's trigger text (frontmatter description) does not state '$PHRASE'"; fi
fi
if command -v python3 >/dev/null 2>&1; then
    #   D2 at every exit-predicate site: the new-symbol freshbad row carries "gating": true, and the top-level
    #   "gating" equals the rows that carry it (the same predicate as the XML gating= and the exit code).
    JPROBE='
import json, sys
try:
    raw = sys.stdin.read()
    d = json.loads(raw)
    if "result" in d: d = json.loads(d["result"]["content"][0]["text"])
except Exception as e: print("BROKEN %s" % e); raise SystemExit
rs = d.get("r", [])
rows = [r for r in rs if r.get("kind") == "defect-shape" and r.get("defect") == "format-arity"]
fresh = [r for r in rows if r.get("sym") == "freshbad"]
ng = sum(1 for r in rs if r.get("gating") is True)
print("ROWS %d FRESH %d FRESHGATE %d TOP %s NG %d" % (len(rows), len(fresh), sum(1 for r in fresh if r.get("gating") is True), d.get("gating"), ng))'
    JS="$( cd "$WORK/fmt_cpp" && "$BIN" . --quality-delta --no-cache --json 2>/dev/null )"
    MC="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$WORK/fmt_cpp"'"}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 )"
    for surf in json mcp; do
        if [ "$surf" = json ]; then V="$( printf '%s' "$JS" | python3 -c "$JPROBE" )"; else V="$( printf '%s' "$MC" | python3 -c "$JPROBE" )"; fi
        set -- $V
        if [ "${1:-}" != ROWS ]; then no "$L $surf: probe: $V"; continue; fi
        n="$2"; fr="$4"; frg="$6"; top="$8"; ng="${10}"
        case "$n$fr$frg$ng" in *[!0-9]*) no "$L $surf: probe printed non-numbers: $V"; continue ;; esac
        if [ "$n" -ge 14 ]; then ok "$L $surf: carries the $n format-arity rows (kind + defect keys)"; else no "$L $surf: carries $n format-arity rows, want >= 14"; fi
        if [ "$fr" = 1 ] && [ "$frg" = 1 ]; then ok "$L $surf: the new-symbol freshbad format-arity row carries \"gating\": true"
        else no "$L $surf: freshbad rows=$fr gating=$frg (want 1 and 1)"; fi
        if [ "$top" = "$ng" ]; then ok "$L $surf: top-level \"gating\" ($top) equals the rows that carry \"gating\": true"
        else no "$L $surf: top-level \"gating\" is $top but $ng rows carry \"gating\": true"; fi
    done
else
    echo "  SKIP  $L: --json and MCP row checks (python3 not installed)"
fi

#   Ack identity (checklist 16): one symbol with BOTH a format-arity and a utf8-cut row. Acking only the
#   format-arity facet must leave the utf8-cut row on the same symbol standing — a facet is part of the
#   finding's identity, not a label on one shared per-symbol key. --ack-only=defect-shape (the kind) takes
#   both facets; each on a fresh copy.
fx_init both
mkdir -p "$WORK/both/src"
cat >"$WORK/both/src/b.cpp" <<'EOF'
#include <format>
#include <string>
std::string label( std::string s, int a ) { return std::format( "{}", a ) + s; }
int drive() { return 0; }
EOF
fx_commit both
cat >"$WORK/both/src/b.cpp" <<'EOF'
#include <format>
#include <string>
std::string label( std::string s, int a )
{
    if( s.size() > 50 )
    {
        s.resize( 50 );
        s += "...";
    }
    return std::format( "{}", a, a ) + s;
}
int drive() { return 1; }
EOF
fx_run both
ds_has "$L ack" format-arity label gating
ds_has "$L ack" utf8-cut     label minor
fx_copy both both_kind
( cd "$WORK/both" && "$BIN" . --quality-delta --no-cache --ack-only=format-arity --quality-ack="deliberate in this fixture" >/dev/null 2>&1 )
ARC=$?
if [ "$ARC" = 0 ]; then ok "$L ack: --ack-only=format-arity selects the facet (exit 0)"; else no "$L ack: --ack-only=format-arity exited $ARC"; fi
fx_run both
if [ "$QD_OK" = 1 ]; then
    if [ -z "$( ds_row format-arity label )" ]; then ok "$L ack: the acked format-arity row is suppressed"; else no "$L ack: the format-arity row survived its ack: $( ds_row format-arity label )"; fi
    if [ -z "$( ds_rows | grep 'gating=' )" ]; then ok "$L ack: no defect-shape row carries gating= after the ack"; else no "$L ack: a defect-shape row still gates: $( ds_rows | grep 'gating=' | head -2 )"; fi
fi
ds_has "$L ack" utf8-cut label minor
gating_split "$L ack" 0
( cd "$WORK/both_kind" && "$BIN" . --quality-delta --no-cache --ack-only=defect-shape --quality-ack="deliberate in this fixture" >/dev/null 2>&1 )
ARC=$?
if [ "$ARC" = 0 ]; then ok "$L ack kind: --ack-only=defect-shape selects the kind (exit 0)"; else no "$L ack kind: --ack-only=defect-shape exited $ARC"; fi
fx_run both_kind
if [ "$QD_OK" = 1 ]; then
    left="$( ds_rows | wc -l | tr -d ' ' )"
    if [ "$left" = 0 ]; then ok "$L ack kind: both facets are suppressed by the kind token"; else no "$L ack kind: $left defect-shape rows survived --ack-only=defect-shape: $( ds_rows | head -2 )"; fi
fi
gating_split "$L ack kind" 0

#   Ack identity, the next layer (checklist 16; rv-cr-qd-kinds-068 §3, fixture p2/ack): the ack key is the anchor,
#   the facet AND the anchor's site set of that facet, so an ack covers exactly the defect it named. (a) swap: defect
#   A is acked and committed with the ledger, then A is fixed and a DIFFERENT defect B lands in the same function →
#   B's row stands and gates, and A's ack is listed stale (finding-gone). (b) beside: A is acked, then B is added
#   NEXT to the untouched A → the row re-reports (now=2). (c) unchanged: A acked and left alone stays suppressed,
#   and its ack is not stale.
L="ack swap"
fx_init swap
cat >"$WORK/swap/a.cpp" <<'EOF'
#include <format>
#include <string>
std::string legend( int a, int b, int c )
{
    std::string s = std::format( "a={} b={}", a, b );
    return s + std::format( "c={}", c );
}
EOF
fx_commit swap
sed -i.bak 's|"a={} b={}", a, b )|"a={} b={}", a, b, c )|' "$WORK/swap/a.cpp" && rm -f "$WORK/swap/a.cpp.bak"
fx_run swap
ds_has "$L premise" format-arity legend gating
( cd "$WORK/swap" && "$BIN" . --quality-delta --no-cache --ack-only=format-arity --quality-ack="defect A, accepted for this fixture" >/dev/null 2>&1 )
ARC=$?
if [ "$ARC" = 0 ]; then ok "$L: --ack-only=format-arity acked defect A (exit 0)"; else no "$L: --ack-only=format-arity exited $ARC"; fi
fx_copy swap swap_beside
fx_run swap
if [ "$QD_OK" = 1 ]; then
    if [ -z "$( ds_row format-arity legend )" ]; then ok "$L unchanged: the acked, unchanged defect A stays suppressed"; else no "$L unchanged: acked A re-reported: $( ds_row format-arity legend )"; fi
    st="$( hdr_attr stale )"
    if [ "$st" = 0 ]; then ok "$L unchanged: the ack of A is not stale while A stands"; else no "$L unchanged: stale=${st:-<none>} while the acked A stands"; fi
fi
( cd "$WORK/swap" && git add -A >/dev/null 2>&1 && git commit -qm "defect A + its ack" >/dev/null 2>&1 ) || no "$L: committing A and its ack failed"
cat >"$WORK/swap/a.cpp" <<'EOF'
#include <format>
#include <string>
std::string legend( int a, int b, int c )
{
    std::string s = std::format( "a={} b={}", a, b );
    return s + std::format( "c={}", c, a );
}
EOF
fx_run swap
ds_has "$L swapped" format-arity legend gating
if [ "$QD_OK" = 1 ]; then
    if printf '%s' "$QD_OUT" | tr '>' '\n' | grep '<sa ' | grep 'kind="defect-shape"' | grep -q 'why="finding-gone"'; then ok "$L swapped: the ack of the fixed A is listed stale (finding-gone)"
    else no "$L swapped: no finding-gone sa row for the ack of the fixed A"; fi
    if [ "$( hdr_attr acked )" = 0 ]; then ok "$L swapped: nothing is acked (A's ack does not cover B)"; else no "$L swapped: acked=$( hdr_attr acked ) — A's ack covered B"; fi
fi
sed -i.bak 's|"c={}", c )|"c={}", c, a )|' "$WORK/swap_beside/a.cpp" && rm -f "$WORK/swap_beside/a.cpp.bak"
fx_run swap_beside
ds_has "$L beside" format-arity legend gating
ds_wasnow "$L beside" format-arity legend 0 2

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
