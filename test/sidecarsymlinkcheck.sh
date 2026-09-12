#!/usr/bin/env bash
# sidecarsymlinkcheck.sh — CWE-59 + CWE-367: a sidecar writer must refuse a symlink at its own fixed name,
# and the refusal must be the OPEN rather than a check the open then re-resolves behind.
#
# THE DEFECT THIS GATE OWNS (reported externally, reproduced on the shipped v0.6.0 binary). Three sidecar
# writers opened a FIXED-NAME destination with a TRUNCATING open that resolves the final path component
# through the filesystem's symlink layer — no O_NOFOLLOW, no lstat/S_ISLNK check:
#
#     .ripwire_quality_baseline   quality::writeBaseline     ofstream( path, trunc )
#     .ripwire_notes              notes::writeNotes          ofstream( path, trunc )
#     .ripwire_arch_baseline      archWriteBaseline          fopen( path, "w" )
#
# A repository carrying a symlink at one of those names turned ripwire's own write into an arbitrary-file
# truncate/overwrite ANYWHERE the invoking user can write. The reporter's proof-of-concept, reproduced here
# verbatim: a victim file holding `important user data` came back holding ripwire's baseline content, and
# `.ripwire_quality_baseline` was STILL A SYMLINK afterwards — the link was followed and its target
# destroyed, not replaced. Indexing a repository is a read-only-feeling act; it must not be able to eat a
# file outside the tree.
#
# WHY THE SYMLINK SURVIVING IS THE TELL, and why this gate asserts it. A tmp+rename publish (what the fourth
# sidecar, .ripwire_quality_acks, already uses) REPLACES the link entry with a regular file and leaves the
# target alone — data-losing in its own way, but not an arbitrary write. A truncating open does the exact
# opposite. So "the link is still a link and the target changed" is the signature of the vulnerable shape,
# and "the link is still a link and the target did NOT change" is the fixed shape. Both are asserted below.
#
# ROUND 2 — THE SECOND DEFECT, IN THE FIRST FIX (CWE-367, TOCTOU). The first fix was an lstat/S_ISLNK
# REFUSAL placed immediately before an unchanged truncating open. That is check-then-open: the answer was
# true when it was given and the open re-resolved the path afterwards, so a replacement landing in the gap
# made the write follow a link after all. The guard was ADVISORY — it described the destination, it did not
# constrain the open. The remedy is that the check and the create are now ONE syscall:
#
#     ::open( path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0666 )   (src/pathguard.h; O_NONBLOCK since round 4, and the
#     O_TRUNC it once carried is now an ftruncate that runs only after the regular-file check)
#
# and the three writers hold the resulting descriptor. There is no window because there is no second
# resolution. The pre-open lstat is GONE from all three writers — which is what makes the (a)/(b) arms
# below mean more than they did: with nothing but O_NOFOLLOW left to refuse with, a green (b) IS the open
# refusing. lstat survives only INSIDE pathguard.h, after a failed open, to decide which sentence ELOOP
# earns; it cannot decide whether to write.
#
# The (r) arms exercise the race directly, and it is worth being exact about what they can prove. They plant
# nothing: a fast swapper (python3 symlink/unlink in a loop) runs alongside repeated verb runs, so the
# destination alternates between absent and a symlink while the writer opens it. The swapper has to be fast —
# a fork-per-swap shell loop rarely lands in the window, and would let this arm pass against the defect it
# exists to catch.
#
# WHAT IT CANNOT PROVE. The arm is ONE-SIDED. Its green means "nothing was observed", not "no window
# exists": a window narrower than the swapper's cycle would pass it. It is a detector for the defect being
# closed, not a proof of atomicity. The proof is structural and lives in the (e)/(f) arms, which assert the MECHANISM: the
# one open carries O_NOFOLLOW, all three writers go through it, and no pre-open symlink predicate survives
# at any of them to be relied on again. (e)/(f) are SOURCE arms — they read $ROOT/src and do NOT move when
# $BIN points at another build, which is worth knowing when reading a red-first run against a base binary.
#
# ARM MAP — discriminating arms first:
#
#     per sidecar:  (a) the victim's bytes are UNTOUCHED after the verb runs
#                   (b) the tool REFUSED — non-zero exit AND a stderr line naming the symlink
#                   (r) THE RACE: with the destination alternating absent↔symlink under a fast swapper,
#                       the victim survives EVERY run — red on the check-then-open build, and one-sided
#                       by construction (see above)
#                   (h) a non-symlink open failure (a DIRECTORY at the sidecar name) is reported with the
#                       real OS reason and is NOT dressed up as a symlink — round 2 added the errno
#                       distinction, so this arm was red before it and is what stops "every failure is a
#                       symlink" from passing (a)/(b)
#     per writer:   (e) MECHANISM: each sidecar has ONE named acquire seam (openBaselineSidecar /
#                       openNotesSidecar / openArchBaselineSidecar); it opens through pathguard's atomic
#                       no-follow create and carries the site's unchanged DEGRADED_PATH_ALERT for the ELOOP
#                       case, the writer takes its descriptor from it and opens nothing itself, and neither
#                       body holds an ofstream/fopen following primitive or a pre-open symlink predicate
#                   (e5/e6) WRITE INTEGRITY: the writer RETURNS pathguard::writeAllAndClose's verdict over the
#                       bytes it assembled (e5), and no stdio stream survives in its body — no fdopen, fclose,
#                       emitRaw or emitTo (e6). Red on archWriteBaseline before it took that shape: its FILE*
#                       emitters report no failed write, and fclose answers only for its own final flush, so a
#                       failed EARLIER flush could still come back true. The two siblings already had the shape,
#                       so on them these rows are green before and after — a regression guard there
#     once:         (f) MECHANISM: src/pathguard.h has exactly TWO ::open — one write open carrying
#                       O_WRONLY/O_CREAT/O_NOFOLLOW and no O_TRUNC, truncating with ftruncate only after its
#                       regular-file check (f1), and one read open carrying O_RDONLY|O_NOFOLLOW
#                       (f3, round 3); and refuseSymlinkWrite — the advisory check-then-open guard — is gone
#                       from src/ entirely, not merely unused (f2)
#
# Arms that are green before AND after are labelled so rather than left to look like coverage they are not
# (CONTRIBUTING §2, shape 7 — an arm asserting something strictly weaker than its name implies). They still
# assert real properties worth holding:
#
#     (c) the planted symlink is still there, still pointing at the victim — refusing must not quietly
#         unlink or replace the user's own entry. Green before AND after; it pins the no-side-effect half.
#     (d) NEGATIVE CONTROL (the reporter's own): with NO symlink present, the verb writes the sidecar
#         normally, as a REGULAR file with real content. Green before and after by design — it is what
#         stops the fix from being "refuse always", which would pass every (a)/(b) arm and break the tool.
#     (g) MODE CONTROL: under `umask 000` each sidecar is created 0666 — what ofstream( trunc ) and
#         fopen( "w" ) both requested before round 2, measured on the pre-change binary, not assumed. Green
#         before and after; it exists because moving to ::open means naming the mode by hand, and 0644
#         written there is invisible under the usual umask 022 (0666 & ~022 == 0644 & ~022). Observed RED
#         with a deliberate 0600 in the open.
#     (w) BYTES (arch baseline): the sidecar equals a file this gate computes from NUMBERS, never one captured
#         from a build — the header line, then one 16-digit zero-padded lowercase hex hash per line, ascending and
#         deduplicated, the shape archReadBaseline and every committed sidecar depend on. (w1) is a plain
#         --baseline over the fixture (no violations, so the header alone); (w2) plants 304 hashes through
#         --baseline-update, spelled so that dropping the padding, upper-casing, or skipping the sort or the
#         dedupe each moves a byte, and past 4096 B so the stdio writer needed more than one flush for it. Green
#         before and after by design: it is the evidence that moving archWriteBaseline onto writeAllAndClose
#         moved no byte. Observed RED with a deliberate `{:x}` in the writer: exit 0, and the 21 rows that
#         start with a zero digit came back unpadded.
#     (x) WRITE FAILURE, a REGRESSION GUARD and not a proof (arch baseline): the (w2) update again under a zero
#         file-size limit with SIGXFSZ ignored, so every write(2) to the sidecar fails. The verb must exit
#         non-zero, name the sidecar it could not write, claim no update, and leave no bytes. The pre-change
#         binary passes it too: swept at every planted size from 1 to 600 rows on macOS, it never reported
#         success, because when EVERY write is refused its fclose still returns the failure. The defect (e5)/(e6)
#         pin needs an earlier failed flush followed by a final one that succeeds — a transient failure no gate
#         can schedule deterministically — so (e5)/(e6) are the proof and (x) only holds the contract in place.
#
# ROUND 3 — THE READERS OF THE SAME THREE NAMES. A deliberate decision, pinned here rather than assumed.
# Rounds 1-2 closed the WRITE half and left every reader following a link: notes::readNotes,
# quality::readBaseline / readBaselineHeadSha / readBaselineAbsorbed, archReadBaseline, and a bare ifstream
# presence probe in the arch verb, whether the link's target was inside the crawl root or not. The round-3
# arms at the bottom of this file were red on the round-2 binary.
#
# DECISION (b): refuse the link on READ too, by O_NOFOLLOW at the open. Not (a), leave the readers following;
# not (c), refuse only a link that leaves the crawl root. The argument is in src/pathguard.h. The arms, each
# named for the alternative it fails under:
#
#     per sidecar:  (n) NEGATIVE CONTROL: the same payload as a REGULAR file is still read and used. Green
#                       before and after; without it, "never read the sidecar" passes every arm below
#                   (k) a link to a VALID payload OUTSIDE the tree is not used, the verb still produces its
#                       document, and stderr names the refusal. Red under (a). For arch, (k2) also requires
#                       the violation that payload would have accepted to come back NEW, with exit 2
#                   (i) THE DECISION PIN: a link to the same payload INSIDE the crawl root is refused as well.
#                       Red under (a) AND under (c) — the only arm that tells (b) from (c)
#                   (t) NEVER OPENED: with the link aimed at a FIFO, no reading verb opens its target at all.
#                       A read whose bytes are discarded (--note-add reads before it writes; the arch probe
#                       reads nothing) can never fail a content arm, so this is its only observable. (t0) is
#                       the probe's positive control: `cat` on the same FIFO must count as an open (shape 5)
#     quality:      (q) the refusal is named IN the document — baseline="git-HEAD (symlinked sidecar refused)"
#                       from the CLI and from MCP, never the "no sidecar existed" marker — and a tree with no
#                       HEAD to fall back to fails without calling the linked sidecar missing
#     per reader:   (m) MECHANISM (source arms, like (e)): each reader takes its bytes from its sidecar's read
#                       seam, the seam reads through pathguard's O_NOFOLLOW read and carries the site's own
#                       DEGRADED_PATH_ALERT, and no following open survives in a reader or in the arch verb;
#                       (f3) pins the read open's flags
#
# ROUND 4 — A NON-REGULAR FILE AT THE NAME, AND A READ THAT HOLDS ONE LINE. A FIFO planted AT a sidecar name
# (no link involved) blocked both opens, read and write, and the round-3 read kept the whole file in memory
# where the stream it replaced held one line. Both opens now carry
# O_NONBLOCK and refuse anything fstat does not report as a regular file, and the readers stream from the
# descriptor:
#
#     per sidecar:  (v1) a READ verb finishes with a FIFO at the name — red on the round-3 binary, which blocked
#                   (v2) a WRITE verb finishes too, exits non-zero, and leaves the FIFO in place — red likewise
#                   (v3) a WRITE verb with a READER holding that FIFO open — the one case where the open succeeds —
#                       exits non-zero and puts no byte into the pipe. Red on the round-3 binary, which wrote the
#                       sidecar into the pipe and exited 0 (or, for --note-add, waited in its read first)
#     once:         (f4) MECHANISM: both opens carry O_NONBLOCK and an fstat S_ISREG check decides before any
#                       byte moves — the pin for non-regular files this gate cannot plant (a device node needs root)
#                   (f5) MECHANISM: the read half holds no whole-file buffer and reads a line at a time through
#                       POSIX getline — neither a buffered copy of the file nor a call per byte
#     per reader:   (m5) MECHANISM: the reader parses a line at a time from the sidecar handle
#     (f5) and (m5) pin memory and cost by SHAPE. Nothing here measures either: RSS and timing are not comparable
#     between the dev and ASan builds this gate runs on, so a threshold would be a guess.
#
# Usage:
#   bash test/sidecarsymlinkcheck.sh                 |  bash test/sidecarsymlinkcheck.sh asan/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/sidecarsymlinkcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams: regression.sh and every differential run pass the binary POSITIONALLY; RIPWIRE_BIN is the
# env form. A gate reading only one of them comes back ALL PASS against whatever is in build/ during a
# red-first run against a BASE binary — the exact way a red-first check fakes itself green (archcheck.sh
# carries the same note for the same reason).
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "sidecarsymlinkcheck: BIN=$BIN  TMP=$TMP"

