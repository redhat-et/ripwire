#!/usr/bin/env bash
# chainrecvcheck.sh — gate for P2-D Rule 4: DEPTH-2 receiver-CHAIN narrowing (lane J2).
#
# The gap this closes: `receiverOf` classified every CHAINED receiver as RecvKind::None, so
# `this->m_pool.acquire()` / `cfg.opts.enable()` / `m_cfg.opts.enable()` — the dominant C++ member-call
# idiom — reached NEITHER Rule 1, Rule 2, Rule 2b, CHA-lite nor receiverStaticType, and resolved by BARE
# NAME against every same-named definition in the corpus. Rule 4 widens the receiver capture by exactly
# ONE intermediate hop (FieldOfThis / FieldOfVar), resolves that hop through the SAME
# `class#field -> declared type` table Rule 2b consumes (buildFieldNarrowTables, built before the resolve
# loop), and then applies Rule 2b's own member/base walk at the final hop.
#
# EXTRACTION change (RecvKind widens, the intermediate field rides Reference::fieldName) => kParserVer
# bump; the (k) arm below is the cache-transparency half that a version bump has to keep true.
#
# Zero false edges is the bar — a narrow that guesses is worse than ambiguity disclosed. Every uncertain
# shape must keep its COMPLETE honest split, and each has its own arm here:
#   * a depth-3 chain (`this->m_cfg.opts.enable()`) — one hop is the pinned bound, not a step toward N;
#   * an unindexed intermediate field type;
#   * a same-NAMED class collision that TOMBSTONES the class#field fact (neither owner may narrow);
#   * a scope-less free function over a file-scope variable (no enclosing class, no local binding);
#   * Python `self.pool.acquire()` and TS `this.cfg.opts.enable()` — the receiver SHAPE is captured for
#     Python (a fact about syntax) but the field-type table is C++ evidence only, so Rule 4 is C-family
#     gated exactly as Rule 2b is, and TS receivers are not captured at all. Both stay split.
#   * a PARAMETER base — the binding capture records a param's NAME but not its TYPE, and the param still
#     shadows a same-named field, so there is no usable base type and the split stays. Arm (d2).
# A precedence arm pins real C++ lookup order: a declared LOCAL shadows a same-named field, so the local's
# type — not the field's — decides the chain. Arm (d).
#
# The fixture is GENERATED here (self-contained; nothing committed under test/). Line numbers in the
# fixture are load-bearing: `--callees` rows carry p="file:LINE", which is how an Opts::enable edge is
# told apart from the same-named OptDecoy::enable and DOpts::enable decoys.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/chainrecvcheck.sh   (or asan/ripwire)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/chainfix"; FIX2="$TMP/dupfix"; FIX3="$TMP/langfix"
mkdir -p "$FIX" "$FIX2" "$FIX3"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"

# LINE NUMBERS ARE ASSERTED BELOW — edit with care.
#   acquire defs: Pool a.cpp:1, Decoy a.cpp:2
#   enable  defs: Opts a.cpp:3, OptDecoy a.cpp:4, DOpts a.cpp:5
cat >"$FIX/a.cpp" <<'EOF'
struct Pool { void acquire() { } };
struct Decoy { void acquire() { } };
struct Opts { void enable() { } };
struct OptDecoy { void enable() { } };
struct DOpts { void enable() { } };
struct Cfg { Opts opts; };
struct DCfg { DOpts opts; };
struct App {
    Pool m_pool;
    Cfg  m_cfg;
    Cfg  cfg;
    void viaThis() { this->m_pool.acquire(); }
    void viaLocal() { Cfg c; c.opts.enable(); }
    void viaField() { m_cfg.opts.enable(); }
    void viaShadow() { DCfg cfg; cfg.opts.enable(); }
    void viaParam( DCfg cfg ) { cfg.opts.enable(); }
    void deep3() { this->m_cfg.opts.enable(); }
};
struct UnkOwner { UnknownT m_u; void unk() { this->m_u.acquire(); } };
Cfg g_cfg;
void freeChain() { g_cfg.opts.enable(); }
EOF

