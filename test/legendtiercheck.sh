#!/usr/bin/env bash
# legendtiercheck.sh — BAND K (tiers): a legend tier never claims a definition the reader does not hold
# (docs/EVALS.md, pre-registration 2026-11-17, amendment 11; src/legenddict.h, src/legendpacks.h).
#
# WHAT THIS GUARDS. `--legend-have=` is an assertion by the caller: "these definitions are in my context, leave them
# out". Until this band the only holding the binary could be told about was the whole dictionary (about 130 KB, about
# 131 calls to repay), so the handshake was a net loss for every ordinary session. A dictionary is now served in
# TIERS — a core of 13 lines, and core + one verb's pack — each with a version that hashes exactly its own lines.
# The saving is not the bar. The bar is the reader:
#
#   K1  HELD OR CARRIED. Every definition a default answer carries is, under every holding, either in the text of a
#       tier the call passed or in a comment of that same answer. Bar 0. An answer that got shorter by leaving out a
#       definition its reader was never sent FAILS here, whatever it saved.
#   K2  IDENTITY. A tier's version is FNV-1a 64 of exactly its lines; two tiers share a version only if they are the
#       same lines; <about have=> names exactly what was passed; a value that is no tier of this binary refuses the
#       whole call, even beside a valid one; a valid pack on another schema's answer is honoured.
#   K3  A PACK EARNS ITS PLACE: it costs at most 3x what it saves per call of its verb. Per pack, never a mean.
#   K4  THE REPAYMENT ARITHMETIC IS PINNED: core <= 1,536 B, ceil(B/S) <= 12, no core entry under 25 % of the cells.
#       A core that quietly grows back toward the dictionary goes red here while K1 stays green.
#   K5  NOTHING LOST: same rows, same root attributes, never longer.   K6  DETERMINISM: same argv, same bytes.
#
# GRAIN. Every figure is at answer (cell) grain, per verb. None is the grader's item or symbol/file grain, none is
# "recall", and K3 is per pack. The cells are a FIXTURE built here; the 453-cell corpus readout lives in docs/EVALS.md.
#
# THREE OUTPUT TOKENS. An arm prints a value, ABSENT (nothing to measure — never a pass by itself) or UNREACHABLE (the
# binary cannot produce the thing to measure — a FAIL). No mean is taken over an empty list.
#
# MUTATION CONTROLS run on EVERY invocation: M1–M10 are applied to a copy of what this run collected, and each must
# turn its named arm red. Five protect the reader (M1–M5). The matrix printed at the end is M11: which arm fails
# under which mutant, so an arm with no independent evidence is visible.
#
#   bash test/legendtiercheck.sh "$PWD/build/ripwire"
#   LEGENDTIER_SHOW=1 … prints every failing cell, not the first three per arm.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"
echo "legendtiercheck: BIN=$BIN"
fail=0

# ── the fixture: C with tests, an interface with implementors, JS with a top-level call (the <file-scope> owner),
#    names defined twice (clamp, scale: the <def ix=> / of_def= rows a real --callers answer carries), and
#    one file no grammar reads (graph_unindexed=) ─────────────────────────────────────────────────────────────────────
FX="$TMP/fx"
mkdir -p "$FX/src" "$FX/tests" "$FX/web" "$FX/docs"
cat >"$FX/src/core.c" <<'EOF'
#include "shape.h"
static int clamp(int v) { return v < 0 ? 0 : v; }
int helper(int x) { return clamp(x) + 1; }
int work(int x) { return helper(x) * 2; }
int area(const struct shape *s) { return s->ops->area(s) + helper(0); }
int total(const struct shape *a, const struct shape *b) { return area(a) + area(b) + work(1); }
int unused_entry(int q) { return clamp(q) - 1; }
int main(void) { return total(0, 0) + work(2); }
EOF
cat >"$FX/src/shape.h" <<'EOF'
struct shape;
struct shape_ops { int (*area)(const struct shape *); };
struct shape { const struct shape_ops *ops; int w, h; };
int helper(int);
int work(int);
int area(const struct shape *);
EOF
cat >"$FX/src/rect.c" <<'EOF'
#include "shape.h"
static int rect_area(const struct shape *s) { return s->w * s->h + helper(1); }
const struct shape_ops rect_ops = { rect_area };
EOF
cat >"$FX/src/tri.c" <<'EOF'
#include "shape.h"
static int clamp(int v) { return v > 9 ? 9 : v; }
int scale(int v) { return clamp(v) * 3; }
static int tri_area(const struct shape *s) { return clamp(s->w * s->h / 2) + helper(2) + scale(1); }
const struct shape_ops tri_ops = { tri_area };
EOF
for n in a b c d e f g h i j; do
    printf 'int work(int);\nint helper(int);\nint test_%s(void) { return work(1) == 4 && helper(1) == 2; }\n' "$n" >"$FX/tests/test_$n.c"
