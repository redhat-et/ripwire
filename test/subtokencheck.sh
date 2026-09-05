#!/usr/bin/env bash
# subtokencheck.sh — the shared subtoken tokenizer must not shred an ALL-CAPS run into nothing.
#
# THE DEFECT THIS PINS (found 2026-08-19, registered in docs/EVALS.md §4). Three mirrors of one state
# machine treated every interior uppercase byte as a token boundary, so an all-caps run came out as
# 1-byte fragments and the >=2-byte rule then dropped them all:
#
#   subtokens( "MCP" )        -> []            (not [mcp])
#   subtokens( "MCPServer" )  -> [server]      (not [mcp, server])
#   subtokens( "HTTPServer" ) -> [server]      (not [http, server])
#   subtokens( "PR" )         -> []            (not [pr])
#
# lexical.h::subtokens() tested its camel boundary against the ALREADY-LOWERCASED accumulator, so its
# "previous byte was uppercase" guard could never be true; lexindex.h::forEachLexSubtoken() and
# ::forEachLexSubtokenHashed() said it in the open ("an interior uppercase char always starts a NEW
# token"). Consequence in production: ripwire-mcp's SKILL.md description is about MCP end to end and
# contributed ZERO `mcp` tokens to the routing index.
#
# The registered rule (docs/EVALS.md §4, "Subtoken acronym shredding"): an uppercase RUN stays one
# token, except that the LAST uppercase of a run of >=2 immediately followed by a lowercase letter
# starts the next token (the ACRONYMWord rule that naminglens.h::splitIdentifier already implements).
#
# Four arms, because the function being right is not the same claim as the shipped path using it:
#   (A) unit — drive rw::subtokens() directly over a table that covers all five required shapes: a
#       pure acronym, acronym+word, mixed camel, snake_case, and a digit-adjacent run.
#   (B) unit, MIRROR EQUIVALENCE — lexindex.h's forEachLexSubtoken() (the corpus-side walker BM25
#       actually scans with) must yield exactly the token list subtokens() yields, over every case in
#       the table. This is the arm that stops the three copies drifting apart again.
#   (C) unit, HASH PARITY — forEachLexSubtokenHashed()'s fused rolling hash must equal
#       lexSubtokenHash() of the token's lowercased bytes. A token may now carry INTERIOR uppercase,
#       which is exactly the input that used to normalize differently on the two paths; if this arm
#       is red, the persisted postings path and the query-time scan disagree.
#   (D) CLI — test/subtokfix/ spells "mcp" and "http" NOWHERE in lowercase, so `--for=MCP` and
#       `--for=http` can only be answered through the acronym rule. Both must lose the weak="1"
#       honesty flag and rank the right FILE first. A control query over ordinary camelCase
#       vocabulary must land on the control file, which proves this arm is not inert (it is green on
#       both binaries by construction).
#
# Usage:  test/subtokencheck.sh   [ RIPWIRE_BIN=path/to/ripwire ]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="test/subtokfix"                                  # kept REPO-RELATIVE: the p= attributes the CLI
cd "$ROOT" || exit 2                                  # arm compares against are relative to the cwd
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "subtokencheck: BIN=$BIN  FIX=$FIX"

# ── fixture presence guard: the CLI arm searches for words the fixture must NOT already spell ───────
# "green while inert" is the failure this guards, in both directions. If the capitalised acronyms ever
# leave the fixture there is nothing to find; if a lowercase spelling ever ENTERS it, arm (D) would be
# answered by the ordinary tokenizer and would stop testing the acronym rule at all.
if ! grep -rq 'MCP' "$FIX" || ! grep -rq 'HTTP' "$FIX"; then
    no "fixture sanity: MCP/HTTP are gone from $FIX — arm (D) has nothing to find"
elif grep -rq -e 'mcp' -e 'http' "$FIX"; then
    no "fixture sanity: $FIX spells 'mcp'/'http' in lower case somewhere — arm (D) is inert"
    grep -rn -e 'mcp' -e 'http' "$FIX" | head -4
else
    ok "fixture sanity: $FIX spells MCP/HTTP in capitals only (the CLI arm can only pass through the acronym rule)"
fi

# ── (A)(B)(C) the unit TU ────────────────────────────────────────────────────────────────────────────
CXX="${CXX:-c++}"
# §CI-P3: ask THIS front end how it spells C++23 rather than assuming the Clang-17 spelling.
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
command -v "$CXX" >/dev/null 2>&1 || CXX=g++
if ! command -v "$CXX" >/dev/null 2>&1; then
    no "no C++ compiler found (CXX=$CXX) — the unit arms cannot run"
else
    UTU="$TMP/subtok.cpp"
    cat > "$UTU" <<'EOF'
#include "lexical.h"
#include "lexindex.h"
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

