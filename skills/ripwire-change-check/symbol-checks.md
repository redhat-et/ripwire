# ripwire-change-check — reference: symbol-checks (read on demand; the recipe is in SKILL.md)

10. **Mid-edit contract check, one symbol at a time** — `ripwire <dir> --edit-check=SYM --legend=compact` (file:name
    disambiguates a same-named symbol, like `--around`/`--lego`). The fast, targeted sibling of step 8's
    `--test-gate`/`--quality-delta`: right after you touch a function, ask "did I just change a contract
    someone depends on" without waiting for a full diff. Reports exactly one of `status="unchanged"` /
    `"new-symbol"` / `"contract-change"` (with `params_was`/`params_now`/`public_was`/`public_now` on the
    latter) vs git HEAD, plus SYM's 1-hop callers with any call-site whose argument count is now provably
    incompatible flagged `incompatible="1"`. Warm (cache-hit) on ripwire's own tree. A `.ripwire_notes` entry
    on SYM (or its file) rides along as a `<note>` child, the same row `--for`/`--expand` surface.

11. **"Can I delete this?" for one symbol** — `ripwire <dir> --safe-delete=SYM --legend=compact` (file:name disambiguates,
    same grammar as `--edit-check`/`--around`/`--lego`). The removal-side sibling of step 10: composes
    1-hop `callers=`, the transitive `--impact` blast radius (`impact_reaches=`), every `--uses`
    read/write/import/call/extends site (`uses=`), how much of that radius the `tested=` lens covers
    (`radius_tested=`/`radius_untested=`), and `--dead-code`'s own zero-caller/internal-linkage shape at
    `defs=1` (`dead_code_candidate=`), into ONE call. `risk=` NAMES what was found — `none-found` / `possible-callers` (a declined call could have
    meant it; its `<dc>` rows name the sites) / `uses-exist` / `unmodelled` / `untested-radius` — never a go/no-go verdict; `radius_untested=` equal to `impact_reaches=` is the
    strongest signal ("nothing downstream is test-covered"). `ambiguous_callers=`/per-row `amb="1"` disclose
    the same call-graph resolution limit `--edit-check`'s `incompatible=` and `--for`'s `amb=` already carry.

## Output

Impact summary: blast-radius count, test coverage (zero = blocking concern), whether any changed file is a
top-10 hotspot, any lint findings in changed files, and any `--metrics` red flags (high/rising `cbo`,
`lcom4>1`, or missing `tested=1`) on a touched symbol. A green change passes: radius understood, tests exist, no new
lint smells, no hotspot surprise, no coupling/cohesion regression. Recommend one of: **safe to merge** /
**needs tests** / **review the hotspot** / **lint issues to fix** / **decouple before merge**. (Ran
quality-bar first? Both green = ship — see the Routing note above.)

**Honesty:** ripwire cedes data-flow/type checks (use-after-move, taint) to the compiler — pair this with
the build's warnings and the test suite. Blast radius is name-based; a high-`amb` edge was guessed.