done
cat >"$FX/web/app.js" <<'EOF'
class Emitter { emit(name) { return name; } on(name) { return this; } }
class Bus extends Emitter { emit(name) { return render(name); } }
class Hub extends Emitter { emit(name) { return format(name); } }
function format(v) { return String(v).trim(); }
function render(v) { return format(v) + "!"; }
function boot() { return render("x"); }
boot();
render(format("top"));
function scale(v) { return format(v) + render(v); }
scale(1);
module.exports = { format, render, boot, Emitter, Bus, Hub };
EOF
cat >"$FX/web/only.js" <<'EOF'
module.exports = function (obj, keys) { return keys.reduce((r, k) => { r[k] = obj[k]; return r; }, {}); };
EOF
cat >"$FX/web/app.test.js" <<'EOF'
const { render } = require("./app");
test("render", () => { expect(render("a")).toBe("a!"); });
EOF
printf '# Notes\nThe `work` function doubles `helper`; `render` decorates `format`.\n' >"$FX/docs/README.md"
printf 'select 1;\n' >"$FX/src/legacy.sql"
( cd "$FX" && git init -q . && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm init ) \
    || { echo "  FAIL  the fixture repository could not be created"; echo "FAILURES"; exit 1; }

# The pack table is a build product of the committed census (bar: byte-identical, so membership cannot be hand-tuned).
if [ -f "$ROOT/bench/legendtier/packs_build.py" ]; then
    if python3 "$ROOT/bench/legendtier/packs_build.py" --check >"$TMP/packs.out" 2>&1; then
        echo "  PASS  (P0) src/legendpacks.h is what bench/legendtier/packs_build.py writes from the committed census"
    else
        echo "  FAIL  (P0) src/legendpacks.h differs from the census's product: $( head -c 300 "$TMP/packs.out" )"; fail=1
    fi
else
    echo "  FAIL  (P0) UNREACHABLE: bench/legendtier/packs_build.py does not exist — the pack table has no generator"; fail=1
fi

cat >"$TMP/arms.py" <<'PY'
import copy, math, os, re, subprocess, sys
BIN, FX = sys.argv[1], sys.argv[2]
SHOW = os.environ.get("LEGENDTIER_SHOW") == "1"

def run(*args):
    p = subprocess.run([BIN, *args], capture_output=True)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")

# ── parsing ──────────────────────────────────────────────────────────────────────────────────────────────────────────
PUR  = re.compile(r"ripwire\.([\w.-]+)/v1 <[^>]*>: ")
CMT  = re.compile(r"<!--.*?-->", re.S)
CDAT = re.compile(r"<!\[CDATA\[.*?\]\]>", re.S)
OPEN = re.compile(r"<!-- ripwire ([\w.-]+) schema=ripwire\.([\w.-]+)/v1: ")
ABOUT = re.compile(r'<about((?:\s+[\w:.-]+="[^"]*")*)\s*/>')
ATTR = re.compile(r'([A-Za-z_][\w:.-]*)="([^"]*)"')
TAG  = re.compile(r"<([A-Za-z_][\w.-]*)((?:\s+[\w:.-]+=\"[^\"]*\")*)\s*/?>")
STRUCTURAL = ("<about ", "schema=ripwire.KEY", "window:", "X_capped=", "under ref,", "have=")

def fnv(lines):
    h = 14695981039346656037
    for line in lines:
        for b in (line + "\n").encode():
            h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h

class Tier:
    """One serving of the dictionary as the binary printed it: head line, N entry lines, an optional closing line."""
    def __init__(self, text):
        self.text = text
        ls = text.split("\n")
        self.head = ls[0] if ls else ""
        m = re.search(r"\b(?:have|dictv)=([0-9a-f]{16})\b", self.head)
        n = re.search(r"\bentries=(\d+)\b", self.head)
        self.version = m.group(1) if m else None
        self.count = int(n.group(1)) if n else None
        self.lines = ls[1:1 + self.count] if self.count is not None else []
    def bodies(self):
        out = set()
        for l in self.lines:
            out.add(l)
            m = PUR.match(l)
            if m:
                out.add(l[m.end():])
        return out
    def rebuilt(self, lines, keep_version=False):
        ls = self.text.split("\n")
        tail = ls[1 + (self.count or 0):]
        head = re.sub(r"\bentries=\d+", "entries=%d" % len(lines), self.head)
        if not keep_version and self.version:
            head = head.replace(self.version, fnv(lines))
        return Tier("\n".join([head] + list(lines) + tail))

def strip_noise(x):
    return CMT.sub("", CDAT.sub("", x))

def comments(x):
    return " ".join(m.group(0) for m in CMT.finditer(CDAT.sub("", x)))

def legend_of(doc):
    for m in CMT.finditer(doc):
        o = OPEN.match(m.group(0))
        if o:
            return o.group(2), m.group(0)[o.end():-3].rstrip()
    return None, None

