#!/usr/bin/env bash
# githardencheck.sh — gate for the git-config trust boundary (harvest round 2026-09-09, the markitdown
# "state the privilege model of every shell-out" lesson, measured against this tree's own git calls).
#
# ripwire runs READ-ONLY git inside the analysed checkout (`status --porcelain` for the +dirty stamp,
# `ls-files`, `log`, `diff --numstat`, `archive`, `rev-parse` — 82 calls across a 13-verb sweep, logged
# through a PATH shim). Git honours the checkout's OWN .git/config, and one key there turns a read-only
# call into arbitrary code: a HOOK-form `core.fsmonitor` (any value that is not a boolean) is a command
# git runs on every status/diff/ls-files. Measured before the fix: a fixture hook fired THREE times per
# `--situ` and once per default map. A cloned repo never carries that config (git clone does not copy
# .git/config), but a tarball-delivered tree, a copied worktree, or a shared checkout does, and ripwire
# runs unattended inside agent loops over directories nobody inspected.
#
# The fix is ONE site: at process start, if any crawl root configures a hook-form fsmonitor, the process
# appends `core.fsmonitor=false` to git's GIT_CONFIG_COUNT/KEY/VALUE environment override (so every git
# child inherits it) and says so on stderr (git_harden=fsmonitor-hook) and in --doctor. A BOOLEAN
# core.fsmonitor — git's builtin daemon, a real speedup on 100k-file trees — is deliberately left alone:
# the override is applied only to the form that executes code. The probe (`git config --get`) runs no hook
# (measured inert).
#
# Arms:
#   (A) presence: the fixture's hook FIRES under plain `git status` — proves the fixture is live; if git
#       ignores hook-form fsmonitor here the gate cannot conclude and exits 2 rather than pass vacuously.
#   (B) `ripwire <fx> --situ` leaves the hook unfired (RED before the fix: 3 firings).
#   (C) the disclosure: stderr carries git_harden=fsmonitor-hook; stdout does NOT (no leak into the XML).
#   (D) `--doctor` emits <c n="git-config-trust" ok="1" fsmonitor="hook" neutralised="1"/>.
#   (E) mutation control — a COPY of the fixture with core.fsmonitor=false (boolean): the mutation is
#       asserted to have TAKEN, the identical extraction is re-run, and it must DIFFER (no git_harden= line,
#       fsmonitor="off" neutralised="0") — the override must not touch the boolean form.
#   (F) env preservation, through a PATH shim that logs what the git CHILD saw: a caller's own
#       GIT_CONFIG_COUNT=1 entry survives (COUNT becomes 2, ours is appended, theirs stays at index 0); on
#       the boolean copy COUNT stays 1.
#   (H) the cheap pre-scan is sound: a hook reached only through `[include] path=` is still neutralised.
#   (I) a linked worktree (`.git` is a file naming a gitdir; the config lives in the commondir) is still probed.
#   (G) determinism: two `--situ` stdouts are byte-identical.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/githardencheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
REALGIT="$( command -v git )"
[ -n "$REALGIT" ] || { echo "git not on PATH — this gate needs it"; exit 2; }
echo "githardencheck: BIN=$BIN git=$( "$REALGIT" --version )"

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME"   # never the user's cache, never the checkout

# ── the fixture: one commit, one .c file, a HOOK-form core.fsmonitor that leaves a mark when run ────────
FX="$TMP/fx"; mkdir -p "$FX"
cat > "$TMP/hook.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/MARK"
printf '/\\0'
EOF
chmod +x "$TMP/hook.sh"
( cd "$FX" && "$REALGIT" init -q && printf 'int add( int a, int b ) { return a + b; }\nint main() { return add( 1, 2 ); }\n' > a.c \
    && "$REALGIT" add -A && "$REALGIT" -c user.name=g -c user.email=g@g commit -qm init \
    && "$REALGIT" config core.fsmonitor "$TMP/hook.sh" ) || { echo "fixture build failed"; exit 2; }

fired(){ [ -f "$TMP/MARK" ] && wc -l < "$TMP/MARK" | tr -d ' ' || echo 0; }

# ── (A) presence: plain git fires the hook ────────────────────────────────────────────────────────────
rm -f "$TMP/MARK"; "$REALGIT" -c core.quotepath=false -C "$FX" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then
    ok "(A) presence: hook-form core.fsmonitor fires under plain git status ($( fired ) call) — the fixture is live"
