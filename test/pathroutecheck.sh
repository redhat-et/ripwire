#!/usr/bin/env bash
# pathroutecheck.sh — a reached --path chain stitched from calls bound by name alone is hedged, refused, or replaced by a proven
# chain; never printed as the plain reachable answer (src/pathroute.h pathRouteVerdict, PATH-ROUTE v2).
#
# THE DEFECT. shortestPathAny is a plain BFS over every out-edge, proven and by-name alike. On LD-2 django-06 it printed
# reachable=1 hops=12 with 5 via="name" hops through the prefetch code (the wrong branch), and nothing on the root said the chain
# was name-stitched: an agent trusts it.
#
# THE CONTRACT (one predicate, both transports):
#   >= 2 by-name hops and a proven-only chain exists  -> the proven chain prints, route_hedged="proven-preferred"
#   >= 2 by-name hops, no proven chain                -> printed, route_hedged="name-stitched" route_by_name= route_cands=
#   >= 4 by-name hops, no proven chain                -> printed, route_hedged="unlikely" (the verdict rides the root, not only the legend),
#                                                        a next= to verify it (from's callees, else the hop body)
#   >= 4 by-name hops, route_cands >= 64, no proven   -> refused: reachable="0" hops="0" route_hedged="not-proven", no hop rows,
#                                                        next="--callees=<from>" (shell-safe: a path with a space is quoted)
#   0..1 by-name hop                                  -> unchanged (no route_hedged=)
#   a pairs answer (several definitions)              -> the first pair's chain is hedged, never refused
#
# WHY route_cands >= 64 AND NOT "> 1" (fix1 of be9c4d62): every real chain the reviews refused carried route_cands 144..23712 and was
# wrong; every TRUE chain checked carried <= 16 (a TS / Go dependency-injection chain through interfaces has route_cands 2..16), and a
# wrong chain whose by-name hop binds a builtin receiver (`stack.pop()` to the repo's one `def pop`) counts 1: route_cands counts
# IN-REPO same-named definitions only, so a low count is no proof and the legend says so.
#
# ARMS
#   (R) refuse: start_entry -> o.s1 -> o.s2 -> o.s3 -> sink, every hop by name over THREE same-named classes (81): refused, no decoy row.
#   (B64/B63) the knob's edge: route_cands exactly 64 is refused, 63 is hedged and printed (the same 4-hop shape).
#   (P) proven-preferred: a 3-hop by-name shortcut beside a 6-hop proven chain: the proven chain prints, no via=name row.
#   (PS) the proven-only search skips EVERY guessed edge, not only the by-name ones (CodeRabbit #481): a 3-hop by-name shortcut beside a
#        6-hop chain whose 4th hop is one arm of a resolver split (prov="split"): the chain is NOT "proven-preferred" (it would print a
#        guessed hop under a proven label); the shortcut prints hedged, route_hedged="name-stitched", and no row carries prov="split".
#   (PI) control: the same shape with the one-implementor edge (via="impl", a proven edge whose row says so) in place of the split arm
#        still prints the 6-hop chain, route_hedged="proven-preferred", via="impl" on its row.
#   (H) hedge: two by-name hops (cands 2): printed whole, route_hedged="name-stitched" route_by_name="2".
#   (N1) near miss: one by-name hop among proven ones: no route_hedged=.
#   (N2) near miss: four by-name hops each with ONE candidate (cands=1): route_hedged="unlikely", printed, never refused.
#   (N3) near miss: three by-name hops with cands=2 each (the LARGE-DEV cpython-02 shape, a TRUE chain): hedged, never refused.
#   (N4) a TRUE 4-hop TypeScript dependency-injection chain (interface-typed fields, one production decorator: route_cands 2): hedged, printed.
#   (N5) the same chain in Go (a production implementor and a fake per interface: route_cands 16): hedged, printed.
#   (N6) five by-name hops with one candidate each (the shape of a chain whose first hop binds a builtin receiver to the repo's one
#        same-named definition: route_cands 1): hedged and printed, never refused.
#   (U) a hedge of >= 4 by-name hops says the chain is unlikely, names that route_cands counts in-repo definitions only (builtin and
#       external receivers are not counted, so a low count is no proof), and carries a next= to verify it (full legend; compact keeps the clause).
#   (S) the refusal's next= is shell-safe: a root with a space in a directory name parses as ONE argv element (sh -n, then sh -c).
#   (PM) a pairs answer (two definitions of the from= name) carries the hedge on its first pair's chain and is never refused.
#   (L) the --legend=full clause rides exactly when route_hedged= does; every answer parses (xmllint when present).
#   (M) MCP path_between: the same verdict attrs and the same rows as the CLI on R, P, H, N4.
#   (F) --for "<path subject>": the <graph_verb> block carries the same verdict as the CLI on R.
#
# Usage: test/pathroutecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "pathroutecheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

