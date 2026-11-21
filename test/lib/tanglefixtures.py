#!/usr/bin/env python3
"""tanglefixtures.py STAGE DIR — write the tanglecheck.sh fixture tree for one history stage.

STAGE: v1 (the tagged release), wip then c2 (two commits of a side branch merged --no-ff after it), wt (the working tree the gate
judges).
Each function lives in its own file so a row's p= names it alone. Shapes (C++):
  tangled   — new in wt: a depth-6 region, a steering flag set inside it and read 60 statements later (a row).
  sequential — new in wt: 150 flat statements (score 0, no row).
  orchestrator — new in wt: 120 calls to named steps (score 0, no row).
  dispatcher — new in wt: a 30-arm switch, each short arm nesting to depth 4 (flat dispatch: no row).
  shorthelper — new in wt: 30 lines at depth 6 (50 lines or fewer: no row).
  steerfar / steernear — new in wt: a flag set then tested 12 statements later (counted) vs in the next statement (not).
  steercursor — new in wt: a cursor advanced, then read 12 statements later only as a bound (`pos < limit`) and an index
          (`xs[ pos ]`): a position, not a decision (census 11-19, lexCpp's `j`): no steer.
  steerscope — new in wt: a counter `a` rewritten inside a block that then closes; 12 statements later a for head declares a new
          `a` and the loop tests it: the closed block's `a` is out of scope (census 11-19, genPathOf): no steer.
  armnest — new in wt: a 6-arm else-if chain whose short arms nest to depth 7, beside one depth-4 region outside it: the
          arms' nesting is theirs (census 11-19, parseArgs): no row.
  creep — tangled at v1 (depth 4, 40 deep lines); +3 deep lines at c2 and +3 more in wt: each step under the rise rule
          (+5), together over it — the ratchet's row.
  shrink — tangled at v1/c2; wt removes its deep region: credited in <improved> (tangle), no row.
  simplify — ccx 21 at v1/c2, ccx 11 in wt: credited in <improved> (complexity).
  nudge — tangled at v1/c2 (40 deep lines); wt drops 2 of them: under the rise step, so no <improved> entry (and no row).
  crossing — 100 flat lines at v1/c2 (score 0); wt gives it tangled's body: it crossed the bar, a GATING row (rule (b), 11-21).
  harnessmain — new in wt under test/: tangled's body, a row that stays sev="minor" (test code never gates by tangle).
  The RATCHET against the range base (QD-RATCHET-BASE, replay 11-21), three over-bar functions (v1 40 deep lines):
  grow1 — 40 at c2, 42 in wt: the score grew a little, under the rise step and under its best since v1's rise: a ratchet row.
  reflow — 46 at c2 (+6 over v1), wt adds one flat line: its inputs moved but the score is the same tenth: no row (the replay's
          buildGraph in #706, +28 lines at 56.9 -> 56.9, that the tag-best compare flagged).
  settle — 48 at c2 (+8 over v1), 47 in wt: the score fell: no row (the replay's captureTagsFacts 29.2 -> 29.1 in #714).
  The wip stage cuts creep to 5 deep lines on the side branch, whose next commit (c2) grows it back: a version the first-parent
  line never stood at, so it must not become creep's best (r1 would read deep 8->49).
"""
import os
import sys


def write(d, name, text):
    with open(os.path.join(d, "src", name), "w") as f:
        f.write(text)


def deep_block(n, depth_indent):
    pad = " " * depth_indent
    return "".join(f"{pad}total += {k};\n" for k in range(n))


def creep(extra):
    # depth: for(1) if(2) for(3) if(4) -> the deep region is the body of the 4th level
    return overbar("creep", 40 + extra, mult=3, gt=0, mod=2)


def shrink(deep):
    if deep:
        inner = ("            for( int y = 0; y < x; ++y )\n            {\n"
                 "                if( y % 3 )\n                {\n"
                 "                    while( total < y )\n                    {\n"
                 + deep_block(40, 24) +
                 "                    }\n                }\n            }\n")
    else:
        inner = "            total += x;\n"
    tail = "".join(f"    total = total * 5 + {k};\n" for k in range(70))
    return ("int shrink( const std::vector<int>& xs )\n{\n    int total = 0;\n"
            "    for( int x : xs )\n    {\n        if( x > 1 )\n        {\n" + inner +
            "        }\n    }\n" + tail + "    return total;\n}\n")