# FIX2 — the same-named-class collision corpus, ISOLATED so its header ambiguous= gauge is exact.
# Symbol scopes drop the namespace (both classes read scope "Dup"), so the two same-named `m_f` fields
# with DIFFERENT types tombstone the field-type entry: NEITHER Dup::go may narrow its chain.
cat >"$FIX2/ns.cpp" <<'EOF'
namespace n1 { struct P1 { void grab() { } };
               struct Dup { P1 m_f; void go() { this->m_f.grab(); } }; }
namespace n2 { struct P2 { void grab() { } };
               struct Dup { P2 m_f; void go() { this->m_f.grab(); } }; }
EOF

# FIX3 — the cross-language honesty corpus, ISOLATED for the same reason.
cat >"$FIX3/p.py" <<'EOF'
class PPool:
    def acquire(self):
        return 1

class PDecoy:
    def acquire(self):
        return 2

class PApp:
    pool: PPool
    def go(self):
        return self.pool.acquire()
EOF

cat >"$FIX3/t.ts" <<'EOF'
class TOpts { enable(): number { return 1; } }
class TDecoy { enable(): number { return 2; } }
class TCfg { opts: TOpts; }
class TApp {
  cfg: TCfg;
  go(): number { return this.cfg.opts.enable(); }
}
EOF

