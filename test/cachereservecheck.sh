#!/usr/bin/env bash
# cachereservecheck.sh — gate for P1-11 (2026-09-10 full audit): THE WARM CACHE PATH MUST NOT REALLOCATE
# ITS ACCUMULATORS, and the claim must be executable rather than read off a profile.
#
# WHAT THE AUDIT SAW. Leaf-of-stack attribution on a WARM llvm `--grep` (8,484 busy samples) put
# `std::vector<RawRef>::push_back` at 12.55%, `RawDef` at 5.14%, `RawBind` at 4.00% and the `_platform_memmove`
# those reallocations force at 8.38% — ~30% of the run — and attributed them to `loadCache`'s deserialize
# plus `rw::ingest`'s merge, concluding the fix was "reserve() before the loops".
#
# WHAT READING THE CODE FOUND. Two of the three suspects already reserve EXACTLY:
#   - `readFileRecord` (ingest_cache.h) reserves every one of a file's eight families from the record's own
#     count before its loop, and has since the count-validation work;
#   - `mergeThreadFacts` (ingest_parsepool.h) reserves each family's exact cross-thread total.
# The one accumulator that could still grow is the PER-THREAD WARM-HIT accumulator that `appendCacheHitFacts`
# feeds — and it reserved only FOUR of the eight families (defs/refs/incs/binds). ffis, routeDefs, routeUses
# and constOpens doubled up from zero on every warm run. The cold path skips those four deliberately
# (`coldParseReserve` only has a bytes-based ESTIMATE and says so), but the warm path is not estimating: the
# cached FileFacts carry the EXACT counts, so summing them is one more add in a loop that already runs and
# `reserve( 0 )` costs nothing when a family is empty.
#
# THE OBSERVABLE. `warm_growths=` on the RIPWIRE_CACHE_STATS line counts, once per family per file, an append
# that was about to cross capacity. Zero is the contract on a single-threaded warm run: with nfiles == 1 the
# pool runs one thread, so each family's per-thread reserve IS its exact total and nothing may reallocate.
# (A multi-threaded run can still show a small non-zero count — that is the lock-free work queue's own skew,
# a worker drawing more than its 1/nthreads share, not a missing reserve. Measured on golang/go, 11,003 files
# warm on 18 threads: 29-36. The gate does not assert on that number; the commit message records it.)
#
# Checks:
#   (A) a one-file RUBY fixture (module/class opens → constOpens; `require` → incs) reports warm_growths=0.
#   (B) a one-file JS fixture (imports + express routes + fetch → routeDefs/routeUses) reports warm_growths=0.
#   (C) a multi-file mixed fixture: the WARM map is byte-identical to the --no-cache map (a reserve must never
#       change an answer), and the stats line still carries the observable on the real multi-thread path.
#   (D) the observable is OFF by default — a warm run without RIPWIRE_CACHE_STATS writes ZERO stderr bytes.
#   (E) the warm map is deterministic (two runs cmp equal) and well-formed.
#
# RED-FIRST. Arms (A) and (B) fail against any binary that does not reserve all eight warm families: the
# pre-change binary emits no `warm_growths=` field at all (the assertion cannot find its zero), and a
# mutation that deletes just the four added reserves reports warm_growths=1 on (A) and (B).
#
# Usage:  test/cachereservecheck.sh   |   RIPWIRE_BIN=build/ripwire test/cachereservecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "cachereservecheck: BIN=$BIN"

# Each fixture gets its own private TMPDIR so the auto-cache under test is one blob we own end to end
# (and so a shared cache dir's eviction sweep can never perturb an arm).
warmgrowths(){   # $1 = repo dir, $2 = private cache base — prime, then re-run warm and echo warm_growths=N
    env -u XDG_CACHE_HOME TMPDIR="$2" "$BIN" "$1" >/dev/null 2>&1
    env -u XDG_CACHE_HOME TMPDIR="$2" RIPWIRE_CACHE_STATS=1 "$BIN" "$1" 2>&1 >/dev/null \
        | sed -n 's/.*\(warm_growths=[0-9]*\).*/\1/p' | head -1
}

# ── (A) one Ruby file: constOpens (module/class opens) + incs (require) ─────────────────────────────
A_REPO="$TMP/a/repo"; A_CB="$TMP/a/cb"; mkdir -p "$A_REPO" "$A_CB/ripwire"
cat > "$A_REPO/widget.rb" <<'RB'
require 'json'

module Outer
  class Widget
    def render( x )
      JSON.generate( x )
    end

    def to_s
      render( { name: 'w' } )
    end
  end