def simplify(branches):
    arms = "".join(f"    if( x == {k} )\n    {{\n        y += {k};\n    }}\n" for k in range(branches))
    return "int simplify( int x )\n{\n    int y = 0;\n" + arms + "    return y;\n}\n"


def nudge(deep):
    return overbar("nudge", deep, mult=11)


def overbar(name, deep, extra=0, mult=13, gt=2, mod=5):
    # nudge's shape under another name: for(1) if(2) for(3) if(4), `deep` lines at depth 4, a flat tail of 70 + extra lines
    inner = deep_block(deep, 20)
    tail = "".join(f"    total = total * {mult} + {k};\n" for k in range(70 + extra))
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n"
            f"    for( int x : xs )\n    {{\n        if( x > {gt} )\n        {{\n"
            "            for( int y = 0; y < x; ++y )\n            {\n"
            f"                if( y % {mod} )\n                {{\n" + inner +
            "                }\n            }\n        }\n    }\n" + tail + "    return total;\n}\n")


def tangled(name="tangled"):
    deep = deep_block(25, 28)
    seq = "".join(f"    total = total + {k};\n" for k in range(60))
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n    bool found = false;\n"
            "    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n"
            "            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y % 2 )\n                {\n"
            "                    while( total < y )\n                    {\n"
            "                        if( total == 7 )\n                        {\n"
            "                            found = true;\n" + deep +
            "                        }\n                        total += 1;\n"
            "                    }\n                }\n            }\n        }\n    }\n"
            + seq + "    if( found )\n    {\n        total *= 2;\n    }\n    return total;\n}\n")


def sequential(name="sequential", n=150):
    return (f"int {name}( int x )\n{{\n    int total = x;\n"
            + "".join(f"    total = total * 7 + {k};\n" for k in range(n)) + "    return total;\n}\n")


def orchestrator():
    steps = "".join(f"int step{k}( int );\n" for k in range(120))
    calls = "".join(f"    x = step{k}( x );\n" for k in range(120))
    return steps + "int orchestrator( int x )\n{\n" + calls + "    return x;\n}\n"


def dispatcher():
    arms = ""
    for k in range(30):
        arms += (f"    case {k}:\n"
                 f"        if( x > {k} )\n        {{\n"
                 f"            for( int i = 0; i < x; ++i )\n            {{\n"
                 f"                if( i == {k} )\n                {{\n"
                 f"                    total += {k};\n                    total *= 2;\n"
                 f"                }}\n            }}\n        }}\n        break;\n")
    return "int dispatcher( int op, int x )\n{\n    int total = 0;\n    switch( op )\n    {\n" + arms + "    }\n    return total;\n}\n"


def shorthelper():
    return ("int shorthelper( const std::vector<int>& xs )\n{\n    int t = 0;\n"
            "    for( int x : xs )\n    {\n        if( x )\n        {\n            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y )\n                {\n                    while( t < y )\n                    {\n"
            "                        if( t == 3 )\n                        {\n"
            + deep_block(8, 28) +
            "                        }\n                        t += 1;\n                    }\n                }\n            }\n        }\n    }\n"
            "    return t;\n}\n")


def steer(name, gap):
    before = "".join(f"    total = total + {k};\n" for k in range(30))
    between = "".join(f"    total = total * 2 + {k};\n" for k in range(gap))
    after = "".join(f"    total = total - {k};\n" for k in range(30))
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n    bool seen = false;\n" + before +
            "    for( int x : xs )\n    {\n        if( x == 3 )\n        {\n            seen = true;\n        }\n    }\n"
            + between + "    if( seen )\n    {\n        total += 1;\n    }\n" + after + "    return total;\n}\n")


def steercursor():
    before = "".join(f"    total = total + {k};\n" for k in range(30))
    between = "".join(f"    total = total * 2 + {k};\n" for k in range(12))
    after = "".join(f"    total = total - {k};\n" for k in range(30))
    return ("int steercursor( const std::vector<int>& xs, int limit )\n{\n    int total = 0;\n    int pos = 0;\n" + before +
            "    for( int x : xs )\n    {\n        if( x == 3 )\n        {\n            pos += 2;\n        }\n    }\n"
            + between + "    if( pos < limit && xs[ pos ] == 3 )\n    {\n        total += 1;\n    }\n" + after + "    return total;\n}\n")


