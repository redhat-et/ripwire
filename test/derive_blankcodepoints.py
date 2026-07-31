#!/usr/bin/env python3
"""Re-derive src/blanktext.h's kBlankRanges table — the code points that CANNOT carry a definition.

WHY THIS SCRIPT EXISTS (capture-audit-4, finding F2). The first version of hasVisibleContent() carried a
hand-picked "closed, sorted 23-entry table" of invisible code points. It was not closed: an adversarial
verifier found 19 further payload shapes that carry no visible column, DELETE the definition on disk and
report {"applied":...} — most damningly U+200E/U+200F (the table listed their block siblings 200B/200C/200D
and 2060) and every C1 control, because the ASCII group stopped at 0x7F. A hand-picked list is exactly what
failed, so the table is now DERIVED from Unicode properties, and this script is how the next round re-derives
it instead of trusting the C++ literal.

THE RULE (see THE RULING at the top of src/blanktext.h, and the ITEM A block in src/mcp.h it grew out of). A payload carries a definition iff it
contains at least one code point OUTSIDE the union of:

  1. Cc                             — every C0 and C1 control (U+0000-001F, U+007F-009F).
  2. Zs + Zl + Zp + White_Space     — every space separator, the line/paragraph separators.
  3. Cf                             — every format character (ALL of it; see the PCM note below).
  4. Default_Ignorable_Code_Point   — Other_Default_Ignorable_Code_Point + Variation_Selector, which is what
                                      DI adds on top of Cf: the CGJ, the Hangul fillers, the Khmer inherent
                                      vowels, the Mongolian/standard variation selectors, and the reserved
                                      ranges Unicode has pre-committed to being default-ignorable.
  5. NAMED BLANKS                   — code points that are neither invisible-by-property nor whitespace but
                                      whose glyph is empty: U+2800 BRAILLE PATTERN BLANK.

Invalid UTF-8 and unassigned (Cn) code points count as CONTENT — the conservative direction, since the cost
of over-refusing is a rejected write and the cost of under-refusing is deleted code. The ODI reserved ranges
are the one Cn exception and they are in on PROPERTY grounds, not on "unassigned" grounds: Unicode guarantees
those specific reserved points will be default-ignorable if they are ever assigned.

ON PCM (Prepended_Concatenation_Mark: U+0600-0605, 06DD, 070F, 0890, 0891, 08E2, 110BD, 110CD). The
DerivedCoreProperties definition of Default_Ignorable SUBTRACTS these ("exceptional format characters that
should be visible"). We keep them, i.e. we take ALL of Cf rather than DI-minus-PCM, for the reason F2 exists:
carving eight code points back out of a Unicode category re-creates the hand-picked seam that failed, and a
payload consisting only of U+0600 is no more "the complete, well-formed replacement definition" than a payload
of spaces. Every real Arabic/Kaithi text these marks prefix contains letters, which are content.

USAGE
  python3 test/derive_blankcodepoints.py              # print the C++ table + the audit report
  python3 test/derive_blankcodepoints.py --check      # compare against src/blanktext.h and exit 1 on drift
"""

import os
import re
import sys
import unicodedata

MAX_CODE_POINT = 0x10FFFF

# ── Unicode data this script cannot read out of `unicodedata` ──────────────────────────────────────────────
#
# Python's unicodedata exposes general CATEGORIES but no derived/binary properties, so the two property lists
# below are transcribed from the Unicode Character Database of the version unicodedata reports (printed in the
# report header, and asserted against the C++ header's citation). Each entry carries its UCD file so a future
# re-derivation can check it: both are small, stable lists that have not changed since Unicode 14.

# PropList.txt — Other_Default_Ignorable_Code_Point
OTHER_DEFAULT_IGNORABLE = [
    (0x034F, 0x034F),      # COMBINING GRAPHEME JOINER
    (0x115F, 0x1160),      # HANGUL CHOSEONG FILLER .. HANGUL JUNGSEONG FILLER
    (0x17B4, 0x17B5),      # KHMER VOWEL INHERENT AQ .. AA
    (0x2065, 0x2065),      # <reserved-2065>
    (0x3164, 0x3164),      # HANGUL FILLER
    (0xFFA0, 0xFFA0),      # HALFWIDTH HANGUL FILLER
    (0xFFF0, 0xFFF8),      # <reserved-FFF0> .. <reserved-FFF8>
    (0xE0000, 0xE0000),    # <reserved-E0000>
    (0xE0002, 0xE001F),    # <reserved-E0002> .. <reserved-E001F>
    (0xE0080, 0xE00FF),    # <reserved-E0080> .. <reserved-E00FF>
    (0xE01F0, 0xE0FFF),    # <reserved-E01F0> .. <reserved-E0FFF>
]

