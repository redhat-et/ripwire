#!/usr/bin/env bash
# historywalkcheck.sh — HISTORY-WALK-HANG: no git of ripwire's downloads on a partial clone, and no history walk runs past its budget
# (src/gitcmd.h NEVER DOWNLOAD, src/gitmine.h THE BUDGET). No network: the promisor is a local bare repository, built at runtime.
#
# In-sample large repositories are single-commit, so nothing else exercises a long or a partial history.
#
# Arms:
#   (P) a blobless clone of a bare repo (uploadpack.allowFilter): the fixture is live, a plain `git log -c --name-only` over a rename
#       really fetches. The history verbs (--for, --metrics, --exemplar, --cochange, --hotspots, --owners, --situ, --quality-delta)
#       then answer, and the clone's object count does not move and no promisor pack appears.
#   (O) the same, with a git shim that drops GIT_NO_LAZY_FETCH (what a git before 2.45 does with it): the protocol layer refuses it.
#   (C) a URL root reaches `git clone` with NO download policy of ours (a shim stands in: no network): the caller's GIT_ALLOW_PROTOCOL (set,
#       empty or unset) is left as it was, and the user's protocol.http.allow=never is honoured. (H1) --run-trace's command never inherits
#       the policy, so a test command that clones works, and a caller's own GIT_ALLOW_PROTOCOL reaches it.
#   (N) a walk over a rename still answers on the blobless clone, every commit read, no history_unread.
#   (N2) --pr-context names the changed files with no blob to diff; (N3) --quality-delta=REF refuses, names the partial clone and the way out.
#   (H2) --stray-content on the blobless clone: an unmerged branch whose blobs are absent is unknown, never merged (the full clone says unmerged).
#   (H3) --pr-context=REF on a DIRTY blobless tree lists the files; a diff git cannot read at all is a refusal naming the cause, not files="0".
#   (B) a long fixture (fast-import) under RIPWIRE_GIT_WALK_COMMITS: --for carries history_unread and the count; a warm second run still
#       does (the cut is cached; --no-cache walks again); --cochange carries history_cut on stdout and stderr; --json stays parseable, the cut on stderr only;
#       a budget above the history is silent, and byte-identical to no budget at all.
#   (T) a git shim that prints the first commits of the real walk and then goes silent for longer than the budget: --for, --cochange exit inside the
#       time budget's reach, disclosed; a shim silent from the first byte ends the same way.
#   (M) --mcp: no comment line on the protocol stream, the cut in the answer's envelope; a stalled walk's short prefix is not stored; the cut
#       sentence and --help=all say the prefix moves with load; a zero-commit cut names the budget (M4); --exemplar starts no walk (L2).
#   (R) red, only when RIPWIRE_BASE_BIN names a pre-fix binary: (P) fetches and (T) outlives its timeout.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rw-histwalk.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
fail=0; pass=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
REALGIT="$(command -v git)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com GIT_CONFIG_NOSYSTEM=1 HOME="$TMP/home"
mkdir -p "$HOME"

# ── the promisor: enough history that a blobless clone misses blobs; a rename with an edit so similarity must read content ──
SRC="$TMP/src"; git init -q -b main "$SRC"
for i in 1 2 3 4 5 6; do
  printf 'int f%s( int a ) { return a + %s; }\nint g%s( int a ) { return f%s( a ) * 2; }\n' "$i" "$i" "$i" "$i" > "$SRC/m$i.c"
done
seq 1 200 > "$SRC/big.txt"
git -C "$SRC" add -A; git -C "$SRC" commit -qm one
for i in 1 2 3 4 5 6; do echo "// edit $i" >> "$SRC/m$i.c"; git -C "$SRC" add -A; git -C "$SRC" commit -qm "edit $i"; done
git -C "$SRC" mv big.txt moved.txt; echo tail >> "$SRC/moved.txt"; git -C "$SRC" add -A; git -C "$SRC" commit -qm rename
git -C "$SRC" checkout -qb side HEAD~2; echo side >> "$SRC/m1.c"; git -C "$SRC" add -A; git -C "$SRC" commit -qm side
git -C "$SRC" checkout -q main; git -C "$SRC" merge -q --no-edit side
git -C "$SRC" checkout -qb stray main; printf 'int stray_only( int a ) { return a * 7; }\n' > "$SRC/stray.c"; git -C "$SRC" add -A; git -C "$SRC" commit -qm stray
git -C "$SRC" checkout -q main
BARE="$TMP/remote.git"; git clone -q --bare "$SRC" "$BARE"; git -C "$BARE" config uploadpack.allowFilter true; git -C "$BARE" config uploadpack.allowAnySHA1InWant true
fresh_partial() {  # a brand-new blobless clone, so one verb's run cannot hide another's fetch
  rm -rf "$1"; git clone -q --filter=blob:none "file://$BARE" "$1" || exit 2
}
objs() { git -C "$1" count-objects -v | awk '/^(count|in-pack):/{n+=$2} END{print n}'; }
packs() { ls "$1/.git/objects/pack" 2>/dev/null | grep -c '\.pack$'; }

