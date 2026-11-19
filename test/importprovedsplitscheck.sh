#!/usr/bin/env bash
# importprovedsplitscheck.sh — IMPORT-PROVED-SPLITS: a call on same-named classes in two or more files, written with the class as
# its receiver (`C.m()`), binds the ONE class the caller file's import of C proves (src/receiverevidence.h pathOwners, the shared
# hook; its per-language resolver src/graph.h ImportProvedClass). Before: the receiver rule kept every same-named class's member,
# a split (or, with a third namesake in the caller's directory, that namesake alone).
#
# The fixtures are written at test time (no committed tree a whole-repo run would index). Rows are read from --pin-census.
#   TypeScript (fixture ts/):  a/uri.ts and b/uri.ts each `export class URI { static file(); static parse() }`
#     POSITIVE  app.ts      import { URI } from './a/uri'; URI.file()                       → a/uri.ts::file only
#               both.ts     import { URI } from a + { URI as URI2 } from b; URI.file(); URI2.parse()  → a's file, b's parse
#               shadow.ts   a closure inside the importing function: URI.parse()             → a's parse
#               tslocal/    app.ts as above beside a THIRD, unexported URI in local.ts      → a's file (base: local.ts's, unhedged)
#     NEGATIVE  neither.ts  no import of URI                                                → still the split of both
#               viabarrel.ts import { URI } from './reexp' (export { URI } from './a/uri')   → still the split (a re-export is not followed)
#               loose.ts    this.u.file() / v.file() on untyped receivers                    → still declined (dc rows), never bound
#               shadow.ts   a parameter named URI: URI.file()                               → unchanged (no class-name reading)
#               tslocal/local.ts  the class of the caller's own file                       → its own file's file, unchanged
#               ren.ts      import { helper as h }; h()                                     → the renamed import still pins (mech import)
# Every negative arm counts the rows it read and fails when it read none (a vacuous arm proves nothing).
#
# Usage: bash test/importprovedsplitscheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "importprovedsplitscheck: $( "$BIN" --version 2>/dev/null )"

# ── fixtures ──
TS="$TMP/ts"; mkdir -p "$TS/a" "$TS/b" "$TS/c"
cat >"$TS/a/uri.ts" <<'EOF'
export class URI {
    static file( p: string ): URI { return new URI(); }
    static parse( p: string ): URI { return new URI(); }
}
EOF
cp "$TS/a/uri.ts" "$TS/b/uri.ts"
printf 'export function helper(): number { return 1; }\n' >"$TS/c/other.ts"
printf "export { URI } from './a/uri';\n" >"$TS/reexp.ts"
cat >"$TS/app.ts" <<'EOF'
import { URI } from './a/uri';
export function open(): URI {
    return URI.file( 'x' );
}
EOF
cat >"$TS/both.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as URI2 } from './b/uri';
export function twice(): number {
    URI.file( 'x' );
    return URI2.parse( 'y' ) ? 1 : 0;
}
EOF
cat >"$TS/shadow.ts" <<'EOF'
import { URI } from './a/uri';
export function shadowed( URI: any ): number {
    return URI.file( 's' ) ? 1 : 0;
}
export function inner(): number {
    const run = () => URI.parse( 'i' );
    return run() ? 1 : 0;
}
EOF
cat >"$TS/neither.ts" <<'EOF'
import { helper } from './c/other';
export function none(): number {
    helper();
    return URI.file( 'z' ) ? 1 : 0;
}
EOF
cat >"$TS/viabarrel.ts" <<'EOF'
import { URI } from './reexp';
export function fromBarrel(): number {
    return URI.file( 'rb' ) ? 1 : 0;
}
EOF
cat >"$TS/loose.ts" <<'EOF'
import { URI } from './a/uri';
import { URI as U2 } from './b/uri';
class Holder {
    private u = pick();
    run(): void {
        this.u.file( 'q' );
        const v = pick();
        v.file( 'r' );
    }
}
function pick() { return Math.random() > 0.5 ? URI : U2; }
EOF
cat >"$TS/ren.ts" <<'EOF'
import { helper as h } from './c/other';
export function viaRen(): number {
    return h();
}
EOF
TL="$TMP/tslocal"; mkdir -p "$TL/a" "$TL/b"
cp "$TS/a/uri.ts" "$TL/a/"; cp "$TS/b/uri.ts" "$TL/b/"; cp "$TS/app.ts" "$TL/"
cat >"$TL/local.ts" <<'EOF'
class URI {
    static file( p: string ): URI { return new URI(); }
}
export function same(): URI {
    return URI.file( 'l' );
}
EOF