mkdir -p "$TMP/r" "$TMP/b64" "$TMP/b63" "$TMP/p" "$TMP/h" "$TMP/n1" "$TMP/n2" "$TMP/n3" "$TMP/n4/test" "$TMP/n5" "$TMP/n6" "$TMP/ps" "$TMP/pi" "$TMP/rs/sub dir" "$TMP/pm" "$TMP/home"
# a 4-hop all-by-name chain start_entry -> o.s1 -> o.s2 -> o.s3 -> o.sink_call where name i is defined by K_i classes (the hop's cands=K_i):
# route_cands = K1*K2*K3*K4. Only the first class of each name continues the chain; the last name's first class is Sink.
genchain(){ python3 - "$@" <<'PYEOF'
import sys
ks = [int(x) for x in sys.argv[2:6]]
names = ["s1", "s2", "s3", "sink_call"]
out = []
for i, k in enumerate(ks):
    for j in range(k):
        cls = "Sink" if (i == 3 and j == 0) else "C%d_%d" % (i, j)
        body = "o.%s(o)" % names[i + 1] if (j == 0 and i < 3) else "%d" % (j + 1)
        out.append("class %s:\n    def %s(self, o):\n        return %s\n" % (cls, names[i], body))
out.append("def start_entry(o):\n    return o.s1(o)\n")
open(sys.argv[1], "w").write("\n".join(out))
PYEOF
}
genchain "$TMP/r/m.py" 3 3 3 3            # (R)   route_cands 81
genchain "$TMP/b64/m.py" 4 4 2 2          # (B64) route_cands exactly 64
genchain "$TMP/b63/m.py" 7 3 3 1          # (B63) route_cands exactly 63
genchain "$TMP/rs/sub dir/m.py" 3 3 3 3   # (S)   the same chain under a directory with a space
genchain "$TMP/pm/m.py" 3 3 3 3           # (PM)  the same chain, plus a second start_entry (a pairs answer)
printf 'def start_entry(o):\n    return o.s1(o)\n' > "$TMP/pm/other.py"
# (P) the by-name shortcut start_entry -> o.s1 -> o.s2 -> o.fin beside a proven 6-hop chain start_entry -> a1 -> a2 -> a3 -> a4 -> Sink.go -> Sink.fin (proven: a constructed receiver, self)
cat > "$TMP/p/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.s2(o)
    def s2(self, o):
        return o.fin(o)

class Beta:
    def s1(self, o):
        return 0
    def s2(self, o):
        return 0

class Sink:
    def go(self, o):
        return self.fin(o)
    def fin(self, o):
        return 3

class Decoy:
    def fin(self, o):
        return 4

def a4(o):
    s = Sink()
    return s.go(o)
def a3(o):
    return a4(o)
def a2(o):
    return a3(o)
def a1(o):
    return a2(o)

def start_entry(o):
    a1(o)
    return o.s1(o)