end
RB
ga="$( warmgrowths "$A_REPO" "$A_CB" )"
[ "$ga" = "warm_growths=0" ] && ok "(A) one-file Ruby fixture: $ga (constOpens/incs reserved exactly)" \
    || no "(A) one-file Ruby fixture reported '${ga:-<no warm_growths field>}' — expected warm_growths=0"

# ── (B) one JS file: imports, express route registrations, a client fetch ───────────────────────────
B_REPO="$TMP/b/repo"; B_CB="$TMP/b/cb"; mkdir -p "$B_REPO" "$B_CB/ripwire"
cat > "$B_REPO/server.js" <<'JS'
import express from 'express';
import { helper } from './helper.js';

const app = express();

app.get( '/widgets/:id', function getWidget( req, res ) { res.send( helper( req.params.id ) ); } );
app.post( '/widgets', function addWidget( req, res ) { res.send( 'ok' ); } );

async function pullWidget( id ) {
    return await fetch( '/api/widgets/' + id );
}
JS
gb="$( warmgrowths "$B_REPO" "$B_CB" )"
[ "$gb" = "warm_growths=0" ] && ok "(B) one-file JS fixture: $gb (routeDefs/routeUses/ffis reserved exactly)" \
    || no "(B) one-file JS fixture reported '${gb:-<no warm_growths field>}' — expected warm_growths=0"

# ── (C) multi-file, multi-language: a reserve must never change an answer ───────────────────────────
C_REPO="$TMP/c/repo"; C_CB="$TMP/c/cb"; mkdir -p "$C_REPO" "$C_CB/ripwire"
cp "$A_REPO/widget.rb" "$C_REPO/"
cp "$B_REPO/server.js" "$C_REPO/"
cat > "$C_REPO/core.cpp" <<'CPP'
#include <string>

namespace core
{
int widen( int x )
{
    return x * 2;
}

std::string label( int x )
{
    return std::to_string( widen( x ) );
}
}
CPP
cat > "$C_REPO/svc.py" <<'PY'
import json


def encode(payload):
    return json.dumps(payload)


def decode(blob):
    return json.loads(blob)
PY

env -u XDG_CACHE_HOME TMPDIR="$C_CB" "$BIN" "$C_REPO" --top-k=100000 >"$TMP/c_prime.xml" 2>/dev/null
env -u XDG_CACHE_HOME TMPDIR="$C_CB" "$BIN" "$C_REPO" --top-k=100000 >"$TMP/c_warm.xml" 2>"$TMP/c_warm.err"
"$BIN" "$C_REPO" --top-k=100000 --no-cache >"$TMP/c_cold.xml" 2>/dev/null
cmp -s "$TMP/c_warm.xml" "$TMP/c_cold.xml" \
    && ok "(C) the WARM map is byte-identical to the --no-cache map (the reserve changes no answer)" \
    || no "(C) warm and cold maps differ — the warm accumulator path changed an answer"

gc="$( env -u XDG_CACHE_HOME TMPDIR="$C_CB" RIPWIRE_CACHE_STATS=1 "$BIN" "$C_REPO" 2>&1 >/dev/null \
        | sed -n 's/.*\(warm_growths=[0-9]*\).*/\1/p' | head -1 )"
[ -n "$gc" ] && ok "(C) the observable survives the real multi-file path: $gc" \
    || no "(C) no warm_growths field on a multi-file warm run"

# ── (D) the observable is OFF by default ───────────────────────────────────────────────────────────
[ ! -s "$TMP/c_warm.err" ] && ok "(D) a warm run without RIPWIRE_CACHE_STATS writes ZERO stderr bytes" \
    || { no "(D) the warm run wrote to stderr with the stats env var unset"; cat "$TMP/c_warm.err"; }

# ── (E) determinism + well-formedness of the warm map ──────────────────────────────────────────────
env -u XDG_CACHE_HOME TMPDIR="$C_CB" "$BIN" "$C_REPO" --top-k=100000 >"$TMP/c_warm2.xml" 2>/dev/null
cmp -s "$TMP/c_warm.xml" "$TMP/c_warm2.xml" && ok "(E) two warm runs are byte-identical (determinism)" \
    || no "(E) two warm runs differ — the warm path is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/c_warm.xml" 2>/dev/null; then ok "(E) warm map is well-formed XML"; else no "(E) warm map is malformed XML"; fi
fi

[ "$fail" -eq 0 ] && echo "cachereservecheck: ALL PASS" || { echo "cachereservecheck: SOME CHECKS FAILED"; exit 1; }