def decompose(doc, full):
    """The default legend's clauses: (dictionary bodies it carries, what no dictionary line accounts for)."""
    key, body = legend_of(doc)
    if key is None:
        return None, [], ""
    text = " " + body
    found = []
    for l in full.lines:
        m = PUR.match(l)
        if m and m.group(1) == key and text.startswith(" " + l[m.end():] + "."):
            found.append(l[m.end():]); text = text[len(l[m.end():]) + 2:]
            break
    terms = sorted({l for l in full.lines if not PUR.match(l) and not l.startswith("for: ")}, key=lambda s: (-len(s), s))
    for t in terms:
        at = text.find(" " + t + ".")
        if at >= 0:
            found.append(t); text = text[:at] + "\x00" + text[at + len(t) + 2:]
    resid = []
    for part in text.split("\x00"):
        part = part.strip()
        if not part:
            continue
        # the two clauses the core holds generically, spelled per answer: the window, and the sub-caps
        part = re.sub(r"^window: (?:[a-z_]+= ?)+\(capped=1 cut(?:; next_offset= pastes as offset=)?\)\.", "\x01", part).strip()
        part = re.sub(r"(?:^|\x01 ?)[a-z_/=]*_capped=(?:/[a-z_]*_capped=)*: 1 = cut\.", "\x02", part).strip()
        resid.append(part)
    return key, found, " ".join(resid)

def is_ref(doc):
    m = ABOUT.search(strip_noise(doc))
    return bool(m) and 'legend="ref"' in m.group(0)

def have_of(doc):
    m = ABOUT.search(strip_noise(doc))
    h = re.search(r'\bhave="([^"]*)"', m.group(0)) if m else None
    return h.group(1) if h else None

def root_and_body(doc):
    x = strip_noise(doc)
    m = re.match(r"\s*(?:<\?xml[^>]*\?>\s*)?<([A-Za-z_][\w.-]*)\b[^>]*>", x)
    if not m:
        return None
    close = "</%s>" % m.group(1)
    j = x.rfind(close)
    return m.group(0), ABOUT.sub("", x[m.end():j] if j > m.end() else "")

def row_multiset(body):
    """Rows as (tag, sorted attrs), a <g n= p="a,b"> group counted as its rows (the ref posture un-groups it)."""
    out = []
    for m in TAG.finditer(body):
        tag, attrs = m.group(1), dict(ATTR.findall(m.group(2)))
        if tag == "g" and "p" in attrs and "n" in attrs:
            rest = sorted((k, v) for k, v in attrs.items() if k not in ("p", "n"))
            out += [("g-row", tuple([("p", q)] + rest)) for q in attrs["p"].split(",")]
        else:
            flat = sorted(attrs.items())
            out.append(("g-row" if tag in ("test", "t") and attrs.get("run_unknown") == "1" else tag, tuple(flat)))
    return sorted(out)

# ── collection ───────────────────────────────────────────────────────────────────────────────────────────────────────
CELLS = [("callers", s) for s in ("helper", "work", "scale", "render", "format", "clamp")]
CELLS += [("callees", s) for s in ("work", "total", "main", "render", "boot", "area")]
CELLS += [("impact", s) for s in ("helper", "work", "clamp", "format", "render", "area")]
CELLS += [("uses", s) for s in ("helper", "work", "area", "render", "format", "clamp")]
CELLS += [("grep", s) for s in ("helper", "work", "area", "render", "format", "shape")]
CELLS += [("around", s) for s in ("work", "helper", "area", "render", "format", "total")]
CELLS += [("expand", s) for s in ("work", "helper", "total", "render", "boot", "only")]
CELLS += [("affected", f) for f in ("src/core.c", "src/shape.h", "src/rect.c", "web/app.js", "src/tri.c")]
CELLS += [("pack-task", t) for t in ("change how helper clamps", "render a string with a suffix", "compute the area of a shape",
                                     "double the work result", "format a value")]
CELLS += [("lego", s) for s in ("Emitter", "shape_ops")]
CELLS += [("dead-code", None), ("whereis", "helper"), ("whereis", "render")]
# schemas the census never measured (their tier is the core alone); --notes and --flags have so little legend that the
# reduced answer is not shorter, which is the inline-kept outcome
CELLS += [("naming-consistency", None), ("notes", None), ("flags", None)]
CELLS += [("for", t) for t in ("change how helper clamps", "render a string with a suffix")]

def argv(cell):
    verb, arg = cell
    return ["--" + verb + ("=" + arg if arg is not None else "")]