CL="$TMP/cl"; fresh_partial "$CL"
before="$(objs "$CL")"
missing="$(git -C "$CL" rev-list --objects --all --missing=print 2>/dev/null | grep -c '^?')"
[ "$missing" -gt 0 ] || { echo "SKIP: the clone is missing no blob; the fixture is not live"; exit 2; }
git -C "$CL" log -c --name-only --format=%H >/dev/null 2>&1
[ "$(objs "$CL")" -gt "$before" ] || { echo "SKIP: plain git did not fetch; the fixture is not live"; exit 2; }
ok "(P0) the fixture is live: plain git log fetched from the promisor"

VERBS=( "--for=edit f1" --metrics "--exemplar=f1" --cochange=m1.c --hotspots --owners=f1 --situ --quality-delta --rank-by=churn )
run_verbs() {  # label prefix, binary, extra env assignment
  local label="$1" bin="$2"; shift 2
  local v
  for v in "${VERBS[@]}"; do
    fresh_partial "$CL"
    local b p
    b="$(objs "$CL")"; p="$(packs "$CL")"
    ( cd "$CL" && env "$@" perl -e 'alarm 120; exec @ARGV' "$bin" "$CL" --no-cache "$v" >"$TMP/out" 2>"$TMP/err" ); local rc=$?
    if [ "$(objs "$CL")" = "$b" ] && [ "$(packs "$CL")" = "$p" ]; then echo "same"; else echo "fetched"; fi >"$TMP/verdict"
    echo "$v rc=$rc $(cat "$TMP/verdict")" >>"$TMP/verdicts.$label"
  done
}
: > "$TMP/verdicts.head"; run_verbs head "$BIN" X=1
while read -r line; do
  case "$line" in *" rc=0 same") ok "(P) no fetch, answered: $line" ;; *) bad "(P) $line" ;; esac
done < "$TMP/verdicts.head"

# ── (O) an old git: the shim drops the first layer ──
SHIMO="$TMP/shim-old"; mkdir -p "$SHIMO"
printf '#!/bin/sh\nunset GIT_NO_LAZY_FETCH\nexec "%s" "$@"\n' "$REALGIT" > "$SHIMO/git"; chmod +x "$SHIMO/git"
: > "$TMP/verdicts.old"; run_verbs old "$BIN" "PATH=$SHIMO:$PATH"
while read -r line; do
  case "$line" in *" rc=0 same") ok "(O) old git, no fetch, answered: $line" ;; *) bad "(O) $line" ;; esac
done < "$TMP/verdicts.old"

# ── (C) a URL root still clones ──
SHIMC="$TMP/shim-clone"; mkdir -p "$SHIMC"
cat > "$SHIMC/git" <<SH
#!/bin/sh
case " \$* " in *" clone "*) printf '[%s]\n' "\${GIT_ALLOW_PROTOCOL-unset}" >>"$TMP/clone-allow"; exit 1 ;; esac
exec "$REALGIT" "\$@"
SH
chmod +x "$SHIMC/git"
cloneenv() { : > "$TMP/clone-allow"; ( cd "$TMP" && env "$@" PATH="$SHIMC:$PATH" TMPDIR="$TMP" "$BIN" "https://example.invalid/r.git" --refetch --no-cache >/dev/null 2>&1 ); }
cloneenv X=1
check "(C1) a URL root's clone carries no download policy of ours: the caller's allow-list is unset, not widened" 'grep -q "^\[unset\]$" "$TMP/clone-allow"'
cloneenv GIT_ALLOW_PROTOCOL=ssh
check "(C2) ... and the caller's own allow-list stays the caller's" 'grep -q "^\[ssh\]$" "$TMP/clone-allow"'
cloneenv GIT_ALLOW_PROTOCOL=
check "(C3) ... an EMPTY allow-list (nothing allowed) stays empty, it is not read as unset" 'grep -q "^\[\]$" "$TMP/clone-allow"'
printf '[protocol "http"]\n\tallow = never\n' > "$HOME/.gitconfig"
( cd "$TMP" && TMPDIR="$TMP" "$BIN" "http://127.0.0.1:9/x.git" --refetch --no-cache >"$TMP/out" 2>"$TMP/err" )
check "(C4) the user's protocol.http.allow=never is honoured by the URL root's clone" 'grep -q "not allowed" "$TMP/err" && ! grep -qi "failed to connect\|couldn.t connect" "$TMP/err"'
rm -f "$HOME/.gitconfig"