EOF
# (PS)/(PI) Java: the by-name shortcut startEntry -> o.s1 -> o.s2 -> o.fin (a Ctx receiver nothing declares: 3 hops by name) beside the 6-hop
# chain startEntry -> a1 -> a2 -> a3 -> {Over.pick: one arm of a two-overload split | OnlyStep.run: the only implementor of a two-method interface} -> Sink.go -> Sink.fin
for d in ps pi; do
    printf 'public class Sink { public int go(Object o) { return this.fin(o); } public int fin(Object o) { return 3; } }\n' > "$TMP/$d/Sink.java"
    printf 'public class Decoy { public int fin(Ctx o) { return 4; } }\n' > "$TMP/$d/Decoy.java"
    printf 'public class Alpha { public int s1(Ctx o) { return o.s2(o); } public int s2(Ctx o) { return o.fin(o); } }\n' > "$TMP/$d/Alpha.java"
    printf 'public class Beta { public int s1(Ctx o) { return 0; } public int s2(Ctx o) { return 0; } }\n' > "$TMP/$d/Beta.java"
done
printf 'public class Over {\n    public int pick(Ctx o) { return new Sink().go(o); }\n    public int pick(Other o) { return 0; }\n}\n' > "$TMP/ps/Over.java"
printf 'public class Chain {\n    static int a3(Over m, Ctx o) { return m.pick(o); }\n    static int a2(Over m, Ctx o) { return a3(m, o); }\n    static int a1(Over m, Ctx o) { return a2(m, o); }\n    static int startEntry(Ctx o, Over m) { a1(m, o); return o.s1(o); }\n}\n' > "$TMP/ps/Chain.java"
printf 'public interface Step { int run(Object o); int size(); }\n' > "$TMP/pi/Step.java"
printf 'public class OnlyStep implements Step { public int run(Object o) { return new Sink().go(o); } public int size() { return 1; } }\n' > "$TMP/pi/OnlyStep.java"
printf 'public class Chain {\n    static int a3(Step i, Ctx o) { return i.run(o); }\n    static int a2(Step i, Ctx o) { return a3(i, o); }\n    static int a1(Step i, Ctx o) { return a2(i, o); }\n    static int startEntry(Ctx o, Step i) { a1(i, o); return o.s1(o); }\n}\n' > "$TMP/pi/Chain.java"
# (H) two by-name hops
cat > "$TMP/h/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.finish(o)

class Beta:
    def s1(self, o):
        return 0

class Sink:
    def finish(self, o):
        return 1

class Decoy:
    def finish(self, o):
        return 2

def start_entry(o):
    return o.s1(o)
EOF
# (N1) one by-name hop among proven ones
cat > "$TMP/n1/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return leaf(o)

class Beta:
    def s1(self, o):
        return 0

def leaf(o):
    return 1

def mid(o):
    return o.s1(o)

def start_entry(o):
    return mid(o)
EOF
# (N2) four by-name hops, each name defined once (cands=1)
cat > "$TMP/n2/m.py" <<'EOF'
class Alpha:
    def u1(self, o):
        return o.u2(o)
    def u2(self, o):
        return o.u3(o)

class Gamma:
    def u3(self, o):
        return o.u4(o)

class Delta:
    def u4(self, o):
        return 1

def start_entry(o):
    return o.u1(o)
EOF

# (N3) three by-name hops, cands=2 each: Alpha.s1 -> o.s2 -> o.sink_call
cat > "$TMP/n3/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.s2(o)
    def s2(self, o):
        return o.sink_call(o)

class Beta:
    def s1(self, o):
        return 0
    def s2(self, o):
        return 0

class Decoy:
    def sink_call(self, o):
        return 1

class Sink:
    def sink_call(self, o):
        return 2

def start_entry(o):
    return o.s1(o)
EOF