# The sentinel the reporter used. Its exact bytes are the thing every (a) arm compares against, so the
# comparison can never degrade into "empty matches empty" (CONTRIBUTING §2, shape 3).
VICTIM_BYTES='important user data'

# ── fixture: a tiny indexable tree, deliberately NOT a git checkout ───────────────────────────────────
# Both --quality-baseline and --note-add degrade cleanly on a non-git root (undated note, empty HEAD
# stamp) and still write their sidecar, so the gate owes nothing to git config, committer identity or
# clone depth. The arch rules file produces a real layer pair so --baseline has something to accept.
mkTree()
{
    local dir="$1"
    rm -rf "$dir"; mkdir -p "$dir/sub"
    printf '#include <stdio.h>\nint helper( int x ) { return x + 1; }\nint main( void ) { printf( "%%d\\n", helper( 1 ) ); return 0; }\n' >"$dir/a.c"
    printf 'int other( int y ) { return y * 2; }\n' >"$dir/sub/b.c"
    printf 'layer core = a.c\nlayer consumer = sub/\ndeny consumer -> core\n' >"$dir/rules.txt"
}

# ── one full symlink arm, run for each of the three sidecars ──────────────────────────────────────────
# `label`     — human name for the rows
# `sidecar`   — the fixed file name the writer opens
# `runner`    — a function name; called with the tree dir, must invoke the verb that writes `sidecar`
#
# The victim lives OUTSIDE the indexed tree on purpose: that is the whole claim — a repository reaching a
# file the repository does not contain.
symlinkArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/$label/tree" victim="$TMP/$label/outside/victim.txt"

    mkTree "$tree"
    mkdir -p "$( dirname "$victim" )"
    printf '%s\n' "$VICTIM_BYTES" >"$victim"
    cp "$victim" "$TMP/$label.pristine"

    # PRESENCE GUARDS — assert the things the arm is about to measure actually exist, before trusting any
    # verdict over them. A vanished victim or an un-planted symlink would make (a) pass while proving
    # nothing (CONTRIBUTING §2, "a vanishing probe target").
    if [ -s "$victim" ] && grep -q "$VICTIM_BYTES" "$victim"; then
        ok "$label: (guard) victim file exists outside the tree, holding the sentinel bytes"
    else
        no "$label: (guard) victim file was not created with the sentinel bytes — every arm below is void"
        return
    fi

    ln -s "$victim" "$tree/$sidecar"
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (guard) symlink planted at $sidecar → the victim"
    else
        no "$label: (guard) could not plant the symlink at $sidecar — every arm below is void"
        return
    fi

    local rc=0
    "$runner" "$tree" >"$TMP/$label.out" 2>"$TMP/$label.err" || rc=$?

    # ── (a) DISCRIMINATING: the victim's bytes survive ────────────────────────────────────────────────
    if cmp -s "$TMP/$label.pristine" "$victim"; then
        ok "$label: (a) victim file is byte-identical after the verb ran"
    else
        no "$label: (a) VICTIM OVERWRITTEN through the symlink — $( wc -c <"$TMP/$label.pristine" | tr -d ' ' ) B became $( wc -c <"$victim" | tr -d ' ' ) B: $( head -c 60 "$victim" )"
    fi

    # ── (b) DISCRIMINATING: the refusal is LOUD ───────────────────────────────────────────────────────
    # Not writing is not enough. A silent skip leaves the user believing a sidecar exists that does not,
    # which is its own defect — so the verb must exit non-zero AND say on stderr that it refused and why.
    if [ "$rc" -ne 0 ]; then
        ok "$label: (b1) verb exited non-zero ($rc) rather than reporting success"
    else
        no "$label: (b1) verb exited 0 — a write that was refused (or worse, redirected) reported success"
    fi
    if grep -q 'refusing to write' "$TMP/$label.err" && grep -q 'symlink' "$TMP/$label.err"; then
        ok "$label: (b2) stderr names the refusal and the reason (symlink)"
    else
        no "$label: (b2) stderr carries no symlink refusal — user is not told why the sidecar is missing: $( head -c 120 "$TMP/$label.err" )"
    fi

    # ── (c) NOT DISCRIMINATING (green before and after): refusing has no side effect on the entry ─────
    if [ -L "$tree/$sidecar" ] && [ "$( readlink "$tree/$sidecar" )" = "$victim" ]; then
        ok "$label: (c) the user's symlink entry is left exactly as it was (not unlinked, not replaced)"
    else
        no "$label: (c) the symlink entry was modified — refusing must not touch the user's own entry"
    fi
}

# ── (d) NEGATIVE CONTROL, run for each sidecar: no symlink → normal write ─────────────────────────────
# This is the arm that keeps the fix honest. "Refuse whenever the destination exists", or "refuse always",
# satisfies every (a) and (b) arm above and breaks the three verbs completely; only this arm notices.
controlArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_ctl/tree"

    mkTree "$tree"
    local rc=0
    "$runner" "$tree" >"$TMP/${label}_ctl.out" 2>"$TMP/${label}_ctl.err" || rc=$?

    if [ "$rc" -eq 0 ]; then
        ok "$label: (d1) no symlink present → verb exits 0"
    else
        no "$label: (d1) no symlink present → verb exited $rc: $( head -c 120 "$TMP/${label}_ctl.err" )"
    fi
    if [ -f "$tree/$sidecar" ] && [ ! -L "$tree/$sidecar" ] && [ -s "$tree/$sidecar" ]; then
        ok "$label: (d2) sidecar written normally as a regular, non-empty file"
    else
        no "$label: (d2) sidecar not written as a regular non-empty file — the guard broke the normal path"
    fi
}

# ── the three runners ─────────────────────────────────────────────────────────────────────────────────
runQualityBaseline(){ "$BIN" "$1" --quality-baseline --no-cache; }
runNoteAdd(){ "$BIN" "$1" --note-add="a.c: sidecar symlink gate" --no-cache; }
# archBaselinePath() returns a BARE file name, resolved against the process CWD rather than the crawl
# root — so this runner must cd into the tree for the sidecar to land there at all. That is current,
# deliberate behaviour (the sidecar is rules-file-independent and repo-committable); the arm is written
# around it rather than against it. If the destination is ever root-qualified, delete the subshell cd
# and nothing else here changes.
runArchBaseline(){ ( cd "$1" && "$BIN" "$1" --arch=rules.txt --baseline --no-cache ); }

symlinkArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
symlinkArm notes           .ripwire_notes            runNoteAdd
symlinkArm archbaseline    .ripwire_arch_baseline    runArchBaseline

controlArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
controlArm notes           .ripwire_notes            runNoteAdd
controlArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (e) MECHANISM (round 2, CWE-367): the refusal IS the open, and nothing before it ──────────────────
# Source arms. They read $ROOT/src and do not follow $BIN, so a red-first run against a base BINARY sees
# the CURRENT tree here — which is the point: what they pin is the shape of the code, and the shape is the
# only place atomicity is observable without an lstat interposer (see the header).
#
# Full-line `//` comments are stripped before the absence checks, because the comments at these sites
# name the ofstream/fopen they replaced — quoting the defect must not read as committing it.
extractFn()
{
    awk -v sig="$2" 'index( $0, sig ) { inFn = 1 } inFn { print } inFn && /^}$/ { exit }' "$1" \
        | grep -v '^[[:space:]]*//'
}