# PropList.txt — Variation_Selector
VARIATION_SELECTOR = [
    (0x180B, 0x180D),      # MONGOLIAN FREE VARIATION SELECTOR ONE .. THREE
    (0x180F, 0x180F),      # MONGOLIAN FREE VARIATION SELECTOR FOUR
    (0xFE00, 0xFE0F),      # VARIATION SELECTOR-1 .. -16
    (0xE0100, 0xE01EF),    # VARIATION SELECTOR-17 .. -256
]

# PropList.txt — White_Space (kept so the script can PROVE it adds nothing beyond Cc/Zs/Zl/Zp rather than
# assuming it: if a future Unicode version adds a White_Space code point outside those categories, the
# assertion below fails loudly instead of the table silently missing it).
WHITE_SPACE = [
    (0x0009, 0x000D), (0x0020, 0x0020), (0x0085, 0x0085), (0x00A0, 0x00A0), (0x1680, 0x1680),
    (0x2000, 0x200A), (0x2028, 0x2029), (0x202F, 0x202F), (0x205F, 0x205F), (0x3000, 0x3000),
]

# Code points whose GLYPH is empty although no Unicode property says so. Each needs a stated reason; the bar
# is "a conforming renderer draws nothing", not "my terminal drew nothing".
NAMED_BLANKS = [
    (0x2800, 0x2800, "BRAILLE PATTERN BLANK — the all-dots-off cell; So, renders as an empty cell by design"),
]

# Deliberately NOT included, recorded so the next round does not re-litigate them:
#   U+0301 and the rest of Mn — a lone combining mark renders as a visible mark on a dotted circle, and Mn is
#     tens of thousands of code points of real text. The Mn members that ARE here (034F, 17B4-17B5, 180B-180D,
#     180F) are here on Default_Ignorable grounds, by property, not by hand.
#   U+FFFC OBJECT REPLACEMENT CHARACTER — renders as a visible placeholder box, not as nothing.
#   U+1D159 MUSICAL SYMBOL NULL NOTEHEAD and friends — "renders as nothing" is font-dependent for these; the
#     bar above is not met, and a payload of them is not a plausible unset-argument bug.


def expand(ranges):
    out = set()
    for lo, hi in ranges:
        out.update(range(lo, hi + 1))
    return out


def by_category(wanted):
    """Every code point whose unicodedata general category is in `wanted`."""
    return {cp for cp in range(MAX_CODE_POINT + 1) if unicodedata.category(chr(cp)) in wanted}


def merge(points):
    """A sorted set of code points -> canonical merged inclusive ranges."""
    out = []
    for cp in sorted(points):
        if out and cp == out[-1][1] + 1:
            out[-1][1] = cp
        else:
            out.append([cp, cp])
    return [(lo, hi) for lo, hi in out]


def cpp_table(ranges):
    lines = []
    row = []
    for lo, hi in ranges:
        row.append("{ 0x%04X, 0x%04X }," % (lo, hi))
        if len(row) == 4:
            lines.append("        " + " ".join(row))
            row = []
    if row:
        lines.append("        " + " ".join(row))
    return "\n".join(lines)


def parse_header_table(path):
    """The kBlankRanges rows as they stand in src/blanktext.h (read as bytes: the file may hold odd bytes)."""
    src = open(path, "rb").read().decode("utf-8", "replace")
    start = src.find("kBlankRanges[]")
    if start < 0:
        return None, None
    end = src.find("};", start)
    body = src[start:end]
    rows = [(int(a, 16), int(b, 16)) for a, b in re.findall(r"\{\s*0x([0-9A-Fa-f]+)\s*,\s*0x([0-9A-Fa-f]+)\s*\}", body)]
    version = None
    head = src[max(0, start - 4000):start]
    m = re.findall(r"Unicode (\d+\.\d+\.\d+)", head)
    if m:
        version = m[-1]
    return rows, version


