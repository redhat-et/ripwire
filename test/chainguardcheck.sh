#!/usr/bin/env bash
# chainguardcheck.sh — gate for the two receiver-guard misfires (registered: docs/EVALS.md §4,
# "Receiver-guard misfires", 2026-08-21; found by the depth-2 lane's REJECT, lane/depth2-chains @ 21f75a9).
#
# Root cause under test: `receiverOf` classified EVERY chained receiver as RecvKind::None, and five guard
# sites key on `recv == RecvKind::None`. Two misfire observably:
#   * Bug 1 — Rule 1's C++ `bareCish` arm treats `this->m_pool.run()` as a BARE unqualified call and pins
#     it to the caller's OWN class's `run` — a silently wrong PRECISE edge where the honest answer is the
#     split that includes `Pool::run`.
#   * Bug 2 — shadow suppression deletes a receiver-qualified member call outright when a local shadows
#     the member's name: `int enable = 0; this->m_cfg.enable();` emits ZERO call edges.
# The fix is the capture widening ALONE (RecvKind FieldOfThis/FieldOfVar, depth-2 only): the guards are
# not edited — a chained receiver simply stops satisfying `recv == None`. NO chain RESOLUTION is asserted
# here: a fixed chained call lands in the honest §2a split, never a narrow (Rule 4 is a different, rejected
# lane). Zero lost edges is the bar — the old wrong target must SURVIVE inside the widened split.
#
# EXTRACTION change (RecvKind values widen) => kParserVer bump; arm (k) is the cache-transparency half a
# version bump has to keep true.
#
# The fixture is GENERATED here (self-contained; nothing committed under test/). Line numbers are
# load-bearing: `--callees` rows carry p="file:LINE", which is how App::run (the wrong pin, a.cpp:10) is
# told apart from Pool::run (the recovered right candidate, a.cpp:1).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/chainguardcheck.sh   (or asan/ripwire)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/guardfix"; FIX2="$TMP/langfix"
mkdir -p "$FIX" "$FIX2"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"

# LINE NUMBERS ARE ASSERTED BELOW — edit with care.
#   run  defs: Pool a.cpp:1,  App a.cpp:10        tick defs: Opts a.cpp:4, App a.cpp:11
#   enable defs: Cfg a.cpp:2, EDecoy a.cpp:3      ping def:  Opts a.cpp:4 (single-def)
cat >"$FIX/a.cpp" <<'EOF'
struct Pool { void run() { } };
struct Cfg { void enable() { } };
struct EDecoy { void enable() { } };
struct Opts { void tick() { } void ping() { } };
struct Box { Opts opts; };
struct App {
    Pool m_pool;
    Cfg  m_cfg;
    Box  m_box;
    void run() { }
    void tick() { }
    void goThis() { this->m_pool.run(); }
    void goVar() { m_box.opts.tick(); }
    void goLoc() { Box b; b.opts.tick(); }
    void goShadow() { int enable = 0; this->m_cfg.enable(); (void)enable; }
    void goVarShadow() { int ping = 0; m_box.opts.ping(); (void)ping; }
    void goBare() { run(); }
    void goOne() { m_cfg.enable(); }
    void deepPin() { this->m_box.opts.tick(); }
    void deepShadow() { int tick = 0; this->m_box.opts.tick(); (void)tick; }
};
EOF

# FIX2 — the cross-language stability corpus, ISOLATED so its gauges are exact. The receiver SHAPE is
# captured for Python (a fact about syntax); TS receivers are not captured at all. NEITHER may change
# edges here: both chained calls keep their COMPLETE honest split, before and after.
cat >"$FIX2/p.py" <<'EOF'
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

cat >"$FIX2/t.ts" <<'EOF'
class TOpts { enable(): number { return 1; } }
class TDecoy { enable(): number { return 2; } }
class TCfg { opts: TOpts; }
class TApp {
  cfg: TCfg;
  go(): number { return this.cfg.opts.enable(); }
}
EOF