def collect():
    d = {"refusals": {}}
    rc, out, _ = run("--legend-dict")
    d["full"] = Tier(out) if rc == 0 else None
    rc, out, err = run("--legend-dict=core")
    d["core"] = Tier(out) if rc == 0 and out else None
    d["core_err"] = err.strip()[:160]
    rc, out, _ = run("--legend-dict=roster")
    d["roster"] = out if rc == 0 else ""
    d["packs"], d["census"] = {}, {}
    rc, out, _ = run("--legend-dict=tiers")
    for line in out.splitlines() if rc == 0 else []:
        f = line.split("\t")
        if len(f) >= 5 and f[0] not in ("core", "full"):
            prc, ptext, _ = run("--legend-dict=" + f[0])
            if prc == 0:
                d["packs"][f[0]] = Tier(ptext)
                d["census"][f[0]] = int(f[4])
    d["cells"] = []
    for cell in CELLS:
        a = [FX] + argv(cell)
        rc, out, err = run(*a)
        key, _ = legend_of(out)
        m = re.search(r'schema="ripwire\.([\w.-]+)/v1"', out[:4000])
        key = key or (m.group(1) if m else None)
        c = {"cell": cell, "verb": cell[0], "key": key, "runs": {"none": (rc, out, err)}, "again": {}}
        holds = {}
        if d["full"] and d["full"].version:
            holds["full"] = (d["full"].version, "full")
        if d["core"] and d["core"].version:
            holds["core"] = (d["core"].version, "core")
            own = key if key in d["packs"] and d["census"].get(key, 0) > 0 else None
            if own:
                holds["own"] = (d["packs"][own].version, "core+" + own)
            other = next((k for k in ("callers", "grep", "impact") if k != key and k in d["packs"] and d["census"].get(k, 0) > 0), None)
            if other:
                holds["other"] = (d["packs"][other].version, "core+" + other)
        c["holds"] = holds
        for h, (v, _) in holds.items():
            c["runs"][h] = run(*a, "--legend-have=" + v)
            c["again"][h] = run(*a, "--legend-have=" + v)
        c["again"]["none"] = run(*a)
        d["cells"].append(c)
    # the refusals K2(d) names
    a = [FX, "--callers=helper"]
    d["refusals"]["unknown"] = ("0123456789abcdef", run(*a, "--legend-have=0123456789abcdef"))
    base = d["core"].version if d["core"] and d["core"].version else (d["full"].version if d["full"] else None)
    if base:
        off = base[:-1] + ("0" if base[-1] != "0" else "1")
        d["refusals"]["one-digit-off"] = (off, run(*a, "--legend-have=" + off))
        d["refusals"]["valid+unknown"] = ("0123456789abcdef", run(*a, "--legend-have=" + base + ",0123456789abcdef"))
    return d

# ── the arms ─────────────────────────────────────────────────────────────────────────────────────────────────────────
def tier_for(d, c, h):
    if h == "full":  return d["full"]
    if h == "core":  return d["core"]
    if h == "own":   return d["packs"].get(c["holds"]["own"][1][5:])
    if h == "other": return d["packs"].get(c["holds"]["other"][1][5:])
    return None

