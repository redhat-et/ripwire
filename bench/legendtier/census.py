#!/usr/bin/env python3
"""census.py — which legend-dictionary entries do a schema's answers actually carry?

Reads saved DEFAULT-posture answers (one XML document per file) and writes the census the pack table is built from
(bench/legendtier/census.tsv -> packs_build.py -> src/legendpacks.h). A default answer's legend is exactly the
definitions it needs, so "the entries this answer carries" is read off the answer: every dictionary line is matched
verbatim, longest first, against the answer's legend comment.

An entry is named by what it DEFINES — attribute, element, listed item — taken from `ripwire --legend-dict=index`,
never by its wording or its id: a reworded definition then stays in its pack, and an inserted row moves nothing.

    python3 bench/legendtier/census.py BIN OUT.tsv LABEL=DIR [LABEL=DIR ...]

DIR is searched recursively for *.xml. An answer with no compact legend (JSON, prose, the --for dialect) is counted
under `skipped` and enters no denominator. The corpora behind the committed census are not in this repository; this
script is how the census is re-taken, not something a gate can re-run.
"""
import collections, glob, os, re, subprocess, sys

PUR  = re.compile(r"ripwire\.([\w.-]+)/v1 <[^>]*>: ")
OPEN = re.compile(r"<!-- ripwire ([\w.-]+) schema=ripwire\.([\w.-]+)/v1: ")
CMT  = re.compile(r"<!--.*?-->", re.S)

def out_of(binary, *args):
    p = subprocess.run([binary, *args], capture_output=True)
    if p.returncode != 0:
        sys.exit("census: %s %s exited %d: %s" % (binary, " ".join(args), p.returncode, p.stderr.decode()[:200]))
    return p.stdout.decode("utf-8")

def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    binary, dest, sources = sys.argv[1], sys.argv[2], sys.argv[3:]
    index = [l.split("\t") for l in out_of(binary, "--legend-dict=index").splitlines()]
    core = set(out_of(binary, "--legend-dict=core").split("\n")[1:])
    by_line = collections.defaultdict(list)          # line -> [(cls, key, attr, tag, item)]
    for f in index:
        if len(f) != 7:
            sys.exit("census: --legend-dict=index row has %d fields, expected 7" % len(f))
        by_line[f[6]].append(tuple(f[1:6]))
    purposes = {}                                    # schema key -> purpose body
    for line in by_line:
        m = PUR.match(line)
        if m:
            purposes.setdefault(m.group(1), []).append(line[m.end():])
    terms = sorted((l for l, rows in by_line.items() if rows[0][0] in ("term", "attr", "name")), key=lambda s: (-len(s), s))

    answers = collections.Counter()                  # key -> n
    counts = collections.Counter()                   # (key, attr, tag, item) -> n
    per_label = collections.Counter()
    skipped = unmatched = 0
    for src in sources:
        label, _, root = src.partition("=")
        for path in sorted(glob.glob(os.path.join(root, "**", "*.xml"), recursive=True)):
            doc = open(path, encoding="utf-8", errors="replace").read()
            legend = next((m.group(0) for m in CMT.finditer(doc) if OPEN.match(m.group(0))), None)
            if legend is None:
                skipped += 1
                continue
            o = OPEN.match(legend)
            key, text = o.group(2), " " + legend[o.end():-3].rstrip()
            if key not in purposes:
                skipped += 1                          # a dialect the dictionary holds no purpose for (--for)
                continue
            answers[key] += 1
            per_label[label] += 1
            seen = set()
            if any(text.startswith(" " + p + ".") for p in purposes[key]):
                seen.add((key, "@purpose", "", ""))
            for line in terms:
                at = text.find(" " + line + ".")
                if at < 0:
                    continue
                text = text[:at] + "\x00" + text[at + len(line) + 2:]
                if line in core:
                    continue
                for cls, okey, attr, tag, item in by_line[line]:
                    if okey in ("", key):
                        seen.add((key, attr, tag, item))
            for handle in seen:
                counts[handle] += 1
    version = out_of(binary, "--version").splitlines()[0].split(" (")[0]
    with open(dest, "w", encoding="utf-8") as fo:
        fo.write("# census.tsv — written by bench/legendtier/census.py; read by bench/legendtier/packs_build.py. Do not edit by hand.\n")
        fo.write("# binary: %s\n" % version)
        fo.write("# answers: %s; %d without a compact legend the dictionary holds (skipped)\n"
                 % (", ".join("%s %d" % kv for kv in sorted(per_label.items())), skipped))
        fo.write("# N<TAB>key<TAB>answers   |   E<TAB>key<TAB>count<TAB>attr<TAB>element<TAB>item   (core-tier lines are not counted)\n")
        for key in sorted(answers):
            fo.write("N\t%s\t%d\n" % (key, answers[key]))
        for (key, attr, tag, item), n in sorted(counts.items()):
            fo.write("E\t%s\t%d\t%s\t%s\t%s\n" % (key, n, attr, tag, item))
    print("census: %d answers over %d schemas, %d entry handles, %d skipped -> %s" % (sum(answers.values()), len(answers), len(counts), skipped, dest))

if __name__ == "__main__":
    main()
