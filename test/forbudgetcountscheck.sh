#!/usr/bin/env bash
# forbudgetcountscheck.sh — under `--for --token-budget=N`, `<sigs past_target="K">` and `<sigs files_first="N">` count rows the
# agent RECEIVED.
#
# THE CLAIMS: past_target=K counts the shown rows past the default 7.5 KB target (graphlegend.h kForPastTargetNote; the render
# records them as the K highest global ranks shown: serialize.h sigsCutRecordPastTargetRanks), files_first=N counts the shown rows
# the head round-robin moved (serialize.h kForFilesFirstNote, reorderHeadRoundRobin). Both readings are present-only. The CLI
# answer under a budget is the UNBUDGETED answer U shed afterwards (forbudgetfit.h, TOKEN-BUDGET-MONOTONE); its rows:N unit cuts
# the worst r= first. Before lane HN1 the fitter wrote past_target= as U's K less the rows cut — true only if the past rows were
# the LAST rows, which the round-robin (it lifts other files' best rows, past-target ones included, into r=1..8) and the docs
# reorder (doc rows take the worst r=) both break — and files_first= as min(U's N, rows kept), true only if every kept row was a
# moved one. Measured by HN1 on GA1 DEV n=87 (base 0e32486b5): files_first= claimed more moved rows than were shown on 83 of 87
# answers at --token-budget=1600, and the past_target= reading stayed with no attribute on 74. Now both are recounted over the
# rows kept (absent at 0, each reading with its attribute).
#
# FIXTURES (generated in TMP): (a) one strong file leads score order, so the round-robin lifts four other files' rows — past-target
# rows among them — into the head; (b) four distinct files lead it, so the round-robin moves only rows past rank 4 (a 4-row answer
# keeps none); (c) test/forcompletefix/ts (the forsigspancheck / fordocsaftercodecheck fixture: docs outrank code) plus five more
# code files, so U passes the target AND moves a doc row below the code rows — the shed cuts that doc row first.
#
# ARMS, per fixture:
#   (O)  ORACLE premise: from the score-order twin (RIPWIRE_NO_HEAD_RR=1 RIPWIRE_NO_DOCS_AFTER_CODE=1, r= = global rank) the
#        past rows are its last K rows; the round-robin is RE-IMPLEMENTED here (8 head slots, a file and a name once, docs may not
#        open a slot while the docs reorder runs) and must reproduce U's printed row order exactly, its moved count = U's N.
#   (P)/(F) EXACT: every answer (U and the --token-budget sweep) prints past_target= / files_first= equal to how many of those
#        rows it shows (absent at 0), each reading iff its attribute, and shows only U's rows.
#   (C)  COVERAGE premise over the sweep, per attribute: an answer where the pre-HN1 formula is false, an answer that keeps
#        none of the rows (attribute and reading gone), and one that keeps some but not all — a sweep that stops producing one is
#        a FAIL, never a quiet pass.
#   (N)  NEGATIVE CONTROLS: the checker must FAIL mutated answers — the pre-HN1 value put back where it was false, U with
#        files_first= removed, a partial answer with past_target= +1, an all-shed answer with the files_first reading put back.
#   (R)  the past_target reading states no POSITION the rows contradict (owner ruling 191): on every answer whose shown past rows
#        are NOT its last K rows by r= (the round-robin lifts them; the docs reorder pushes doc rows below them), the reading must
#        not place them ("last"/"first"/"top"/"bottom"/"final"/"leading"/"trailing" K). Premise: the sweep holds such an answer; (N)
#        puts the pre-ruling reading ("the last K rows are past ...") back into one and the checker must FAIL it.
#   (W)  every answer is well formed (xmllint) and deterministic (run twice, byte-identical).
#
# FLOOR, named: a "doc row" is read by its p= extension (.md .markdown .rst .adoc .org .mdx — the Lang::Markdown rows of
# ingest_crawl.h kLangTable), as fordocsaftercodecheck reads it; "a name once" compares the n= tail after the last :: . or #.
#
# Exits non-zero on any failure.