# (N4) a TRUE 4-hop TypeScript dependency-injection chain: interface-typed fields, one production decorator of IRepo (route_cands 2)
cat > "$TMP/n4/app.ts" <<'EOF'
export interface IConn { execute(sql: string): string }
export interface IRepo { save(row: string): string }
export interface IHandler { handle(req: string): string }
export interface IRouter { dispatch(req: string): string }
export class Conn implements IConn { execute(sql: string): string { return sql; } }
export class Repo implements IRepo { constructor(private conn: IConn) {} save(row: string): string { return this.conn.execute("insert"); } }
export class Handler implements IHandler { constructor(private repo: IRepo) {} handle(req: string): string { return this.repo.save(req); } }
export class Router implements IRouter { constructor(private handler: IHandler) {} dispatch(req: string): string { return this.handler.handle(req); } }
export class App { constructor(private router: IRouter) {} serve(req: string): string { return this.router.dispatch(req); } }
EOF
cat > "$TMP/n4/cached.ts" <<'EOF'
import { IRepo } from "./app";
export class CachedRepo implements IRepo { constructor(private inner: IRepo) {} save(row: string): string { return this.inner.save(row); } }
EOF
cat > "$TMP/n4/test/fakes.ts" <<'EOF'
import { IConn, IRepo, IHandler, IRouter } from "../app";
export class FakeConn implements IConn { execute(sql: string): string { return ""; } }
export class FakeRepo implements IRepo { save(row: string): string { return ""; } }
export class FakeHandler implements IHandler { handle(req: string): string { return ""; } }
export class FakeRouter implements IRouter { dispatch(req: string): string { return ""; } }
EOF
# (N5) the same chain in Go: a production implementor and a fake per interface (route_cands 16)
cat > "$TMP/n5/go.mod" <<'EOF'
module di
go 1.21
EOF
cat > "$TMP/n5/app.go" <<'EOF'
package di

type IConn interface{ Execute(sql string) string }
type IRepo interface{ Save(row string) string }
type IHandler interface{ Handle(req string) string }
type IRouter interface{ Dispatch(req string) string }

type Conn struct{}
func (c *Conn) Execute(sql string) string { return sql }
type Repo struct{ conn IConn }
func (r *Repo) Save(row string) string { return r.conn.Execute("insert") }
type Handler struct{ repo IRepo }
func (h *Handler) Handle(req string) string { return h.repo.Save(req) }
type Router struct{ handler IHandler }
func (r *Router) Dispatch(req string) string { return r.handler.Handle(req) }
type App struct{ router IRouter }
func (a *App) Serve(req string) string { return a.router.Dispatch(req) }
EOF
cat > "$TMP/n5/fakes.go" <<'EOF'
package di

type FakeConn struct{}
func (c *FakeConn) Execute(sql string) string { return "" }
type FakeRepo struct{}
func (r *FakeRepo) Save(row string) string { return "" }
type FakeHandler struct{}
func (h *FakeHandler) Handle(req string) string { return "" }
type FakeRouter struct{}
func (r *FakeRouter) Dispatch(req string) string { return "" }
EOF
# (N6) five by-name hops, each name defined once (cands=1 everywhere)
cat > "$TMP/n6/m.py" <<'EOF'
class Pump:
    def prevent(self, o):
        return o.pop_item(o)

class ListView:
    def pop_item(self, o):
        return o.step_a(o)

class Mid:
    def step_a(self, o):
        return o.step_b(o)
    def step_b(self, o):
        return o.step_c(o)

class Widget:
    def step_c(self, o):
        return o.step_d(o)

class Clamp:
    def step_d(self, o):
        return 1
EOF

run(){ local d=$1; shift; ( cd "$TMP/$d" || exit 1; env -u RIPWIRE_LEGEND HOME="$TMP/home" "$BIN" "$TMP/$d" --no-cache "$@" < /dev/null 2>/dev/null ); }
attr(){ python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<path [^>]*>",t); a=re.search(r"\s"+sys.argv[1]+r"=\"([^\"]*)\"",m.group(0)) if m else None; print(a.group(1) if a else "-")' "$1"; }
rows(){ python3 -c 'import re,sys; t=sys.stdin.read(); print(" ".join(re.findall(r"<s [^>]*n=\"([^\"]*)\"",t)))'; }

# (R)
R="$( run r --path=start_entry,Sink.sink_call )"
if [ "$( attr reachable <<<"$R" )" = 0 ] && [ "$( attr route_hedged <<<"$R" )" = not-proven ] && [ "$( attr route_by_name <<<"$R" )" = 4 ] && [ "$( attr route_cands <<<"$R" )" = 81 ] \
   && [ -z "$( rows <<<"$R" )" ] && [ "$( attr next <<<"$R" )" != - ] && [ "$( attr next <<<"$R" | cut -c1-10 )" = --callees= ]; then
    ok "(R) a 4-hop by-name chain (route_cands 81) is refused: reachable=0 route_hedged=not-proven, no hop rows, next=--callees"
