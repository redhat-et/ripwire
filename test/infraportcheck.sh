#!/usr/bin/env bash
# infraportcheck.sh — src/infra/ is a VENDORABLE set. This gate is the boundary that keeps it one.
#
# WHY THIS GATE EXISTS
#   The headers under src/infra/ are copied wholesale into a sibling repo whose directory layout is
#   NOT this one's. Nothing in a normal build can notice when that stops being possible: a layer file
#   that reaches up into src/, names a domain type, or talks about the host project still compiles
#   here, perfectly, forever. The breakage surfaces on ARRIVAL, in the other repo, weeks later, as a
#   missing header or a comment that describes a program the reader has never run. So the property has
#   to be asserted here, where the edit happens.
#
#   THE PROPERTY, in three parts, for every file under src/infra/:
#     (A) no #include reaching outside the layer — no `../`, no `src/`-relative path, and no header
#         that lives only in src/. A sibling in the layer is fine; so is a third_party/ header, because
#         the vendored deps travel with the layer.
#     (B) no host domain type named — Symbol, NodeId, IngestResult, Reference, SymKind, Graph. These
#         are the index/graph model; a layer file that knows one of them is not infrastructure any more.
#     (C) no mention of the host project by name. Deliberately a plain case-insensitive SUBSTRING, so it
#         catches identifiers and build-option names (a `RIPWIRE_*` macro) as well as prose — those are
#         the ones that read as noise, or as a lie, once the file is in another tree.
#
#   Sibling includes inside the layer stay BARE (`#include "hashutil.h"`, never `"infra/hashutil.h"`) for
#   exactly the same reason: the destination has no `infra/` directory to prefix. Rule (A) is what makes
#   that spelling checkable rather than a convention someone remembers.
#
# NON-VACUITY (CONTRIBUTING.md §2 — the gate must be able to observe what it asserts). Two guards:
#   1. the scan must actually reach ≥1 file; an empty layer, a moved directory or a broken glob would
#      otherwise report "no violations" and pass while measuring nothing;
#   2. the three detectors are run against a synthetic file that violates all three, and each one must
#      FIRE. A detector whose regex has rotted reports a clean tree in exactly the same words as a
#      detector that works.
#
# Usage:  bash test/infraportcheck.sh
# Exits non-zero on any violation; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
LAYER="$ROOT/src/infra"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "infraportcheck: LAYER=$LAYER"

if [ ! -d "$LAYER" ]; then
    no "src/infra/ does not exist — this gate has nothing to scan (repoint it, do not delete it)"
    echo "SOME CHECKS FAILED"
    exit 1
fi

# ── the three detectors. Each takes a FILE and the directory that stands in for the layer root, and
#    prints one line per violation (nothing at all when clean). Factored as functions so the synthetic
#    non-vacuity probe below runs the SAME code the real scan runs, not a restatement of it. ─────────
detect_include(){            # $1 = file, $2 = directory the file is treated as living in
    local file="$1" dir="$2" base
    base="$( basename "$file" )"
    grep -oE '^[[:space:]]*#[[:space:]]*include[[:space:]]*"[^"]+"' "$file" 2>/dev/null \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | while IFS= read -r inc; do
              case "$inc" in
                  ../*|*/../*) printf '%s: #include "%s" — a `..` path escapes the layer\n' "$base" "$inc"; continue ;;
                  src/*)       printf '%s: #include "%s" — a src/-relative path names the host tree\n' "$base" "$inc"; continue ;;
              esac
              # a sibling in the layer, or a vendored dependency that is copied along with it, is fine
              if [ -f "$dir/$inc" ] || [ -f "$ROOT/third_party/$inc" ]; then
                  continue
              fi
              if [ -f "$ROOT/src/$inc" ]; then
                  printf '%s: #include "%s" — resolves only to src/%s, which is ABOVE the layer\n' "$base" "$inc" "$inc"
              else
                  printf '%s: #include "%s" — resolves nowhere inside the vendorable set (layer + third_party/)\n' "$base" "$inc"
              fi
          done
}

detect_domain(){             # $1 = file
    grep -nwE '(Symbol|NodeId|IngestResult|Reference|SymKind|Graph)' "$1" 2>/dev/null \
        | sed -E "s|^|$( basename "$1" ):|"
}

detect_host(){               # $1 = file — plain case-insensitive substring, on purpose (see (C) above)
    grep -niE 'ripwire' "$1" 2>/dev/null \
        | sed -E "s|^|$( basename "$1" ):|"
}

# ── guard 1: the scan reaches real files ────────────────────────────────────────────────────────────
FILES="$( find "$LAYER" -maxdepth 1 -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.inl' -o -name '*.cpp' \) | LC_ALL=C sort )"
FILE_COUNT="$( printf '%s' "$FILES" | grep -c . | tr -d ' ' )"
if [ "$FILE_COUNT" -ge 1 ]; then
    ok "scan reaches $FILE_COUNT file(s) under src/infra/ (a zero-file scan would pass vacuously)"
else
    no "scan reached 0 files under src/infra/ — the glob or the directory moved; every arm below would pass while measuring nothing"
    echo "SOME CHECKS FAILED"
    exit 1
fi

# ── guard 2: every detector fires on a file that violates all three ─────────────────────────────────
PROBE="$TMP/probe.h"
cat > "$PROBE" <<'PROBE_EOF'
#pragma once
#include "../src/model.h"
// this probe file names the host project, ripwire, on purpose
inline void probe( const IngestResult& ing, NodeId id ) { (void) ing; (void) id; }
PROBE_EOF
probeInclude="$( detect_include "$PROBE" "$TMP" )"
probeDomain="$(  detect_domain  "$PROBE" )"
probeHost="$(    detect_host    "$PROBE" )"
[ -n "$probeInclude" ] && ok "detector (A) include-escape fires on a deliberate violation" \
                       || no "detector (A) include-escape did NOT fire on a deliberate violation — it cannot observe what it asserts"
[ -n "$probeDomain" ]  && ok "detector (B) domain-type fires on a deliberate violation" \
                       || no "detector (B) domain-type did NOT fire on a deliberate violation — it cannot observe what it asserts"
[ -n "$probeHost" ]    && ok "detector (C) host-name fires on a deliberate violation" \
                       || no "detector (C) host-name did NOT fire on a deliberate violation — it cannot observe what it asserts"

# ── the real scan ───────────────────────────────────────────────────────────────────────────────────
: > "$TMP/hits.include"
: > "$TMP/hits.domain"
: > "$TMP/hits.host"
while IFS= read -r file; do
    [ -n "$file" ] || continue
    detect_include "$file" "$LAYER" >> "$TMP/hits.include"
    detect_domain  "$file"          >> "$TMP/hits.domain"
    detect_host    "$file"          >> "$TMP/hits.host"
done <<EOF
$FILES
EOF

report(){                    # $1 = hits file, $2 = the rule's one-line statement
    local hits="$1" what="$2" n
    n="$( grep -c . < "$hits" | tr -d ' ' )"
    if [ "$n" = 0 ]; then
        ok "$what"
    else
        no "$what — $n violation(s):"
        sed -E 's/^/          /' "$hits"
    fi
}

report "$TMP/hits.include" "(A) no file under src/infra/ includes anything outside the layer (siblings + third_party/ only)"
report "$TMP/hits.domain"  "(B) no file under src/infra/ names a host domain type (Symbol/NodeId/IngestResult/Reference/SymKind/Graph)"
report "$TMP/hits.host"    "(C) no file under src/infra/ mentions the host project by name"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