mechArm()
{
    local label="$1" src="$2" acquireSig="$3" writerSig="$4" acquireFn="$5" alert="$6"
    local acq="$TMP/acq_$label.txt" body="$TMP/body_$label.txt"

    extractFn "$ROOT/$src" "$acquireSig" >"$acq"
    extractFn "$ROOT/$src" "$writerSig"  >"$body"

    # PRESENCE GUARD — an extraction that returned nothing makes every absence check below pass for the
    # emptiest possible reason (CONTRIBUTING §2, shape 3: nothing matches nothing).
    local acqLines bodyLines
    acqLines="$( wc -l <"$acq" | tr -d ' ' )"
    bodyLines="$( wc -l <"$body" | tr -d ' ' )"
    if [ "$acqLines" -ge 4 ] && [ "$bodyLines" -ge 5 ] && grep -q 'return' "$acq" && grep -q 'return' "$body"; then
        ok "$label: (e0/guard) extracted $acqLines code lines of $acquireFn and $bodyLines of the writer from $src"
    else
        no "$label: (e0/guard) could not extract both bodies from $src (acquire=$acqLines writer=$bodyLines) — (e1)-(e6) are void"
        return
    fi

    if grep -q 'openNoFollowTruncate' "$acq"; then
        ok "$label: (e1) $acquireFn opens through pathguard's atomic O_NOFOLLOW create"
    else
        no "$label: (e1) no openNoFollowTruncate in $acquireFn — the destination is resolved by something else"
    fi

    # The things that must NOT be there, in EITHER body: a following primitive of either flavour, and any
    # pre-open symlink predicate. The second half is the round-2 finding itself — an advisory check that the
    # code then relies on is the defect, so its ABSENCE is the property, not the presence of a better check.
    local leftovers=""
    grep -qh 'std::ofstream'      "$acq" "$body" && leftovers="$leftovers ofstream"
    grep -qh 'std::fopen'         "$acq" "$body" && leftovers="$leftovers fopen"
    grep -qh 'refuseSymlinkWrite' "$acq" "$body" && leftovers="$leftovers refuseSymlinkWrite"
    grep -qh 'isSymlink'          "$acq" "$body" && leftovers="$leftovers isSymlink"
    grep -qh 'lstat'              "$acq" "$body" && leftovers="$leftovers lstat"
    if [ -z "$leftovers" ]; then
        ok "$label: (e2) no following primitive and no pre-open symlink predicate survives at the site"
    else
        no "$label: (e2) check-then-open shape still present at the site:$leftovers"
    fi

    # "Same exit path, same alert" is a promise about THIS site, so it is asserted at this site.
    if grep -qF "$alert" "$acq"; then
        ok "$label: (e3) the site's own DEGRADED_PATH_ALERT for the symlink case is unchanged"
    else
        no "$label: (e3) the site's DEGRADED_PATH_ALERT text changed — expected: $alert"
    fi

    # The seam is only worth anything if the WRITER actually writes through the descriptor it hands back.
    if grep -q "$acquireFn(" "$body"; then
        ok "$label: (e4) the writer takes its descriptor from $acquireFn and opens nothing itself"
    else
        no "$label: (e4) the writer does not call $acquireFn — it acquires its destination some other way"
    fi

    # (e5)/(e6) WRITE INTEGRITY — a writer's result has to answer for its bytes, and a stdio stream adopted from
    # the descriptor cannot: the FILE* emitters report no failed write, and fclose answers only for its OWN final
    # flush. Anchored on `return`, because a writeAllAndClose whose verdict is dropped would pass a bare grep.
    if grep -Eq 'return[[:space:]]+(rw::pathguard::)?writeAllAndClose\(' "$body"; then
        ok "$label: (e5) the writer returns writeAllAndClose's verdict over the bytes it assembled"
    else
        no "$label: (e5) the writer does not return writeAllAndClose's verdict — its result does not answer for a failed write"
    fi
    local streams=""
    grep -qh 'fdopen'  "$body" && streams="$streams fdopen"
    grep -qh 'fclose'  "$body" && streams="$streams fclose"
    grep -qh 'emitRaw' "$body" && streams="$streams emitRaw"
    grep -qh 'emitTo'  "$body" && streams="$streams emitTo"
    if [ -z "$streams" ]; then
        ok "$label: (e6) no stdio stream survives in the writer (no fdopen, fclose, emitRaw or emitTo)"
    else
        no "$label: (e6) the writer still writes through a stdio stream:$streams"
    fi
}

mechArm qualitybaseline src/quality.h 'inline int openBaselineSidecar( const std::string& path )' \
        'inline bool writeBaseline( const Snapshot& s, const std::string& path' 'openBaselineSidecar' \
        'quality: refusing to write the baseline sidecar through a symlink'
mechArm notes           src/notes.h   'inline int openNotesSidecar( const std::string& path )' \
        'inline bool writeNotes( const std::string& path' 'openNotesSidecar' \
        'notes: refusing to write the notes sidecar through a symlink'
mechArm archbaseline    src/arch.h    'inline int openArchBaselineSidecar( const std::string& sidecarPath )' \
        'inline bool archWriteBaseline( const std::string&' 'openArchBaselineSidecar' \
        'arch: refusing to write the arch baseline sidecar through a symlink'

# ── (f) MECHANISM: the two opens, and the advisory guard that must not come back ──────────────────────
# Round 3 put the READ open beside the write open, so the census is two, and each is pinned by the flags that
# make it what it is: a second write open, a write open without O_NOFOLLOW, or a read open that lost it all
# fail here rather than hiding inside a count that happens to still be right.
PG="$ROOT/src/pathguard.h"
PGCODE="$TMP/pathguard_code.txt"
grep -v '^[[:space:]]*//' "$PG" >"$PGCODE"
openLines="$( grep -c '::open(' "$PGCODE" | tr -d ' ' )"
writeOpens="$( grep '::open(' "$PGCODE" | grep -c 'O_WRONLY' | tr -d ' ' )"
readOpens="$( grep '::open(' "$PGCODE" | grep -c 'O_RDONLY' | tr -d ' ' )"
# The write open does NOT truncate. With O_TRUNC on the open, an existing regular sidecar was emptied before the
# fstat check had looked at anything; the writer now truncates the descriptor with ftruncate, and only after fstat has
# confirmed a regular file. (w2) is the behavioural half: a rewrite over a longer planted baseline must still come
# out byte-identical, which it cannot if the truncation stopped happening.
WTRUNC="$TMP/pathguard_truncate_fn.txt"
awk '/inline OpenedFile openNoFollowTruncate\(/ { f = 1 } f { print } f && /^}$/ { exit }' "$PGCODE" >"$WTRUNC"
if [ "$openLines" = "2" ] && [ "$writeOpens" = "1" ] && [ -s "$WTRUNC" ] \
   && grep '::open(' "$PGCODE" | grep 'O_WRONLY' | grep -q 'O_CREAT' \
   && grep '::open(' "$PGCODE" | grep 'O_WRONLY' | grep -q 'O_NOFOLLOW' \
   && ! grep '::open(' "$PGCODE" | grep 'O_WRONLY' | grep -q 'O_TRUNC' \
   && awk '/S_ISREG/ { seen = 1 } seen && /::ftruncate\(/ { found = 1 } END { exit !found }' "$WTRUNC"; then
    ok "pathguard: (f1) exactly two ::open; the write open carries O_WRONLY|O_CREAT|O_NOFOLLOW and no O_TRUNC, and ::ftruncate runs only after the S_ISREG check"
else
    no "pathguard: (f1) expected two ::open, one write open with O_WRONLY|O_CREAT|O_NOFOLLOW and no O_TRUNC, and an ::ftruncate after the S_ISREG check — found $openLines open(s), $writeOpens write, $( wc -l <"$WTRUNC" | tr -d ' ' ) line(s) of openNoFollowTruncate: $( grep '::open(' "$PGCODE" | tr '\n' ' ' | head -c 200 )"
fi
if [ "$readOpens" = "1" ] \
   && grep '::open(' "$PGCODE" | grep 'O_RDONLY' | grep -q 'O_NOFOLLOW' \
   && ! grep '::open(' "$PGCODE" | grep 'O_RDONLY' | grep -qE 'O_WRONLY|O_CREAT|O_TRUNC'; then
    ok "pathguard: (f3) exactly one read ::open, carrying O_RDONLY|O_NOFOLLOW and nothing that creates or truncates"
else
    no "pathguard: (f3) expected exactly one read ::open carrying O_RDONLY|O_NOFOLLOW — found $readOpens: $( grep '::open(' "$PGCODE" | tr '\n' ' ' | head -c 240 )"
fi

# Round 4: a descriptor that is not a regular file is refused before a byte moves. O_NONBLOCK is what lets the
# open RETURN for a FIFO with nobody at the other end; the fstat check is what refuses it, and any other
# non-regular file, once it has. Either half alone is wrong: without the first the open still waits, without
# the second the tool reads from, or writes into, a pipe.
nonblockOpens="$( grep '::open(' "$PGCODE" | grep -c 'O_NONBLOCK' | tr -d ' ' )"
fstatCalls="$( grep -c '::fstat(' "$PGCODE" | tr -d ' ' )"
regChecks="$( grep -c 'S_ISREG' "$PGCODE" | tr -d ' ' )"
if [ "$nonblockOpens" = "2" ] && [ "$fstatCalls" -ge 2 ] && [ "$regChecks" -ge 2 ]; then
    ok "pathguard: (f4) both opens carry O_NONBLOCK, and an fstat S_ISREG check follows each"
else
    no "pathguard: (f4) expected O_NONBLOCK on both opens and an fstat S_ISREG check after each — found O_NONBLOCK on $nonblockOpens open(s), $fstatCalls fstat call(s), $regChecks S_ISREG test(s)"
fi

