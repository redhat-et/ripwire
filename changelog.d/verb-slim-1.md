### Changed — default `--expand` puts the body first, and default `--quality-delta` leaves out counters that are zero

Two verbs' default (CLI, no `--legend=`) answers lose bytes that the brief-shape audit found no reader using. Everything else in those answers stays.

- **`--expand`.** The file context `sibs=`/`sibs_total=`/`sibs_capped=` and `inc=`/`inc_total=`/`inc_capped=` used to sit in the `<b>` tag, ahead of the body, and took 22-85 % of the answer. It now comes after the body, as an `<fctx …/>` element right after the `</b>`. Inside, the `<b>` keeps today's shape (the CDATA body, then `<calls>`), so a script that reads the body up to `]]></b>` still works. The sibling list is kept whole: a trace check over 142 real expand answers found 9 calls whose next Read or Grep used a name that only `sibs=` carried, at ranks up to 99 of 100. No traced call used the include list, so it becomes `inc_total=` plus `inc_next=`, the pasteable call that prints it. When the list is shorter than that pointer, `inc=` stays inline. The `<ctx>` root keeps `root=` (the rows' `p=` are relative to it) and drops `topk_default=` and `map_next=`. It also drops `est_tokens=`, except when a budget names a ceiling or the estimate is degraded, since those are the readers who act on it. The legend explains `<fctx>` and every attribute it carries.
- **`--quality-delta`.** The root leaves out `acked=`, `stale=`, `register-macro-excluded=`, `api-new-surface=`, `value-ref-excluded=` and `declined-call-excluded=` when they are 0, along with their legend readings, and says so with `omit0="1"`, whose reading names those counts. `regressions=`, `minor=`, `gating=`, `preexisting-worse=` and `new-symbol=` always print. Every row's `sym=` stays whole: it is the canonical id that scripts and `--ack-only` read. The `<r kind=…>` row shape, exit codes and gating are unchanged.

`--legend=full`, `--legend-have=`, `--legend-seen=`, the MCP server and `RIPWIRE_VERB_SLIM=0` print both answers exactly as before (the OFF switch is byte-identical to main on every measured cell). Five gates that pin the full fields (`defectackschemecheck`, `defectshapecheck`, `estchargecheck`, `expandtokencheck`, `expandtopk0check`) run with `RIPWIRE_VERB_SLIM=0`, and `emittertruthcheck` judges its "printed even at zero" claims on `--legend=full`, plus `omit0=` on the default.

Measured base (main) vs this change on real repositories (jq, zed, cockroach, vscode, llvm), with the audit's pre-registered items scored on the real outputs:

- **`--expand`, 13 cells:** median 3,774 to 3,197 B, sum ratio 0.881, items 82 to 82.
- **`--quality-delta`, 15 cells:** median 1,700 to 1,389 B, sum ratio 0.835, items 30 to 30, exit codes equal.
- **Other verbs:** `--callers`, `--callees`, `--grep` and `--whereis` are byte-identical in every cell. A 321-call `--for`/rung-0 replay and the `--deps`/map md5s on three large repositories are byte-identical too.

New gate: `test/verbslimcheck.sh`.
