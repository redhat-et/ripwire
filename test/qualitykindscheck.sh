#!/usr/bin/env bash
# qualitykindscheck.sh — gate for the THREE GitClear-2026-backed --quality-delta kinds ( §D#4 / §E-17):
#   error-masking            — a NEW error-masking construct (empty catch / bare-pass except / swallowed .catch)
#   short-horizon-churn      — a symbol whose FILE had ≥2 commits in the last 14 days (from git commit
#                              TIMESTAMPS vs HEAD's epoch, NOT wall-clock) that this diff rewrites again
#   new-clone-of-reused-helper — a NEW clone of an existing helper with fan-in ≥ 3 (reuse-connectivity decline)
#
# Each kind must fire ONLY on a regression vs baseline (never on pre-existing debt) and preserve the
# quality-delta exit-2 contract. Uses git-init fixtures + the auto-vs-HEAD baseline path (same idiom as
# qualitycheck.sh §7). Operates entirely in temp dirs; the repo is never touched.
#
# Usage:  RIPWIRE_BIN=build_w3/ripwire bash test/qualitykindscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualitykindscheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qualitykindscheck: BIN=$BIN  (temp corpora)"

# ── 1) ERROR-MASKING ────────────────────────────────────────────────────────────────────────────────────
#   Baseline (committed): handle() catches AND logs; a SEPARATE pre-existing empty catch lives in legacy() —
#   committed too, so it is pre-existing debt. Working-tree edit adds an EMPTY catch to handle() (the
#   regression) and does NOT touch legacy(). Assert: handle flagged, legacy NOT flagged, exit 2.
EM="$WORK/em"; mkdir -p "$EM/src"
( cd "$EM" && git init -q && git config user.email t@t && git config user.name t )
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) { log_it(); } }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
( cd "$EM" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dem(){  ( cd "$EM" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecem(){ ( cd "$EM" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 1a) clean tree (== HEAD) → zero regressions, exit 0 (the pre-existing empty catch in legacy() is NOT flagged)
[ "$( ecem )" = 0 ] && dem | grep -q 'regressions="0"' \
    && ok "error-masking: clean tree → exit 0 (pre-existing empty catch in legacy() NOT flagged)" \
    || { no "error-masking: clean tree should be clean (exit $( ecem ))"; dem | tr '>' '\n' | grep '<r '; }

# 1b) add an EMPTY catch to handle() (uncommitted) → regression fires, exit 2
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) {} }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
OEM="$( dem )"
[ "$( ecem )" = 2 ] && ok "error-masking: new empty catch → exit 2" || no "error-masking: new empty catch should exit 2 (got $( ecem ))"
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking: handle() flagged (empty catch added)" || { no "error-masking: handle() not flagged"; printf '%s\n' "$OEM" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="legacy"' \
    && no "error-masking: legacy() wrongly flagged (its empty catch is pre-existing, untouched)" \
    || ok "error-masking: pre-existing empty catch in untouched legacy() NOT flagged (contract)"

# 1c) determinism + xml
[ "$OEM" = "$( dem )" ] && ok "error-masking: delta byte-identical run-to-run" || no "error-masking: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OEM" | xmllint --noout - 2>/dev/null && ok "error-masking: xml well-formed" || no "error-masking: xml malformed"
fi

# 1d) Python bare/pass except — a second-language sanity check on the rule table.
PY="$WORK/empy"; mkdir -p "$PY"
( cd "$PY" && git init -q && git config user.email t@t && git config user.name t )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        log_it()\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
( cd "$PY" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        pass\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
OPY="$( cd "$PY" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OPY" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking (python): except: pass flagged on handle()" || { no "error-masking (python): except-pass not flagged"; printf '%s\n' "$OPY" | tr '>' '\n' | grep '<r '; }

# ── 2) SHORT-HORIZON CHURN ───────────────────────────────────────────────────────────────────────────────
#   A file committed TWICE (both within the 14-day window measured from HEAD's own commit epoch), then
#   rewritten a THIRD time in the working tree. Its symbol must flag short-horizon-churn (file ≥2 in-window
#   commits AND rewritten again). A DIFFERENT file committed only ONCE and edited must NOT flag (churn<2).
SH="$WORK/shc"; mkdir -p "$SH/src"
( cd "$SH" && git init -q && git config user.email t@t && git config user.name t )
# hot.cpp: two commits (both recent) → will be edited a third time. cold.cpp: one commit → edited once.
printf 'int hot(){ return 1; }\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int hot(){ return 2; }\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
# a SEPARATE file with only ONE commit (churn == 1 < 2 → never flags short-horizon-churn even when edited)
printf 'int lone(){ return 0; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c3single >/dev/null 2>&1 )
dsh(){  ( cd "$SH" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecsh(){ ( cd "$SH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 2a) clean tree (== HEAD) → nothing rewritten → zero short-horizon-churn regressions.
[ "$( ecsh )" = 0 ] && dsh | grep -q 'regressions="0"' \
    && ok "short-horizon-churn: clean tree → exit 0 (nothing rewritten)" \
    || { no "short-horizon-churn: clean tree should be clean (exit $( ecsh ))"; dsh | tr '>' '\n' | grep '<r '; }

# 2b) rewrite hot() (its file has 2 in-window commits) AND lone() (its file has 1) in the working tree.
printf 'int hot(){ return 3; }\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
printf 'int lone(){ return 9; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
OSH="$( dsh )"
[ "$( ecsh )" = 2 ] && ok "short-horizon-churn: rewrite of a high-churn file → exit 2" || no "short-horizon-churn: should exit 2 (got $( ecsh ))"
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="hot"' \
    && ok "short-horizon-churn: hot() flagged (file had ≥2 recent commits, rewritten again)" || { no "short-horizon-churn: hot() not flagged"; printf '%s\n' "$OSH" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="lone"' \
    && no "short-horizon-churn: lone() wrongly flagged (its file had only 1 commit < 2)" \
    || ok "short-horizon-churn: single-commit file NOT flagged even when edited (min-commits gate)"
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="cold"' \
    && no "short-horizon-churn: cold() wrongly flagged (in a churny file but NOT rewritten this diff)" \
    || ok "short-horizon-churn: untouched symbol in a churny file NOT flagged (rewrite gate)"
[ "$OSH" = "$( dsh )" ] && ok "short-horizon-churn: delta byte-identical run-to-run (deterministic)" || no "short-horizon-churn: non-deterministic delta"

# ── 3) NEW-CLONE-OF-REUSED-HELPER ────────────────────────────────────────────────────────────────────────
#   A helper accumulate() with fan-in ≥ 3 (called from three sites) is committed. The working tree adds a
#   NEW function reinvent() whose body is a Type-1/2 clone of accumulate() — reuse-connectivity decline.
#   Assert the new-clone-of-reused-helper kind fires (exit 2) and names the clone pair.
RC="$WORK/reuse"; mkdir -p "$RC/src"
( cd "$RC" && git init -q && git config user.email t@t && git config user.name t )
# accumulate() has a distinctive ≥18-token body; it is called from c1/c2/c3 → in-edge fan-in = 3.
printf 'int accumulate(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\n' >  "$RC/src/h.cpp"
printf 'int c1(){ return accumulate(); }\nint c2(){ return accumulate(); }\nint c3(){ return accumulate(); }\n' >> "$RC/src/h.cpp"
( cd "$RC" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
drc(){  ( cd "$RC" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecrc(){ ( cd "$RC" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 3a) clean tree → exit 0 (no clone group yet)
[ "$( ecrc )" = 0 ] && drc | grep -q 'regressions="0"' \
    && ok "reuse-connectivity: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity: clean tree should be clean (exit $( ecrc ))"; drc | tr '>' '\n' | grep '<r '; }

# 3b) add reinvent() — a byte-for-byte body clone of accumulate() (which has fan-in 3) in a new file.
printf 'int reinvent(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\nint user(){ return reinvent(); }\n' > "$RC/src/dup.cpp"
ORC="$( drc )"
[ "$( ecrc )" = 2 ] && ok "reuse-connectivity: new clone of a reused helper → exit 2" || no "reuse-connectivity: should exit 2 (got $( ecrc ))"
printf '%s' "$ORC" | grep -q 'kind="new-clone-of-reused-helper"' && printf '%s' "$ORC" | grep -q 'accumulate' \
    && ok "reuse-connectivity: new-clone-of-reused-helper flagged (reinvent duplicates accumulate, fan-in≥3)" \
    || { no "reuse-connectivity: new-clone-of-reused-helper missing"; printf '%s\n' "$ORC" | tr '>' '\n' | grep '<r '; }
[ "$ORC" = "$( drc )" ] && ok "reuse-connectivity: delta byte-identical run-to-run (deterministic)" || no "reuse-connectivity: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$ORC" | xmllint --noout - 2>/dev/null && ok "reuse-connectivity: xml well-formed" || no "reuse-connectivity: xml malformed"
fi

# ── 4) SELF vs AMBIENT CHURN (B10.2d, signal-to-noise round 2) ─────────────────────────────────────────────
#   A symbol that already clears the three short-horizon-churn gates above gets a further split: does THIS
#   uncommitted diff modify a pre-existing line that was itself last committed inside the churn window (SELF —
#   genuine thrash, stays major, facet churn="self"), or does it only ADD new lines / touch lines that predate
#   the window (AMBIENT — the file is hot but this edit isn't touching hot content) → sev="minor",
#   facet churn="ambient". Three sub-cases: 4a in-place edit of a recently-committed line (self, control — the
#   existing hot()-flagged assertions in §2 above already cover this shape, so this control just names the
#   facet); 4b a pure line-count-growing insertion into an already window-churned function (ambient: adds
#   lines); 4c an edit that touches a line whose real last commit predates the window even though the FILE
#   is churn-hot from unrelated recent activity (ambient: touches cold lines — needs a backdated commit via
#   GIT_AUTHOR_DATE/GIT_COMMITTER_DATE, same idiom rankbycheck.sh/ownerscheck.sh already use).
commit_at(){ local dir="$1" ts="$2" msg="$3"; git -C "$dir" add -A >/dev/null 2>&1
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_DATE="$ts" \
        git -C "$dir" commit -q -m "$msg" >/dev/null 2>&1; }
NOW="$( date -u +%Y-%m-%dT%H:%M:%S )"

# 4a) SELF (control): in-place rewrite of a line committed in the last window commit, edited again now.
SF="$WORK/selfchurn"; mkdir -p "$SF/src"
( cd "$SF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){ return 1; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c1
printf 'int hot(){ return 2; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c2
printf 'int hot(){ return 3; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
OSF="$( cd "$SF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*churn="self"' \
    && ok "self/ambient churn: in-place edit of a recently-committed line → facet churn=\"self\"" \
    || { no "self/ambient churn: expected churn=\"self\" on hot()"; printf '%s\n' "$OSF" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"' \
    && no "self/ambient churn: genuine thrash wrongly downgraded to sev=\"minor\"" \
    || ok "self/ambient churn: genuine thrash stays MAJOR (no sev=\"minor\")"

# 4b) AMBIENT — adds lines: the working-tree edit only INSERTS a new statement, touching no existing line.
AF="$WORK/ambientadd"; mkdir -p "$AF/src"
( cd "$AF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int y=1;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c1
printf 'int hot(){\n    int y=9;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c2
printf 'int hot(){\n    int y=9;\n    int z=2;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
OAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
EAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
printf '%s' "$OAF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: pure line-insertion edit → sev=\"minor\" churn=\"ambient\" (adds lines)" \
    || { no "self/ambient churn: pure-insert edit not downgraded to ambient"; printf '%s\n' "$OAF" | tr '>' '\n' | grep '<r '; }
[ "$EAF" = 0 ] && ok "self/ambient churn: ambient-only finding does not gate exit 2" || no "self/ambient churn: ambient-only run should exit 0 (got $EAF)"

# 4c) AMBIENT — touches a cold line: the file is churn-hot (2 recent commits) via an UNRELATED line, but the
#     working tree edits a line whose real last commit is a backdated, out-of-window commit.
CF="$WORK/ambientcold"; mkdir -p "$CF/src"
( cd "$CF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int a=1;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "2026-01-01T00:00:00" "c1 backdated (>14d before HEAD)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c2 recent (touches a — the committed-thrash evidence)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c3 recent (2nd in-window file commit, does not touch hot())"
printf 'int hot(){\n    int a=9;\n    int b=20;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
OCF="$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OCF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: edit of a line last committed outside the window → ambient (touches cold lines)" \
    || { no "self/ambient churn: cold-line edit not downgraded to ambient"; printf '%s\n' "$OCF" | tr '>' '\n' | grep '<r '; }
[ "$OCF" = "$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "self/ambient churn: delta byte-identical run-to-run" || no "self/ambient churn: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OSF" | xmllint --noout - 2>/dev/null && printf '%s' "$OAF" | xmllint --noout - 2>/dev/null && printf '%s' "$OCF" | xmllint --noout - 2>/dev/null \
        && ok "self/ambient churn: xml well-formed (self + both ambient outputs)" || no "self/ambient churn: xml malformed"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