# Round 4: the read half hands its caller a LINE at a time. The round-3 read accumulated the whole file into a
# string (`std::string bytes`, grown by `resize( used + … )`) before any parsing began; the stream it replaced
# held one line. It now reads through POSIX getline over the descriptor's stream, a buffered read as cheap as the
# std::ifstream readers. Not rw::readByteSafeLine: a call per byte measured ~15× slower on 64 MB of sidecar
# lines. Not a custom streambuf under std::getline: libc++ narrows a high byte through its no-get-area fallback,
# which aborts the sanitizer build (src/infra/stdinline.h). This arm pins the SHAPE; it measures no cost.
if grep -qE 'std::string[[:space:]]+bytes|resize\( used' "$PGCODE"; then
    no "pathguard: (f5) the read half still accumulates the whole file: $( grep -nE 'std::string[[:space:]]+bytes|resize\( used' "$PGCODE" | tr '\n' ' ' | head -c 200 )"
elif ! grep -q '::getline(' "$PGCODE" || grep -q 'readByteSafeLine(' "$PGCODE"; then
    no "pathguard: (f5) the read half does not read a line at a time through POSIX ::getline — a per-byte reader, or some other shape whose cost is unpinned"
else
    ok "pathguard: (f5) the read half holds no whole-file buffer and reads a line at a time through POSIX ::getline"
fi

if grep -rq 'refuseSymlinkWrite' "$ROOT/src"; then
    no "pathguard: (f2) refuseSymlinkWrite (the advisory check-then-open guard) is still in src/: $( grep -rl 'refuseSymlinkWrite' "$ROOT/src" | tr '\n' ' ' )"
else
    ok "pathguard: (f2) the advisory check-then-open guard is gone from src/, not merely unused"
fi

# ── (g) MODE CONTROL: the hand-written mode must equal what ofstream/fopen asked for ──────────────────
# umask 000 is what makes this discriminating: under the usual 022 a wrong 0644 is indistinguishable from
# the correct 0666. GNU stat and BSD stat disagree about -f, so pick the flavour once (CONTRIBUTING §1).
if stat --version >/dev/null 2>&1; then
    fileMode(){ stat -c '%a' "$1"; }
else
    fileMode(){ stat -f '%Lp' "$1"; }
fi

modeArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_mode/tree"

    mkTree "$tree"
    ( umask 000; "$runner" "$tree" ) >"$TMP/${label}_mode.out" 2>"$TMP/${label}_mode.err"

    if [ ! -f "$tree/$sidecar" ]; then
        no "$label: (g) sidecar was not written under umask 000 — the mode arm is void"
        return
    fi
    local mode
    mode="$( fileMode "$tree/$sidecar" )"
    if [ "$mode" = "666" ]; then
        ok "$label: (g) created 0666 under umask 000 — the mode ofstream/fopen asked for, unchanged"
    else
        no "$label: (g) created 0$mode under umask 000, not 0666 — the open's mode argument changed the permissions"
    fi
}

modeArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
modeArm notes           .ripwire_notes            runNoteAdd
modeArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (h) an open failure that is NOT a symlink must not be reported as one ─────────────────────────────
# A directory at the sidecar name is the cheapest deterministic non-ELOOP failure there is (EISDIR on both
# targets, strerror "Is a directory"). Round 1 mapped nothing to errno at all, so the real reason never
# reached the user; round 2 must report it AND must not reach for the symlink sentence, which would be a
# false security claim rather than a diagnosis.
notLinkArm()
{
    local label="$1" sidecar="$2" runner="$3"
    local tree="$TMP/${label}_dir/tree"

    mkTree "$tree"
    mkdir -p "$tree/$sidecar"
    if [ ! -d "$tree/$sidecar" ] || [ -L "$tree/$sidecar" ]; then
        no "$label: (h/guard) could not plant a directory at $sidecar — the arm below is void"
        return
    fi

    local rc=0
    "$runner" "$tree" >"$TMP/${label}_dir.out" 2>"$TMP/${label}_dir.err" || rc=$?

    if [ "$rc" -ne 0 ]; then
        ok "$label: (h1) a directory at the sidecar name is a refusal, not a success ($rc)"
    else
        no "$label: (h1) verb exited 0 with a directory at the sidecar name — nothing was written and it said so anyway"
    fi
    if grep -qi 'directory' "$TMP/${label}_dir.err" && ! grep -q 'symlink' "$TMP/${label}_dir.err"; then
        ok "$label: (h2) stderr gives the real OS reason and does not dress it up as a symlink"
    else
        no "$label: (h2) stderr is not honest about a non-symlink failure: $( head -c 200 "$TMP/${label}_dir.err" | tr '\n' ' ' )"
    fi
}

notLinkArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
notLinkArm notes           .ripwire_notes            runNoteAdd
notLinkArm archbaseline    .ripwire_arch_baseline    runArchBaseline

# ── (w) BYTES and (x) WRITE FAILURE: what archWriteBaseline puts on disk, and what it says when it cannot ────
# What each proves, and what (x) cannot, is in the header. Every expected row is rendered by THIS script's own
# printf from a number — never copied from the planted text or from any build's output — so (w) is not the
# writer compared against itself.
ARCH_HEADER='# ripwire arch baseline — do not edit by hand. Regenerate with --baseline or --baseline-update.'
ARCH_MUL=$(( 0x9E3779B97F4A7C15 ))   # 2^64/φ: i × this (mod 2^64) spreads 1..300 over the whole 64-bit range

runArchBaselineUpdate(){ ( cd "$1" && "$BIN" "$1" --arch=rules.txt --baseline-update --no-cache ); }

ARCH_DIR="$TMP/archbytes"
ARCH_TREE="$TMP/archbytes/tree"
ARCH_SIDE="$TMP/archbytes/tree/.ripwire_arch_baseline"
ARCH_PLANTED="$TMP/archbytes/planted.txt"
ARCH_WANT="$TMP/archbytes/want.txt"

# The planted sidecar and its expectation. Returns non-zero, having said why, when the population (w2) and (x)
# need is not there — so neither runs over a void fixture.
archPlant()
{
    local i rows lead0 bytes

    mkTree "$ARCH_TREE"
    # Planted: 300 generated rows in DESCENDING i, which is not ascending value; then the rows a renderer gets
    # wrong — small values (padding), one spelled unpadded, one upper-case, all ones, and a duplicate of 1 in its
    # canonical spelling; and a comment and a blank line, which the reader skips.
    {
        printf '# planted by sidecarsymlinkcheck (w2)\n\n'
        for (( i = 300; i >= 1; i-- )); do printf '%016x\n' $(( i * ARCH_MUL )); done
        printf '1\nFF\n00000000DEADBEEF\nffffffffffffffff\n0000000000000001\n'
    } >"$ARCH_PLANTED"
    # Expected, from the VALUES: the 300 generated plus 1, 255, 0xdeadbeef and 2^64-1 (bash's -1), each rendered
    # as 16 lowercase digits, then byte-sorted and deduplicated — which for fixed-width lowercase hex IS ascending
    # numeric order.
    {
        printf '%s\n' "$ARCH_HEADER"
        {
            for (( i = 1; i <= 300; i++ )); do printf '%016x\n' $(( i * ARCH_MUL )); done
            printf '%016x\n' 1 255 3735928559 -1
        } | LC_ALL=C sort -u
    } >"$ARCH_WANT"

    # GUARD — 304 distinct well-formed rows (a collapsed generator would dedupe to fewer), deep zero padding and
    # hex letters present, past one 4096-byte stdio buffer, and different from the planted text, so a writer that
    # left the file alone cannot match it.
    rows="$( tail -n +2 "$ARCH_WANT" | grep -c '^[0-9a-f]\{16\}$' )"
    lead0="$( tail -n +2 "$ARCH_WANT" | grep -c '^0' )"
    bytes="$( wc -c <"$ARCH_WANT" | tr -d ' ' )"
    if [ "$rows" = 304 ] && [ "$( wc -l <"$ARCH_WANT" | tr -d ' ' )" = 305 ] && grep -q '^00000000' "$ARCH_WANT" \
       && tail -n +2 "$ARCH_WANT" | grep -q '[a-f]' && [ "$bytes" -gt 4096 ] && ! cmp -s "$ARCH_PLANTED" "$ARCH_WANT"; then
        ok "archbaseline: (w2/guard) the expectation holds 304 distinct 16-digit rows ($lead0 with a leading zero, hex letters present, $bytes B) and differs from the planted text"
        return 0
    fi
    no "archbaseline: (w2/guard) the expectation is not the population (w2) needs (rows=$rows lead0=$lead0 bytes=$bytes) — (w1), (w2) and (x) are void"
    return 1
}

# (w1) a plain --baseline over the fixture, which has no violations, is the header line and nothing else — read
# from the (d) control's sidecar rather than running the verb again. (w2) the planted set through
# --baseline-update, compared with the expectation archPlant computed.
archBytesArm()
{
    local ctlSide="$TMP/archbaseline_ctl/tree/.ripwire_arch_baseline" rc=0

    printf '%s\n' "$ARCH_HEADER" >"$ARCH_DIR/header_only.txt"
    if ! grep -qF '(0 violation(s) accepted)' "$TMP/archbaseline_ctl.err"; then
        no "archbaseline: (w1/guard) the (d) control did not accept 0 violations, so header-only is not the expectation: $( head -c 160 "$TMP/archbaseline_ctl.err" )"
    elif cmp -s "$ARCH_DIR/header_only.txt" "$ctlSide"; then
        ok "archbaseline: (w1) --baseline with no violations wrote exactly the header line"
    else
        no "archbaseline: (w1) the --baseline sidecar is not exactly the header line: $( head -c 160 "$ctlSide" | tr '\n' ' ' )"
    fi

    cp "$ARCH_PLANTED" "$ARCH_SIDE"
    runArchBaselineUpdate "$ARCH_TREE" >"$ARCH_DIR/w2.out" 2>"$ARCH_DIR/w2.err" || rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$ARCH_WANT" "$ARCH_SIDE"; then
        ok "archbaseline: (w2) --baseline-update rewrote the planted set byte-identical to the computed expectation"
    else
        no "archbaseline: (w2) rc=$rc and the sidecar is not the expected bytes: $( diff "$ARCH_WANT" "$ARCH_SIDE" 2>&1 | head -n 6 | tr '\n' ' ' )"
    fi
}