# ── (H1) the user's own command never inherits the download policy of the git commands ripwire runs ──
RTC="$TMP/rt-clone"; rm -rf "$RTC" "$TMP/rt-env"
( cd "$SRC" && "$BIN" "$SRC" --no-cache --run-trace="git clone -q file://$BARE $RTC && echo CLONED; env | grep -c '^GIT_NO_LAZY_FETCH\|^GIT_ALLOW_PROTOCOL=ripwire' > $TMP/rt-env" >"$TMP/out" 2>"$TMP/err" )
check "(H1) --run-trace: a command that clones through git is not refused by our allow-list" '[ -d "$RTC/.git" ] && ! grep -q "not allowed" "$TMP/out" "$TMP/err"'
check "(H1b) ... and its environment holds none of our download variables" '[ "$(cat "$TMP/rt-env" 2>/dev/null)" = 0 ]'
rm -f "$TMP/rt-env"
( cd "$SRC" && GIT_ALLOW_PROTOCOL=file "$BIN" "$SRC" --no-cache --run-trace="printf '%s' \"\${GIT_ALLOW_PROTOCOL-unset}\" > $TMP/rt-env" >"$TMP/out" 2>"$TMP/err" )
check "(H1c) ... a caller's own GIT_ALLOW_PROTOCOL reaches it unchanged" '[ "$(cat "$TMP/rt-env" 2>/dev/null)" = file ]'

# ── (N) the walk reads every commit of the blobless clone, rename included ──
fresh_partial "$CL"
( cd "$CL" && "$BIN" "$CL" --no-cache --for="edit f1" >"$TMP/out" 2>"$TMP/err" )
check "(N) --for on the blobless clone: the walk was read, no history_unread" '! grep -q history_unread "$TMP/out" && grep -q "churn=" "$TMP/out"'