else
    echo "  SKIP  (A) this git does not run a hook-form core.fsmonitor here — the gate cannot conclude (exit 2)"; exit 2
fi

# ── (B)+(C) ripwire --situ: hook silent, disclosure on stderr only ─────────────────────────────────────
rm -f "$TMP/MARK"
"$BIN" "$FX" --situ > "$TMP/situ.out" 2> "$TMP/situ.err"
[ "$( fired )" -eq 0 ] \
    && ok "(B) ripwire --situ does not run the checkout's hook-form fsmonitor (0 firings)" \
    || no "(B) ripwire --situ ran the checkout's hook-form fsmonitor $( fired ) time(s): $( head -3 "$TMP/MARK" | tr '\n' ';' )"
grep -q 'git_harden=fsmonitor-hook' "$TMP/situ.err" \
    && ok "(C) stderr discloses the neutralisation (git_harden=fsmonitor-hook): $( grep -m1 'git_harden=' "$TMP/situ.err" )" \
    || no "(C) stderr carries no git_harden=fsmonitor-hook line: $( head -c 300 "$TMP/situ.err" )"
grep -q 'git_harden=' "$TMP/situ.out" \
    && no "(C) the disclosure leaked into stdout (the XML must not carry a stderr note)" \
    || ok "(C) stdout carries no git_harden= (disclosure stays on stderr)"

# ── (D) --doctor row ────────────────────────────────────────────────────────────────────────────────────
DOC="$( "$BIN" "$FX" --doctor 2>/dev/null )"
DOCROW="$( printf '%s' "$DOC" | grep -oE '<c n="git-config-trust"[^>]*/>' )"
{ printf '%s' "$DOCROW" | grep -q 'ok="1"' && printf '%s' "$DOCROW" | grep -q 'fsmonitor="hook"' && printf '%s' "$DOCROW" | grep -q 'neutralised="1"'; } \
    && ok "(D) --doctor row: $DOCROW" \
    || no "(D) --doctor lacks <c n=\"git-config-trust\" ok=\"1\" fsmonitor=\"hook\" neutralised=\"1\"/>: got '${DOCROW:-<absent>}'"

# ── (E) mutation control: the BOOLEAN form must be left alone ───────────────────────────────────────────
FB="$TMP/fb"; cp -R "$FX" "$FB"; "$REALGIT" -C "$FB" config core.fsmonitor false
[ "$( "$REALGIT" -C "$FB" config --get core.fsmonitor )" = "false" ] \
    && ok "(E) mutation took: the copy's core.fsmonitor reads 'false'" \
    || { no "(E) mutation did NOT take — control void"; }
"$BIN" "$FB" --situ > "$TMP/situb.out" 2> "$TMP/situb.err"
DOCB="$( "$BIN" "$FB" --doctor 2>/dev/null | grep -oE '<c n="git-config-trust"[^>]*/>' )"
grep -q 'git_harden=' "$TMP/situb.err" \
    && no "(E) the boolean form was ALSO neutralised — the override must be scoped to the hook form: $( grep -m1 git_harden= "$TMP/situb.err" )" \
    || ok "(E) boolean core.fsmonitor=false: no git_harden= line (untouched)"
{ printf '%s' "$DOCB" | grep -q 'fsmonitor="off"' && printf '%s' "$DOCB" | grep -q 'neutralised="0"'; } \
    && ok "(E) --doctor on the boolean copy: $DOCB" \
    || no "(E) --doctor on the boolean copy should say fsmonitor=\"off\" neutralised=\"0\": got '${DOCB:-<absent>}'"
[ "$DOCROW" != "$DOCB" ] \
    && ok "(E) the two extractions differ (hook vs boolean) — the control has contrast" \
    || no "(E) identical doctor rows for the hook and boolean fixtures — the arm cannot see the difference"

# ── (F) env preservation, observed from the git CHILD through a PATH shim ────────────────────────────────
mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<EOF
#!/bin/bash
printf 'COUNT=%s K0=%s V0=%s K1=%s V1=%s\\n' "\${GIT_CONFIG_COUNT:-}" "\${GIT_CONFIG_KEY_0:-}" "\${GIT_CONFIG_VALUE_0:-}" "\${GIT_CONFIG_KEY_1:-}" "\${GIT_CONFIG_VALUE_1:-}" >> "$TMP/shim.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shim/git"
rm -f "$TMP/shim.log"
PATH="$TMP/shim:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=gateprobe "$BIN" "$FX" --situ >/dev/null 2>&1
SEEN="$( sort -u "$TMP/shim.log" 2>/dev/null | head -3 | tr '\n' ';' )"
grep -q '^COUNT=2 K0=user.name V0=gateprobe K1=core.fsmonitor V1=false$' "$TMP/shim.log" 2>/dev/null \
    && ok "(F) the git child saw the caller's entry at index 0 and ours appended at index 1 (COUNT=2)" \
    || no "(F) the git child's override block is wrong — expected COUNT=2 K0=user.name V0=gateprobe K1=core.fsmonitor V1=false, saw: ${SEEN:-<nothing logged>}"