# (x) The same update under a zero file-size limit. Both streams go to a PIPE and the limit is set inside the
# subshell that execs the verb: RLIMIT_FSIZE applies to every regular file the limited process writes, so a file
# redirect would make the failure message fail to land too. `trap '' XFSZ` turns the signal into an EFBIG return
# from write(2) instead of a kill; an ignored disposition survives exec.
archWriteFailArm()
{
    local rc
    cp "$ARCH_PLANTED" "$ARCH_SIDE"
    ( cd "$ARCH_TREE" || exit 97; ulimit -f 0 || exit 98; trap '' XFSZ; exec "$BIN" "$ARCH_TREE" --arch=rules.txt --baseline-update --no-cache ) 2>&1 | cat >"$ARCH_DIR/x.log"
    rc="${PIPESTATUS[0]}"

    # GUARD — the limit took and nothing landed. Without it, the non-zero exit below could be a failed cd or
    # ulimit, or a failure somewhere other than the sidecar write.
    if [ "$rc" = 97 ] || [ "$rc" = 98 ] || [ ! -s "$ARCH_PLANTED" ] || [ ! -f "$ARCH_SIDE" ] || [ -s "$ARCH_SIDE" ]; then
        no "archbaseline: (x0/guard) the limit did not take (rc=$rc, sidecar $( wc -c <"$ARCH_SIDE" 2>/dev/null | tr -d ' ' ) B) — (x1)-(x3) are void"
        return
    fi
    ok "archbaseline: (x0/guard) under a zero file-size limit the sidecar was truncated and no byte landed"
    if [ "$rc" -ne 0 ]; then
        ok "archbaseline: (x1) the failed write exits non-zero ($rc)"
    else
        no "archbaseline: (x1) exit 0 although no byte of the baseline reached the disk"
    fi
    if grep -qF -e '--baseline-update cannot write sidecar: .ripwire_arch_baseline' "$ARCH_DIR/x.log"; then
        ok "archbaseline: (x2) the verb names the sidecar it could not write"
    else
        no "archbaseline: (x2) no 'cannot write sidecar' line: $( head -c 200 "$ARCH_DIR/x.log" | tr '\n' ' ' )"
    fi
    if grep -qF -e 'baseline updated' -e 'baseline-update mode' "$ARCH_DIR/x.log"; then
        no "archbaseline: (x3) the verb claimed an update it did not make: $( grep -F 'baseline' "$ARCH_DIR/x.log" | head -c 200 | tr '\n' ' ' )"
    else
        ok "archbaseline: (x3) no success claim on either stream"
    fi
}

if archPlant; then
    archBytesArm
    archWriteFailArm
fi

# ── (r) THE RACE, run for real ────────────────────────────────────────────────────────────────────────
# The swapper is python3 and not shell on purpose: a fork per swap is too slow to land in the window
# reliably, so a shell swapper would pass this arm against the defect it exists to catch. python3 is a
# documented suite prerequisite
# (CONTRIBUTING §1), so its absence is a FAILURE here, never a skip — a skipped arm reports success for
# work it did not do.
#
# It stops on a FILE, not a signal: no kill, no "Terminated" line landing in the middle of the gate's own
# rows, and no orphan if this script dies (the loop carries its own wall-clock deadline as the backstop).
RACE_MIN_RUNS=25
RACE_MAX_RUNS=150

if ! command -v python3 >/dev/null 2>&1; then
    no "race: python3 is not on PATH — the (r) arms cannot run, and a skipped race arm proves nothing"
else
    cat >"$TMP/swap.py" <<'PY'
import os, sys, time
side, victim, stop, ready = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
deadline = time.time() + 120.0
n = 0
while True:
    try:
        os.symlink( victim, side )
        if n == 0:
            open( ready, 'w' ).close()
    except OSError:
        pass
    try:
        os.unlink( side )
    except OSError:
        pass
    n += 1
    if ( n & 511 ) == 0 and ( os.path.exists( stop ) or time.time() > deadline ):
        break
PY

    raceArm()
    {
        local label="$1" sidecar="$2" runner="$3"
        local dir="$TMP/${label}_race" tree="$TMP/${label}_race/tree" victim="$TMP/${label}_race/outside/victim.txt"

        mkTree "$tree"
        mkdir -p "$dir/outside"
        local side="$tree/$sidecar" stop="$dir/stop" ready="$dir/ready"

        python3 "$TMP/swap.py" "$side" "$victim" "$stop" "$ready" &
        local swapper=$!

        # LIVENESS, part one: the swapper is actually swapping before a single verdict is taken.
        local spin=0
        while [ ! -e "$ready" ] && [ "$spin" -lt 200 ]; do
            spin=$(( spin + 1 ))
            sleep 0.05
        done
        if [ ! -e "$ready" ]; then
            : >"$stop"; wait "$swapper" 2>/dev/null
            no "$label: (r0/guard) the swapper never planted a symlink — the race arm below is void"
            return
        fi

        local runs=0 hits=0 refusals=0 writes=0 rc=0
        while [ "$runs" -lt "$RACE_MAX_RUNS" ]; do
            printf '%s\n' "$VICTIM_BYTES" >"$victim"
            rc=0
            "$runner" "$tree" >/dev/null 2>"$dir/err" || rc=$?
            runs=$(( runs + 1 ))
            grep -q "$VICTIM_BYTES" "$victim" || hits=$(( hits + 1 ))
            if grep -q 'refusing to write' "$dir/err"; then refusals=$(( refusals + 1 )); fi
            if [ "$rc" -eq 0 ]; then writes=$(( writes + 1 )); fi
            if [ "$runs" -ge "$RACE_MIN_RUNS" ] && [ "$refusals" -gt 0 ] && [ "$writes" -gt 0 ]; then
                break
            fi
        done
        : >"$stop"; wait "$swapper" 2>/dev/null

        # LIVENESS, part two — the arm's whole worth rests on this. A run that only ever met a symlink
        # proves the ordinary refusal, not the race; a run that only ever met an absent path never offered
        # the writer a link to follow. Both sides of the flicker have to have been observed, or the zero
        # below is the emptiest kind of green (CONTRIBUTING §2, shape 3).
        if [ "$refusals" -gt 0 ] && [ "$writes" -gt 0 ]; then
            # BRACES ARE LOAD-BEARING HERE. `$refusals×` reads as the identifier `refusals×` under the
            # locale pargates runs gates in — bash takes the multibyte × as part of the name — and `set -u`
            # then kills the gate mid-transcript with "unbound variable". An interactive run in a different
            # locale passes, so the suite is what found it. Brace any expansion a non-ASCII character
            # follows; do not rely on the separator being obvious to a reader.
            ok "$label: (r0/guard) over $runs runs the writer met the symlink ${refusals}× and an absent path ${writes}× — the window was open on both sides"
        else
            no "$label: (r0/guard) over $runs runs: refusals=$refusals writes=$writes — the destination never flickered, so (r1) is void"
            return
        fi

        if [ "$hits" -eq 0 ]; then
            ok "$label: (r1) victim survived all $runs racing runs — no run resolved the destination twice"
        else
            no "$label: (r1) VICTIM DESTROYED on $hits of $runs racing runs — the guard is advisory, not atomic (CWE-367)"
        fi
    }

    raceArm qualitybaseline .ripwire_quality_baseline runQualityBaseline
    raceArm notes           .ripwire_notes            runNoteAdd
    raceArm archbaseline    .ripwire_arch_baseline    runArchBaseline
fi

# ══ ROUND 3 — THE READERS (decision and arm map in the header) ════════════════════════════════════════════

# ONE valid record on a target the fixture really defines, so --notes lists it the moment the file is read. The
# sentinel is its text; nothing else in any output can spell it.
READ_SENTINEL='sidecar-read-sentinel-outside-note'
# Anchored on the ELEMENT, not the bare attribute: the quality legend states each marker's meaning in a sentence
# that quotes the marker, so an unanchored pattern could be satisfied by the dictionary instead of the verdict.
# The element opens `<quality-delta schema="ripwire.quality-delta/v1" baseline="…"`; the legend spells the schema
# with a colon after it, never a quote, so `v1" baseline=` can only be the element.
QD_LIVE='<quality-delta schema="'
QD_HONORED='quality-delta/v1" baseline="sidecar"'
QD_REFUSED='quality-delta/v1" baseline="git-HEAD (symlinked sidecar refused)"'

# mkTree's rules produce NO violation — fine for the writer arms, where an empty accepted set is still a write,
# and useless here: a baseline that accepts nothing suppresses nothing, so "the linked baseline was not used"
# would pass for the emptiest reason (shape 3). So this is mkTree plus one include that crosses a denied pair
# in archcheck's fixture shape, with the rules replaced to deny exactly that pair: one violation, no more.
mkArchViolTree()
{
    local dir="$1"
    mkTree "$dir"
    mkdir -p "$dir/render" "$dir/test"
    printf 'int shade( int x ) { return x; }\n' >"$dir/render/shader.h"
    printf '#include "../render/shader.h"\nint main( void ) { return shade( 1 ); }\n' >"$dir/test/main.cpp"
    printf 'deny test -> render\n' >"$dir/rules.txt"
}

# The quality marker needs a HEAD to fall back to, and a sidecar is honored only when its pin EQUALS that HEAD.
# So the payload is pinned in THIS repo and every mode reuses the repo: a second repo would carry a different
# sha, and the control would read "stale" instead of "sidecar".
mkQualityRepo()
{
    local dir="$1"
    rm -rf "$dir"; mkdir -p "$dir"
    printf 'int helper( int x ) { return x + 1; }\nint main( void ) { return helper( 1 ); }\n' >"$dir/a.c"
    ( cd "$dir" && git init -q && git config user.email x@y && git config user.name x && git add a.c && git commit -qm init ) >/dev/null 2>&1
}