echo "chainguardcheck: BIN=$BIN  CORPUS=$FIX + $FIX2 (generated)"

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null | tr '>' '\n' )"
callees(){ "$BIN" "$FIX" "--callees=$1" --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n'; }

# ── presence guards (a gate that cannot observe what it asserts is green-while-inert) ──
for want in '::Pool::run"' '::Cfg::enable"' '::EDecoy::enable"' '::Opts::tick"' '::Opts::ping"' \
            '::App::run"' '::App::tick"' '::App::goThis"' '::App::goVar"' '::App::goLoc"' \
            '::App::goShadow"' '::App::goVarShadow"' '::App::goBare"' '::App::goOne"' \
            '::App::deepPin"' '::App::deepShadow"'; do
    printf '%s\n' "$MAP" | grep -qF "$want" || no "presence guard: fixture symbol $want not indexed"
done
[ "$fail" = 0 ] && ok "presence: all fixture symbols indexed"

# ── Bug 1 / #B1 — corrected targets: the wrong PRECISE pin becomes the complete honest split ──────────
# (a) FieldOfThis: `this->m_pool.run()` must reach Pool::run (a.cpp:1) AND keep App::run (a.cpp:10).
T="$( callees goThis )"
printf '%s\n' "$T" | grep 'n="run"' | grep -q 'a.cpp:1"' \
    && ok "(a) goThis() this->m_pool.run() reaches Pool::run — the chained receiver is no longer a bare call" \
    || no "(a) goThis() has NO edge to Pool::run — bareCish still wrong-narrows the chained receiver to the caller's own class"
printf '%s\n' "$T" | grep 'n="run"' | grep -q 'a.cpp:10"' \
    && ok "(a) goThis() keeps App::run inside the split (zero lost edges)" \
    || no "(a) goThis() LOST its App::run edge — the widening removed a candidate instead of widening the pin"

# (b) FieldOfVar over a FIELD base: `m_box.opts.tick()` → split {Opts::tick a.cpp:4, App::tick a.cpp:11}.
V="$( callees goVar )"
printf '%s\n' "$V" | grep 'n="tick"' | grep -q 'a.cpp:4"' \
    && ok "(b) goVar() m_box.opts.tick() reaches Opts::tick — the field-based chain is no longer a bare call" \
    || no "(b) goVar() has NO edge to Opts::tick — bareCish still wrong-narrows the field-based chain"
printf '%s\n' "$V" | grep 'n="tick"' | grep -q 'a.cpp:11"' \
    && ok "(b) goVar() keeps App::tick inside the split (zero lost edges)" \
    || no "(b) goVar() LOST its App::tick edge"

# (c) FieldOfVar over a typed LOCAL base: `Box b; b.opts.tick()` → the same complete split.
L="$( callees goLoc )"
printf '%s\n' "$L" | grep 'n="tick"' | grep -q 'a.cpp:4"' \
    && ok "(c) goLoc() b.opts.tick() reaches Opts::tick — the local-based chain is no longer a bare call" \
    || no "(c) goLoc() has NO edge to Opts::tick — bareCish still wrong-narrows the local-based chain"
printf '%s\n' "$L" | grep 'n="tick"' | grep -q 'a.cpp:11"' \
    && ok "(c) goLoc() keeps App::tick inside the split (zero lost edges)" \
    || no "(c) goLoc() LOST its App::tick edge"

# ── Bug 2 / #B2 — recovered edges: the shadow-deleted member call comes back ──────────────────────────
# (d) multi-def flavor: `int enable = 0; this->m_cfg.enable();` recovers as the honest 2-way split.
S="$( callees goShadow )"
printf '%s\n' "$S" | grep 'n="enable"' | grep -q 'a.cpp:2"' \
    && ok "(d) goShadow() this->m_cfg.enable() recovered — a local named enable no longer deletes the member call" \
    || no "(d) goShadow() emits NO edge to Cfg::enable — shadow suppression still deletes the receiver-qualified call"
printf '%s\n' "$S" | grep 'n="enable"' | grep -q 'a.cpp:3"' \
    && ok "(d) goShadow() recovers as the COMPLETE honest split (EDecoy::enable linked too — no sneak narrow)" \
    || no "(d) goShadow() recovered only a partial split — a recovered call must spray honestly, not guess"

# (e) single-def flavor: `int ping = 0; m_box.opts.ping();` recovers precise (ping has ONE def).
P="$( callees goVarShadow )"
printf '%s\n' "$P" | grep 'n="ping"' | grep -q 'a.cpp:4"' \
    && ok "(e) goVarShadow() m_box.opts.ping() recovered to Opts::ping (single-def name lands precise)" \
    || no "(e) goVarShadow() emits NO edge to Opts::ping — shadow suppression still deletes the chained call"

# ── controls — green before AND after ─────────────────────────────────────────────────────────────────
# (f) a genuinely BARE call inside the class still Rule-1 narrows: goBare() → App::run ONLY.
BQ="$( callees goBare )"
printf '%s\n' "$BQ" | grep 'n="run"' | grep -q 'a.cpp:10"' \
    && ok "(f) goBare() run() still Rule-1 pins App::run (bare calls unaffected)" \
    || no "(f) goBare() lost its App::run pin — the widening broke Rule 1's genuine bare arm"
printf '%s\n' "$BQ" | grep 'n="run"' | grep -q 'a.cpp:1"' \
    && no "(f) goBare() linked to Pool::run — a genuine bare call must stay narrowed to the enclosing class" \
    || ok "(f) goBare() decoy Pool::run NOT linked (Rule 1 narrow intact)"

# (g) a depth-1 NamedVar field receiver still Rule-2b narrows: goOne() m_cfg.enable() → Cfg::enable ONLY.
O="$( callees goOne )"
printf '%s\n' "$O" | grep 'n="enable"' | grep -q 'a.cpp:2"' \
    && ok "(g) goOne() m_cfg.enable() still Rule-2b narrows to Cfg::enable (depth-1 receivers unaffected)" \
    || no "(g) goOne() lost its Cfg::enable narrow — the widening broke Rule 2b's depth-1 arm"
printf '%s\n' "$O" | grep 'n="enable"' | grep -q 'a.cpp:3"' \
    && no "(g) goOne() linked to EDecoy::enable — Rule 2b's narrow regressed to a spray" \
    || ok "(g) goOne() decoy EDecoy::enable NOT linked (Rule 2b narrow intact)"

# (h) The depth-3 residual, CLOSED (Phase 5, docs/EVALS.md "Phase 5"; was a disclosed residual until then).
#     The capture bound is still ONE intermediate hop, so a depth-3 chain's receiver stays undecidable — but
#     ingest now stamps such a member access FieldOfVar with an EMPTY recvVar instead of None, so no bare-name
#     guard reads it as a bare call: deepPin() `this->m_box.opts.tick()` takes the honest split (Opts::tick +
#     App::tick, amb=1) instead of Rule 1's wrong App::tick pin, and deepShadow() (the same call under a
#     shadowing local `tick`) keeps both edges instead of being deleted by shadow suppression.
D="$( callees deepPin )"
( printf '%s\n' "$D" | grep 'n="tick"' | grep -q 'a.cpp:4"' ) && ( printf '%s\n' "$D" | grep 'n="tick"' | grep -q 'a.cpp:11"' ) \
    && ok "(h) deepPin() depth-3 chain takes the honest split (Opts::tick + App::tick) — no enclosing-class pin" \
    || no "(h) deepPin() depth-3 chain is not the complete Opts::tick + App::tick split: $( printf '%s' "$D" | tr '\n' ' ' )"
DS="$( callees deepShadow )"
( printf '%s\n' "$DS" | grep 'n="tick"' | grep -q 'a.cpp:4"' ) && ( printf '%s\n' "$DS" | grep 'n="tick"' | grep -q 'a.cpp:11"' ) \
    && ok "(h) deepShadow() depth-3 shadowed chain keeps its split — shadow suppression no longer deletes it" \
    || no "(h) deepShadow() lost its edges under the shadowing local — the depth-3 chain is read as a bare name again"

# ── (i) the header gauges agree with the arms above, counted from the fixture rather than guessed.
#        Post-fix: goThis 2 + goVar 2 + goLoc 2 + goShadow 2 + goVarShadow 1 + goBare 1 + goOne 1
#        + deepPin 2 + deepShadow 2 = 15 edges; ambiguous = the four widened/recovered splits
#        (goThis/goVar/goLoc/goShadow) + the two depth-3 chains (Phase 5) = 6. Base binary read
#        edges=6 ambiguous=0 (pre-widening) and 12 / 4 before Phase 5 closed the depth-3 residual — six calls pinned
#        or deleted, ZERO disclosed ambiguity, wrong five times over: exactly why ambiguous= could not
#        be this round's instrument. ──
AMB="$( printf '%s\n' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB" = "ambiguous=6" ] \
    && ok "(i) header gauge ambiguous=6 — the recovered/widened calls and both depth-3 chains disclose their splits" \
    || no "(i) header gauge is '$AMB', expected ambiguous=6 (wrong pins widened + shadowed calls recovered + depth-3 chains split)"
