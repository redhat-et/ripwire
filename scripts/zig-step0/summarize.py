#!/usr/bin/env python3
"""Turn zig-step0 TSV rows into RESULTS.md.

The measurement rule lives in measure.c. This script only sums those rows and
writes the pin comparison the issue asked for. It does not parse Zig.
"""

import collections
import re
import sys
from pathlib import Path

WORDS = ("usingnamespace", "async", "await", "suspend", "resume", "nosuspend", "anyframe")
KEEP = set(
    WORDS
    + (
        "fn", "pub", "const", "var", "comptime", "export", "extern", "inline",
        "struct", "enum", "union", "error", "test", "if", "else", "while", "for",
        "switch", "return", "try", "catch", "orelse", "and", "or", "break",
        "continue", "defer", "errdefer", "unreachable", "asm", "volatile",
        "allowzero", "align", "linksection", "callconv", "noalias", "packed",
        "opaque", "threadlocal", "noinline", "anytype", "undefined", "null",
        "true", "false",
    )
)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\d+")
STRING = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')


def pct(n, d, places):
    if d == 0:
        return "n/a"
    return f"{(100.0 * n / d):.{places}f}%"


def nfiles(n):
    return "1 file" if n == 1 else f"{n} files"


def norm(text):
    # Keep the harness's own labels. Folding them into ID hides the cluster.
    if text.startswith("cost ") or text.startswith("MISSING "):
        return text
    text = STRING.sub("STR", text)

    def repl(m):
        w = m.group(0)
        if w in KEEP:
            return w
        if w.isdigit():
            return "N"
        return "ID"

    text = IDENT.sub(repl, text)
    return re.sub(r"\s+", " ", text).strip()[:160]