else
    no "(R) refuse: $( grep -o '<path [^>]*>' <<<"$R" ) rows=[$( rows <<<"$R" )]"
fi
if grep -q 'Decoy' <<<"$R"; then no "(R) the decoy rides in the answer"; else ok "(R) no decoy row"; fi
# (P)
P="$( run p --path=start_entry,Sink.fin )"
if [ "$( attr route_hedged <<<"$P" )" = proven-preferred ] && [ "$( attr reachable <<<"$P" )" = 1 ] && [ "$( attr hops <<<"$P" )" = 6 ] && ! grep -q 'via="name"' <<<"$P"; then
    ok "(P) the proven 6-hop chain prints over the by-name shortcut (route_hedged=proven-preferred)"
else
    no "(P) proven-preferred: $( grep -o '<path [^>]*>' <<<"$P" ) rows=[$( rows <<<"$P" )]"
fi
# (PS) a split arm is a guess: the proven-only search must not take it
PS="$( run ps --path=Chain.startEntry,Sink.fin )"
if [ "$( attr route_hedged <<<"$PS" )" = name-stitched ] && [ "$( attr route_by_name <<<"$PS" )" = 3 ] && [ "$( attr hops <<<"$PS" )" = 3 ] && ! grep -q 'prov="split"' <<<"$PS"; then
    ok "(PS) a chain through a split arm is not proven-preferred: the by-name shortcut prints hedged (route_hedged=name-stitched)"
else
    no "(PS) split arm under a proven label: $( grep -o '<path [^>]*>' <<<"$PS" ) rows=[$( rows <<<"$PS" )] split=$( grep -c 'prov="split"' <<<"$PS" )"
fi
# (PI) the one-implementor edge is a proven edge (its row says via="impl"): still preferred
PI="$( run pi --path=Chain.startEntry,Sink.fin )"
if [ "$( attr route_hedged <<<"$PI" )" = proven-preferred ] && [ "$( attr hops <<<"$PI" )" = 6 ] && grep -q 'via="impl"' <<<"$PI" && ! grep -q 'via="name"' <<<"$PI"; then
    ok "(PI) the one-implementor edge stays proven: the 6-hop chain prints (route_hedged=proven-preferred, via=impl on its row)"
else
    no "(PI) impl control: $( grep -o '<path [^>]*>' <<<"$PI" ) rows=[$( rows <<<"$PI" )]"
fi
# (H)
H="$( run h --path=start_entry,Sink.finish )"
if [ "$( attr route_hedged <<<"$H" )" = name-stitched ] && [ "$( attr route_by_name <<<"$H" )" = 2 ] && [ "$( attr reachable <<<"$H" )" = 1 ] && [ "$( attr hops <<<"$H" )" = 2 ]; then
    ok "(H) a 2-hop by-name chain prints hedged (route_hedged=name-stitched route_by_name=2)"
else
    no "(H) hedge: $( grep -o '<path [^>]*>' <<<"$H" )"
fi
# (N1)
N1="$( run n1 --path=start_entry,leaf )"
if [ "$( attr reachable <<<"$N1" )" = 1 ] && [ "$( attr route_hedged <<<"$N1" )" = - ]; then ok "(N1) one by-name hop: no route_hedged="; else no "(N1) $( grep -o '<path [^>]*>' <<<"$N1" )"; fi
# (N2)
N2="$( run n2 --path=start_entry,Delta.u4 )"
if [ "$( attr reachable <<<"$N2" )" = 1 ] && [ "$( attr route_cands <<<"$N2" )" = 1 ] && [ "$( attr route_hedged <<<"$N2" )" = unlikely ] && [ "$( attr route_by_name <<<"$N2" )" = 4 ]; then
    ok "(N2) four by-name hops with one candidate each: route_hedged=unlikely, printed, never refused"
else
    no "(N2) $( grep -o '<path [^>]*>' <<<"$N2" )"