set -u
# θ5 (src/forpages.h): this gate reads the FULL page-1 legend of a default --for answer (or pins its bytes/rows); the default's
# core legend is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TS="$ROOT/test/forcompletefix/ts"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"   # a private warm cache (forsigspancheck: a shared one is a stderr flake)
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$TS" ] || { echo "fixture missing: $TS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required (W)"; exit 2; }
echo "forbudgetcountscheck: BIN=$BIN"

python3 - "$TMP" "$TS" <<'PY'
import os, shutil, sys
tmp, ts = sys.argv[1], sys.argv[2]
def fn(o, stem, i, reps):
    o.write("/* %s%s step %d builds one gadget from its parts, validating every part against the catalogue before it is placed and logged */\n" % ("gadget assembler " * reps, stem, i))
    o.write("int %sGadgetAssembler%d( int partCount, const char* catalogueName, double toleranceMillimetres, unsigned long serialNumber ) { return partCount + %d; }\n\n" % (stem, i, i))
a = tmp + "/fa/src"; os.makedirs(a)
for stem, n, strong in [("assembler", 14, 3), ("catalogue", 8, 1), ("inspector", 8, 1), ("packer", 8, 1), ("ledger", 8, 1)]:
    with open("%s/%s.c" % (a, stem), "w") as o:
        for i in range(n): fn(o, stem, i, strong if i < 6 else 1)
b = tmp + "/fb/src"; os.makedirs(b)
for k, stem in enumerate(["alpha", "bravo", "charlie", "delta"]):
    with open("%s/%s.c" % (b, stem), "w") as o:
        fn(o, stem, 0, 5)
        for i in range(1, 12 if k == 0 else 1): fn(o, stem, i, 3)
for stem in ["echo", "foxtrot", "golf", "hotel"]:
    with open("%s/%s.c" % (b, stem), "w") as o:
        for i in range(6): fn(o, stem, i, 1)
shutil.copytree(ts, tmp + "/fc")
for stem in ["session", "tenant", "scope", "binder", "tracker"]:
    with open("%s/fc/src/%s.ts" % (tmp, stem), "w") as o:
        o.write("export class %sContextFactory {\n" % stem.capitalize())
        for i in range(7):
            o.write("  // Create the per-request context for a %s request, step %d of building the context\n" % (stem, i))
            o.write("  createRequestContext%d( requestIdentifier: string, incomingHeaders: Record<string, string>, deadlineMilliseconds: number, retryBudget: number ): Context%d { return new Context%d(); }\n" % (i, i, i))
        o.write("}\n")
        for i in range(7): o.write("export class Context%d {}\n" % i)
PY
[ $? -eq 0 ] || { echo "forbudgetcountscheck: could not generate the fixtures"; exit 2; }

BUDGETS="1000 2000 2500 2800 3000"
# run FIX OUT ENV... -- ARGS... : one call, twice (W); stdout decoded to the element form (test/rowlines.py) beside the raw bytes
run(){
    local fix="$1" out="$2"; shift 2; local envs=(); while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    ( cd "$TMP/$fix" && env "${envs[@]}" "$BIN" . --no-cache "$@" >"$out.raw" 2>"$out.err" ); printf '%s' "$?" >"$out.rc"
    ( cd "$TMP/$fix" && env "${envs[@]}" "$BIN" . --no-cache "$@" >"$out.again" 2>/dev/null )
    python3 "$ROOT/test/rowlines.py" <"$out.raw" >"$out" 2>/dev/null || printf 'decode-failed' >"$out.rc"
}
ANSWERS=()
for fix in fa fb fc; do
    case "$fix" in fc) Q='How is a per-request context created?' ;; *) Q='gadget assembler' ;; esac
    run "$fix" "$TMP/$fix.twin" RIPWIRE_NO_HEAD_RR=1 RIPWIRE_NO_DOCS_AFTER_CODE=1 -- "--for=$Q"
    run "$fix" "$TMP/$fix.u" X=1 -- "--for=$Q"
    for b in $BUDGETS; do run "$fix" "$TMP/$fix.b$b" X=1 -- "--for=$Q" "--token-budget=$b"; ANSWERS+=( "$TMP/$fix.b$b" ); done
    ANSWERS+=( "$TMP/$fix.u" )
    for f in "$TMP/$fix.twin" "$TMP/$fix.u" "$TMP/$fix".b*; do
        case "$f" in *.raw|*.err|*.rc|*.again) continue ;; esac
        [ "$( cat "$f.rc" )" = 0 ] || no "${f##*/}: rc=$( cat "$f.rc" )"
        cmp -s "$f.raw" "$f.again" || no "(W) ${f##*/}: two runs differ"
        xmllint --noout "$f.raw" 2>/dev/null || no "(W) ${f##*/}: xmllint rejects the answer"
    done
