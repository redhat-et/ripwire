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
#   (C) a URL root still reaches `git clone` with an allow-list that lets it out (a shim stands in: no network): the one command that
#       means to use the network. A caller's own GIT_ALLOW_PROTOCOL is honoured there.
#   (N) a walk over a rename still answers on the blobless clone, every commit read, no history_unread.
#   (N2) --pr-context names the changed files with no blob to diff; (N3) --quality-delta=REF refuses and names the partial clone.
#   (B) a long fixture (fast-import) under RIPWIRE_GIT_WALK_COMMITS: --for carries history_unread and the count; a warm second run still
#       does (the cut is cached); --cochange carries history_cut on stdout and stderr; --json stays parseable, the cut on stderr only;
#       a budget above the history is silent, and byte-identical to no budget at all.
#   (T) a git shim that prints the first commits of the real walk and then goes silent for an hour: --for, --cochange exit inside the
#       time budget's reach, disclosed; a shim silent from the first byte ends the same way.
#   (R) red, only when RIPWIRE_BASE_BIN names a pre-fix binary: (P) fetches and (T) outlives its timeout.
set -u
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
case " \$* " in *" clone "*) printf '%s\n' "\${GIT_ALLOW_PROTOCOL:-unset}" >>"$TMP/clone-allow"; exit 1 ;; esac
exec "$REALGIT" "\$@"
SH
chmod +x "$SHIMC/git"
( cd "$TMP" && PATH="$SHIMC:$PATH" TMPDIR="$TMP" "$BIN" "https://example.invalid/r.git" --refetch --no-cache >/dev/null 2>&1 )
check "(C1) a URL root's clone gets the network back, and never ext::" 'grep -q "^https:http:ssh:git:file$" "$TMP/clone-allow"'
: > "$TMP/clone-allow"
( cd "$TMP" && PATH="$SHIMC:$PATH" GIT_ALLOW_PROTOCOL=ssh TMPDIR="$TMP" "$BIN" "https://example.invalid/r.git" --refetch --no-cache >/dev/null 2>&1 )
check "(C2) ... and the caller's own allow-list stays the caller's" 'grep -q "^ssh$" "$TMP/clone-allow"'

# ── (N) the walk reads every commit of the blobless clone, rename included ──
fresh_partial "$CL"
( cd "$CL" && "$BIN" "$CL" --no-cache --for="edit f1" >"$TMP/out" 2>"$TMP/err" )
check "(N) --for on the blobless clone: the walk was read, no history_unread" '! grep -q history_unread "$TMP/out" && grep -q "churn=" "$TMP/out"'

git -C "$CL" log -1 >/dev/null
( cd "$CL" && "$BIN" "$CL" --no-cache --pr-context=HEAD~3 >"$TMP/out" 2>"$TMP/err" )
check "(N2) --pr-context on a base whose blobs are absent still lists the changed files" 'grep -q "moved.txt\|m1.c" "$TMP/out"'
( cd "$CL" && "$BIN" "$CL" --no-cache --quality-delta=HEAD~3 >"$TMP/out" 2>"$TMP/err" ); rc=$?
check "(N3) --quality-delta=REF that needs absent blobs refuses and says why (rc=$rc)" '[ "$rc" != 0 ] && grep -q "partial clone" "$TMP/err"'

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

# ── (T) the time budget against a git that stops talking ──
SHIMT="$TMP/shim-stall"; mkdir -p "$SHIMT"
cat > "$SHIMT/git" <<SH
#!/bin/sh
# Only the record walk stalls: it prints what real git prints for the first commits, then says nothing for an hour.
case " \$* " in
  *" --name-only "*" -z "*|*" -z --name-only "*)
    if [ -n "\${STALL_AT_START:-}" ]; then exec sleep 3600; fi
    "$REALGIT" "\$@" -n 5 2>/dev/null | cat; exec sleep 3600 ;;
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