# placeSidecar MODE TREE SIDECAR PAYLOAD — PAYLOAD's bytes reachable at TREE/SIDECAR in MODE's way, with nothing
# left over from the previous mode:
#   ctl  a REGULAR file at the name
#   out  a symlink at the name → a copy in a SIBLING of the tree, i.e. outside the crawl root
#   in   a RELATIVE symlink at the name → a copy under TREE/docs/, so the link never leaves the crawl root
placeSidecar()
{
    local mode="$1" tree="$2" sidecar="$3" payload="$4"
    rm -rf "$tree/$sidecar" "$tree/docs" "$tree.outside"
    case "$mode" in
        ctl) cp "$payload" "$tree/$sidecar" ;;
        out) mkdir -p "$tree.outside" && cp "$payload" "$tree.outside/shared-sidecar" \
                 && ln -s "$tree.outside/shared-sidecar" "$tree/$sidecar" ;;
        in)  mkdir -p "$tree/docs" && cp "$payload" "$tree/docs/shared-sidecar" \
                 && ( cd "$tree" && ln -s docs/shared-sidecar "$sidecar" ) ;;
    esac
}

# runReadMode MODE ARM WHERE LABEL TREE SIDECAR PAYLOAD LIVE RUNNER — plant the payload MODE's way, run the verb,
# and keep stdout/stderr/rc as $TMP/<label>_read_<mode>.{out,err,rc} for the arms that read them. Returns non-zero,
# after saying why, when the run can prove nothing:
#   - PRESENCE GUARD: the entry is not the shape MODE claims, or does not resolve to the payload's bytes;
#   - LIVE GUARD: the verb printed no normal document, so a crash would pass "the payload is absent" (shape 3).
runReadMode()
{
    local mode="$1" arm="$2" where="$3" label="$4" tree="$5" sidecar="$6" payload="$7" live="$8" runner="$9"
    local base="$TMP/${label}_read_$mode" isLink=0 rc=0

    placeSidecar "$mode" "$tree" "$sidecar" "$payload"
    [ -L "$tree/$sidecar" ] && isLink=1
    if ! cmp -s "$payload" "$tree/$sidecar" || { [ "$mode" = ctl ] && [ "$isLink" = 1 ]; } || { [ "$mode" != ctl ] && [ "$isLink" = 0 ]; }; then
        no "$label: ($arm/guard) could not plant the payload $where at $sidecar — ($arm) is void"
        return 1
    fi

    "$runner" "$tree" >"$base.out" 2>"$base.err" || rc=$?
    printf '%s\n' "$rc" >"$base.rc"
    if ! grep -qF "$live" "$base.out"; then
        no "$label: ($arm/guard) the verb produced no normal document (rc=$rc) with the payload $where — ($arm) is void: $( head -c 160 "$base.err" | tr '\n' ' ' )"
        return 1
    fi
}

# readArm LABEL TREE SIDECAR PAYLOAD USED LIVE RUNNER — the control, then the two link modes, over one tree.
#   USED  a fixed string whose presence in stdout means the payload was read AND used
#   LIVE  a fixed string every normal run of the verb prints (see runReadMode's LIVE GUARD)
# The control must show USED before either link mode's ABSENCE of it is allowed to mean anything.
readArm()
{
    local label="$1" tree="$2" sidecar="$3" payload="$4" used="$5" live="$6" runner="$7" mode arm where base

    if [ ! -s "$payload" ]; then
        no "$label: (read/guard) no payload was produced to plant — (n)/(k)/(i) are void"
        return
    fi
    runReadMode ctl n "as a regular file" "$label" "$tree" "$sidecar" "$payload" "$live" "$runner" || return
    if ! grep -qF "$used" "$TMP/${label}_read_ctl.out"; then
        no "$label: (n) the regular sidecar's payload was not used — the fixture or the reader is broken, and (k)/(i) are void"
        return
    fi
    ok "$label: (n) a REGULAR sidecar is still read and used — the document shows: $used"

    for mode in out in; do
        arm="k"; where="outside the tree"
        [ "$mode" = in ] && { arm="i"; where="INSIDE the crawl root"; }
        runReadMode "$mode" "$arm" "$where" "$label" "$tree" "$sidecar" "$payload" "$live" "$runner" || continue
        base="$TMP/${label}_read_$mode"
        if grep -qF "$used" "$base.out"; then
            no "$label: ($arm) a symlink at $sidecar → a valid payload $where was READ AND USED (rc=$( cat "$base.rc" )): $used"
        else
            ok "$label: ($arm) a symlink at $sidecar → a valid payload $where was not used"
        fi
        if grep -q 'refusing to read' "$base.err" && grep -q 'symlink' "$base.err"; then
            ok "$label: ($arm) stderr names the read refusal and the reason (symlink)"
        else
            no "$label: ($arm) stderr carries no read refusal — the sidecar went unused without saying why: $( head -c 160 "$base.err" | tr '\n' ' ' )"
        fi
    done
}

readNotesList(){ "$BIN" "$1" --notes --no-cache; }
readQualityDelta(){ "$BIN" "$1" --quality-delta --legend=compact --no-cache; }
readArchCheck(){ ( cd "$1" && "$BIN" "$1" --arch=rules.txt --no-cache ); }

# ── notes ─────────────────────────────────────────────────────────────────────────────────────────────────
printf 'a.c\t2026-01-01\t%s\n' "$READ_SENTINEL" >"$TMP/payload_notes"
RN="$TMP/notes_read/tree"
mkTree "$RN"
readArm notes "$RN" .ripwire_notes "$TMP/payload_notes" "$READ_SENTINEL" '<notes>' readNotesList

# ── quality baseline: (n)/(k)/(i), then (q) — where the refusal is disclosed ──────────────────────────────
RQ="$TMP/qualitybaseline_read/tree"
mkQualityRepo "$RQ"
"$BIN" "$RQ" --quality-baseline --no-cache >/dev/null 2>&1
if [ -f "$RQ/.ripwire_quality_baseline" ] && grep -qE '^head [0-9a-f]{40}' "$RQ/.ripwire_quality_baseline"; then
    mv "$RQ/.ripwire_quality_baseline" "$TMP/payload_quality"
    readArm qualitybaseline "$RQ" .ripwire_quality_baseline "$TMP/payload_quality" "$QD_HONORED" "$QD_LIVE" readQualityDelta

    QOUT="$TMP/qualitybaseline_read_out.out"; QERR="$TMP/qualitybaseline_read_out.err"
    if [ -s "$QOUT" ] && grep -qF "$QD_REFUSED" "$QOUT"; then
        ok "qualitybaseline: (q1) the CLI report names the floor it could not use: $QD_REFUSED"
    else
        no "qualitybaseline: (q1) the CLI report does not carry $QD_REFUSED — it says: $( grep -o 'quality-delta/v1" baseline="[^"]*"' "$QOUT" 2>/dev/null | head -1 )"
    fi
    # Absence of two FALSE sentences. Green on the round-2 binary (it printed neither, because it used the link);
    # observed RED on an intermediate build that refused the read and left the wording alone, which said the
    # sidecar did not exist while the link was sitting right there.
    if grep -q 'ripwire: no ' "$QERR" || grep -q 'not a readable baseline' "$QERR"; then
        no "qualitybaseline: (q2) stderr calls the refused link missing or unrecognizable — it is neither: $( grep -E 'ripwire: no |not a readable baseline' "$QERR" | head -c 200 )"
    else
        ok "qualitybaseline: (q2) stderr does not describe the refused link as missing or unrecognizable"
    fi

    # MCP has its own marker step (mcpverbs.h::mcpBaselineMarker), which probes the path itself — so it is
    # asserted on its own, against the same link.
    placeSidecar out "$RQ" .ripwire_quality_baseline "$TMP/payload_quality"
    MCPLINE="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$RQ"'"}}}' \
                | "$BIN" --mcp 2>/dev/null | tail -1 )"
    if ! printf '%s' "$MCPLINE" | grep -q 'baseline'; then
        no "qualitybaseline: (q3/guard) MCP quality_delta returned no baseline marker at all — (q3) is void: $( printf '%s' "$MCPLINE" | head -c 200 )"
    elif printf '%s' "$MCPLINE" | grep -qF 'git-HEAD (symlinked sidecar refused)'; then
        ok "qualitybaseline: (q3) MCP quality_delta names the refused link in its marker"
    else
        no "qualitybaseline: (q3) MCP quality_delta does not name the refused link — it says: $( printf '%s' "$MCPLINE" | grep -o 'baseline[^,]*' | head -1 )"
    fi
else
    no "qualitybaseline: (read/guard) could not pin a HEAD-stamped payload in a git fixture — (n)/(k)/(i)/(q1)-(q3) are void"
fi

# NO HEAD: the refused link leaves no floor at all, so the verb must fail — and its fatal must not say the
# sidecar is missing, which is false while the link is right there. mkTree lives under $TMP, not in a checkout.
RQN="$TMP/qualitybaseline_nogit/tree"
mkTree "$RQN"
"$BIN" "$RQN" --quality-baseline --no-cache >/dev/null 2>&1
if [ -f "$RQN/.ripwire_quality_baseline" ] && mv "$RQN/.ripwire_quality_baseline" "$TMP/payload_quality_nogit"; then
    placeSidecar out "$RQN" .ripwire_quality_baseline "$TMP/payload_quality_nogit"
    rc=0
    "$BIN" "$RQN" --quality-delta --legend=compact --no-cache >"$TMP/q_nogit.out" 2>"$TMP/q_nogit.err" || rc=$?
    if [ "$rc" -ne 0 ] && ! grep -qF "$QD_HONORED" "$TMP/q_nogit.out"; then
        ok "qualitybaseline: (q4) with no HEAD to fall back to, the refused link is a failure ($rc), not an honored floor"
    else
        no "qualitybaseline: (q4) with no HEAD to fall back to, the verb exited $rc and reported $( grep -o 'quality-delta/v1" baseline="[^"]*"' "$TMP/q_nogit.out" | head -1 )"
    fi
    if grep -q 'refusing to read' "$TMP/q_nogit.err" && ! grep -q 'ripwire: no ' "$TMP/q_nogit.err"; then
        ok "qualitybaseline: (q5) the no-HEAD fatal names the refusal and does not call the sidecar missing"
    else
        no "qualitybaseline: (q5) the no-HEAD fatal is not honest about the link: $( head -c 240 "$TMP/q_nogit.err" | tr '\n' ' ' )"
    fi
    # The MCP twin of (q5). Its no-HEAD answer is mcpverbs.h's own errMsg, not the CLI's fatal, so it can be wrong
    # on its own and is asserted on its own.
    MCPNG="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"quality_delta","arguments":{"path":"'"$RQN"'"}}}' \
              | "$BIN" --mcp 2>/dev/null | tail -1 )"
    if printf '%s' "$MCPNG" | grep -q 'is a symlink' && ! printf '%s' "$MCPNG" | grep -q 'no \.ripwire_quality_baseline'; then
        ok "qualitybaseline: (q6) MCP quality_delta's no-HEAD answer names the refused link and does not call the sidecar missing"
    else
        no "qualitybaseline: (q6) MCP quality_delta's no-HEAD answer is not honest about the link: $( printf '%s' "$MCPNG" | head -c 240 )"
    fi