fi
# (N3)
N3="$( run n3 --path=start_entry,Sink.sink_call )"
if [ "$( attr reachable <<<"$N3" )" = 1 ] && [ "$( attr route_by_name <<<"$N3" )" = 3 ] && [ "$( attr route_hedged <<<"$N3" )" = name-stitched ]; then
    ok "(N3) three by-name hops with two candidates each: hedged and printed, never refused"
else
    no "(N3) $( grep -o '<path [^>]*>' <<<"$N3" )"
fi
# (B64) / (B63) the knob's edge
B64="$( run b64 --path=start_entry,Sink.sink_call )"
if [ "$( attr route_cands <<<"$B64" )" = 64 ] && [ "$( attr route_hedged <<<"$B64" )" = not-proven ] && [ "$( attr reachable <<<"$B64" )" = 0 ]; then
    ok "(B64) route_cands exactly 64 with 4 by-name hops is refused"
else
    no "(B64) $( grep -o '<path [^>]*>' <<<"$B64" )"
fi
B63="$( run b63 --path=start_entry,Sink.sink_call )"
if [ "$( attr route_cands <<<"$B63" )" = 63 ] && [ "$( attr route_hedged <<<"$B63" )" = unlikely ] && [ "$( attr reachable <<<"$B63" )" = 1 ] \
   && [ "$( rows <<<"$B63" | wc -w | tr -d ' ' )" = 5 ] && [ "$( attr next <<<"$B63" )" != - ]; then
    ok "(B63) route_cands 63 with 4 by-name hops is hedged and printed whole (5 rows), with a next= to verify it"
else
    no "(B63) $( grep -o '<path [^>]*>' <<<"$B63" ) rows=[$( rows <<<"$B63" )]"
fi
# (N4) / (N5) a true DI chain through interfaces: hedged and printed, never refused
N4="$( run n4 --path=App.serve,Conn.execute )"
if [ "$( attr reachable <<<"$N4" )" = 1 ] && [ "$( attr route_by_name <<<"$N4" )" = 4 ] && [ "$( attr route_hedged <<<"$N4" )" = unlikely ] \
   && [ "$( rows <<<"$N4" | wc -w | tr -d ' ' )" = 5 ]; then
    ok "(N4) a true 4-hop TypeScript DI chain (route_cands $( attr route_cands <<<"$N4" )) is hedged and printed whole, never refused"
else
    no "(N4) $( grep -o '<path [^>]*>' <<<"$N4" ) rows=[$( rows <<<"$N4" )]"
fi
N5="$( run n5 --path=App.Serve,Conn.Execute )"
if [ "$( attr reachable <<<"$N5" )" = 1 ] && [ "$( attr route_by_name <<<"$N5" )" = 4 ] && [ "$( attr route_hedged <<<"$N5" )" = unlikely ] \
   && [ "$( rows <<<"$N5" | wc -w | tr -d ' ' )" = 5 ]; then
    ok "(N5) a true 4-hop Go DI chain (route_cands $( attr route_cands <<<"$N5" )) is hedged and printed whole, never refused"
else
    no "(N5) $( grep -o '<path [^>]*>' <<<"$N5" ) rows=[$( rows <<<"$N5" )]"
fi
# (N6) five by-name hops, one candidate each
N6="$( run n6 --path=Pump.prevent,Clamp.step_d )"
if [ "$( attr reachable <<<"$N6" )" = 1 ] && [ "$( attr route_by_name <<<"$N6" )" = 5 ] && [ "$( attr route_cands <<<"$N6" )" = 1 ] \
   && [ "$( attr route_hedged <<<"$N6" )" = unlikely ]; then
    ok "(N6) five by-name hops with one candidate each: hedged and printed, never refused"
else
    no "(N6) $( grep -o '<path [^>]*>' <<<"$N6" )"
fi
# (U) a hedge of >= 4 by-name hops says it is unlikely, and what route_cands does not count; next= rides
ulegend(){ local mode=$1 a=$2; case $a in
    B63) run b63 --legend="$mode" --path=start_entry,Sink.sink_call;;
    N4)  run n4 --legend="$mode" --path=App.serve,Conn.execute;;
    *)   run n6 --legend="$mode" --path=Pump.prevent,Clamp.step_d;;
    esac; }