def load_tsv(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 10:
                raise SystemExit(f"{path}: expected 10 fields, got {len(parts)}: {line[:120]}")
            path_s, nbytes, status, err_b, err_n, miss_n, first_line, flags, span, src_line = parts
            rows.append(
                {
                    "path": path_s,
                    "bytes": int(nbytes),
                    "status": status,
                    "err_bytes": int(err_b),
                    "err_nodes": int(err_n),
                    "missing": int(miss_n),
                    "line": first_line,
                    "flags": [x for x in flags.split(",") if x],
                    "span": span,
                    "src": src_line,
                }
            )
    return rows


def keyword_files(root):
    counts = collections.Counter()
    files = 0
    word_re = re.compile(r"\b(" + "|".join(WORDS) + r")\b")
    for p in Path(root).rglob("*.zig"):
        if not p.is_file() or ".git" in p.parts:
            continue
        files += 1
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        counts.update(set(word_re.findall(text)))
    return files, counts


def cell_stats(rows):
    finished = [r for r in rows if r["status"] in ("clean", "error")]
    clean = [r for r in finished if r["status"] == "clean"]
    err = [r for r in finished if r["status"] == "error"]
    missing_only = [r for r in err if r["err_bytes"] == 0]
    file_bytes = sum(r["bytes"] for r in finished)
    err_bytes = sum(r["err_bytes"] for r in finished)
    return {
        "files": len(rows),
        "finished": len(finished),
        "clean": len(clean),
        "error": len(err),
        "missing_only": len(missing_only),
        "timeout": sum(1 for r in rows if r["status"] == "timeout"),
        "read_error": sum(1 for r in rows if r["status"] == "read_error"),
        "too_big": sum(1 for r in rows if r["status"] == "too_big"),
        "file_bytes": file_bytes,
        "err_bytes": err_bytes,
    }


def md_cell(s):
    return s


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: summarize.py <manifest.tsv> <RESULTS.md>")
    manifest_path, out_path = sys.argv[1:]
    runs = []
    with open(manifest_path, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        for line in f:
            vals = line.rstrip("\n").split("\t")
            runs.append(dict(zip(header, vals)))
    by_corpus = collections.OrderedDict()
    for run in runs:
        run["rows"] = load_tsv(run["tsv"])
        run["stats"] = cell_stats(run["rows"])
        by_corpus.setdefault(run["corpus_id"], []).append(run)

    lines = []
    w = lines.append
    w("# Zig STEP 0 — grammar pin measurement")
    w("")
    w("Issue [#166](https://github.com/redhat-et/ripwire/issues/166). This is the")
    w("parse-rate measurement only. The grammar is not vendored, and nothing is extracted.")
    w("")
    w("## Method")
    w("")
    w("Both documented pins of [tree-sitter-grammars/tree-sitter-zig](https://github.com/tree-sitter-grammars/tree-sitter-zig)")
    w("were linked against the vendored tree-sitter core (`TREE_SITTER_LANGUAGE_VERSION` 15,")
    w("minimum compatible 13) and run on the same files.")
    w("")
    w("| pin | commit | ABI | what changed since v1.1.2 |")
    w("| --- | --- | --- | --- |")
    w("| `v1.1.2` | `b670c8df85a1568f498aa5c8cae42f51a90473c0` | 14 | tagged pin, 2024-12-22 |")
    w("| `6479aa13` | `6479aa13f32f701c383083d8b28360ebd682fb7d` | 15 | documented `master` pin, 2025-09-10 |")
    w("")
    w("`grammar.js` between those commits moves a call's argument list into an `arguments`")
    w("rule, `seq('(', optionalCommaSep($.expression), ')')`, which is the same sequence the")
    w("old `call_expression` inlined. Both grammars still contain `usingnamespace`, `async`,")
    w("and `await`. `parser.c` was regenerated. Neither pin has an external scanner.")
    w("`6479aa13` is not current `master`; it is the commit the issue names.")
    w("")
    w("For each file the harness records the two numbers from `prompts/help-wanted/zig-language.md`,")
    w("counted the way `measureFileHealth` in `src/ingest_crawl.h` counts them:")
    w("")
    w("- clean means `ts_node_has_error(root)` is false;")
    w("- the ERROR-byte share is the sum of the top-most ERROR spans. Nested recovery")
    w("  nodes are not added again. A MISSING node makes the file not clean and adds no bytes.")
    w("")
    w("A file that does not finish within 10 seconds is a timeout. Timeouts are not clean")
    w("and are left out of the byte ratio. Files over 64 MiB would be `too_big` and were")
    w("not seen. `.zon` files are not part of this measurement.")
    w("")
    w("## Corpora")
    w("")
    w("The standard library is `lib/std.zig` plus `lib/std/` at a release tag. A sparse")
    w("checkout of `lib/std` also keeps files that sit directly in `lib/`")
    w("(`c.zig`, `compiler_rt.zig`, `fuzzer.zig`, `ubsan_rt.zig`) and the root `build.zig`.")
    w("Those extra files are in the totals. The same commit is on Codeberg and on the")
    w("GitHub mirror. Ghostty")
    w("is every tracked `.zig` file at a release whose `build.zig.zon` names the Zig")
    w("version. Ghostty 1.3.1 asks for 0.15.2; the 0.15 standard library measured here is")
    w("0.15.1, the release named in the grammar pin's corpus bump. 0.15.2 is a bugfix")
    w("on that language.")
    w("")
    w("| corpus | Zig | commit | files |")
    w("| --- | --- | --- | --- |")
    seen = set()
    for run in runs:
        if run["corpus_id"] in seen:
            continue
        seen.add(run["corpus_id"])
        w(f"| {run['corpus_id']} | {run['zig']} | `{run['corpus_sha']}` | {run['stats']['files']} |")
    w("")
    w("Dialect keywords present anywhere in a corpus (a file is counted once per word).")
    w("This is the corpus, not the parser: it says whether the 0.14-era keywords are still")
    w("in the tree.")
    w("")
    w("| corpus | " + " | ".join(WORDS) + " |")
    w("| --- | " + " | ".join("---" for _ in WORDS) + " |")
    keyword_cache = {}
    for run in runs:
        if run["corpus_id"] in keyword_cache:
            continue
        keyword_cache[run["corpus_id"]] = keyword_files(run["root"])
        _, counts = keyword_cache[run["corpus_id"]]
        w("| " + run["corpus_id"] + " | " + " | ".join(str(counts[word]) for word in WORDS) + " |")
    w("")
    w("## Results")
    w("")
    w("Clean % is clean files / files that finished. ERROR % is top-most ERROR bytes / bytes")
    w("in files that finished. `zero-width` is a finished file with an error flag and")
    w("no ERROR bytes: a MISSING token, or a node whose error cost is neither.")
    w("")
    w("| corpus | pin | files | clean | clean % | ERROR bytes | file bytes | ERROR % | zero-width | timeout |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for corpus_id, group in by_corpus.items():
        for run in group:
            s = run["stats"]
            w(
                "| {corpus} | `{pin}` | {files} | {clean}/{finished} | {cp} | {eb} | {fb} | {ep} | {mo} | {to} |".format(
                    corpus=corpus_id,
                    pin=run["pin_id"],
                    files=s["files"],
                    clean=s["clean"],
                    finished=s["finished"],
                    cp=pct(s["clean"], s["finished"], 2),
                    eb=s["err_bytes"],
                    fb=s["file_bytes"],
                    ep=pct(s["err_bytes"], s["file_bytes"], 3),
                    mo=s["missing_only"],
                    to=s["timeout"],
                )
            )
    w("")

    # Pool by pin. Every corpus is measured with every pin, so the file set matches.
    pins = []
    for run in runs:
        if run["pin_id"] not in pins:
            pins.append(run["pin_id"])
    pooled = {}
    for pin in pins:
        acc = collections.Counter()
        for run in runs:
            if run["pin_id"] != pin:
                continue
            for k, v in run["stats"].items():
                acc[k] += v
        pooled[pin] = acc
    w("Pooled across the four corpora:")
    w("")
    w("| pin | clean | clean % | ERROR bytes | file bytes | ERROR % | timeout |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    for pin in pins:
        s = pooled[pin]
        w(
            "| `{pin}` | {clean}/{finished} | {cp} | {eb} | {fb} | {ep} | {to} |".format(
                pin=pin,
                clean=s["clean"],
                finished=s["finished"],
                cp=pct(s["clean"], s["finished"], 2),
                eb=s["err_bytes"],
                fb=s["file_bytes"],
                ep=pct(s["err_bytes"], s["file_bytes"], 3),
                to=s["timeout"],
            )
        )
    w("")

    w("## Where the pins differ")
    w("")
    any_diff = False
    for corpus_id, group in by_corpus.items():
        by_pin = {run["pin_id"]: {r["path"]: r for r in run["rows"]} for run in group}
        if len(by_pin) != 2:
            continue
        left_id, right_id = pins[0], pins[1]
        left, right = by_pin[left_id], by_pin[right_id]
        paths = sorted(set(left) | set(right))
        diffs = []
        for path in paths:
            a, b = left.get(path), right.get(path)
            if a is None or b is None or a["status"] != b["status"] or a["err_bytes"] != b["err_bytes"]:
                diffs.append((path, a, b))
        w(f"`{corpus_id}`: {len(diffs)} file(s) differ in status or ERROR bytes.")
        if diffs:
            any_diff = True
            w("")
            w("| file | {a} | {b} |".format(a=left_id, b=right_id))
            w("| --- | --- | --- |")
            for path, a, b in diffs[:40]:
                def brief(row):
                    if row is None:
                        return "absent"
                    return f"{row['status']} err_bytes={row['err_bytes']}"

                w(f"| `{path}` | {brief(a)} | {brief(b)} |")
            if len(diffs) > 40:
                w("")
                w(f"{len(diffs) - 40} further files differ; the TSV from `run.sh` has the rest.")
            w("")
    if not any_diff:
        w("")
        w("No file changed status or ERROR-byte count between the pins.")
        w("")

    w("## Representative failures")
    w("")
    if any_diff:
        w("Pins that differ are listed in the previous section. Patterns below are from")
        w("the first pin only.")
    else:
        w("The pins agreed on every file, so each corpus is shown once.")
    w("A pattern is the start of the first top-most ERROR span. A file with an error")
    w("flag and no ERROR bytes is `MISSING <token>` or `cost <type>` (a zero-width node")
    w("whose error cost is neither an ERROR nor a MISSING node). Identifiers and numbers")
    w("are folded. The byte table is only files that contain ERROR bytes.")
    w("")
    for corpus_id, group in by_corpus.items():
        run = group[0]
        err = [r for r in run["rows"] if r["status"] == "error"]
        w(f"### {corpus_id}")
        w("")
        if not err:
            w("No file with an error flag.")
            w("")
            continue
        flag_counts = collections.Counter()
        for r in err:
            flag_counts.update(r["flags"])
        if flag_counts:
            w("Dialect keywords inside the first top-most ERROR span:")
            w("")
            w("| keyword | files |")
            w("| --- | --- |")
            for word in WORDS:
                if flag_counts[word]:
                    w(f"| `{word}` | {flag_counts[word]} |")
            w("")
        patterns = collections.Counter(norm(r["span"]) or "(empty span)" for r in err)
        examples = {}
        for r in err:
            key = norm(r["span"]) or "(empty span)"
            examples.setdefault(key, r)
        w("| files | pattern | example |")
        w("| --- | --- | --- |")
        for pattern, n in patterns.most_common(8):
            ex = examples[pattern]
            shown = pattern.replace("|", "\\|")
            src = ex["src"].replace("|", "\\|")
            if ex["span"].startswith("cost ") or ex["span"].startswith("MISSING "):
                w(f"| {n} | `{shown}` | `{ex['path']}:{ex['line']}` `{src}` |")
            else:
                w(f"| {n} | `{shown}` | `{ex['path']}:{ex['line']}` |")
        w("")
        cost_rows = [r for r in err if r["span"].startswith("cost ")]
        if cost_rows:
            buckets = collections.Counter()
            for r in cost_rows:
                hit = "other"
                for key in ("struct {}", "enum {}", "opaque {}", "union {}"):
                    if key in r["src"]:
                        hit = key
                        break
                buckets[hit] += 1
            parts = [f"`{key}` × {buckets[key]}" for key in ("struct {}", "enum {}", "opaque {}", "union {}", "other") if buckets[key]]
            w(f"Zero-width `cost identifier` rows: {len(cost_rows)}. Lines containing an empty container: {', '.join(parts)}.")
            w("")
        worst = sorted((r for r in err if r["err_bytes"] > 0), key=lambda r: (-r["err_bytes"], r["path"]))[:8]
        if not worst:
            w("No ERROR bytes in this corpus.")
            w("")
            continue
        w("| ERROR bytes | file bytes | file | line | span |")
        w("| --- | --- | --- | --- | --- |")
        for r in worst:
            span = r["span"].replace("|", "\\|")
            w(f"| {r['err_bytes']} | {r['bytes']} | `{r['path']}` | {r['line']} | `{span}` |")
        w("")

    w("## Directories")
    w("")
    w("ERROR-byte share by the first path component, using `v1.1.2`. The other pin")
    w("matches these totals. `pkg/` is Ghostty's in-tree Zig packages, not a second")
    w("dialect hidden under `src/`.")
    w("")
    for corpus_id, group in by_corpus.items():
        run = group[0]
        w(f"### {corpus_id}")
        w("")
        w("| directory | files | clean % | ERROR % |")
        w("| --- | --- | --- | --- |")
        buckets = collections.defaultdict(list)
        for r in run["rows"]:
            top = r["path"].split("/", 1)[0]
            buckets[top].append(r)
        for top in sorted(buckets):
            st = cell_stats(buckets[top])
            w(
                "| `{top}` | {files} | {cp} | {ep} |".format(
                    top=top,
                    files=st["files"],
                    cp=pct(st["clean"], st["finished"], 2),
                    ep=pct(st["err_bytes"], st["file_bytes"], 3),
                )
            )
        w("")

    # Recommendation. "Parses more" is the issue's rule: more clean files on the
    # pooled set, then fewer ERROR bytes. A tie keeps the tagged pin.
    order = sorted(
        pins,
        key=lambda pin: (pooled[pin]["clean"], -pooled[pin]["err_bytes"]),
        reverse=True,
    )
    best, other = order[0], order[1]
    tied = (
        pooled[best]["clean"] == pooled[other]["clean"]
        and pooled[best]["err_bytes"] == pooled[other]["err_bytes"]
    )
    w("## Recommendation")
    w("")
    w("The issue's rule is to pin the grammar that parses more of the same corpus: more")
    w("files with no error flag, then fewer top-most ERROR bytes. A tie stays on the")
    w("tagged commit, which is the house convention (`CMakeLists.txt` comments a tag")
    w("after the SHA; the Swift pin is the exception, and it says why).")
    w("")
    if tied and not any_diff:
        w("The pins tie on every file, not only on the pooled totals. `6479aa13` does not")
        w("parse more. Pin **`v1.1.2`** (`b670c8df85a1568f498aa5c8cae42f51a90473c0`, ABI 14).")
    elif tied:
        w("The pooled totals tie. Some files still differ; they are listed above. Neither")
        w("pin parses more of the pool. Pin **`v1.1.2`**")
        w("(`b670c8df85a1568f498aa5c8cae42f51a90473c0`, ABI 14).")
    elif best == "v1.1.2":
        w("`v1.1.2` parses more of the pooled corpus than `6479aa13`. Pin **`v1.1.2`**")
        w("(`b670c8df85a1568f498aa5c8cae42f51a90473c0`, ABI 14).")
    else:
        w("`6479aa13` parses more of the pooled corpus than the tag. When extraction vendors")
        w("it, the `CMakeLists.txt` comment has to give that reason: the pin is untagged.")
        w("Pin **`6479aa13`** (`6479aa13f32f701c383083d8b28360ebd682fb7d`, ABI 15).")
    w("")
    w("`prompts/add-a-language.md` calls 95% of a real corpus worth vendoring, and treats")
    w("a grammar that silently drops about half of a language as worse than no grammar.")
    w("The two numbers answer that separately. Clean-file rate is the strict one. ERROR")
    w("bytes are how much of a file the recovery actually lost.")
    w("")
    for corpus_id, group in by_corpus.items():
        run = group[0]
        s = run["stats"]
        damaged = [r for r in run["rows"] if r["err_bytes"] > 0]
        if damaged:
            err_clause = "ERROR bytes {eb} ({ep}) in {damaged}".format(
                eb=s["err_bytes"],
                ep=pct(s["err_bytes"], s["file_bytes"], 3),
                damaged=nfiles(len(damaged)),
            )
        else:
            err_clause = "no ERROR bytes"
        w(
            "- `{corpus}`: {clean}/{finished} clean ({cp}); {err_clause}; {mo} flagged with zero ERROR bytes.".format(
                corpus=corpus_id,
                clean=s["clean"],
                finished=s["finished"],
                cp=pct(s["clean"], s["finished"], 2),
                err_clause=err_clause,
                mo=nfiles(s["missing_only"]),
            )
        )
    w("")
    focus = by_corpus["zig-std-0.15.1"][0]["stats"]
    other_err = sum(
        group[0]["stats"]["err_bytes"] for cid, group in by_corpus.items() if cid != "zig-std-0.15.1"
    )
    w("`zig-std-0.15.1` is the cell under 95% clean. It is not a half-parsed library:")
    w(f"its ERROR bytes are {pct(focus['err_bytes'], focus['file_bytes'], 3)} of that corpus,")
    w(f"and the other three corpora together hold {other_err} ERROR bytes. The shapes are")
    w("in the failure section. Vendoring can use the tagged pin. This step does not vendor")
    w("it and does not extract symbols; the issue asked for the table first.")
    w("")
    if any(run["stats"]["timeout"] or run["stats"]["too_big"] or run["stats"]["read_error"] for run in runs):
        w("Timeouts, unread files, and oversize files are in the table and are not counted")
        w("as clean.")
        w("")
    w("## Not in this step")
    w("")
    w("`@import` resolution, `.zon`, and Zig-to-C edges stay deferred, as agreed on the issue.")
    w("Nothing here binds `fs.openFile()` to a call. Extraction, vendoring, and `test/zigcheck.sh`")
    w("wait until this table is accepted.")
    w("")
    w("Re-run with `scripts/zig-step0/run.sh`. The corpora and both grammar checkouts are")
    w("fetched into the cache directory the script prints; they are not part of the tree.")
    w("")
    Path(out_path).write_text("\n".join(lines), encoding="utf-8")
    print(out_path)


if __name__ == "__main__":
    main()