done

python3 - "$TMP" $BUDGETS <<'PY'
import os, re, sys
T, budgets = sys.argv[1], sys.argv[2:]
DOC_EXTS = (".md", ".markdown", ".rst", ".adoc", ".org", ".mdx")
ATTR = {"past": "past_target", "ff": "files_first"}
READING = {"past": "[sigs past_target=K:", "ff": "[files_first=N:"}
POSITIONAL = re.compile(r"\b(last|first|top|bottom|final|leading|trailing)\s+(K|N|\d+)\b", re.I)
OLD_PAST_READING = ("[sigs past_target=K: the last K rows are past the budget_bytes target, served because they are rows of the ranked head;"
                    " none is cut]")
fails = 0
def say(ok, msg):
    global fails
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); fails += 0 if ok else 1
def attrs(t): return dict(re.findall(r'\s([a-z_]+)="([^"]*)"', t))
def read(doc):
    bare = re.sub(r"<!--.*?-->", "", doc, flags=re.S)
    m = re.search(r"<sigs\b([^>]*)>(.*?)</sigs>", bare, re.S)
    if not m: raise ValueError("no <sigs> block")
    rows = [attrs(" " + a) for _, a in re.findall(r"<([dt])\s([^>]*?)/?>", m.group(2))]
    return attrs(" " + m.group(1)), rows
def key(a): return "%s|%s" % (a.get("p", ""), a.get("n", a.get("sym", "")))
def is_doc(a): return a.get("p", "").lower().endswith(DOC_EXTS)
def num(tag, k): return int(tag.get(k, "0") or 0)
def bare_name(n): return re.split(r"::|\.|#", n or "")[-1]
def head_rr(rows, may_open):
    order, taken, files, names = [], [False] * len(rows), [], []
    for i, a in enumerate(rows):
        if len(order) >= 8: break
        nm = bare_name(a.get("n", a.get("sym")))
        if not may_open(a) or a.get("p") in files or nm in names: continue
        order.append(i); taken[i] = True; files.append(a.get("p")); names.append(nm)
    return order + [i for i in range(len(rows)) if not taken[i]]
