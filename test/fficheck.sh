#!/usr/bin/env bash
# fficheck.sh — the A4-R5 cross-language FFI binding-edge gate.
#
#   test/fficheck.sh                       # uses build/ripwire on test/ffifix
#   RIPWIRE_BIN=asan/ripwire test/fficheck.sh
#
# Fixture test/ffifix/ exercises the three wave-1 binding patterns:
#   pybind11 (module.cpp)  m.def("fast_transform",&fast_transform_impl) + Solver::step;
#                          caller.py calls ffimod.fast_transform(...) and solver.step(...).
#   extern "C" (clib.cpp)  extern-C clib_scale(); user.py loads a CDLL and calls lib.clib_scale(...).
#   JNI (jni.cpp)          Java_com_example_Foo_bar → decoded readable Java name.
#   CONTROL (control.py)   a LOCAL Python def `combine` colliding with the pybind alias "combine"
#                          (bound to combine_impl) — the local def MUST win, no false binding edge.
#
# Asserts: (a) --callers on the C++ target finds the Python call site + binding provenance is visible;
# (b) --impact crosses the language border; (c) determinism; (d) NO false edge to the C++ target when a
# same-name local Python def exists; (e) xmllint-clean output. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/ffifix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "fficheck: BIN=$BIN  CORPUS=$CORPUS"

callers(){ "$BIN" "$CORPUS" --callers="$1" --no-cache 2>/dev/null; }
count_of(){ printf '%s' "$1" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*'; }

# --- (c) determinism ---------------------------------------------------------------------------------
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical, $(wc -c <"$TMP/a" | tr -d ' ') B)" || no "determinism (non-deterministic output)"
MAP="$(cat "$TMP/a")"

# --- (a) pybind: --callers on the C++ target finds the Python call site ------------------------------
C="$( callers fast_transform_impl )"
[ "$( count_of "$C" )" = "1" ] && printf '%s' "$C" | grep -q 'caller.py' \
  && ok "pybind free-fn: fast_transform_impl called from caller.py (cross-language)" \
  || { no "pybind free-fn: expected 1 caller in caller.py"; printf '    %s\n' "$C"; }

C="$( callers step )"
[ "$( count_of "$C" )" = "1" ] && printf '%s' "$C" | grep -q 'caller.py' \
  && ok "pybind method: Solver::step called from caller.py (cross-language)" \
  || { no "pybind method: expected 1 caller in caller.py"; printf '    %s\n' "$C"; }

# --- (a) extern-C / ctypes: --callers finds the Python ctypes call site ------------------------------
C="$( callers clib_scale )"
printf '%s' "$C" | grep -q 'user.py' \
  && ok "extern-C ctypes: clib_scale called from user.py (cross-language, low-confidence)" \
  || { no "extern-C ctypes: expected a caller in user.py"; printf '    %s\n' "$C"; }

# --- (a) provenance visible: binding edges carry the amb= honesty mark + header ambiguous>0 ----------
#   run_pipeline (caller.py) has 2 binding edges → amb="2"; scale_via_ctypes (user.py) has 1 → amb="1".
#   The precise prov="binding" label rides outProv=2, pending the reported serialize.h one-liner.
printf '%s' "$MAP" | grep -q 'n="run_pipeline" amb="2"' \
  && ok "provenance: binding edges surface amb=\"2\" on the Python caller (verify-in-source mark)" \
  || { no "provenance: run_pipeline missing amb=\"2\""; }
AMBIG="$( printf '%s' "$MAP" | grep -o 'ambiguous=[0-9]*' | grep -o '[0-9]*' )"
[ "${AMBIG:-0}" -ge 1 ] && ok "provenance: header ambiguous=$AMBIG reflects the binding edges" || no "provenance: header ambiguous count not raised"

# --- (b) --impact crosses the language border -------------------------------------------------------
IMP="$( "$BIN" "$CORPUS" --impact=fast_transform_impl --no-cache 2>/dev/null )"
printf '%s' "$IMP" | grep -q 'caller.py' && ok "impact: fast_transform_impl blast radius reaches caller.py" || { no "impact: border not crossed"; printf '    %s\n' "$IMP"; }
IMP="$( "$BIN" "$CORPUS" --impact=clib_scale --no-cache 2>/dev/null )"
printf '%s' "$IMP" | grep -q 'user.py' && ok "impact: clib_scale blast radius reaches user.py" || { no "impact: extern-C border not crossed"; printf '    %s\n' "$IMP"; }

# --- (d) CONTROL: a same-name local Python def wins — NO false binding edge --------------------------
C="$( callers combine_impl )"
[ "$( count_of "$C" )" = "0" ] \
  && ok "control: combine_impl has NO caller (local Python combine won — no false binding edge)" \
  || { no "control: combine_impl gained a false cross-language edge"; printf '    %s\n' "$C"; }
C="$( callers combine )"
printf '%s' "$C" | grep -q 'control.py' \
  && ok "control: the LOCAL combine resolves the control.py call (same-language §2a wins)" \
  || { no "control: local combine call not resolved locally"; printf '    %s\n' "$C"; }

# --- (JNI) the mangled export is captured; readable decode is rendered as bind= on the default map ----
printf '%s' "$MAP" | grep -q 'Java_com_example_Foo_bar' \
  && ok "JNI: Java_com_example_Foo_bar def captured" \
  || no "JNI: Java_ export not captured"
printf '%s' "$MAP" | grep -q 'n="Java_com_example_Foo_bar"[^>]* bind="com.example.Foo.bar"' \
  && ok "JNI: bind=\"com.example.Foo.bar\" rendered on the mangled def (readable alias)" \
  || { no "JNI: bind= attribute missing or wrong value on Java_com_example_Foo_bar"; printf '    %s\n' "$MAP" | grep -o '<s[^>]*Java_com_example_Foo_bar[^>]*>'; }

# --- (e) xmllint-clean --------------------------------------------------------------------------------
printf '%s' "$MAP" | xmllint --noout - 2>/dev/null && ok "xmllint: default map is well-formed" || no "xmllint: default map malformed"

echo
[ "$fail" = "0" ] && { echo "fficheck: ALL PASS"; exit 0; } || { echo "fficheck: FAILURES"; exit 1; }
