#!/usr/bin/env python3
"""tanglefixtures.py STAGE DIR — write the tanglecheck.sh fixture tree for one history stage.

STAGE: v1 (the tagged release), c2 (one commit after it), wt (the working tree the gate judges).
Each function lives in its own file so a row's p= names it alone. Shapes (C++):
  tangled   — new in wt: a depth-6 region, a steering flag set inside it and read 60 statements later (a row).
  sequential — new in wt: 150 flat statements (score 0, no row).
  orchestrator — new in wt: 120 calls to named steps (score 0, no row).
  dispatcher — new in wt: a 30-arm switch, each short arm nesting to depth 4 (flat dispatch: no row).
  shorthelper — new in wt: 30 lines at depth 6 (50 lines or fewer: no row).
  steerfar / steernear — new in wt: a flag set then tested 12 statements later (counted) vs in the next statement (not).
  creep — tangled at v1 (depth 4, 40 deep lines); +3 deep lines at c2 and +3 more in wt: each step under the rise rule
          (+5), together over it — the ratchet's row.
  shrink — tangled at v1/c2; wt removes its deep region: credited in <improved> (tangle), no row.
  simplify — ccx 21 at v1/c2, ccx 11 in wt: credited in <improved> (complexity).
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
    body = deep_block(40 + extra, 20)
    tail = "".join(f"    total = total * 3 + {k};\n" for k in range(70))
    return ("int creep( const std::vector<int>& xs )\n{\n    int total = 0;\n"
            "    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n"
            "            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y % 2 )\n                {\n"
            + body +
            "                }\n            }\n        }\n    }\n"
            + tail + "    return total;\n}\n")


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


def tangled():
    deep = deep_block(25, 28)
    seq = "".join(f"    total = total + {k};\n" for k in range(60))
    return ("int tangled( const std::vector<int>& xs )\n{\n    int total = 0;\n    bool found = false;\n"
            "    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n"
            "            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y % 2 )\n                {\n"
            "                    while( total < y )\n                    {\n"
            "                        if( total == 7 )\n                        {\n"
            "                            found = true;\n" + deep +
            "                        }\n                        total += 1;\n"
            "                    }\n                }\n            }\n        }\n    }\n"
            + seq + "    if( found )\n    {\n        total *= 2;\n    }\n    return total;\n}\n")


def sequential():
    return ("int sequential( int x )\n{\n    int total = x;\n"
            + "".join(f"    total = total * 7 + {k};\n" for k in range(150)) + "    return total;\n}\n")


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


def main():
    stage, d = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(d, "src"), exist_ok=True)
    hdr = "#include <vector>\n"
    extra = {"v1": 0, "c2": 3, "wt": 6}[stage]
    write(d, "creep.cpp", hdr + creep(extra))
    write(d, "shrink.cpp", hdr + shrink(stage != "wt"))
    write(d, "simplify.cpp", simplify(20 if stage != "wt" else 10))
    if stage == "wt":
        write(d, "tangled.cpp", hdr + tangled())
        write(d, "sequential.cpp", sequential())
        write(d, "orchestrator.cpp", orchestrator())
        write(d, "dispatcher.cpp", dispatcher())
        write(d, "shorthelper.cpp", hdr + shorthelper())
        write(d, "steerfar.cpp", hdr + steer("steerfar", 12))
        write(d, "steernear.cpp", hdr + steer("steernear", 0))


if __name__ == "__main__":
    main()