def oracle(fix):
    """(U doc, {attr: set of U r= values}, U row count) — or raise with the premise that failed"""
    twin_tag, twin = read(open(os.path.join(T, fix + ".twin")).read())
    udoc = open(os.path.join(T, fix + ".u")).read()
    utag, urows = read(udoc)
    trows = sorted(twin, key=lambda a: int(a.get("r", "0") or 0))
    if sorted(map(key, trows)) != sorted(map(key, urows)): raise ValueError("U and its score-order twin show different rows")
    byk = {}
    for a in sorted(urows, key=lambda a: int(a.get("r", "0") or 0)): byk.setdefault(key(a), []).append(a.get("r"))
    seen, t2u = {}, []
    for a in trows:   # same-key rows keep score order through both reorders: the j-th of a key in the twin is the j-th in U
        k = key(a); j = seen.get(k, 0); seen[k] = j + 1; t2u.append(byk[k][j])
    K = num(twin_tag, "past_target")
    if K != num(utag, "past_target"): raise ValueError("twin past_target=%d, U past_target=%d" % (K, num(utag, "past_target")))
    past = {t2u[i] for i in range(len(trows) - K, len(trows))}
    o = head_rr(trows, lambda a: not is_doc(a)); ordered = [trows[i] for i in o]
    final = [a for a in ordered if not is_doc(a)] + [a for a in ordered if is_doc(a)]
    if [key(a) for a in final] != [key(a) for a in urows]: raise ValueError("the re-implemented round-robin + docs reorder does not reproduce U's order")
    moved = {t2u[i] for k, i in enumerate(o) if i != k}
    if len(moved) != num(utag, "files_first"): raise ValueError("oracle moved %d rows, U files_first=%d" % (len(moved), num(utag, "files_first")))
    return udoc, {"past": past, "ff": moved}, len(urows)
def check(doc, U, sets):
    """the attributes' claims against the shown rows: (failures, {attr: (printed, true)})"""
    bad, out = [], {}
    tag, rows = read(doc)
    ur = {a.get("r"): key(a) for a in read(U)[1]}
    stray = [a.get("r") for a in rows if ur.get(a.get("r")) != key(a)]
    if stray: bad.append("premise: %d shown row(s) are not U's rows (r=%s)" % (len(stray), stray[0]))
    shown = {a.get("r") for a in rows}
    for k in ("past", "ff"):
        printed, true = num(tag, ATTR[k]), len(shown & sets[k])
        out[k] = (printed, true)
        if printed != true: bad.append("%s=%s but %d of its rows are shown (of %d rows)" % (ATTR[k], printed or "absent", true, len(rows)))
        if (READING[k] in doc) != (printed > 0): bad.append("%s reading %s, attribute %s" % (ATTR[k], "present" if READING[k] in doc else "absent", printed or "absent"))
    # (R): where the shown past rows are not the last K rows by r=, a reading that places them there is false
    pastShown = sorted(int(r) for r in shown & sets["past"])
    lastK = sorted(int(a.get("r")) for a in rows)[len(rows) - len(pastShown):] if pastShown else []
    out["contradicted"] = bool(pastShown) and pastShown != lastK
    clause = re.search(r"\[sigs past_target=K:[^\]]*\]", doc)
    if out["contradicted"] and clause and POSITIONAL.search(clause.group(0)):
        bad.append("(R) the past_target reading places its rows (%r) but they are r=%s, not the last %d" % (POSITIONAL.search(clause.group(0)).group(0), pastShown, len(pastShown)))
    return bad, out, len(rows)

cover = {k: {"formula_false": 0, "none_kept": 0, "partial": 0} for k in ("past", "ff")}
ctl = {"formula": None, "partial_past": None, "none_ff": None, "contradicted": None}
contradicted = 0
for fix in ("fa", "fb", "fc"):
    try:
        U, sets, nU = oracle(fix)
    except (ValueError, KeyError, IndexError) as e:
        say(False, "(O) %s premise: %s" % (fix, e)); continue
    say(True, "(O) %s: the oracle reproduces U's order (%d rows, past_target=%d, files_first=%d)" % (fix, nU, len(sets["past"]), len(sets["ff"])))
    for b in ["u"] + ["b" + x for x in budgets]:
        doc = open(os.path.join(T, fix + "." + b)).read()
        try:
            bad, out, n = check(doc, U, sets)
        except (ValueError, KeyError) as e:
            say(False, "(P/F) %s.%s: %s" % (fix, b, e)); continue
        for x in bad: say(False, "(P/F) %s.%s: %s" % (fix, b, x))
        if not bad:
            say(True, "(P/F) %s.%s: %d rows, past_target=%s, files_first=%s" % (fix, b, n, out["past"][0] or "absent", out["ff"][0] or "absent"))
        if out.get("contradicted"):
            contradicted += 1
            ctl["contradicted"] = ctl["contradicted"] or (doc, U, sets, "%s.%s" % (fix, b))
        cut = nU - n
        for k in ("past", "ff"):
            u, true = len(sets[k]), out[k][1]
            if not u or not cut: continue
            formula = max(u - cut, 0) if k == "past" else min(u, n)
            if formula != true:
                cover[k]["formula_false"] += 1
                ctl["formula"] = ctl["formula"] or (doc, U, sets, k, formula, "%s.%s" % (fix, b))
            if true == 0: cover[k]["none_kept"] += 1
            if 0 < true < u: cover[k]["partial"] += 1
            if k == "past" and 0 < true < u: ctl["partial_past"] = ctl["partial_past"] or (doc, U, sets, true, "%s.%s" % (fix, b))
            if k == "ff" and true == 0: ctl["none_ff"] = ctl["none_ff"] or (doc, U, sets, "%s.%s" % (fix, b))
    if fix == "fb": ctl["U"] = (U, sets)