echo "chainrecvcheck: BIN=$BIN  CORPUS=$FIX + $FIX2 + $FIX3 (generated)"

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null | tr '>' '\n' )"
callees(){ "$BIN" "$FIX" "--callees=$1" --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n'; }

# ── presence guards (a gate that cannot observe what it asserts is green-while-inert) ──
for want in '::Pool::acquire"' '::Decoy::acquire"' '::Opts::enable"' '::OptDecoy::enable"' '::DOpts::enable"' \
            '::App::viaThis"' '::App::viaLocal"' '::App::viaField"' '::App::viaShadow"' '::App::viaParam"' '::App::deep3"' \
            '::UnkOwner::unk"' 'n="freeChain"'; do   # a free function is unscoped → no id= attribute, match by name
    printf '%s\n' "$MAP" | grep -qF "$want" || no "presence guard: fixture symbol $want not indexed"
done
[ "$fail" = 0 ] && ok "presence: all fixture symbols indexed"

# ── (a) FieldOfThis: `this->m_pool.acquire()` → Pool::acquire (a.cpp:1) ONLY ──
T="$( callees viaThis )"
printf '%s\n' "$T" | grep -q 'a.cpp:1"' \
    && ok "(a) viaThis() → Pool::acquire (this->FIELD.method, field m_pool's declared type)" \
    || no "(a) viaThis() has NO edge to Pool::acquire — depth-2 this-chain narrow missing or dropped the correct edge"
printf '%s\n' "$T" | grep -q 'a.cpp:2"' \
    && no "(a) viaThis() still linked to Decoy::acquire — the chained receiver still sprays by bare name" \
    || ok "(a) viaThis() decoy Decoy::acquire NOT linked"

# ── (b) FieldOfVar over a typed LOCAL: `c.opts.enable()` with `Cfg c;` → Opts::enable (a.cpp:3) ONLY ──
L="$( callees viaLocal )"
printf '%s\n' "$L" | grep -q 'a.cpp:3"' \
    && ok "(b) viaLocal() → Opts::enable (local base type Cfg, field opts)" \
    || no "(b) viaLocal() has NO edge to Opts::enable — local-based chain narrow missing"
( printf '%s\n' "$L" | grep -q 'a.cpp:4"' ) || ( printf '%s\n' "$L" | grep -q 'a.cpp:5"' ) \
    && no "(b) viaLocal() still linked to a decoy enable (a.cpp:4 / a.cpp:5)" \
    || ok "(b) viaLocal() decoys OptDecoy::enable / DOpts::enable NOT linked"

# ── (c) FieldOfVar over a FIELD base: `m_cfg.opts.enable()` → Opts::enable (a.cpp:3) ONLY ──
F="$( callees viaField )"
printf '%s\n' "$F" | grep -q 'a.cpp:3"' \
    && ok "(c) viaField() → Opts::enable (field base m_cfg : Cfg, then field opts)" \
    || no "(c) viaField() has NO edge to Opts::enable — field-based chain narrow missing"
( printf '%s\n' "$F" | grep -q 'a.cpp:4"' ) || ( printf '%s\n' "$F" | grep -q 'a.cpp:5"' ) \
    && no "(c) viaField() still linked to a decoy enable (a.cpp:4 / a.cpp:5)" \
    || ok "(c) viaField() decoys NOT linked"

# ── (d) precedence: a declared LOCAL shadows the same-named field, so the LOCAL's type decides the chain.
#        `void viaShadow() { DCfg cfg; … }` against field `Cfg cfg` → DOpts::enable (a.cpp:5), never Opts (a.cpp:3) ──
S="$( callees viaShadow )"
printf '%s\n' "$S" | grep -q 'a.cpp:5"' \
    && ok "(d) viaShadow() local DCfg cfg → DOpts::enable — the local shadows the same-named field" \
    || no "(d) viaShadow() has NO edge to DOpts::enable — the local's type lost to the field's"
printf '%s\n' "$S" | grep -q 'a.cpp:3"' \
    && no "(d) viaShadow() linked to Opts::enable — the FIELD type beat the shadowing local (wrong C++ lookup order)" \
    || ok "(d) viaShadow() field type Cfg NOT used (local shadows field)"

# ── (d2) degrade, and a DISCLOSED LIMIT: a PARAMETER's type is not part of the binding capture, so a
#        param base has no usable type — and the param name still shadows the same-named field, so the
#        field's type must NOT be substituted for it. The honest 3-way split is the right answer, and it
#        is the same answer Rule 2 already gives a depth-1 param receiver. ──
P="$( callees viaParam )"
( printf '%s\n' "$P" | grep -q 'a.cpp:3"' ) && ( printf '%s\n' "$P" | grep -q 'a.cpp:4"' ) && ( printf '%s\n' "$P" | grep -q 'a.cpp:5"' ) \
    && ok "(d2) viaParam( DCfg cfg ) keeps its COMPLETE 3-way split (param types uncaptured; the param still shadows the field)" \
    || no "(d2) viaParam() lost part of its honest split — an untyped-but-shadowing base must refuse, not fall back to the field"

# ── (e) degrade: a DEPTH-3 chain refuses — one hop is the pinned bound, not a step toward N ──
D3="$( callees deep3 )"
( printf '%s\n' "$D3" | grep -q 'a.cpp:3"' ) && ( printf '%s\n' "$D3" | grep -q 'a.cpp:4"' ) && ( printf '%s\n' "$D3" | grep -q 'a.cpp:5"' ) \
    && ok "(e) deep3() this->m_cfg.opts.enable() keeps its COMPLETE 3-way split (depth-3 refuses)" \
    || no "(e) deep3() lost part of its honest split — a depth-3 chain must not narrow"

# ── (f) degrade: an unindexed intermediate field type refuses ──
U="$( callees unk )"
( printf '%s\n' "$U" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$U" | grep -q 'a.cpp:2"' ) \
    && ok "(f) unk() unknown intermediate type UnknownT keeps its COMPLETE 2-way split" \
    || no "(f) unk() lost part of its honest split — an unindexed field type must degrade, not narrow"

# ── (g) degrade: a scope-less free function over a file-scope variable refuses ──
FR="$( callees freeChain )"
( printf '%s\n' "$FR" | grep -q 'a.cpp:3"' ) && ( printf '%s\n' "$FR" | grep -q 'a.cpp:4"' ) && ( printf '%s\n' "$FR" | grep -q 'a.cpp:5"' ) \
    && ok "(g) freeChain() keeps its COMPLETE 3-way split (no enclosing class, no local binding)" \
    || no "(g) freeChain() lost part of its honest split — a file-scope base must not narrow"

# ── (h) the header gauges agree with the arms above, counted from the fixture rather than guessed.
#        4 chains narrowed (viaThis/viaLocal/viaField/viaShadow), 4 honest splits kept (viaParam/deep3/
#        unk/freeChain). edges: 4*1 + 3 + 3 + 2 + 3 = 15. ZERO correct edges lost — every removed edge is
#        a decoy the narrow provably excludes, and every degrade arm above still carries its full split. ──
AMB="$( printf '%s\n' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB" = "ambiguous=4" ] \
    && ok "(h) header gauge ambiguous=4 — only viaParam/deep3/unk/freeChain remain honestly split" \
    || no "(h) header gauge is '$AMB', expected ambiguous=4 (4 chains narrowed, 4 honest splits kept)"
EDG="$( printf '%s\n' "$MAP" | grep -o 'edges=[0-9]*' | head -1 )"
[ "$EDG" = "edges=15" ] \
    && ok "(h) header gauge edges=15 — the four narrows removed decoy edges only" \
    || no "(h) header gauge is '$EDG', expected edges=15 — a correct edge was dropped or a decoy survived"

# ── (i) TOMBSTONE (FIX2): two same-NAMED classes whose same-named field has DIFFERENT types → neither narrows ──
MAP2="$( "$BIN" "$FIX2" --no-cache 2>/dev/null | tr '>' '\n' )"
printf '%s\n' "$MAP2" | grep -qF '::Dup::go"' || no "(i) presence guard: Dup::go not indexed in FIX2"
AMB2="$( printf '%s\n' "$MAP2" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB2" = "ambiguous=2" ] \
    && ok "(i) both n1::Dup::go and n2::Dup::go stay ambiguous (collided field type tombstoned)" \
    || no "(i) FIX2 header gauge is '$AMB2', expected ambiguous=2 — a name-collided field type must never narrow"