def evaluate(d, k2a=True):
    F = {a: [] for a in ("R0", "K1", "K2a", "K2b", "K2c", "K2d", "K2e", "K3", "K4a", "K4b", "K4c", "K5", "K6", "C4", "NV")}
    info = {}
    full, core = d["full"], d["core"]
    if not full or not full.lines:
        F["K2a"].append("UNREACHABLE: --legend-dict printed no dictionary")
        return F, info
    roster = [l.split("\t") for l in d["roster"].splitlines() if l.count("\t") == 2]
    roster = [r for r in roster if r[2] in ("term", "attr", "window")]
    if not roster:
        F["R0"].append("the roster is empty — K1 would pass with nothing to check")
    tiers = {"full": full}
    if core: tiers["core"] = core
    tiers.update(d["packs"])

    # K2(a) each tier's version is the hash of exactly the lines it prints
    for name, t in tiers.items():
        if t.version is None or t.count is None:
            F["K2a"].append("%s: line 1 names no version/entries= (%s)" % (name, t.head[:80]))
        elif len(t.lines) != t.count or fnv(t.lines) != t.version:
            F["K2a"].append("%s: have=%s but its %d line(s) hash to %s" % (name, t.version, len(t.lines), fnv(t.lines)))
        elif name != "full" and not set(t.lines) <= set(full.lines):
            F["K2a"].append("%s: prints a line the dictionary does not hold" % name)
    if not core:
        F["K2a"].append("UNREACHABLE: --legend-dict=core is refused (%s) — no holding smaller than the dictionary exists" % d["core_err"])
    # K2(b) versions pairwise distinct unless the line sets are equal
    names = sorted(tiers)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if tiers[a].version == tiers[b].version and set(tiers[a].lines) != set(tiers[b].lines):
                F["K2b"].append("%s and %s share have=%s with different lines" % (a, b, tiers[a].version))
    # K2(d) a value that is no tier refuses the whole call
    for label, (value, (rc, out, err)) in d["refusals"].items():
        if rc == 0 or out or value not in err or "--legend-dict=core" not in err:
            F["K2d"].append("%s: rc=%d stdout=%dB stderr names value=%s core command=%s" % (label, rc, len(out), value in err, "--legend-dict=core" in err))
    if "one-digit-off" not in d["refusals"]:
        F["K2d"].append("UNREACHABLE: no tier version to perturb")

    held_bodies = {name: t.bodies() for name, t in tiers.items()}
    held_text = {name: "\n".join(t.lines) for name, t in tiers.items()}
    posture = {}
    nv = dict(carry=0, zero_carry=0, not_applicable=0, inline_kept=0, modscope=0, key_differs=0, no_census=0)
    savings = {"core": [], "full": [], "own": []}
    pack_gain = {}
    core_freq = {}
    n_cells = len(d["cells"])
    for c in d["cells"]:
        rc0, base, _ = c["runs"]["none"]
        name = "%s=%s" % c["cell"]
        if rc0 != 0 or not base:
            F["K5"].append("%s: the default answer failed (rc=%d, %dB)" % (name, rc0, len(base)))
            continue
        key, clauses, resid = decompose(base, full)
        if "MODULE SCOPE" in (legend_of(base)[1] or ""): nv["modscope"] += 1
        if key and key != c["verb"]: nv["key_differs"] += 1
        if core and key and d["census"].get(key, 0) == 0: nv["no_census"] += 1
        for b in clauses:
            core_freq[b] = core_freq.get(b, 0) + 1
        for h in ("none", "core", "own", "other", "full"):
            if h not in c["runs"]:
                continue
            rc, doc, err = c["runs"][h]
            if c["again"][h][:2] != (rc, doc):
                F["K6"].append("%s under %s: two runs differ" % (name, h))
            if h == "none":
                continue
            if rc != rc0:
                F["K5"].append("%s under %s: rc %d, default %d" % (name, h, rc, rc0)); continue
            ref = is_ref(doc)
            said = "not-applicable" if "not-applicable" in err else "inline-kept" if "inline-kept" in err else None
            state = "ref" if ref else (said or "unsaid")
            posture.setdefault((c["verb"], h), []).append(state)
            if not ref:
                if doc != base:
                    F["K5"].append("%s under %s: served without the ref pointer, yet it differs from the default answer" % (name, h))
                if state == "unsaid":
                    F["C4"].append("%s under %s: served inline and stderr does not say inline-kept or not-applicable" % (name, h))
                if h == "core" and state == "not-applicable": nv["not_applicable"] += 1
                if state == "inline-kept": nv["inline_kept"] += 1
                if h in savings: savings[h].append(0)
                if h == "own": pack_gain.setdefault(c["holds"]["own"][1][5:], []).append(0)
                continue
            # K2(c) have= names exactly what was passed; K2(e) a pack on another schema's answer is honoured
            want = c["holds"][h][1]
            if have_of(doc) != want:
                F["K2e" if h == "other" else "K2c"].append("%s under %s: have=%r, passed %r" % (name, h, have_of(doc), want))
            # K1 held or carried — against the tier PASSED, never the answer's own claim
            t = tier_for(d, c, h)
            tname = {"full": "full", "core": "core"}.get(h) or c["holds"][h][1][5:]
            mine = comments(doc)
            carried = 0
            for b in clauses:
                if b in held_bodies[tname]:
                    continue
                if b in mine:
                    carried += 1
                    continue
                F["K1"].append("%s under %s: %s — dropped, in no tier passed and not in the answer" % (name, h, b[:48]))
            for part in [p for p in re.split(r"[\x01\x02]", resid) if p.strip()]:
                if part.strip() not in mine:
                    F["K1"].append("%s under %s: UNENTERED clause, no dictionary line and not in the answer: %s" % (name, h, part.strip()[:60]))
            if "\x01" in resid and not any(l.startswith("window:") for l in t.lines):
                F["K1"].append("%s under %s: the window clause was dropped and the tier holds no window: line" % (name, h))
            if "\x02" in resid and not any(l.startswith("X_capped=") for l in t.lines):
                F["K1"].append("%s under %s: a sub-cap clause was dropped and the tier holds no X_capped= line" % (name, h))
            tags = [(m.group(1), dict(ATTR.findall(m.group(2)))) for m in TAG.finditer(strip_noise(doc))]
            defined = held_text[tname] + "\n" + mine
            for attr, element, _src in roster:
                if any(attr in a and (element == "*" or tg == element) for tg, a in tags) and (attr + "=") not in defined:
                    F["K1"].append("%s under %s: roster attribute %s= is carried and defined in no tier passed nor in the answer" % (name, h, attr))
            if h == "core" and carried: nv["carry"] += 1
            if h == "own" and carried == 0: nv["zero_carry"] += 1
            # K5 nothing lost
            pa, pb = root_and_body(base), root_and_body(doc)
            if not pa or not pb:
                F["K5"].append("%s under %s: no XML root to compare" % (name, h))
            else:
                ra, rb = sorted(ATTR.findall(pa[0])), sorted(ATTR.findall(pb[0]))
                if ra != rb:
                    F["K5"].append("%s under %s: root attributes differ (%s)" % (name, h, sorted(set(ra) ^ set(rb))[:2]))
                if row_multiset(pa[1]) != row_multiset(pb[1]):
                    F["K5"].append("%s under %s: the rows differ" % (name, h))
            if len(doc.encode()) > len(base.encode()):
                F["K5"].append("%s under %s: %dB, longer than the default %dB" % (name, h, len(doc.encode()), len(base.encode())))
            if h in savings: savings[h].append(len(base.encode()) - len(doc.encode()))
            if h == "own" and "core" in c["runs"]:
                pack_gain.setdefault(c["holds"]["own"][1][5:], []).append(len(c["runs"]["core"][1].encode()) - len(doc.encode()))
    # C4: a verb whose cells all went not-applicable under a holding (--for excepted by name)
    for (verb, h), states in sorted(posture.items()):
        if verb != "for" and states and all(s == "not-applicable" for s in states):
            F["C4"].append("%s under %s: every cell is not-applicable (%d)" % (verb, h, len(states)))
    info["posture"] = posture
    # K3 per pack
    info["k3"] = {}
    for key, t in sorted(d["packs"].items()):
        gains = pack_gain.get(key, [])
        if len(gains) < 5:
            info["k3"][key] = "ABSENT n=%d" % len(gains)
            continue
        cost = len(t.text.encode()) - len(core.text.encode())
        gain = sum(gains) / len(gains)
        info["k3"][key] = "cost %d B, gain %.1f B/call, ratio %s (n=%d)" % (cost, gain, "%.2f" % (cost / gain) if gain > 0 else "inf", len(gains))
        if cost > 3 * gain:
            F["K3"].append("%s: costs %d B for %.1f B per call — over 3x" % (key, cost, gain))
    if core and not any(v for k, v in info["k3"].items() if not v.startswith("ABSENT")):
        F["K3"].append("ABSENT for every pack: no pack has 5 ref-capable cells, so K3 measured nothing")
    if not core:
        F["K3"].append("UNREACHABLE: no pack exists on this binary")
        F["K1"].append("UNREACHABLE under corev and packv: no tier smaller than the dictionary can be named")
    # K4 the repayment arithmetic — on a binary with no core the only obtainable holding is the dictionary, which is the premise
    hold = core or full
    S = savings["core" if core else "full"]
    B = len(hold.text.encode())
    if not S:
        F["K4b"].append("ABSENT: no cell measured")
    else:
        mean = sum(S) / len(S)
        q = math.ceil(B / mean) if mean > 0 else None
        info["k4"] = "B=%d S=%.1f B/call ceil(B/S)=%s n=%d (%s)" % (B, mean, q, len(S), "core" if core else "NO CORE: the whole dictionary")
        if B > 1536: F["K4a"].append("B=%d > 1,536" % B)
        if q is None or q > 12: F["K4b"].append("ceil(B/S)=%s > 12 (B=%d, S=%.1f, n=%d)" % (q, B, mean, len(S)))
    low = [l for l in hold.lines if not l.startswith(STRUCTURAL) and 4 * core_freq.get(l, 0) < n_cells]
    for l in low[:8]:
        F["K4c"].append("core line under 25 %% of the cells (%d of %d): %s" % (core_freq.get(l, 0), n_cells, l[:50]))
    if len(low) > 8: F["K4c"].append("… and %d more" % (len(low) - 8))
    # non-vacuity
    info["nv"] = nv
    if core:
        for k in ("carry", "zero_carry", "not_applicable", "modscope", "key_differs", "no_census", "inline_kept"):
            if nv[k] == 0:
                F["NV"].append("%s: 0 cells — the arm that depends on it measured nothing" % k)
    info["savings"] = {h: (sum(v), len(v)) for h, v in savings.items() if v}
    return F, info

