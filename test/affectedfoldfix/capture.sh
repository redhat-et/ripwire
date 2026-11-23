#!/usr/bin/env bash
# capture.sh BIN FIXDIR OUTDIR — the calls affectedfoldcheck.sh makes, one file per call, plus rc.txt. Run from anywhere:
# every call is made with FIXDIR as cwd and the fixture named by its bare directory, so root= is the same bytes everywhere.
# golden/ is this script's output for the binary at 994f0021f (before the fold); the gate runs it again on the binary
# under test.
set -u
BIN="$1"; FIX="$2"; OUT="$3"; mkdir -p "$OUT"; : > "$OUT/rc.txt"
cd "$FIX" || exit 2
one(){ # name fixture args...
    local name="$1" fx="$2"; shift 2
    "$BIN" "$fx" "$@" > "$OUT/$name" 2> "$OUT/$name.err"; echo "$name $?" >> "$OUT/rc.txt"
}
for fx in big small brace odd; do
    case "$fx" in big) ch="pkg/core.py,web/lib.ts" ;; *) ch="pkg/core.py" ;; esac
    case "$fx" in small) ex="tests/test_s1.py" ;; odd) ex="sub/w.y.py" ;; *) ex="tests/unit/alpha/test_a01.py" ;; esac
    one "$fx.affected.xml"       "$fx" "--affected=$ch"
    one "$fx.affected.full.xml"  "$fx" "--affected=$ch" --legend=full
    one "$fx.test-gate.xml"      "$fx" "--test-gate=$ch"
    one "$fx.test-gate.full.xml" "$fx" "--test-gate=$ch" --legend=full
    one "$fx.test-gate.json"     "$fx" "--test-gate=$ch" --json
    one "$fx.situ.txt"           "$fx" "--situ=$ch"
    one "$fx.exercises.xml"      "$fx" "--exercises=$ex"
    one "$fx.pack-task.xml"      "$fx" "--pack-task=change core_value in pkg/core.py"
done
find "$OUT" -name '*.err' -size 0 -delete