for a in B63 N4 N6; do
    full="$( ulegend full "$a" )"
    cmp="$( ulegend compact "$a" )"
    nx="$( attr next <<<"$full" )"
    if grep -q 'UNLIKELY' <<<"$full" && grep -q 'builtin and external receivers are not counted, so a low count is no proof' <<<"$full" \
       && grep -q 'builtin and external receivers are not counted, so a low count is no proof' <<<"$cmp" && [ "$nx" != - ] \
       && [ "$( attr route_hedged <<<"$full" )" = unlikely ] && grep -q 'route_hedged=unlikely' <<<"$full" && grep -q '=unlikely' <<<"$cmp"; then
        ok "(U) $a: the >= 4-hop hedge is route_hedged=unlikely on the root, both legends define it, says route_cands counts in-repo definitions only, and carries a next="
    else
        no "(U) $a: next=[$nx] unlikely=$( grep -c UNLIKELY <<<"$full" ) fullclause=$( grep -c 'a low count is no proof' <<<"$full" ) compactclause=$( grep -c 'a low count is no proof' <<<"$cmp" )"
    fi
done
# with the hop-body next= off (RIPWIRE_NO_HOP_BODY) the root has no other next=, so a >= 4-hop hedge names from='s callees (shell-safe)
U2="$( RIPWIRE_NO_HOP_BODY=1 run b63 --path=start_entry,Sink.sink_call )"
if [ "$( attr route_hedged <<<"$U2" )" = unlikely ] && [ "$( attr next <<<"$U2" )" = "--callees=m.py:start_entry" ]; then
    ok "(U) B63 without the hop-body next=: the >= 4-hop hedge names from='s callees"
else
    no "(U) B63 no-hop-body: $( grep -o '<path [^>]*>' <<<"$U2" )"
fi
# a 2-hop hedge is NOT called unlikely and carries no next=
if grep -q 'UNLIKELY' <<<"$( run h --legend=full --path=start_entry,Sink.finish )" || [ "$( attr next <<<"$H" )" != - ]; then no "(U) H: a 2-hop hedge is called unlikely or carries next="; else ok "(U) H: a 2-hop hedge is neither unlikely nor given a next="; fi
# the compact path purpose no longer says "when none" in front of a refusal
if grep -q 'reachable=0 hops=0 when none shown' <<<"$( run r --legend=compact --path=start_entry,Sink.sink_call )"; then ok "(U) compact legend: reachable=0 hops=0 when none shown (a refusal is not none)"; else no "(U) compact path purpose still says 'when none'"; fi
# (S) the refusal's next= pastes into a shell as ONE argument
RS="$( run rs --path=start_entry,Sink.sink_call )"
nx="$( attr next <<<"$RS" | python3 -c 'import html,sys; print(html.unescape(sys.stdin.read().strip()))' )"
if [ "$( attr route_hedged <<<"$RS" )" = not-proven ] && [ -n "$nx" ] && sh -n -c "set -- $nx" 2>/dev/null && [ "$( sh -c "set -- $nx; echo \$#" 2>/dev/null )" = 1 ] \
   && [ "$( sh -c "set -- $nx; printf '%s' \"\$1\"" 2>/dev/null | cut -c1-10 )" = --callees= ]; then
    ok "(S) a refusal under a directory with a space: next= is one shell argument ($nx)"
else
    no "(S) next=[$nx] argc=$( sh -c "set -- $nx; echo \$#" 2>/dev/null )"
fi
# (PM) a pairs answer: two start_entry definitions
PM="$( run pm --path=start_entry,Sink.sink_call )"
if [ "$( attr pairs_reaching <<<"$PM" )" != - ] && [ "$( attr reachable <<<"$PM" )" = 1 ] && [ "$( attr route_hedged <<<"$PM" )" = unlikely ] \
   && [ "$( attr route_by_name <<<"$PM" )" = 4 ] && [ "$( attr route_cands <<<"$PM" )" = 81 ]; then
    ok "(PM) a pairs answer carries the hedge on its first pair's chain (route_by_name=4 route_cands=81), never refused"
else
    no "(PM) $( grep -o '<path [^>]*>' <<<"$PM" )"
fi
# (L)
fullof(){ case $1 in
    R) run r --legend=full --path=start_entry,Sink.sink_call;;
    P) run p --legend=full --path=start_entry,Sink.fin;;
    H) run h --legend=full --path=start_entry,Sink.finish;;
    *) run n1 --legend=full --path=start_entry,leaf;;
    esac; }