GO2="$( "$BIN" "$FIX2" --callees=go --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n' )"
( printf '%s\n' "$GO2" | grep -q 'ns.cpp:1"' ) && ( printf '%s\n' "$GO2" | grep -q 'ns.cpp:3"' ) \
    && ok "(i) both grab() defs stay linked across the collision" \
    || no "(i) a grab() edge vanished — the tombstone dropped a correct edge"

# ── (j) cross-language honesty (FIX3): Python/TS chained receivers are UNCHANGED — the field-type table
#        is C++ evidence only, so Rule 4 is C-family gated (Rule 2b's own disclosed limit) ──
MAP3="$( "$BIN" "$FIX3" --no-cache 2>/dev/null | tr '>' '\n' )"
printf '%s\n' "$MAP3" | grep -qF '::PApp::go"' || no "(j) presence guard: PApp::go not indexed in FIX3"
printf '%s\n' "$MAP3" | grep -qF 'n="go"'      || no "(j) presence guard: TApp::go not indexed in FIX3"
GO3="$( "$BIN" "$FIX3" --callees=go --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n' )"
( printf '%s\n' "$GO3" | grep -q 'p.py:2"' ) && ( printf '%s\n' "$GO3" | grep -q 'p.py:6"' ) \
    && ok "(j-py) PApp.go() self.pool.acquire() stays honestly split (no Python field-type evidence — disclosed)" \
    || no "(j-py) PApp.go() lost its honest split — Python chain resolution must be unchanged"
( printf '%s\n' "$GO3" | grep -q 't.ts:1"' ) && ( printf '%s\n' "$GO3" | grep -q 't.ts:2"' ) \
    && ok "(j-ts) TApp.go() this.cfg.opts.enable() stays honestly split (TS receivers uncaptured — disclosed)" \
    || no "(j-ts) TApp.go() lost its honest split — TS receiver behavior must be unchanged"
AMB3="$( printf '%s\n' "$MAP3" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB3" = "ambiguous=2" ] \
    && ok "(j) FIX3 header gauge ambiguous=2 — both cross-language chains stay split" \
    || no "(j) FIX3 header gauge is '$AMB3', expected ambiguous=2"

# ── (k) determinism + cache transparency across the kParserVer bump ──
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "(k) deterministic (chainfix map byte-identical across two runs)" \
    || { no "(k) non-deterministic chainfix map"; diff "$TMP/m1" "$TMP/m2" | head -6; }
rm -rf "$TMP/cc"
"$BIN" "$FIX" --cache="$TMP/cc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/cc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null && ok "(k) cache-transparent (warm == cold; the chain hop round-trips the blob)" \
    || { no "(k) cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