EDG="$( printf '%s\n' "$MAP" | grep -o 'edges=[0-9]*' | head -1 )"
[ "$EDG" = "edges=15" ] \
    && ok "(i) header gauge edges=15 — recovered and widened edges present, none lost" \
    || no "(i) header gauge is '$EDG', expected edges=15 — a recovered edge is missing or one was lost"

# ── (j) cross-language stability (FIX2): Python/TS chained-call edges are byte-stable ─────────────────
MAP2="$( "$BIN" "$FIX2" --no-cache 2>/dev/null | tr '>' '\n' )"
printf '%s\n' "$MAP2" | grep -qF '::PApp::go"' || no "(j) presence guard: PApp.go not indexed in FIX2"
GO2="$( "$BIN" "$FIX2" --callees=go --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n' )"
( printf '%s\n' "$GO2" | grep -q 'p.py:2"' ) && ( printf '%s\n' "$GO2" | grep -q 'p.py:6"' ) \
    && ok "(j-py) PApp.go() self.pool.acquire() keeps its COMPLETE split (Python shape capture changes no edge)" \
    || no "(j-py) PApp.go() lost part of its split — the widening changed Python edges"
( printf '%s\n' "$GO2" | grep -q 't.ts:1"' ) && ( printf '%s\n' "$GO2" | grep -q 't.ts:2"' ) \
    && ok "(j-ts) TApp.go() this.cfg.opts.enable() keeps its COMPLETE split (TS receivers uncaptured)" \
    || no "(j-ts) TApp.go() lost part of its split — TS receiver behavior must be unchanged"
AMB2="$( printf '%s\n' "$MAP2" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB2" = "ambiguous=2" ] \
    && ok "(j) FIX2 header gauge ambiguous=2 — both cross-language chains stay split" \
    || no "(j) FIX2 header gauge is '$AMB2', expected ambiguous=2"
EDG2="$( printf '%s\n' "$MAP2" | grep -o 'edges=[0-9]*' | head -1 )"
[ "$EDG2" = "edges=4" ] \
    && ok "(j) FIX2 header gauge edges=4 — cross-language edge sets byte-stable" \
    || no "(j) FIX2 header gauge is '$EDG2', expected edges=4"

# ── (k) determinism + cache transparency across the kParserVer bump ───────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "(k) deterministic (guardfix map byte-identical across two runs)" \
    || { no "(k) non-deterministic guardfix map"; diff "$TMP/m1" "$TMP/m2" | head -6; }
rm -rf "$TMP/cc"
"$BIN" "$FIX" --cache="$TMP/cc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/cc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null && ok "(k) cache-transparent (warm == cold; the receiver kind round-trips the blob)" \
    || { no "(k) cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