# ── the mutants ──────────────────────────────────────────────────────────────────────────────────────────────────────
def a_core_answer_with_carry(d):
    for c in d["cells"]:
        if "core" in c["runs"] and is_ref(c["runs"]["core"][1]):
            doc = c["runs"]["core"][1]
            end = doc.find(" --><about ")
            start = doc.rfind("<!-- ", 0, end) if end >= 0 else -1
            if start >= 0 and "-->" not in doc[start:end]:
                return c, (start, end + 4)
    return None, None

def set_run(c, h, doc):
    rc, _, err = c["runs"][h]
    c["runs"][h] = (rc, doc, err); c["again"][h] = (rc, doc, err)

def m1(d):
    c, m = a_core_answer_with_carry(d)
    doc = c["runs"]["core"][1]
    set_run(c, "core", doc[:m[0]] + doc[m[1]:])
def m2(d):
    m1(d)
    for c in d["cells"]:
        if "core" in c["runs"]:
            set_run(c, "core", c["runs"]["core"][1].replace('have="core"', 'have="full"'))
def m2b(d):
    for c in d["cells"]:
        if "core" in c["runs"]:
            set_run(c, "core", c["runs"]["core"][1].replace('have="core"', 'have="full"'))
def m3b(d):
    v = d["core"].version
    d["core"] = Tier(d["core"].text.replace(v, v[:-1] + ("0" if v[-1] != "0" else "1"), 1))
def m7c(d):
    d["core"] = d["core"].rebuilt(d["core"].lines + ["under ref, a forty-byte structural line more"])
def m3(d):
    keep = [l for l in d["core"].lines if not l.startswith("next=")]
    d["core"] = d["core"].rebuilt(keep, keep_version=True)
def m4(d):
    t = d["packs"]["callers"]
    d["packs"]["callers"] = Tier(t.text.replace(t.version, d["core"].version, 1))
def m5(d):
    drop = lambda t: t.rebuilt([l for l in t.lines if "MODULE SCOPE" not in l])
    d["full"], d["core"] = drop(d["full"]), drop(d["core"])
    d["packs"] = {k: drop(t) for k, t in d["packs"].items()}
def m6(d):
    value, _ = d["refusals"]["one-digit-off"]
    d["refusals"]["one-digit-off"] = (value, d["cells"][0]["runs"]["core"])
