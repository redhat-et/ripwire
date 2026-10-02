# shardmatch.py — one ripwire --match over a whole tree, COMPLETE whatever the tree's size.
#
# WHY. The --match engine stops at a hard per-query budget (kMatchMaxHits, src/verbs_lint.h) and says so with
# hits_capped="1". crashsweepcheck.sh and hazardpatterncheck.sh run their static rules over src/, and src/ grows: the
# function-definition query crossed the budget (4987 on main, >= 5000 once two 0.6.7 lanes merged) and both gates went
# red for a reason that had nothing to do with the rules they hold. Raising the cap would only move the cliff. So the
# scan SHARDS instead: when a whole-tree scan is capped, the tree's files (sorted by path) are split into contiguous
# halves, each half is copied into its own root with the same relative paths, and the half is scanned again — recursively,
# until every shard answers uncapped. The rows are the concatenation of the shards' rows in path order, each shard's own
# order kept, so a match's capture rows stay adjacent (what the gates' pairs()/tuples() regroup on).
#
# WHAT IT GUARANTEES. A tree whose whole scan is uncapped is scanned exactly as before (one run, same rows, same order). A
# capped tree yields every hit, or the scan FAILS: one file that alone reaches the budget cannot be split and is refused
# by name (exit 3) — the result is never a silent partial. --match is a per-file structural query, so a file's hits do
# not depend on which other files share its root; shardmatchcheck-style arms in both gates prove it on src/ itself
# (a scan forced to split at a tiny budget equals the whole-tree scan) and on a generated tree past the engine cap.
#
# The gates import this file (sys.path insert of test/lib); it has no state beyond the shard copies it writes under `work`.
import html, os, re, shutil, subprocess, sys


def _run(binary, root, query, env):
    proc = subprocess.run([binary, root, "--match=" + query, "--limit=5000"], capture_output=True, text=True, env=env)
    head = re.search(r"<match [^>]*>", proc.stdout)
    if proc.returncode != 0 or head is None:
        print("SCANFAIL rc=%d query=%s stderr=%s" % (proc.returncode, query[:100], proc.stderr[-1200:]))
        sys.exit(3)
    capped = 'hits_capped="1"' in head.group(0) or 'capped="1"' in head.group(0)
    rows = []
    for p, fn, text in re.findall(r'<m p="([^"]*)" in="([^"]*)">(.*?)</m>', proc.stdout, re.S):
        f, _, ln = p.rpartition(":")
        rows.append((f, int(ln), html.unescape(fn), html.unescape(text)))
    return capped, rows


def _files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            out.append(os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(out)


def _materialize(root, files, dest):
    for rel in files:
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        try:
            os.link(os.path.join(root, rel), target)
        except OSError:
            shutil.copy2(os.path.join(root, rel), target)


class ShardedMatch:
    """match(query) -> [(file, line, fn, text)], complete or exit 3. `budget` (tests only) treats a scan returning more
    than that many rows as capped too, which forces the split on a tree the engine would answer whole."""

    def __init__(self, binary, root, work, env=None, budget=None):
        self.binary, self.root, self.work, self.env, self.budget = binary, root, work, env, budget
        self.shardsRun = 0     # shard scans beyond the whole-tree one, summed over every query (the gates print it)
        self._files = None
        self._serial = 0

    def _over(self, capped, rows):
        return capped or (self.budget is not None and len(rows) > self.budget)

    def match(self, query):
        capped, rows = _run(self.binary, self.root, query, self.env)
        if not self._over(capped, rows):
            return rows
        if self._files is None:
            self._files = _files(self.root)
        return self._split(query, self._files)

    def _split(self, query, files):
        out = []
        for half in (files[:len(files) // 2], files[len(files) // 2:]):
            if not half:
                continue
            self._serial += 1
            dest = os.path.join(self.work, "shard%05d" % self._serial)
            _materialize(self.root, half, dest)
            capped, rows = _run(self.binary, dest, query, self.env)
            self.shardsRun += 1
            shutil.rmtree(dest, ignore_errors=True)
            if not self._over(capped, rows) or ( len(half) == 1 and not capped ):
                out += rows   # (a single file over a TEST budget but under the engine's is complete: keep it)
            elif len(half) == 1:
                print("SCANFAIL one file alone reaches the --match budget, so the scan cannot be completed: %s (%s)" % (half[0], query[:80]))
                sys.exit(3)
            else:
                out += self._split(query, half)
        return out


# ── self-test: the arm both gates run (python3 shardmatch.py selftest BIN WORK [SRC]) ───────────────────────────────────
# (Z1) INDEPENDENT OF TREE SIZE: a generated tree of 6000 one-line function definitions — past the engine's budget, which
#      the arm first proves by the plain scan coming back capped — is scanned COMPLETE: exactly 6000 distinct names.
# (Z2) SHARDING CHANGES NOTHING: on SRC itself, queries the engine answers whole are re-run forced to split (a budget of
#      half their rows) and must return the same rows, file by file, in the same per-file order.
# Prints PASS/FAIL lines; exits 1 when any arm failed.
def _selftest(binary, work, src):
    failed = False

    def say(passed, text):
        nonlocal failed
        failed = failed or not passed
        print(("PASS  " if passed else "FAIL  ") + text)

    big = os.path.join(work, "bigtree")
    for fileIndex in range(60):
        os.makedirs(os.path.join(big, "d%02d" % (fileIndex % 7)), exist_ok=True)
        with open(os.path.join(big, "d%02d" % (fileIndex % 7), "f%02d.cpp" % fileIndex), "w") as out:
            out.write("".join("int f%02d_%03d( int x ) { return x + %d; }\n" % (fileIndex, k, k) for k in range(100)))
    query = "(function_definition declarator: (function_declarator declarator: (_) @name))"
    capped, plain = _run(binary, big, query, None)
    say(capped, "(Z1) premise: the plain scan of 6000 definitions reaches the engine budget (hits_capped=1, %d rows)" % len(plain))
    scanner = ShardedMatch(binary, big, os.path.join(work, "bigshards"))
    rows    = scanner.match(query)
    names   = {r[3] for r in rows}
    say(len(rows) == 6000 and len(names) == 6000,
        "(Z1) the sharded scan is complete past the budget: %d rows, %d distinct names (want 6000), %d shard scans" % (len(rows), len(names), scanner.shardsRun))

    for q in ("(catch_clause) @c", "(throw_statement) @t", "(enum_specifier name: (type_identifier) @n)") if src else ():
        capped, whole = _run(binary, src, q, None)
        if capped or len(whole) < 4:
            say(False, "(Z2) premise: %s must be answered whole with rows to split (capped=%s, %d rows)" % (q, capped, len(whole)))
            continue
        forced = ShardedMatch(binary, src, os.path.join(work, "srcshards"), budget=max(1, len(whole) // 2))
        split  = forced.match(q)
        byFile = lambda rs: {f: [r for r in rs if r[0] == f] for f in sorted({r[0] for r in rs})}
        say(byFile(split) == byFile(whole) and forced.shardsRun >= 2,
            "(Z2) %s: forced to %d shard scans, the same %d rows as the whole-tree scan, file by file" % (q, forced.shardsRun, len(whole)))
    return 1 if failed else 0


if __name__ == "__main__" and len(sys.argv) >= 4 and sys.argv[1] == "selftest":
    sys.exit(_selftest(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None))
