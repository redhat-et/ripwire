#!/usr/bin/env bash
# ccjsoncheck.sh — gate for Wave-4: --export=cc.json[:FILE] (CodeCharta interchange export).
#
# Runs --export=cc.json on test/fixture and asserts:
#   - valid JSON (python3 -m json.tool)
#   - top-level shape: projectName, apiVersion="1.3", nodes[] with a root Folder
#   - folder tree: sub/consumer.cpp nests under a "sub" Folder
#   - expected File nodes present (all 6 fixture files)
#   - attribute values sane: LOC of geometry.cpp == wc -l, fan_in of geometry.h > 0
#   - determinism (byte-identical run-to-run)
#   - the :FILE form writes valid JSON to disk
#
# Usage:
#   test/ccjsoncheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/ccjsoncheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]  || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ]  || { echo "no fixture dir at $FIX"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required for JSON validation"; exit 2; }
echo "ccjsoncheck: BIN=$BIN"

# ── Run --export=cc.json to stdout ──────────────────────────────────────────────────────────────────
CC="$TMP/cc.json"
"$BIN" "$FIX" --export=cc.json --no-cache >"$CC" 2>/dev/null
[ -s "$CC" ] || { no "cc.json output is empty"; echo; echo "SOME CHECKS FAILED"; exit 1; }

# valid JSON
python3 -m json.tool "$CC" >/dev/null 2>&1 \
    && ok "valid JSON (python3 -m json.tool)" \
    || no "invalid JSON"

# structural + attribute assertions in one python pass
python3 - "$CC" "$FIX" <<'PY'
import json, sys, os
cc, fixdir = sys.argv[1], sys.argv[2]
d = json.load(open(cc))
errs = []

if d.get("apiVersion") != "1.3": errs.append("apiVersion != 1.3 (got %r)" % d.get("apiVersion"))
if not d.get("projectName"):     errs.append("missing projectName")
if not isinstance(d.get("nodes"), list) or not d["nodes"]: errs.append("nodes[] missing/empty")

root = d["nodes"][0]
if root.get("type") != "Folder": errs.append("root node is not a Folder")

# collect File nodes by relative path + note folders seen
files = {}
folders = set()
def walk(n, p=""):
    fp = (p + "/" + n["name"]) if p else n["name"]
    if n["type"] == "File":
        files[fp] = n["attributes"]
    else:
        folders.add(n["name"])
        for c in n.get("children", []): walk(c, fp)
walk(root)

# expected fixture files (relative to fixture root, under the synthetic "root" folder)
expected = ["app.py","geometry.cpp","geometry.h","notes.md","related.md","sub/consumer.cpp"]
for e in expected:
    key = "root/" + e
    if key not in files: errs.append("missing File node: %s" % key)

# folder tree: a "sub" folder must exist (consumer.cpp nests under it)
if "sub" not in folders: errs.append("no 'sub' Folder (folder tree not built from path)")

# attribute sanity: LOC of geometry.cpp == wc -l
gc = files.get("root/geometry.cpp")
if gc is None:
    errs.append("geometry.cpp node missing for LOC check")
else:
    with open(os.path.join(fixdir, "geometry.cpp"), "rb") as f:
        wc = f.read().count(b"\n")   # wc -l counts newlines
    if gc["loc"] != wc: errs.append("geometry.cpp loc=%d != wc -l=%d" % (gc["loc"], wc))
    for k in ("symbols","cx","cognitive_cx","fan_in","fan_out","churn"):
        if k not in gc: errs.append("geometry.cpp missing attribute %s" % k)

# fan_in of geometry.h should be > 0 (included by geometry.cpp and sub/consumer.cpp)
gh = files.get("root/geometry.h")
if gh is None: errs.append("geometry.h node missing")
elif gh["fan_in"] <= 0: errs.append("geometry.h fan_in should be > 0, got %d" % gh["fan_in"])

if errs:
    print("STRUCTFAIL")
    for e in errs: print("  " + e)
    sys.exit(1)
print("STRUCTOK")
print("  geometry.cpp loc=%d (== wc -l)" % files["root/geometry.cpp"]["loc"])
print("  geometry.h  fan_in=%d" % files["root/geometry.h"]["fan_in"])
PY
if [ $? -eq 0 ]; then
    ok "structure: apiVersion 1.3, root Folder, folder tree, all File nodes, sane attributes"
else
    no "structure/attribute assertions failed (see above)"
fi

# ── Determinism ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --export=cc.json --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIX" --export=cc.json --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism: byte-identical run-to-run" || no "determinism: output differs"

# ── :FILE form writes valid JSON to disk ────────────────────────────────────────────────────────────
OF="$TMP/out.cc.json"
"$BIN" "$FIX" --export=cc.json:"$OF" --no-cache >/dev/null 2>&1
{ [ -s "$OF" ] && python3 -m json.tool "$OF" >/dev/null 2>&1; } \
    && ok "--export=cc.json:FILE writes valid JSON to disk" \
    || no "--export=cc.json:FILE did not produce valid JSON at $OF"

# ── Summary ─────────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