// the registered table. Every row is (input, expected tokens joined by '|'), and the five shapes the
// round's registration requires are all present and labelled.
struct Row { const char* in; const char* want; const char* shape; };
static const Row kRows[] = {
    // pure acronym — the headline defect: these produced NOTHING at all
    { "MCP",                             "mcp",                                  "pure acronym"        },
    { "PR",                              "pr",                                   "pure acronym"        },
    { "CI",                              "ci",                                   "pure acronym"        },
    { "MCP end to end",                  "mcp|end|to|end",                       "acronym in prose"    },
    // acronym + word — the ACRONYMWord rule: last upper of a >=2 run before a lowercase splits
    { "MCPServer",                       "mcp|server",                           "acronym+word"        },
    { "HTTPServer",                      "http|server",                          "acronym+word"        },
    { "HTTPServerBinder",                "http|server|binder",                   "acronym+word"        },
    { "IOError",                         "io|error",                             "acronym+word"        },
    { "XMLHttpRequest",                  "xml|http|request",                     "acronym+word"        },
    // mixed camel — unchanged behaviour, pinned so the fix cannot pay for acronyms with camelCase
    { "updateCollisionPositionVelocity", "update|collision|position|velocity",   "mixed camel"         },
    { "negotiateSession",                "negotiate|session",                    "mixed camel"         },
    { "aB",                              "",                                     "mixed camel (<2B)"   },
    // snake_case — unchanged
    { "_max_speed",                      "max|speed",                            "snake_case"          },
    { "bind_listen_socket",              "bind|listen|socket",                   "snake_case"          },
    { ".mcp.json",                       "mcp|json",                             "snake_case/separator"},
    // digit-adjacent — digits stay token-INTERIOR and never open a boundary
    { "utf8Encode",                      "utf8|encode",                          "digit-adjacent"      },
    { "sha256sum",                       "sha256sum",                            "digit-adjacent"      },
    { "MCP2Server",                      "mcp2|server",                          "digit-adjacent"      },
    { "sha256Digest",                    "sha256|digest",                        "digit-adjacent"      },
};

static std::string join( const std::vector<std::string>& toks )
{
    std::string out;
    for( std::size_t i = 0; i < toks.size(); ++i )
    {
        if( i != 0 ) { out.push_back( '|' ); }
        out += toks[i];
    }
    return out;
}

int main()
{
    int bad = 0;

    // (A) subtokens() itself
    for( const Row& r : kRows )
    {
        std::vector<std::string> got;
        rw::subtokens( r.in, got );
        const std::string joined = join( got );
        if( joined != r.want )
        {
            std::printf( "A-MISMATCH [%s] %-32s got=\"%s\" want=\"%s\"\n", r.shape, r.in, joined.c_str(), r.want );
            ++bad;
        }
    }

    // (B) the corpus-side walker must produce the SAME tokens (lowercased, >=2 bytes dropped)
    for( const Row& r : kRows )
    {
        const std::string_view       text( r.in );
        std::vector<std::string> got;
        rw::forEachLexSubtoken( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
        {
            if( tokEndByte - tokStartByte < 2 ) { return; }
            std::string tok;
            for( std::size_t k = tokStartByte; k < tokEndByte; ++k )
            {
                const unsigned char c = static_cast<unsigned char>( text[k] );
                tok.push_back( char( ( c >= 'A' && c <= 'Z' ) ? c - 'A' + 'a' : c ) );
            }
            got.push_back( tok );
        } );
        const std::string joined = join( got );
        if( joined != r.want )
        {
            std::printf( "B-MIRROR-DRIFT [%s] %-32s forEachLexSubtoken=\"%s\" want=\"%s\"\n", r.shape, r.in, joined.c_str(), r.want );
            ++bad;
        }
    }

    // (C) the fused rolling hash must equal lexSubtokenHash() of the token's lowercased bytes
    for( const Row& r : kRows )
    {
        const std::string_view text( r.in );
        rw::forEachLexSubtokenHashed( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte, std::uint64_t rolled )
        {
            std::string tok;
            for( std::size_t k = tokStartByte; k < tokEndByte; ++k )
            {
                const unsigned char c = static_cast<unsigned char>( text[k] );
                tok.push_back( char( ( c >= 'A' && c <= 'Z' ) ? c - 'A' + 'a' : c ) );
            }
            const std::uint64_t reference = rw::lexSubtokenHash( tok.data(), tok.size() );
            if( reference != rolled )
            {
                std::printf( "C-HASH-DRIFT %-32s tok=\"%s\" rolled=%llu lexSubtokenHash=%llu\n",
                             r.in, tok.c_str(), static_cast<unsigned long long>( rolled ),
                             static_cast<unsigned long long>( reference ) );
                ++bad;
            }
        } );
    }

    if( bad == 0 ) { std::puts( "UNIT_OK" ); return 0; }
    std::printf( "UNIT_FAIL %d\n", bad );
    return 1;
}
EOF
    if "$CXX" "$CXXSTD" -I "$ROOT/src" -I "$ROOT/src/infra" -I "$ROOT/third_party" "$UTU" -o "$TMP/subtok" 2>"$TMP/subtok.err"; then
        "$TMP/subtok" >"$TMP/subtok.out" 2>&1; rc_u=$?
        if [ $rc_u -eq 0 ] && grep -q UNIT_OK "$TMP/subtok.out"; then
            ok "unit (A) subtokens() splits all five shapes per the registered rule"
            ok "unit (B) forEachLexSubtoken() mirrors subtokens() token-for-token"
            ok "unit (C) forEachLexSubtokenHashed() agrees with lexSubtokenHash() on every token"
        else
            grep -q '^A-MISMATCH'      "$TMP/subtok.out" && no "unit (A) subtokens() disagrees with the registered rule" || ok "unit (A) subtokens() splits all five shapes per the registered rule"
            grep -q '^B-MIRROR-DRIFT'  "$TMP/subtok.out" && no "unit (B) forEachLexSubtoken() has drifted from subtokens()" || ok "unit (B) forEachLexSubtoken() mirrors subtokens() token-for-token"
            grep -q '^C-HASH-DRIFT'    "$TMP/subtok.out" && no "unit (C) the fused rolling hash disagrees with lexSubtokenHash()" || ok "unit (C) forEachLexSubtokenHashed() agrees with lexSubtokenHash() on every token"
            sed -n '1,24p' "$TMP/subtok.out"
        fi
    else
        no "unit TU failed to compile"
        sed -n '1,20p' "$TMP/subtok.err"
    fi