for k in ("past", "ff"):
    for what, n in cover[k].items():
        say(n > 0, "(C) %s: %d answer(s) in the sweep where %s" % (ATTR[k], n, {"formula_false": "the pre-HN1 formula is false", "none_kept": "none of its rows is kept",
                                                                             "partial": "some but not all of its rows are kept"}[what]))
say(contradicted > 0, "(R) premise: %d answer(s) in the sweep whose shown past_target rows are not their last rows by r=" % contradicted)
print("(N) negative controls: the checker must FAIL each mutated answer")
def sigs_tag(doc): return re.search(r"<sigs\b[^>]*>", re.sub(r"<!--.*?-->", "", doc, flags=re.S)).group(0)
def set_attr(doc, name, val):
    t = sigs_tag(doc); t2 = re.sub(r'\s%s="[0-9]+"' % name, "", t)
    t2 = t2 if val == 0 else t2.replace("<sigs", '<sigs %s="%d"' % (name, val), 1)
    return doc.replace(t, t2, 1)
def expect_fail(label, doc, U, sets):
    bad = check(doc, U, sets)[0]
    say(bool(bad), "(N) %s: %s" % (label, ("caught (%s)" % bad[0]) if bad else "the checker passed a false count (vacuous)"))
if None in (ctl["formula"], ctl["partial_past"], ctl["none_ff"]) or "U" not in ctl:
    say(False, "(N) premise: no answer to mutate")
else:
    doc, U, sets, k, formula, at = ctl["formula"]
    expect_fail("%s with the pre-HN1 %s=%d put back" % (at, ATTR[k], formula), set_attr(doc, ATTR[k], formula), U, sets)
    U2, sets2 = ctl["U"]
    expect_fail("fb's unbudgeted answer with files_first= removed", set_attr(U2, "files_first", 0), U2, sets2)
    doc, U, sets, true, at = ctl["partial_past"]
    expect_fail("%s with past_target=%d (one more than shown)" % (at, true + 1), set_attr(doc, "past_target", true + 1), U, sets)
    doc, U, sets, at = ctl["none_ff"]
    expect_fail("%s with the files_first reading put back" % at, doc.replace("-->", " [files_first=N: x] -->", 1), U, sets)
if ctl["contradicted"] is None:
    say(False, "(N) premise: no answer whose past rows contradict a positional reading")
else:
    doc, U, sets, at = ctl["contradicted"]
    mut = re.sub(r"\[sigs past_target=K:[^\]]*\]", lambda m: OLD_PAST_READING, doc, count=1)
    say(mut != doc, "(N) premise: %s carries a past_target reading to replace" % at)
    expect_fail("%s with the pre-ruling positional reading put back" % at, mut, U, sets)
sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "forbudgetcountscheck: FAIL"; exit 1; fi
echo "forbudgetcountscheck: PASS"