def m7a(d):
    extra = [l for l in d["full"].lines if l not in d["core"].lines][:100]
    d["core"] = d["core"].rebuilt(d["core"].lines + extra)
def m7b(d):
    d["core"] = d["core"].rebuilt(d["full"].lines)
def m8(d):
    met = set()
    for c in d["cells"]:
        met |= set(decompose(c["runs"]["none"][1], d["full"])[1])
    never = [l for l in d["full"].lines if l not in met and not PUR.match(l) and l not in d["packs"]["grep"].lines][:40]
    d["packs"]["grep"] = d["packs"]["grep"].rebuilt(d["packs"]["grep"].lines + never)
def a_ref_with_rows(d):
    for c in d["cells"]:
        if "core" in c["runs"] and is_ref(c["runs"]["core"][1]) and c["verb"] == "callers":
            return c
def m9a(d):
    c = a_ref_with_rows(d); doc = c["runs"]["core"][1]
    m = re.search(r"<s\b[^>]*/>", doc)
    set_run(c, "core", doc[:m.start()] + doc[m.end():])
def m9b(d):
    c = a_ref_with_rows(d); doc = c["runs"]["core"][1]
    set_run(c, "core", re.sub(r'(<\w+[^>]*?\broot=")[^"]*', r"\1elsewhere", doc, count=1))
def m10(d):
    d["roster"] = ""

MUTANTS = [
    ("M1",  m1,  {"K1"},          "reader: the inline definition comment is deleted — bytes shrink, rows unchanged"),
    ("M2",  m2,  {"K1", "K2c"},   "reader: have=\"full\" over-claimed and the comment gone — the old serveAll()"),
    ("M3",  m3,  {"K2a", "K1"},   "reader: the core's text loses a line and keeps its have="),
    ("M4",  m4,  {"K2b"},         "reader: packv(callers) forced equal to corev"),
    ("M5",  m5,  {"K1"},          "reader: the module-scope reading is in no tier while answers still drop it"),
    ("M6",  m6,  {"K2d"},         "a value one digit off is served instead of refused"),
    ("M7a", m7a, {"K4a", "K4c"},  "100 real lines added to the core (K1 must stay green)"),
    ("M7b", m7b, {"K4b"},         "the core becomes the dictionary"),
    ("M8",  m8,  {"K3"},          "40 never-met lines added to the grep pack"),
    ("M9a", m9a, {"K5"},          "one row deleted"),
    ("M9b", m9b, {"K5"},          "one root attribute's value changed"),
    ("M10", m10, {"R0"},          "the roster is empty"),
    # not among the registered eleven: three single-arm mutants, so K2c, K2a and K4a each have evidence of their own
    ("M2b", m2b, {"K2c"},         "solo: have= over-claims and nothing else changes"),
    ("M3b", m3b, {"K2a"},         "solo: the core's have= is one digit off its lines"),
    ("M7c", m7c, {"K4a"},         "solo: one exempt line takes the core past 1,536 B"),
]

# ── the run ──────────────────────────────────────────────────────────────────────────────────────────────────────────
data = collect()
F, info = evaluate(data)
fails = 0
def report(arm, text):
    global fails
    bad = F[arm]
    if not bad:
        print("  PASS  (%s) %s" % (arm, text))
        return
    fails += 1
    print("  FAIL  (%s) %s — %d failure(s)" % (arm, text, len(bad)))
    for b in (bad if SHOW else bad[:3]):
        print("          %s" % b)

n = len(data["cells"])
verbs = {}
for c in data["cells"]:
    verbs[c["verb"]] = verbs.get(c["verb"], 0) + 1
print("  cells: %d — %s" % (n, ", ".join("%s %d" % kv for kv in sorted(verbs.items()))))
if data["core"]:
    print("  tiers: core %d B / %s entries; %d packs (%d with a census); full %d B / %s entries"
          % (len(data["core"].text.encode()), data["core"].count, len(data["packs"]),
             sum(1 for k in data["packs"] if data["census"].get(k, 0) > 0), len(data["full"].text.encode()), data["full"].count))
report("R0",  "the roster is read and is not empty")
report("K1",  "HELD OR CARRIED: every definition of the default answer is in a tier passed or in the answer, every cell x holding")
report("K2a", "each tier's version is FNV-1a 64 of exactly the lines it prints")
report("K2b", "tier versions are pairwise distinct unless the line sets are equal")
report("K2c", "<about have=> names exactly the tiers passed")
report("K2d", "a value that is no tier of this binary refuses the whole call, naming it and --legend-dict=core")
report("K2e", "a valid pack on another schema's answer is honoured as core+PACK")
report("K3",  "each pack with >= 5 cells costs at most 3x its per-call gain")
for key, line in sorted(info.get("k3", {}).items()):
    if not line.startswith("ABSENT") or SHOW:
        print("          K3 %-12s %s" % (key, line))
absent = sum(1 for v in info.get("k3", {}).values() if v.startswith("ABSENT"))
if absent:
    print("          K3 ABSENT for %d pack(s) with fewer than 5 cells here — not passed, not measured" % absent)