git -C "$CL" log -1 >/dev/null
( cd "$CL" && "$BIN" "$CL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" )
check "(N2) --pr-context on a base whose blobs are absent still lists the changed files" 'grep -q "moved.txt\|m1.c" "$TMP/out"'
( cd "$CL" && "$BIN" "$CL" --no-cache --quality-delta=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(N3) --quality-delta=REF that needs absent blobs refuses and says why (rc=$rc)" '[ "$rc" != 0 ] && grep -q "partial clone" "$TMP/err"'
check "(N3b) ... and names the way out: a git archive of that sha in the user's own shell" 'grep -q "git archive [0-9a-f]* >/dev/null" "$TMP/err"'

# (H2) --stray-content: a branch whose blob this clone does not hold is unknown, never merged
fresh_partial "$CL"; git -C "$CL" branch stray origin/stray
( cd "$CL" && "$BIN" "$CL" --no-cache --stray-content >"$TMP/out" 2>"$TMP/err" )
check "(H2) --stray-content on a blobless clone: the unmerged branch is not reported merged" '! grep -q " merged=\"1\"" "$TMP/out" && grep -q "unknown=\"1\"" "$TMP/out"'
FULL="$TMP/full"; rm -rf "$FULL"; git clone -q "file://$BARE" "$FULL"; git -C "$FULL" branch stray origin/stray
( cd "$FULL" && "$BIN" "$FULL" --no-cache --stray-content >"$TMP/out" 2>"$TMP/err" )
check "(H2b) control: the full clone says the branch is unmerged" 'grep -q "unmerged=\"1\"" "$TMP/out"'

# (H3) --pr-context=REF on a DIRTY tree of a blobless clone lists the files (N2 is the clean tree)
fresh_partial "$CL"; echo "// dirty" >> "$CL/m1.c"
( cd "$CL" && "$BIN" "$CL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(H3) --pr-context=REF, dirty blobless tree: the changed files are listed, not files=\"0\" (rc=$rc)" '[ "$rc" = 0 ] && ! grep -q "<pr-context [^>]*files=\"0\"" "$TMP/out" && grep -q "<pr-context [^>]*files=\"[1-9]" "$TMP/out" && grep -q "m1.c" "$TMP/out"'
SHIMD="$TMP/shim-nodiff"; mkdir -p "$SHIMD"
printf '#!/bin/sh\ncase " $* " in *" diff "*) exit 128 ;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$SHIMD/git"; chmod +x "$SHIMD/git"
( cd "$CL" && PATH="$SHIMD:$PATH" "$BIN" "$CL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(H3b) a diff git cannot read at all is a refusal naming the cause, not an empty bundle (rc=$rc)" '[ "$rc" = 1 ] && grep -q "could not read the diff" "$TMP/err" && ! grep -q "<pr-context [^>]*files=\"0\"" "$TMP/out"'

# ── (F1) a partial clone starts no git that reads a blob: on a big one git parses every object of the promisor pack before it fails ──
# A logging shim records every git ripwire starts. A promisor repo must see no `--numstat`, no `-p` and no `archive` from the verbs that used
# them (--pr-context=REF, --quality-delta=REF, --whereis --with-history, --naming-calibration); the control is the full clone, which does start them.
# The fixtures hold a few dozen objects, where git fails at once, so only the shim can see what a ClickHouse-sized pack would turn into minutes.
SHIML="$TMP/shim-log"; mkdir -p "$SHIML"
cat > "$SHIML/git" <<SH
#!/bin/sh
printf '%s\\n' "\$*" >> "\$F1LOG"
case " \$* " in *" --numstat "*) [ -n "\${NUMSTAT_SLEEP:-}" ] && sleep "\$NUMSTAT_SLEEP"
                                  [ -n "\${NUMSTAT_FAIL:-}" ] && { printf '1\\t1\\tphantom_row.c\\n'; exit 3; } ;; esac
case " \$* " in *" diff "*" --name-only "*) [ -n "\${NAMEONLY_SLEEP:-}" ] && sleep "\$NAMEONLY_SLEEP" ;; esac
exec "$REALGIT" "\$@"
SH
chmod +x "$SHIML/git"
blobreaders() { grep -c -e ' --numstat ' -e ' -p -U0' -e ' archive ' "$F1LOG" 2>/dev/null || true; }
fresh_partial "$CL"; git -C "$CL" log -1 >/dev/null
for v in --pr-context=HEAD~3 --quality-delta=HEAD~3 "--whereis=f1 --with-history" --naming-calibration; do
  export F1LOG="$TMP/f1log"; : > "$F1LOG"
  ( cd "$CL" && PATH="$SHIML:$PATH" perl -e 'alarm 60; exec @ARGV' "$BIN" "$CL" --no-cache $v >"$TMP/out" 2>"$TMP/err" )
  check "(F1) partial clone, $v: no git that reads a blob was started ($(blobreaders) of them)" '[ "$(blobreaders)" = 0 ]'
done
export F1LOG="$TMP/f1log"; : > "$F1LOG"
( cd "$CL" && PATH="$SHIML:$PATH" "$BIN" "$CL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" )
check "(F1b) ... --pr-context=REF on it still lists the changed files, and says it is a partial clone" 'grep -q "<pr-context [^>]*files=\"[1-9]" "$TMP/out" && grep -q "partial clone" "$TMP/err"'
( cd "$CL" && PATH="$SHIML:$PATH" "$BIN" "$CL" --no-cache --whereis=f1 --with-history >"$TMP/out" 2>"$TMP/err" )
check "(F1c) ... the history probe says why it did not run: probed=\"0\" r=\"partial-clone\"" 'grep -q "probed=\"0\" r=\"partial-clone\"" "$TMP/out"'
( cd "$CL" && PATH="$SHIML:$PATH" "$BIN" "$CL" --no-cache --quality-delta=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(F1d) ... --quality-delta=REF with absent blobs still refuses, naming the partial clone (rc=$rc)" '[ "$rc" != 0 ] && grep -q "partial clone" "$TMP/err"'
: > "$F1LOG"; ( cd "$FULL" && PATH="$SHIML:$PATH" "$BIN" "$FULL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" )
check "(F1e) control: the full clone does run git diff --numstat ($(blobreaders) blob-reading gits)" '[ "$(blobreaders)" -gt 0 ]'
# the stalled case: a git that sits in --numstat for 90 s, budget 3 s (a loaded machine needs the headroom: an ingest alone can take 20 s, and the fallback is two more gits). Today: two serial numstats, wall 39 s, rc 0, no cut said.
: > "$F1LOG"; t0=$(date +%s)
( cd "$FULL" && PATH="$SHIML:$PATH" NUMSTAT_SLEEP=90 RIPWIRE_GIT_WALK_SECONDS=3 perl -e 'alarm 100; exec @ARGV' "$BIN" "$FULL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
secs=$(( $(date +%s) - t0 ))
check "(F1f) a git stalled in --numstat ends at the budget, not after it (rc=$rc ${secs}s), is said, and the files are listed" '[ "$rc" = 0 ] && [ "$secs" -lt 60 ] && grep -q "did not finish within the 3 s git budget" "$TMP/err" && grep -q "<pr-context [^>]*files=\"[1-9]" "$TMP/out"'

# (F1g) CodeRabbit on #498, prcontext.h:235: the fallback list is read under the budget too. A git stalled in --numstat AND in --name-only (the
# promisor-pack scan of a big clone stalls both) ended after the fallback had run its whole stall. Now: one budget each, a refusal that says why.
: > "$F1LOG"; t0=$(date +%s)
( cd "$FULL" && PATH="$SHIML:$PATH" NUMSTAT_SLEEP=90 NAMEONLY_SLEEP=90 RIPWIRE_GIT_WALK_SECONDS=3 perl -e 'alarm 100; exec @ARGV' "$BIN" "$FULL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
secs=$(( $(date +%s) - t0 ))
check "(F1g) a git stalled in --numstat and in --name-only ends within both budgets (rc=$rc ${secs}s), says so, and serves no list" ' [ "$secs" -lt 60 ] && grep -q "git diff --name-only did not finish within the 3 s git budget" "$TMP/err" && ! grep -q "files=\"[1-9]" "$TMP/out"'
# (F1h) CodeRabbit on #498, prcontext.h:286: a numstat that printed a row and then failed is a prefix, not a list; the tree-level list stands in
: > "$F1LOG"
( cd "$FULL" && PATH="$SHIML:$PATH" NUMSTAT_FAIL=1 "$BIN" "$FULL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(F1h) a git diff --numstat that fails after a row keeps no row: the list is the tree-level one (rc=$rc)" '[ "$rc" = 0 ] && ! grep -q phantom_row "$TMP/out" && grep -q "<pr-context [^>]*files=\"[1-9]" "$TMP/out"'

# ── (B) the commit budget, on a long history ──
LONG="$TMP/long"; git init -q -b main "$LONG"
python3 -I - "$LONG" <<'PY' | git -C "$LONG" fast-import --quiet
import sys,time
now=int(time.time())
N=3000
out=sys.stdout
for i in range(N):
    body=f"int f{i%7}( int a ) {{ return a + {i}; }}\nint caller{i%7}( int a ) {{ return f{i%7}( a ); }}\n"
    out.write(f"commit refs/heads/main\nmark :{i+1}\ncommitter t <t@example.com> {now-(N-i)*600} +0000\ndata 1\nc\n")
    if i: out.write(f"from :{i}\n")
    out.write(f"M 100644 inline m{i%7}.c\ndata {len(body)}\n{body}\n")
PY
git -C "$LONG" reset -q --hard main
rw() { ( cd "$LONG" && "$BIN" "$LONG" "$@" ); }
C="$TMP/cache"; mkdir -p "$C"
RIPWIRE_GIT_WALK_COMMITS=100 rw --cache="$C/c" --for="caller f1" >"$TMP/out" 2>"$TMP/err"
check "(B1) --for: a commit cut is history_unread with the count" 'grep -q "history_unread=\"1\"" "$TMP/out" && grep -q "hit its budget after the newest 100 commits" "$TMP/out"'
RIPWIRE_GIT_WALK_COMMITS=100 rw --cache="$C/c" --for="caller f1" >"$TMP/out2" 2>/dev/null
check "(B2) warm: the cached prefix still says it is one" 'grep -q "hit its budget after the newest 100 commits" "$TMP/out2"'
RIPWIRE_GIT_WALK_COMMITS=100 rw --no-cache --cochange=m1.c >"$TMP/out" 2>"$TMP/err"
check "(B3) --cochange: history_cut on stdout and stderr" 'grep -q "<!--history_cut=1" "$TMP/out" && grep -q "history_cut=1" "$TMP/err"'
RIPWIRE_GIT_WALK_COMMITS=100 rw --no-cache --rank-by=churn --json >"$TMP/out" 2>"$TMP/err"
check "(B4) --json stays parseable: the cut on stderr only" '! grep -q "history_cut" "$TMP/out" && grep -q "history_cut" "$TMP/err" && python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/out"'
RIPWIRE_GIT_WALK_COMMITS=3000 rw --no-cache --for="caller f1" 2>/dev/null | sed 's/ at="[^"]*"//; s/est_tokens="[^"]*"//' >"$TMP/at"
RIPWIRE_GIT_WALK_COMMITS=0 RIPWIRE_GIT_WALK_SECONDS=0 rw --no-cache --for="caller f1" 2>/dev/null | sed 's/ at="[^"]*"//; s/est_tokens="[^"]*"//' >"$TMP/none"
check "(B5) a budget exactly the history's size is silent, and byte-identical to no budget" '! grep -q "history_" "$TMP/at" && cmp -s "$TMP/at" "$TMP/none"'
RIPWIRE_GIT_WALK_COMMITS=abc RIPWIRE_GIT_WALK_SECONDS=-1 rw --no-cache --for="caller f1" 2>/dev/null | sed 's/ at="[^"]*"//; s/est_tokens="[^"]*"//' >"$TMP/badenv"
check "(B6) a malformed budget keeps the default" 'cmp -s "$TMP/badenv" "$TMP/none"'
# (B7) CodeRabbit on #498, gitmine.h:823: a budget past the ceiling keeps the default. UINT64_MAX wrapped the commit cap to `git log -n 0`
# (an empty history read as a clean one) and a huge SECONDS overflowed the deadline.
for big in 18446744073709551615 1000000001 99999999999999999999; do
  RIPWIRE_GIT_WALK_COMMITS=$big RIPWIRE_GIT_WALK_SECONDS=$big rw --no-cache --for="caller f1" 2>/dev/null | sed 's/ at="[^"]*"//; s/est_tokens="[^"]*"//' >"$TMP/bigenv"
  check "(B7) a budget of $big keeps the default: the answer is byte-identical to no budget" 'cmp -s "$TMP/bigenv" "$TMP/none"'
done
RIPWIRE_GIT_WALK_COMMITS=18446744073709551615 rw --no-cache --cochange=m1.c >"$TMP/out" 2>"$TMP/err"
check "(B7b) ... and --cochange under COMMITS=UINT64_MAX reads the history (commits found), not an empty one" 'grep -q "<cochange [^>]*commits=\"[1-9]" "$TMP/out"'

# ── (T) the time budget against a git that stops talking ──
SHIMT="$TMP/shim-stall"; mkdir -p "$SHIMT"
cat > "$SHIMT/git" <<SH
#!/bin/sh
# Only the record walk stalls: it prints what real git prints for the first commits, then says nothing for far longer than the budget.
case " \$* " in
  *" --name-only "*" -z "*|*" -z --name-only "*)
    if [ -n "\${STALL_AT_START:-}" ]; then
      # STALL_ONCE=<file>: only the first walk stalls (an earlier request's cut, then a request the budget never touched)
      if [ -z "\${STALL_ONCE:-}" ] || [ ! -e "\$STALL_ONCE" ]; then [ -z "\${STALL_ONCE:-}" ] || : > "\$STALL_ONCE"; exec sleep 45; fi
    fi
    "$REALGIT" "\$@" -n 5 2>/dev/null | cat; exec sleep 45 ;;
esac
exec "$REALGIT" "\$@"
SH
chmod +x "$SHIMT/git"
timed() { local t0 rc; t0=$(date +%s); ( cd "$LONG" && PATH="$SHIMT:$PATH" RIPWIRE_GIT_WALK_SECONDS="${TWS:-2}" perl -e 'alarm 30; exec @ARGV' "$1" "$LONG" --no-cache "${@:2}" >"$TMP/out" 2>"$TMP/err" ); rc=$?; echo "$rc $(( $(date +%s) - t0 ))"; }
read -r rc secs <<<"$(timed "$BIN" --for="caller f1")"
check "(T1) --for against a git gone silent: exit 0, on time (rc=$rc ${secs}s), disclosed" '[ "$rc" = 0 ] && [ "$secs" -lt 25 ] && grep -q "history_unread=\"1\"" "$TMP/out"'
read -r rc secs <<<"$(timed "$BIN" --cochange=m1.c)"
check "(T2) --cochange against a git gone silent: on time (rc=$rc ${secs}s), disclosed" '[ "$secs" -lt 25 ] && grep -q "history_cut=1" "$TMP/err"'
export STALL_AT_START=1 TWS=3   # a budget of its own: T1's prefix is cached under its budget
read -r rc secs <<<"$(timed "$BIN" --for="caller f1")"
check "(T3) --for against a git silent from the first byte: exit 0, on time (rc=$rc ${secs}s), disclosed" '[ "$rc" = 0 ] && [ "$secs" -lt 25 ] && grep -q "hit its budget after the newest 0 commits" "$TMP/out"'
unset STALL_AT_START

# ── (M) a cut is said where the host can hold it ──
# (M1) --mcp: stdout is the protocol, so no comment line on it; the cut rides the envelope of the answer that read it.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"cochange\",\"arguments\":{\"path\":\"$LONG\",\"file\":\"m1.c\"}}}" \
  | ( cd "$LONG" && RIPWIRE_GIT_WALK_COMMITS=100 perl -e 'alarm 60; exec @ARGV' "$BIN" "$LONG" --mcp >"$TMP/out" 2>"$TMP/err" )
check "(M1) --mcp: every stdout line is a JSON-RPC message (no history_cut comment line)" 'python3 -I -c "import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]" "$TMP/out" && ! grep -q "<!--" "$TMP/out"'
check "(M1b) ... and the answer that read a cut walk carries it in its envelope" 'grep -q "_history_cut" "$TMP/out" && grep -q "history_cut" "$TMP/err"'

# (M3) a counting shim: how many record walks ran. The stall variant also goes silent after 5 commits.
SHIMW="$TMP/shim-count"; mkdir -p "$SHIMW"
cat > "$SHIMW/git" <<SH
#!/bin/sh
case " \$* " in *" --name-only "*" -z "*|*" -z --name-only "*)
  echo walk >>"$TMP/walklog"
  if [ -n "\${STALL_AFTER_5:-}" ]; then "$REALGIT" "\$@" -n 5 2>/dev/null | cat; exec sleep 45; fi ;;
esac
exec "$REALGIT" "\$@"
SH
chmod +x "$SHIMW/git"
walks() { [ -f "$TMP/walklog" ] && wc -l < "$TMP/walklog" | tr -d ' ' || echo 0; }
QC="$TMP/qc"; mkdir -p "$QC"; rm -f "$TMP/walklog"
wrun() { ( cd "$LONG" && PATH="$SHIMW:$PATH" TMPDIR="$QC" RIPWIRE_GIT_WALK_COMMITS=100 perl -e 'alarm 60; exec @ARGV' "$BIN" "$LONG" "$@" >"$TMP/out" 2>"$TMP/err" ); }
wrun --for="caller f1"; w1="$(walks)"
wrun --for="caller f1"; w2="$(walks)"
wrun --no-cache --for="caller f1"; w3="$(walks)"
check "(M3a) a stored commit cut is served warm (walks $w1 then $w2) ..." '[ "$w1" -ge 1 ] && [ "$w2" = "$w1" ]'
check "(M3b) ... and --no-cache walks again instead of serving it (walks $w3)" '[ "$w3" -gt "$w2" ] && grep -q "history_unread=\"1\"" "$TMP/out"'
# a stalled git's 5-commit prefix is not stored as the answer for that HEAD
rm -f "$TMP/walklog"; QC="$TMP/qc2"; mkdir -p "$QC"
STALL_AFTER_5=1 RIPWIRE_GIT_WALK_SECONDS=2 wrun --for="caller f1"; s1="$(walks)"
STALL_AFTER_5=1 RIPWIRE_GIT_WALK_SECONDS=2 wrun --for="caller f1"; s2="$(walks)"
check "(M3c) a short prefix of a stalled walk is not stored: the second run walks again (walks $s1 then $s2), disclosed" '[ "$s2" -gt "$s1" ] && grep -q "history_unread=\"1\"" "$TMP/out"'
check "(M3d) the cut disclosure says the prefix moves with machine load" 'grep -q "moves with machine load" "$TMP/out"'
"$BIN" --help=all 2>/dev/null | grep -q "except a disclosed history cut"; hrc=$?
check "(M3e) --help=all and the README no longer claim byte-identical runs without the cut exception" '[ "$hrc" = 0 ] && grep -q "moves with machine load" "$ROOT/README.md"'
# (M4) a walk cut before its first commit is not "git unavailable"
export STALL_AT_START=1 TWS=2
for v in --hotspots --owners "--cochange"; do
  read -r rc secs <<<"$(timed "$BIN" $v)"
  check "(M4) $v against a git silent from the first byte: exit 1, names the budget, not an unavailable git (rc=$rc)" '[ "$rc" = 1 ] && grep -q "hit its budget" "$TMP/err" && ! grep -q "git unavailable" "$TMP/err"'
done
unset STALL_AT_START TWS
# (M5) CodeRabbit on #498, verbs_report.h:1405: a --since window is not "empty" when the walk was cut before its first record
export STALL_AT_START=1 TWS=2
for v in --hotspots --cochange; do
  read -r rc secs <<<"$(timed "$BIN" $v --since="1 year ago")"
  check "(M5) $v --since=... against a git silent from the first byte: exit 1, names the budget, no empty-window claim (rc=$rc)" '[ "$rc" = 1 ] && grep -q "hit its budget" "$TMP/err" && ! grep -q "matched no commits" "$TMP/out"'
done
# (M5b) the neighbour the review did not name: --rank-by=churn --since says "found no commits in its window" of a walk that was only cut
read -r rc secs <<<"$(timed "$BIN" --rank-by=churn "--since=1 year ago")"
check "(M5b) --rank-by=churn --since=... against a git silent from the first byte: the no-commits line names the budget (rc=$rc)" 'grep -q "found no commits in its window (its git history walk hit its budget" "$TMP/err"'
unset STALL_AT_START TWS
# (F2) the same refusal over MCP: the error of `owners` (and `symbol`) names the budget, not "no git history"
export STALL_AT_START=1
for sym in "" f1; do
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"owners\",\"arguments\":{\"path\":\"$LONG\",\"symbol\":\"$sym\"}}}" \
    | ( cd "$LONG" && PATH="$SHIMT:$PATH" RIPWIRE_GIT_WALK_SECONDS=1 perl -e 'alarm 60; exec @ARGV' "$BIN" "$LONG" --mcp --no-cache >"$TMP/out" 2>"$TMP/err" )
  check "(F2) --mcp owners symbol='$sym' against a git silent from the first byte: the error names the budget, not a missing history" 'grep -q "hit its budget" "$TMP/out" && ! grep -q "no git history" "$TMP/out"'
done
unset STALL_AT_START
# (F2b) CodeRabbit on #498, mcp.h:2505: the cause is THIS request's. One server, two calls: the first walk is cut, the second request is a
# symbol that does not exist; its refusal is the missing symbol, not the first request's budget.
export STALL_AT_START=1
rm -f "$TMP/stalled"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"owners\",\"arguments\":{\"path\":\"$LONG\",\"symbol\":\"\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"owners\",\"arguments\":{\"path\":\"$LONG\",\"symbol\":\"zz_no_such_symbol\"}}}" \
  | ( cd "$LONG" && PATH="$SHIMT:$PATH" STALL_ONCE="$TMP/stalled" RIPWIRE_GIT_WALK_SECONDS=1 perl -e 'alarm 60; exec @ARGV' "$BIN" "$LONG" --mcp --no-cache >"$TMP/out" 2>"$TMP/err" )
check "(F2b) --mcp: the first owners call names the budget; a later call for a missing symbol does not" 'grep "\"id\":2" "$TMP/out" | grep -q "hit its budget" && ! grep "\"id\":3" "$TMP/out" | grep -q "hit its budget" && grep -q "\"id\":3" "$TMP/out"'
unset STALL_AT_START
# (L2) --exemplar runs no history walk (it prints neither churn= nor amp=)
rm -f "$TMP/walklog"; QC="$TMP/qc3"; mkdir -p "$QC"
wrun --no-cache --exemplar=f1
check "(L2) --exemplar starts no record walk (walks $(walks))" '[ "$(walks)" = 0 ] && [ -s "$TMP/out" ]'

# ── (R) red-first, on a named pre-fix binary ──
if [ -n "${RIPWIRE_BASE_BIN:-}" ]; then
  VERBS=( "--for=edit f1" --cochange=m1.c )
  : > "$TMP/verdicts.base"; run_verbs base "$RIPWIRE_BASE_BIN" X=1
  check "(R1) the pre-fix binary fetched on the partial clone" '[ "$(grep -c fetched "$TMP/verdicts.base")" -gt 0 ]'
  read -r rc secs <<<"$(timed "$RIPWIRE_BASE_BIN" --for="caller f1")"
  check "(R2) the pre-fix binary outlived a silent git (rc=$rc ${secs}s)" '[ "$rc" != 0 ] && [ "$secs" -ge 29 ]'
fi

echo "historywalkcheck: $pass ok, $fail failed"
[ "$fail" = 0 ]