fi

# ── (D) the CLI arm: the shipped --for path must reach an acronym-only word ──────────────────────────
# topFile prints the p= of the FIRST <d> row of the bundle — --for emits rows in rank order (RE-PINNED
# P7 (terminality round A, lane R, 2026-09-05): the lens <sigs> is FLAT — <d … p="FILE" … r=N> rows in rank order, no <f p=> wrapper (test/forrankordercheck.sh)) — REJOINED with
# the bundle's root=, so what this arm compares is the repo-relative path it names below.
#
# The rejoin is a MERGE-TIME correction, recorded rather than quietly applied (2026-08-19, integrating
# this branch into integration/wave2-2026-08-17). This gate was authored against a binary whose --for
# emitted the raw ingest path (`p="test/subtokfix/session.cpp"`); the wave's root-relative-paths lane
# made `--for` emit `root="test/subtokfix"` with `p="session.cpp"`. Neither side touched the other's
# file, so git saw no conflict and the arm went red at the merged head against a spelling, while all
# three probes still ranked exactly the files named below. Comparing root+p instead of p keeps the
# assertion the one the header claims — "the top-ranked FILE is test/subtokfix/session.cpp" — and makes
# it independent of which of the two path shapes the binary emits, so it cannot go red on this again.
topFile(){ python3 -c "
import os, re, sys
s = open(sys.argv[1]).read()
m = re.search(r'<d [^>]*?\bp=\"([^\"]+)\"', s)
if not m:
    print('(none)')
    raise SystemExit
p = m.group(1)
r = re.search(r'<ctx [^>]*?root=\"([^\"]*)\"', s)
root = r.group(1).rstrip('/') if r else ''
print(os.path.join(root, p) if root and root != '.' and not p.startswith(root + '/') else p)
" "$1"; }
isWeak(){ grep -q 'weak=\"1\"' "$1"; }

for probe in "MCP:test/subtokfix/session.cpp:the pure acronym" "http:test/subtokfix/binder.cpp:the ACRONYMWord split"; do
    q="${probe%%:*}"; rest="${probe#*:}"; want="${rest%%:*}"; label="${rest#*:}"
    OUT="$TMP/for_$q.xml"
    "$BIN" "$FIX" --for="$q" --no-cache >"$OUT" 2>/dev/null
    if isWeak "$OUT"; then
        no "--for=$q ($label): bundle is weak=\"1\" — the query found NO lexical grounding, i.e. the acronym is unindexed"
    else
        ok "--for=$q ($label): bundle is not weak — the acronym carries real lexical evidence"
    fi
    got="$( topFile "$OUT" )"
    [ "$got" = "$want" ] \
        && ok "--for=$q ($label): top-ranked file is $want" \
        || no "--for=$q ($label): top-ranked file is $got, want $want"
done

# control: ordinary camelCase vocabulary must route to the control file on ANY binary — the presence
# guard that proves the two probes above are measuring the tokenizer and not a broken fixture.
OUT="$TMP/for_ctl.xml"
"$BIN" "$FIX" --for="serialize payload into the caller buffer" --no-cache >"$OUT" 2>/dev/null
if ! isWeak "$OUT" && [ "$( topFile "$OUT" )" = "test/subtokfix/payload.cpp" ]; then
    ok "control: ordinary camelCase query still ranks test/subtokfix/payload.cpp first (this arm is not inert)"
else
    no "control: the camelCase query no longer reaches payload.cpp — the fixture or the ranker moved, not the tokenizer"
fi

[ $fail -eq 0 ] && echo "subtokencheck: ALL PASS" || echo "subtokencheck: FAILURES"
exit $fail