report("K4a", "the core is at most 1,536 B")
report("K4b", "ceil(B/S) <= 12")
report("K4c", "no core entry is present in fewer than 25 % of the cells (structural readings exempt by name)")
print("          K4 %s" % info.get("k4", "ABSENT"))
report("K5",  "NOTHING LOST: same rows, same root attributes, never longer; an unreduced answer is the default byte for byte")
report("K6",  "DETERMINISM: every cell x holding, twice, byte-identical")
report("C4",  "the unreduced count is a number: every inline answer says inline-kept or not-applicable; no verb is all not-applicable (--for excepted)")
by_verb = {}
for (verb, h), states in info.get("posture", {}).items():
    by_verb.setdefault(verb, {})[h] = "%d/%d/%d" % (states.count("ref"), states.count("inline-kept"), states.count("not-applicable")) + ("+%d unsaid" % states.count("unsaid") if states.count("unsaid") else "")
for verb in sorted(by_verb):
    print("          C4 %-10s ref/inline-kept/not-applicable  %s" % (verb, "  ".join("%s %s" % (h, by_verb[verb][h]) for h in ("core", "own", "other", "full") if h in by_verb[verb])))
report("NV",  "non-vacuity: inline carry, zero carry, not-applicable, inline-kept, module scope, a key unlike its flag, a schema with no census")
if "nv" in info:
    print("          NV %s" % "  ".join("%s=%d" % kv for kv in info["nv"].items()))
for h, (tot, k) in sorted(info.get("savings", {}).items()):
    print("          saving under %-4s %d B over %d cells = %.1f B per call" % (h, tot, k, tot / k))

# the mutation controls: each must turn its arm red, on a copy of what was collected
ARMS = ["R0", "K1", "K2a", "K2b", "K2c", "K2d", "K2e", "K3", "K4a", "K4b", "K4c", "K5", "K6", "C4", "NV"]
if data["core"] and data["packs"].get("callers") and data["packs"].get("grep") and not any(F[a] for a in ARMS):
    matrix = {}
    for name, fn, must, what in MUTANTS:
        d2 = copy.deepcopy(data)
        try:
            fn(d2)
            F2, i2 = evaluate(d2)
        except Exception as e:
            fails += 1
            print("  FAIL  (%s) the mutant could not be applied: %r" % (name, e))
            continue
        red = {a for a in ARMS if F2[a]}
        matrix[name] = red
        ok = must <= red
        extra = ""
        if name == "M1":
            ok = ok and any(re.search(r" under core: \S+.*— dropped", b) for b in F2["K1"])   # it names the definition lost
        if name == "M7a":
            ok = ok and "K1" not in red; extra = "; K1 stays green"
        if name == "M7b":
            q = re.search(r"ceil\(B/S\)=(\d+)", i2.get("k4", "")); ok = ok and q and int(q.group(1)) > 100
            extra = "; quotient %s" % (q.group(1) if q else "?")
        if name == "M8":
            ok = ok and len(F2["K3"]) == 1 and F2["K3"][0].startswith("grep:"); extra = "; the grep pack alone"
        if name == "M5":
            ok = ok and any("UNENTERED" in b for b in F2["K1"]); extra = "; as UNENTERED"
        if ok:
            print("  PASS  (%s) goes RED on %s%s — %s" % (name, "+".join(sorted(must)), extra, what))
        else:
            fails += 1
            print("  FAIL  (%s) must go red on %s%s, went red on {%s} — %s" % (name, "+".join(sorted(must)), extra, ",".join(sorted(red)), what))
    # M11: solo firing — an arm that never fails without another has no independent evidence
    print("  (M11) which arm fails under which mutant (the unmutated run is all green):")
    for name, _, _, _ in MUTANTS:
        if name in matrix:
            print("          %-4s %s" % (name, " ".join(sorted(matrix[name])) or "—"))
    solo = {a: [m for m, red in matrix.items() if red == {a}] for a in ARMS}
    never = [a for a in ("K1", "K2a", "K2b", "K2c", "K2d", "K3", "K4a", "K4b", "K4c", "K5", "R0") if not any(a in red for red in matrix.values())]
    print("          fires ALONE: %s" % "  ".join("%s(%s)" % (a, ",".join(m)) for a, m in solo.items() if m))
    with_others = [a for a in ("K1", "K2a", "K2b", "K2c", "K2d", "K3", "K4a", "K4b", "K4c", "K5", "R0") if not solo[a] and a not in never]
    if with_others:
        print("          fires only beside another arm: %s" % " ".join(with_others))
    if never:
        fails += 1
        print("  FAIL  (M11) no mutant turns %s red — an arm that cannot fail is not evidence" % " ".join(never))
    else:
        print("  PASS  (M11) every K arm is turned red by at least one mutant")
else:
    fails += 1
    print("  FAIL  (M) the mutation controls did not run: they need a green unmutated run with a core, a callers pack and a grep pack")
sys.exit(1 if fails else 0)
PY
python3 "$TMP/arms.py" "$BIN" "$FX" || fail=1

[ "$fail" -eq 0 ] && { echo "legendtiercheck: OK"; exit 0; }
echo "FAILURES"; exit 1