else
    no "qualitybaseline: (q4/guard) could not pin a payload in a non-git tree — (q4)/(q5) are void"
fi

# ── arch baseline ─────────────────────────────────────────────────────────────────────────────────────────
RA="$TMP/archbaseline_read/tree"
mkArchViolTree "$RA"
( cd "$RA" && "$BIN" "$RA" --arch=rules.txt --baseline --no-cache ) >/dev/null 2>&1
if [ -f "$RA/.ripwire_arch_baseline" ] && grep -qE '^[0-9a-f]{8,}' "$RA/.ripwire_arch_baseline"; then
    mv "$RA/.ripwire_arch_baseline" "$TMP/payload_arch"
    readArm archbaseline "$RA" .ripwire_arch_baseline "$TMP/payload_arch" 'baselined="1"' '<arch layers=' readArchCheck
    # FAIL-CLOSED, not merely unused: the one violation the refused baseline would have accepted is reported NEW
    # and the verb exits 2, exactly as with no sidecar at all.
    if grep -qF 'new_violations="1"' "$TMP/archbaseline_read_out.out" 2>/dev/null \
       && [ "$( cat "$TMP/archbaseline_read_out.rc" 2>/dev/null )" = "2" ]; then
        ok "archbaseline: (k2) the violation the refused baseline would have accepted is reported NEW, exit 2"
    else
        no "archbaseline: (k2) the refused baseline still changed the verdict: $( grep -o '<arch [^>]*>' "$TMP/archbaseline_read_out.out" 2>/dev/null ) rc=$( cat "$TMP/archbaseline_read_out.rc" 2>/dev/null )"
    fi
else
    no "archbaseline: (read/guard) could not pin a baseline holding a real violation hash — (n)/(k)/(k2)/(i) are void"
fi

# ── (t) NEVER OPENED ──────────────────────────────────────────────────────────────────────────────────────
# A reader that follows the link opens whatever is at its end. Aimed at a FIFO with no writer, that open BLOCKS
# until something opens the other end, so the probe opens the FIFO for writing with O_NONBLOCK — which succeeds
# only while a reader holds or awaits it (ENXIO otherwise) — counts the success, and closes to let the reader go
# on. The verdict is opens=0 or not, and it does not depend on speed: an O_NOFOLLOW open is refused with ELOOP
# without reaching the FIFO at all, and a following open cannot complete before the probe has seen it, because
# the probe is the only writer there is. The COUNT is approximate (a reader still draining EOF can be seen twice)
# and nothing asserts on it.
if ! command -v python3 >/dev/null 2>&1; then
    no "read: python3 is not on PATH — the (t) arms cannot run, and a skipped arm proves nothing"
else
    cat >"$TMP/fifoopens.py" <<'PY'
import errno, os, subprocess, sys, time
fifo, cwd, argv = sys.argv[1], sys.argv[2], sys.argv[3:]
p = subprocess.Popen( argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL )
opens, deadline = 0, time.time() + 60.0
while p.poll() is None and time.time() < deadline:
    try:
        fd = os.open( fifo, os.O_WRONLY | os.O_NONBLOCK )
    except OSError as e:
        if e.errno != errno.ENXIO:
            raise
        time.sleep( 0.002 )
        continue
    opens += 1
    os.close( fd )
    time.sleep( 0.02 )
if p.poll() is None:
    p.kill()
    p.wait()
    print( 'opens=%d rc=hung' % opens )
else:
    print( 'opens=%d rc=%d' % ( opens, p.returncode ) )
PY

    # fifoLink DIR SIDECAR — DIR/tree already built; plants DIR/outside/fifo and a link at the sidecar name to it.
    fifoLink()
    {
        local dir="$1" sidecar="$2"
        mkdir -p "$dir/outside" && mkfifo "$dir/outside/fifo" && ln -s "$dir/outside/fifo" "$dir/tree/$sidecar" \
            && [ -p "$dir/outside/fifo" ] && [ -L "$dir/tree/$sidecar" ]
    }

    # opensArm LABEL VERB CWD FIFO ARGV... — the verb, run from CWD, must never open FIFO.
    opensArm()
    {
        local label="$1" verb="$2" cwd="$3" fifo="$4" res
        shift 4
        res="$( python3 "$TMP/fifoopens.py" "$fifo" "$cwd" "$@" 2>&1 )"
        case "$res" in
            'opens=0 rc='[0-9]*) ok "$label: (t) $verb never opened the link's target ($res)" ;;
            *)                   no "$label: (t) $verb OPENED the link's target, or hung — $res" ;;
        esac
    }

    mkdir -p "$TMP/fifo_ctl" && mkfifo "$TMP/fifo_ctl/fifo"
    CTLRES="$( python3 "$TMP/fifoopens.py" "$TMP/fifo_ctl/fifo" "$TMP/fifo_ctl" cat "$TMP/fifo_ctl/fifo" 2>&1 )"
    case "$CTLRES" in
        'opens='[1-9]*' rc=0')
            ok "read: (t0/guard) the probe counts a real open of the FIFO — cat gave $CTLRES"

            mkTree "$TMP/notes_fifo/tree"
            if fifoLink "$TMP/notes_fifo" .ripwire_notes; then
                FT="$TMP/notes_fifo/tree"; FF="$TMP/notes_fifo/outside/fifo"
                opensArm notes --notes    "$FT" "$FF" "$BIN" "$FT" --notes --no-cache
                opensArm notes --note-add "$FT" "$FF" "$BIN" "$FT" --note-add="a.c: read-side probe" --no-cache
                opensArm notes --for      "$FT" "$FF" "$BIN" "$FT" --for=helper --no-cache
            else
                no "notes: (t/guard) could not plant a FIFO behind a link at .ripwire_notes — (t) is void"
            fi

            mkTree "$TMP/qualitybaseline_fifo/tree"
            if fifoLink "$TMP/qualitybaseline_fifo" .ripwire_quality_baseline; then
                FT="$TMP/qualitybaseline_fifo/tree"; FF="$TMP/qualitybaseline_fifo/outside/fifo"
                opensArm qualitybaseline --quality-delta "$FT" "$FF" "$BIN" "$FT" --quality-delta --no-cache
            else
                no "qualitybaseline: (t/guard) could not plant a FIFO behind a link at .ripwire_quality_baseline — (t) is void"
            fi

            mkArchViolTree "$TMP/archbaseline_fifo/tree"
            if fifoLink "$TMP/archbaseline_fifo" .ripwire_arch_baseline; then
                FT="$TMP/archbaseline_fifo/tree"; FF="$TMP/archbaseline_fifo/outside/fifo"
                opensArm archbaseline --arch            "$FT" "$FF" "$BIN" "$FT" --arch=rules.txt --no-cache
                opensArm archbaseline --baseline-update "$FT" "$FF" "$BIN" "$FT" --arch=rules.txt --baseline-update --no-cache
            else
                no "archbaseline: (t/guard) could not plant a FIFO behind a link at .ripwire_arch_baseline — (t) is void"
            fi
            ;;
        *)
            no "read: (t0/guard) the probe did not count cat's open of the FIFO ($CTLRES) — every (t) arm is void"
            ;;
    esac
fi

# ── (m) MECHANISM (source): every reader of the three names reads through its sidecar's seam ──────────────
# Like (e): these read $ROOT/src and do not follow $BIN. The reader half is checked even when the seam cannot be
# extracted, so a tree that never grew a seam shows the following open that is still there, not only a void.
readMechArm()
{
    local label="$1" src="$2" readerSig="$3" readerFn="$4" seamSig="$5" seamFn="$6" alert="$7" checkSeam="$8"
    local rd="$TMP/rd_${label}_$readerFn.txt" sm="$TMP/seam_${label}_$seamFn.txt" rdLines smLines

    extractFn "$ROOT/$src" "$readerSig" >"$rd"
    rdLines="$( wc -l <"$rd" | tr -d ' ' )"
    if [ "$rdLines" -ge 5 ] && grep -q 'return' "$rd"; then
        ok "$label: (m0/guard) extracted $rdLines code lines of $readerFn from $src"
    else
        no "$label: (m0/guard) could not extract $readerFn from $src ($rdLines lines) — (m1) is void"
        return
    fi
    if grep -q "$seamFn(" "$rd" && ! grep -qE 'std::ifstream|std::fopen|readWholeFile\(' "$rd"; then
        ok "$label: (m1) $readerFn takes its bytes from $seamFn and opens nothing itself"
    else
        no "$label: (m1) $readerFn does not read through $seamFn, or still opens the sidecar itself: $( grep -E 'std::ifstream|std::fopen|readWholeFile\(' "$rd" | head -c 160 )"
    fi
    # Round 4: a line at a time from the sidecar handle, never a buffered copy of the whole file.
    if grep -q 'sidecar\.readLine(' "$rd" && ! grep -q 'sidecar\.bytes' "$rd"; then
        ok "$label: (m5) $readerFn parses a line at a time from the sidecar handle, not a buffered copy of the file"
    else
        no "$label: (m5) $readerFn still parses a buffered copy of the whole sidecar: $( grep -E 'sidecar\.bytes|istringstream f\(' "$rd" | head -c 160 )"
    fi

    [ "$checkSeam" = 1 ] || return
    extractFn "$ROOT/$src" "$seamSig" >"$sm"
    smLines="$( wc -l <"$sm" | tr -d ' ' )"
    if [ "$smLines" -lt 4 ] || ! grep -q 'return' "$sm"; then
        no "$label: (m2/guard) could not extract the read seam $seamFn from $src ($smLines lines) — (m2)/(m3) are void"
        return
    fi
    # Round 4 renamed the read half: it no longer reads the WHOLE file, so the old name would have been a claim
    # about a shape the code no longer has.
    if grep -q 'openNoFollowRead' "$sm"; then
        ok "$label: (m2) $seamFn opens through pathguard's O_NOFOLLOW read"
    else
        no "$label: (m2) $seamFn does not open through rw::pathguard::openNoFollowRead"
    fi
    if grep -qF "$alert" "$sm"; then
        ok "$label: (m3) $seamFn carries the site's own DEGRADED_PATH_ALERT for the refused link"
    else
        no "$label: (m3) $seamFn does not carry the expected alert: $alert"
    fi
}