def main():
    cc = by_category({"Cc"})
    zs = by_category({"Zs", "Zl", "Zp"})
    cf = by_category({"Cf"})
    ws = expand(WHITE_SPACE)
    odi = expand(OTHER_DEFAULT_IGNORABLE)
    vs = expand(VARIATION_SELECTOR)
    named = {cp for lo, hi, _ in NAMED_BLANKS for cp in range(lo, hi + 1)}

    # White_Space must be a subset of Cc + Z*: this is what lets the table state "Zs/Zl/Zp + White_Space" as
    # one group instead of carrying a fourth source no reader can check.
    stray_ws = sorted(ws - cc - zs)
    assert not stray_ws, "White_Space members outside Cc/Zs/Zl/Zp: %s" % [hex(c) for c in stray_ws]

    blank = cc | zs | cf | ws | odi | vs | named
    ranges = merge(blank)

    print("# derived from Unicode %s (python unicodedata %s, python %s)"
          % (unicodedata.unidata_version, unicodedata.unidata_version, sys.version.split()[0]))
    print("# code points: %d   ranges: %d" % (len(blank), len(ranges)))
    print("#   Cc                          %5d" % len(cc))
    print("#   Zs+Zl+Zp                    %5d" % len(zs))
    print("#   White_Space (adds nothing)  %5d  (subset of the two above, asserted)" % len(ws))
    print("#   Cf                          %5d" % len(cf))
    print("#   Other_Default_Ignorable     %5d" % len(odi))
    print("#   Variation_Selector          %5d" % len(vs))
    print("#   named blanks                %5d" % len(named))
    print()
    print(cpp_table(ranges))
    print()

    # The F2 witnesses: every shape the verifier proved deleted a definition must now be in the set, and the
    # controls must stay out. This list is the finding, transcribed — it is the script's own red-first proof.
    witnesses = [0x200E, 0x200F, 0x00AD, 0x180E, 0x0085, 0x009F, 0x2800, 0x3164, 0x115F, 0xFFA0,
                 0xFE0F, 0x202E, 0x2066, 0x061C, 0x17B4, 0xFFF9, 0xE0020, 0x00A0, 0xFEFF, 0x20, 0x00]
    missing = [hex(c) for c in witnesses if c not in blank]
    assert not missing, "F2 witnesses NOT covered: %s" % missing
    content = [0x41, 0x7B, 0x301, 0x600, 0xFFFC, 0x4E00, 0x1F600, 0x10FFFF]
    wrong = [hex(c) for c in content if c in blank and c != 0x600]
    assert not wrong, "these must stay CONTENT: %s" % wrong
    print("# %d F2 witnesses covered; %d content controls stay content (U+0600 is Cf, see the PCM note)"
          % (len(witnesses), len(content) - 1))

    if "--check" in sys.argv:
        # EXIT CODES, so a gate can tell real drift from an environment difference and never fail open:
        #   0 = the header's table IS this derivation (whatever Unicode version produced either)
        #   1 = the versions MATCH and the tables differ  → genuine drift, somebody hand-edited a row
        #   2 = the versions DIFFER and the tables differ → this python's UCD is not the header's; report it,
        #       do not fail the build on it, and do not pretend the table was checked
        header = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "blanktext.h")
        rows, version = parse_header_table(header)
        if rows is None:
            print("CHECK FAIL: no kBlankRanges table found in %s" % header)
            return 1
        if rows == ranges:
            print("CHECK OK: src/blanktext.h kBlankRanges == derivation (%d ranges, Unicode %s)"
                  % (len(rows), unicodedata.unidata_version))
            return 0
        print("CHECK DRIFT: header table has %d rows, derivation has %d" % (len(rows), len(ranges)))
        for row in sorted(set(ranges) - set(rows)):
            print("  derivation only: { 0x%04X, 0x%04X }" % row)
        for row in sorted(set(rows) - set(ranges)):
            print("  header only:     { 0x%04X, 0x%04X }" % row)
        if version != unicodedata.unidata_version:
            print("CHECK NOTE: header cites Unicode %s, this python has %s — the diff above is very likely the"
                  " UCD version, not a hand edit. Re-derive on the cited version before changing the header."
                  % (version, unicodedata.unidata_version))
            return 2
        print("CHECK FAIL: same Unicode version (%s), different table — a row was hand-edited"
              % unicodedata.unidata_version)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