for a in R P H N1; do
    full="$( fullof "$a" )"
    if grep -q 'route_hedged=' <<<"$full"; then
        if python3 -c 'import re,sys; sys.exit(0 if any("route_hedged=" in c for c in re.findall(r"<!--(.*?)-->",sys.stdin.read(),re.S)) else 1)' <<<"$full"; then ok "(L) $a: the legend clause rides with route_hedged="; else no "(L) $a: route_hedged= without its legend clause"; fi
    else
        if grep -q 'route_hedged' <<<"$full"; then no "(L) $a: legend clause without the attribute"; else ok "(L) $a: no attribute, no clause"; fi
    fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '<r>%s</r>' "$full" | xmllint --noout - 2>/dev/null; then ok "(L) $a parses"; else no "(L) $a: xmllint"; fi
    fi
done
# (M) MCP path_between: same verdict and rows
mcp(){ local d=$1 f=$2 t=$3; printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"g","version":"0"}}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"path_between\",\"arguments\":{\"path\":\"$TMP/$d\",\"from\":\"$f\",\"to\":\"$t\"}}}" \
    | ( cd "$TMP/$d" || exit 1; HOME="$TMP/home" "$BIN" --mcp --mcp-legend=inline 2>/dev/null ) | python3 -c 'import json,sys
for l in sys.stdin:
    try: m=json.loads(l)
    except Exception: continue
    if m.get("id")==2: print("".join(c.get("text","") for c in m.get("result",{}).get("content",[])))'; }
for a in R P H N4; do
    if [ "$a" = R ]; then cli="$R"; m="$( mcp r start_entry Sink.sink_call )"
    elif [ "$a" = P ]; then cli="$P"; m="$( mcp p start_entry Sink.fin )"
    elif [ "$a" = N4 ]; then cli="$N4"; m="$( mcp n4 App.serve Conn.execute )"
    else cli="$H"; m="$( mcp h start_entry Sink.finish )"; fi
    if [ -z "$m" ]; then no "(M) $a: no MCP answer"; continue; fi
    if [ "$( attr route_hedged <<<"$m" )" = "$( attr route_hedged <<<"$cli" )" ] && [ "$( attr reachable <<<"$m" )" = "$( attr reachable <<<"$cli" )" ] \
       && [ "$( attr route_by_name <<<"$m" )" = "$( attr route_by_name <<<"$cli" )" ] && [ "$( rows <<<"$m" )" = "$( rows <<<"$cli" )" ]; then
        ok "(M) $a: path_between carries the CLI's verdict and rows"
    else
        no "(M) $a: MCP $( grep -o '<path [^>]*>' <<<"$m" | head -1 ) vs CLI $( grep -o '<path [^>]*>' <<<"$cli" )"
    fi
done
# (F) --for graph_verb block
F="$( run r '--for=path from start_entry to Sink.sink_call' )"
blk="$( python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<graph_verb[^>]*>.*?</graph_verb>",t,re.S); print(m.group(0) if m else "")' <<<"$F" )"
if [ -z "$blk" ]; then
    no "(F) no <graph_verb> block on the --for path subject"
elif [ "$( attr route_hedged <<<"$blk" )" = not-proven ] && [ -z "$( rows <<<"$blk" )" ]; then
    ok "(F) the --for <graph_verb> block refuses the same chain"
else
    no "(F) $( grep -o '<path [^>]*>' <<<"$blk" )"
fi
[ "$fail" = 0 ] && echo "pathroutecheck: PASS" || echo "pathroutecheck: FAIL"
exit "$fail"