rm -f "$TMP/shim.log"
PATH="$TMP/shim:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=gateprobe "$BIN" "$FB" --situ >/dev/null 2>&1
grep -q '^COUNT=1 K0=user.name V0=gateprobe K1= V1=$' "$TMP/shim.log" 2>/dev/null \
    && ok "(F) on the boolean copy the caller's block is passed through untouched (COUNT=1)" \
    || no "(F) the boolean copy's git child saw a changed block: $( sort -u "$TMP/shim.log" 2>/dev/null | head -3 | tr '\n' ';' )"

# ── (H) the cheap tier must not open a hole: a hook reached only through [include] ──────────────────────
# The startup probe reads the LOCAL config files for the bytes "fsmonitor"/"include" before paying for a git
# subprocess. A hostile config that hides the key behind an include must still be caught.
FH="$TMP/fh"; cp -R "$FX" "$FH"
printf '[core]\n\tfsmonitor = %s\n' "$TMP/hook.sh" > "$TMP/hidden.inc"
( cd "$FH" && "$REALGIT" config --unset core.fsmonitor && "$REALGIT" config include.path "$TMP/hidden.inc" )
grep -qi fsmonitor "$FH/.git/config" \
    && no "(H) the fixture still spells fsmonitor in .git/config — the include arm is not testing the include" \
    || ok "(H) mutation took: .git/config no longer spells fsmonitor; the key lives only behind include.path"
rm -f "$TMP/MARK"; "$REALGIT" -C "$FH" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then ok "(H) presence: git itself follows the include (hook fired $( fired ))"; else no "(H) git did not follow the include — the arm cannot conclude"; fi
rm -f "$TMP/MARK"; "$BIN" "$FH" --situ >/dev/null 2> "$TMP/situh.err"
[ "$( fired )" -eq 0 ] && grep -q 'git_harden=fsmonitor-hook' "$TMP/situh.err" \
    && ok "(H) a hook reached only through [include] is still neutralised and disclosed" \
    || no "(H) include-hidden hook: fired=$( fired ), disclosure=$( grep -c git_harden= "$TMP/situh.err" )"

# ── (I) a linked worktree: .git is a FILE naming a gitdir whose commondir holds the config ────────────────
"$REALGIT" -C "$FX" worktree add -q "$TMP/wt" -b gatewt >/dev/null 2>&1 || no "(I) could not create a linked worktree"
if [ -f "$TMP/wt/.git" ]; then ok "(I) the worktree's .git is a file ($( head -c 40 "$TMP/wt/.git" | tr -d '\n' )…)"; else no "(I) expected $TMP/wt/.git to be a gitdir: FILE"; fi
rm -f "$TMP/MARK"; "$REALGIT" -C "$TMP/wt" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then ok "(I) presence: the shared config's hook fires in the worktree ($( fired ))"; else no "(I) the hook did not fire in the worktree — the arm cannot conclude"; fi
rm -f "$TMP/MARK"; "$BIN" "$TMP/wt" --situ >/dev/null 2> "$TMP/situi.err"
[ "$( fired )" -eq 0 ] && grep -q 'git_harden=fsmonitor-hook' "$TMP/situi.err" \
    && ok "(I) the worktree root is neutralised and disclosed (gitdir/commondir resolved)" \
    || no "(I) worktree root: fired=$( fired ), disclosure=$( grep -c git_harden= "$TMP/situi.err" )"
"$REALGIT" -C "$FX" worktree remove --force "$TMP/wt" >/dev/null 2>&1 || true

# ── (G) determinism ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FX" --situ > "$TMP/situ2.out" 2>/dev/null
cmp -s "$TMP/situ.out" "$TMP/situ2.out" \
    && ok "(G) two --situ runs on the hook fixture are byte-identical" \
    || no "(G) two --situ runs differ: $( diff "$TMP/situ.out" "$TMP/situ2.out" | head -3 | tr '\n' ';' )"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