def steerscope():
    before = "".join(f"    total = total + {k};\n" for k in range(30))
    between = "".join(f"    total = total * 2 + {k};\n" for k in range(12))
    after = "".join(f"    total = total - {k};\n" for k in range(30))
    return ("int steerscope( const std::vector<int>& xs )\n{\n    int total = 0;\n" + before +
            "    {\n        int a = 0;\n        for( int x : xs )\n        {\n            if( x == 3 )\n            {\n                a += 1;\n"
            "            }\n        }\n        total += a;\n    }\n"
            + between + "    for( int a = 0;; )\n    {\n        if( a == 5 )\n        {\n            break;\n        }\n        a = a + 1;\n    }\n"
            + after + "    return total;\n}\n")


def armnest():
    arms = ""
    for k in range(6):
        kw = "if" if k == 0 else "else if"
        arms += (f"    {kw}( op == {k} )\n    {{\n"
                 f"        for( int a = 0; a < x; ++a )\n        {{\n"
                 f"            if( a > {k} )\n            {{\n"
                 f"                while( total < a )\n                {{\n"
                 f"                    if( total == {k} )\n                    {{\n"
                 f"                        for( int b = 0; b < a; ++b )\n                        {{\n"
                 f"                            if( b == {k} )\n                            {{\n"
                 f"                                total += {k};\n"
                 f"                            }}\n                        }}\n                    }}\n"
                 f"                    total += 1;\n                }}\n            }}\n        }}\n    }}\n")
    outside = ("    for( int a = 0; a < x; ++a )\n    {\n        if( a > 2 )\n        {\n"
               "            for( int b = 0; b < a; ++b )\n            {\n                if( b == 1 )\n                {\n"
               "                    total += a;\n                    total *= 3;\n"
               "                }\n            }\n        }\n    }\n")
    tail = "".join(f"    total = total * 3 + {k};\n" for k in range(30))
    return "int armnest( int op, int x )\n{\n    int total = 0;\n" + arms + outside + tail + "    return total;\n}\n"


def main():
    stage, d = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(d, "src"), exist_ok=True)
    hdr = "#include <vector>\n"
    extra = {"v1": 0, "wip": -35, "c2": 3, "wt": 6}[stage]
    write(d, "creep.cpp", hdr + creep(extra))
    write(d, "shrink.cpp", hdr + shrink(stage != "wt"))
    write(d, "simplify.cpp", simplify(20 if stage != "wt" else 10))
    write(d, "nudge.cpp", hdr + nudge(40 if stage != "wt" else 38))
    if stage != "wt":
        write(d, "crossing.cpp", sequential("crossing", 100))
    write(d, "grow1.cpp", hdr + overbar("grow1", 42 if stage == "wt" else 40, mult=17))
    write(d, "reflow.cpp", hdr + overbar("reflow", 40 if stage == "v1" else 46, extra=1 if stage == "wt" else 0, mult=19))
    write(d, "settle.cpp", hdr + overbar("settle", {"v1": 40, "wt": 47}.get(stage, 48), mult=23))
    if stage == "wt":
        write(d, "crossing.cpp", hdr + tangled("crossing"))
        os.makedirs(os.path.join(d, "test"), exist_ok=True)
        with open(os.path.join(d, "test", "harness.cpp"), "w") as f:
            f.write(hdr + tangled("harnessmain"))
        write(d, "tangled.cpp", hdr + tangled())
        write(d, "sequential.cpp", sequential())
        write(d, "orchestrator.cpp", orchestrator())
        write(d, "dispatcher.cpp", dispatcher())
        write(d, "shorthelper.cpp", hdr + shorthelper())
        write(d, "steerfar.cpp", hdr + steer("steerfar", 12))
        write(d, "steernear.cpp", hdr + steer("steernear", 0))
        write(d, "steercursor.cpp", hdr + steercursor())
        write(d, "armnest.cpp", armnest())
        write(d, "steerscope.cpp", hdr + steerscope())


if __name__ == "__main__":
    main()
