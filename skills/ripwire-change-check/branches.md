# ripwire-change-check — reference: branches (read on demand; the recipe is in SKILL.md)

9. **Landing several concurrent branches?** — `ripwire <dir> --merge-scout=REF1,REF2,... --legend=compact` (read-only; the
   dirty working tree joins automatically as an implicit extra arm). For each REF it diffs the ref's tree
   against its merge-base with HEAD (git-archive temp copies — nothing is checked out or mutated) and
   reports, per pair, **same-symbol conflicts** (both arms touched the identical symbol — a real merge will
   fight over it) and **same-file/different-symbol risks** (no content collision, still worth a glance), plus
   a `<landing order="…">` — the fewest-conflicts-first sequence to land them in. Run this BEFORE picking a
   merge order for several agent branches instead of hand-diffing each pair.

9b. **Is anything STRANDED on a branch — and was it already re-done?** — `ripwire <dir> --stray-content --legend=compact`
    (`=SUBSTR` filters ref names). `--merge-scout` above answers "which of these named branches collide";
    this answers the prior question — *of all my branches, which still hold work the live line does not
    have?* Per ref it reports the lines that ref's own work AUTHORED (vs its merge-base with HEAD) that HEAD
    lacks, with a verdict: `unmerged` (genuinely absent — this is the queue to work), `superseded` (the live
    line removed the SAME base code this ref removed, i.e. it re-implemented the work), `merged` (omitted).
    **`superseded` is the case `git cherry` structurally cannot see** — it compares commit ancestry, so a fix
    the live line re-did differently stays "unmerged" forever, which is exactly how a finished fix sits on a
    branch for days behind a ledger that says "ported". Every row prints its raw `del=`/`redone=`/`sim=`
    evidence — read those before acting, the verdict is a summary, not an oracle. Line-granular, not
    semantic. Read-only, single-root.

9c. **"Where does this content live?"** — `ripwire <dir> --whereis=SYM --legend=compact`. Which ref's tree defines or mentions
    a symbol, HEAD first; `on-head="0"` alongside branch hits is content that exists ONLY on a branch. Each
    distinct blob is read once (git is content-addressed), so 30 branches cost about one tree. `kind="def"`
    is a parser's answer on every row — HEAD's from the index, a branch row's from the same extraction over that
    branch's blob (only blobs holding a line a loose lexical test calls worth parsing are parsed; `kind="text"` is
    such a line no parse read, never a definition). By default only the `kind="def"` rows are listed and the mentions are
    counted in one `<refs count=N next=…>` row (its `next=` lists them) when that page lists MORE definitions than
    the all page does under the same row cap (a capped all page can list fewer), or the same ones in strictly fewer
    bytes; otherwise, and with `--whereis-listing=all`, every row is listed. A line over 300 bytes prints its `t=` as a
    200-byte preview (`t_bytes=` is the whole line's size) when that makes the page shorter; the page's `<t_cut next=…>` replays
    it with `--whereis-full-text`, every line whole.
    A tree scan only finds what some ref *still carries*, so `hits="0"` cannot by itself tell a name this repo
    never had from one it deleted. Add `--with-history` and a `<fate>` row says which: `v="never"`, or
    `v="removed" commit=… date=… p=…` naming the commit that took it out. One `git log` pass, memoized per
    (repo, HEAD sha) and shared with `--doc-drift --with-history`.

9d. **"Of all my branches, which still hold REAL work, and in what order should I land them?"** — `ripwire
    <dir> --stray-content --plan`. Composes 9b + 9 in one call: selects the refs 9b calls `v="unmerged"`,
    DROPS the `v="superseded"` ones (`<excluded reason="…">` names them — landing a superseded branch would
    re-do work the live line already did, exactly the waste 9b exists to catch), and feeds the survivors to
    9's pairwise-conflict + fewest-conflicts-first landing-order machinery, unmodified. `<ref scouted="0">`
    is real unmerged work NOT fed to merge-scout THIS run — a cost bound, not a verdict (`bounded=` on the
    root element counts it; `--detail` lifts the bound to scout everything). **Cost**: 9b is a cheap per-blob
    sweep, but 9 is per-ARM (git-archive + full ingest of each ref's tree) — measured ~3s/ref on a real C++
    repo, so this is an EXPLICIT "before you land" call (pass both flags on purpose), not a per-question one.
    Bare `--plan` refuses loudly without `--stray-content`. Read-only; single-root only.
9d. **Did a branch silently break a CPU/GPU struct's byte layout?** — `ripwire <dir> --stray-content --legend=compact --abi`
    (`=SUBSTR` filters ref names, same as 9b). Neither `--layout=STRUCT` (one index, the working tree) nor
    `--stray-content` (line-granular — "added a float field" is just a stray line to it) catches a branch
    that adds one field to a dual-compile uniform struct: the merge is textually clean, review sees a
    harmless "+1 field", and the CPU ends up writing more bytes than the GPU reads for — wrong pixels, no
    compiler error. This runs `--layout`'s own field-offset arithmetic LEXICALLY on every ref that changed a
    path HEAD declares a struct/class in, and diffs the result against HEAD's computed fields. `kind="drift"`
    is a real byte-contract break (the only kind that exits 2); `kind="spelling"`/`"stub"` mirror `--layout`'s
    own harmless cases; `kind="unknown"` is a ref-side copy that could not be modelled (its caveats ride along
    — never reported as unchanged); `kind="absent"` is a ref that does not define the struct there at all.
    Matching structs are omitted (report only differences). Read-only, single-root, exit 2 on a real drift.