# census DIR → $TMP/<name>.census (rc checked: a failed run would make every arm below vacuous)
census(){ ( cd "$1" && "$BIN" . --no-cache --pin-census="$TMP/$2.census" >/dev/null 2>"$TMP/$2.err" ); local rc=$?
          [ "$rc" -eq 0 ] || { no "$2: the --pin-census run failed (rc=$rc)"; return 1; }; return 0; }
# row NAME CALLER_FILE CALLEE LINE → "mech<TAB>targets" of the one C row (empty when none); the row count goes to $TMP/rows
row(){ awk -F'\t' -v f="$2" -v c="$3" -v l="$4" '$1=="C" && index($6,f"::")==1 && $7==c && $9==l { print $2"\t"$8; n++ } END { print n+0 > "'"$TMP"'/rows" }' "$TMP/$1.census"; }
targets(){ printf '%s' "$1" | cut -f2 | tr '|' '\n' | sed 's/#[0-9]*$//' | sort | tr '\n' ' ' | sed 's/ $//'; }
seen=0   # rows the negative arms read
# expect NAME FILE CALLEE LINE WANT_TARGETS [MECH] — the site's one row has exactly these targets (and this mechanism)
expect(){ local r; r=$( row "$1" "$2" "$3" "$4" ); local n; n=$( cat "$TMP/rows" ); local t; t=$( targets "$r" )
          if [ "$n" = 1 ] && [ "$t" = "$5" ] && { [ -z "${6:-}" ] || [ "$( printf '%s' "$r" | cut -f1 )" = "$6" ]; }; then ok "$1 $2:$4 $3 -> $5${6:+ ($6)}"
          else no "$1 $2:$4 $3: want $5${6:+ ($6)}, got rows=$n [$r]"; fi; }

census "$TS" ts || exit 1
census "$TL" tslocal || exit 1

echo "── TypeScript: the import proves one class ──"
expect ts app.ts file 3 "a/uri.ts::file"
expect ts both.ts file 4 "a/uri.ts::file"
expect ts both.ts parse 5 "b/uri.ts::parse"
expect ts shadow.ts parse 6 "a/uri.ts::parse"
expect tslocal app.ts file 3 "a/uri.ts::file"

echo "── TypeScript: nothing proves one class, or the receiver is not the class ──"
neg(){ expect "$@"; seen=$(( seen + $( cat "$TMP/rows" ) )); }
neg ts neither.ts file 4 "a/uri.ts::file b/uri.ts::file" split
neg ts viabarrel.ts file 3 "a/uri.ts::file b/uri.ts::file" split
neg ts shadow.ts file 3 "a/uri.ts::file"
neg tslocal local.ts file 5 "local.ts::file"
neg ts ren.ts h 3 "c/other.ts::helper" import
( cd "$TS" && "$BIN" . --no-cache --callers=file --legend=compact ) >"$TMP/loose.callers" 2>/dev/null || no "loose: the --callers=file run failed"
ndc=$( grep -o '<dc [^>]*p="loose.ts:[68]"[^>]*>' "$TMP/loose.callers" | grep -c 'via="declined"' )
if [ "$ndc" -eq 2 ] && ! grep -q '<s [^>]*p="loose.ts:[68]"' "$TMP/loose.callers"; then ok "loose.ts:6/8 this.u.file() / v.file() stay declined (2 dc rows, no caller row)"
else no "loose.ts: want 2 declined sites and no caller row, got $ndc"; sed 's/<!--.*-->//; s/^/        | /' "$TMP/loose.callers" | head -5; fi
seen=$(( seen + ndc ))
if [ "$seen" -ge 7 ]; then ok "the negative arms read $seen rows (premise: none vacuous)"; else no "the negative arms read only $seen rows (want >= 7)"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