readMechArm notes           src/notes.h   'inline std::vector<Note> readNotes( const std::string& path )' readNotes \
            'readNotesSidecar( const std::string& path )' readNotesSidecar \
            'notes: refusing to read the notes sidecar through a symlink' 1
readMechArm qualitybaseline src/quality.h 'inline bool readBaseline( const std::string& path, Snapshot& out, BaselineReadStats& stats )' readBaseline \
            'readBaselineSidecar( const std::string& path )' readBaselineSidecar \
            'quality: refusing to read the baseline sidecar through a symlink' 1
readMechArm qualitybaseline src/quality.h 'inline std::string readBaselineHeadSha( const std::string& path )' readBaselineHeadSha \
            'readBaselineSidecar( const std::string& path )' readBaselineSidecar '' 0
readMechArm qualitybaseline src/quality.h 'inline std::size_t readBaselineAbsorbed( const std::string& path )' readBaselineAbsorbed \
            'readBaselineSidecar( const std::string& path )' readBaselineSidecar '' 0
readMechArm archbaseline    src/arch.h    'archReadBaseline( const std::string& sidecarPath )' archReadBaseline \
            'readArchBaselineSidecar( const std::string& sidecarPath )' readArchBaselineSidecar \
            'arch: refusing to read the arch baseline sidecar through a symlink' 1

# The arch verb used to open the sidecar a SECOND time, with a bare stream, only to learn whether it existed. It
# read nothing, so no content arm could ever see it; (t) sees it behaviourally and this sees its shape.
VRCODE="$TMP/verbs_report_code.txt"
grep -v '^[[:space:]]*//' "$ROOT/src/verbs_report.h" >"$VRCODE"
if ! grep -q 'archReadBaseline(' "$VRCODE"; then
    no "archbaseline: (m4/guard) src/verbs_report.h no longer calls archReadBaseline — (m4) is void"
elif grep -qE 'ifstream[^;]*sidecarPath' "$VRCODE"; then
    no "archbaseline: (m4) the arch verb still opens the sidecar with a following stream: $( grep -E 'ifstream[^;]*sidecarPath' "$VRCODE" | head -c 160 )"
else
    ok "archbaseline: (m4) the arch verb holds no following open of the sidecar — presence comes from the reader"
fi

# ── (v) A NON-REGULAR FILE AT THE NAME: no sidecar verb may wait on it ────────────────────────────────────
# A FIFO planted AT a sidecar name, with no link involved, used to block both opens: a read open waits for a
# writer, a write open for a reader. Each verb runs under a 20 s deadline. The fixed build finishes in well under a second and the guarded failure is an UNBOUNDED wait, so the
# deadline never has to decide a close call. A write verb must also exit non-zero and leave the FIFO in place.
if ! command -v python3 >/dev/null 2>&1; then
    no "nonregular: python3 is not on PATH — the (v) arms cannot run, and a skipped arm proves nothing"
else
    cat >"$TMP/bounded.py" <<'PY'
import subprocess, sys
deadline, cwd, argv = float( sys.argv[1] ), sys.argv[2], sys.argv[3:]
try:
    r = subprocess.run( argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=deadline )
    print( 'rc=%d' % r.returncode )
except subprocess.TimeoutExpired:
    print( 'hung' )
PY

    # nonRegularArm LABEL SIDECAR MAKER READ_ARG -- WRITE_ARGS... — run from inside the tree, so the CWD-relative
    # arch sidecar resolves to the planted FIFO like the root-qualified ones do.
    nonRegularArm()
    {
        local label="$1" sidecar="$2" maker="$3" readArg="$4"
        shift 4
        [ "$1" = "--" ] && shift
        local tree="$TMP/${label}_fifoname/tree" res
        "$maker" "$tree"
        mkfifo "$tree/$sidecar"
        if [ ! -p "$tree/$sidecar" ] || [ -L "$tree/$sidecar" ]; then
            no "$label: (v/guard) could not plant a FIFO at $sidecar — (v1)/(v2) are void"
            return
        fi

        res="$( python3 "$TMP/bounded.py" 20 "$tree" "$BIN" "$tree" "$readArg" --no-cache 2>&1 )"
        case "$res" in
            rc=*) ok "$label: (v1) $readArg finished with a FIFO at $sidecar ($res)" ;;
            *)    no "$label: (v1) $readArg did not finish with a FIFO at $sidecar — the read open waited for a writer ($res)" ;;
        esac

        res="$( python3 "$TMP/bounded.py" 20 "$tree" "$BIN" "$tree" "$@" --no-cache 2>&1 )"
        case "$res" in
            rc=0) no "$label: (v2) $* exited 0 with a FIFO at $sidecar — a write that could not happen reported success" ;;
            rc=*) if [ -p "$tree/$sidecar" ] && [ ! -L "$tree/$sidecar" ]; then
                      ok "$label: (v2) $* refused a FIFO at $sidecar without waiting ($res), and left it in place"
                  else
                      no "$label: (v2) $* finished ($res) but the FIFO at $sidecar was replaced or removed"
                  fi ;;
            *)    no "$label: (v2) $* did not finish with a FIFO at $sidecar — the write open waited for a reader ($res)" ;;
        esac
    }

    nonRegularArm notes           .ripwire_notes            mkTree         --notes          -- "--note-add=a.c: fifo at the name"
    nonRegularArm qualitybaseline .ripwire_quality_baseline mkTree         --quality-delta  -- --quality-baseline
    nonRegularArm archbaseline    .ripwire_arch_baseline    mkArchViolTree --arch=rules.txt -- --arch=rules.txt --baseline

    # (v3) A READER ALREADY HOLDS THE FIFO OPEN. That is the one case where a write open on a FIFO SUCCEEDS, so only
    # the regular-file check stands between the verb and writing the sidecar into somebody else's pipe. The probe
    # opens the FIFO for reading (non-blocking), runs the write verb, and counts every byte that arrives. A verb that
    # waits instead (a read before its write, say) is killed at the deadline and reported as a failure, never passed.
    cat >"$TMP/fifowriter.py" <<'PY'
import os, subprocess, sys, time
deadline, fifo, cwd, argv = float( sys.argv[1] ), sys.argv[2], sys.argv[3], sys.argv[4:]
rfd = os.open( fifo, os.O_RDONLY | os.O_NONBLOCK )
p = subprocess.Popen( argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL )
got, end = 0, time.time() + deadline
def drain():
    n = 0
    while True:
        try:
            chunk = os.read( rfd, 65536 )
        except BlockingIOError:
            return n
        if not chunk:
            return n
        n += len( chunk )
while True:
    got += drain()
    if p.poll() is not None:
        got += drain()
        break
    if time.time() > end:
        p.kill(); p.wait(); os.close( rfd )
        print( 'hung bytes=%d' % got ); sys.exit( 0 )
    time.sleep( 0.005 )
os.close( rfd )
print( 'rc=%d bytes=%d' % ( p.returncode, got ) )
PY

    # readerAttachedArm LABEL SIDECAR MAKER WRITE_ARGS...
    readerAttachedArm()
    {
        local label="$1" sidecar="$2" maker="$3" tree res
        shift 3
        tree="$TMP/${label}_fiforeader/tree"
        "$maker" "$tree"
        mkfifo "$tree/$sidecar"
        if [ ! -p "$tree/$sidecar" ] || [ -L "$tree/$sidecar" ]; then
            no "$label: (v3/guard) could not plant a FIFO at $sidecar — (v3) is void"
            return
        fi
        res="$( python3 "$TMP/fifowriter.py" 20 "$tree/$sidecar" "$tree" "$BIN" "$tree" "$@" --no-cache 2>&1 )"
        case "$res" in
            'rc=0 '*)       no "$label: (v3) $* exited 0 with a reader on the FIFO at $sidecar — $res" ;;
            rc=*' bytes=0') if [ -p "$tree/$sidecar" ] && [ ! -L "$tree/$sidecar" ]; then
                                ok "$label: (v3) $* refused a FIFO a reader held open ($res): no byte reached the pipe"
                            else
                                no "$label: (v3) $* finished ($res) but the FIFO at $sidecar was replaced or removed"
                            fi ;;
            *)              no "$label: (v3) $* with a reader on the FIFO at $sidecar: $res — it wrote into the pipe, or waited" ;;
        esac
    }

    readerAttachedArm notes           .ripwire_notes            mkTree         "--note-add=a.c: fifo with a reader"
    readerAttachedArm qualitybaseline .ripwire_quality_baseline mkTree         --quality-baseline
    readerAttachedArm archbaseline    .ripwire_arch_baseline    mkArchViolTree --arch=rules.txt --baseline
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
