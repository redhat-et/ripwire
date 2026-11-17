# legendcoverage.sh — the shared answer to "is this attribute DOCUMENTED?", for every gate that asserts it.
# SOURCED (after the gate defines ok/no), never run. The python twin is test/lib/legendcoverage.py.
#
# WHY THIS EXISTS. ~50 sites across the suite assert legend coverage by grepping the answer's own head
# comment for the attribute name, in several spellings, the commonest being
#
#     grep -o '<!--.*-->' "$DOC" | grep -q 'sites_total='
#
# Two problems with that, and the second is why this file is here.
#
# 1. `<!--.*-->` is GREEDY and ripwire's output is minified onto one line, so on a document with two
#    comments it spans from the first `<!--` to the LAST `-->` — everything between them included. One
#    arm in this suite was made unfirable by exactly that, and a comment in another gate already warns
#    about it. Worse, `--expand` and `--for` answers carry ripwire's own C++ in CDATA, and that source
#    contains comment-shaped text (`<!--" + add + "-->` is a real string in it), so a document-wide scan
#    collects payload as legend.
#
# 2. THE CONTRACT ITSELF IS WRONG. "Defined in THIS ANSWER'S legend" cannot be satisfied by an answer
#    that carries no legend, and ripwire now has a posture that serves none: --legend=dict replaces the
#    prose with a pointer (`dict="ripwire --legend-dict" dictv=`). Under it, 80 of 849 gates fail — not
#    because an attribute became undocumented, but because the definition moved to where the pointer
#    says it is. METHODOLOGY.md §9 principle 3 is explicit that a disclosed hand-off is terminal: the
#    reader is told exactly which call fetches what the answer left out.
#
# So the contract this file implements is: **an emitted attribute must be defined somewhere the reader
# can OBTAIN it** — in the answer's own legend when it carries one, or in `ripwire --legend-dict`, which
# the answer names. That is the same bar test/legenddefaultcheck.sh (D5) holds the prose-free posture to.
#
# WHAT THIS IS NOT. It is not a weakening. An attribute in NEITHER place still fails, and lc_selftest
# proves it: the whole point of a coverage gate is to catch an attribute shipped with no definition
# anywhere, which is a real defect this suite has caught before (an emitted attribute whose dictionary
# row was never registered shipped undocumented and silently).
#
# API
#   lc_init BIN                     read the dictionary once per gate run (it costs a process; cache it)
#   lc_defines DOC ATTR             0 if ATTR is documented for DOC: in DOC's own head comments, else in
#                                   the dictionary. Sets LC_WHERE to "legend" | "dict" | "nowhere".
#   lc_assert LABEL DOC ATTR        lc_defines + the gate's ok/no, with LC_WHERE named in the message
#   lc_head_comments DOC            prints DOC's head comments, one per line, BOUNDED (see below)
#   lc_selftest                     synthetic arms proving each verdict can go red (no binary needed)
#
# THE BOUNDED SCAN. lc_head_comments walks only the two runs where a legend can live: the contiguous
# comment/whitespace run BEFORE the root element's open tag, and the one immediately AFTER it. It stops at
# the first byte that is neither comment nor whitespace. That is exactly what src/legenddict.h's
# headComments() does, and it is CDATA-safe by construction rather than by escaping.

LC_LIB="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LC_DICT=""
LC_WHERE=""
LC_BIN=""

lc_init(){
    LC_BIN="${1:-${RIPWIRE_BIN:-}}"
    LC_DICT=""
    if [ -n "$LC_BIN" ] && [ -x "$LC_BIN" ]; then
        # Both tiers: the full dictionary and the completeness roster. A gate must not care which holds a row.
        LC_DICT="$( "$LC_BIN" --legend-dict 2>/dev/null; "$LC_BIN" --legend-dict=roster 2>/dev/null )"
    fi
    if [ -z "$LC_DICT" ]; then
        # NOT silently degraded to "the legend only". A gate that cannot read the dictionary cannot judge
        # coverage under the prose-free posture, and a coverage verdict from half the sources is a guess.
        printf '  FAIL  legendcoverage: --legend-dict printed nothing from BIN=%s — coverage cannot be judged\n' "${LC_BIN:-<unset>}"
        return 1
    fi
    return 0
}

lc_head_comments(){
    python3 "$LC_LIB/legendcoverage.py" --head-comments "$1"
}

lc_defines(){
    local doc="$1" attr="$2"
    LC_WHERE="nowhere"
    [ -f "$doc" ] || return 1
    if lc_head_comments "$doc" | grep -qF -- "${attr}="; then
        LC_WHERE="legend"; return 0
    fi
    if printf '%s' "$LC_DICT" | grep -qF -- "${attr}="; then
        LC_WHERE="dict"; return 0
    fi
    return 1
}

# Many sites hold the answer in a SHELL VARIABLE rather than a file, so both forms are needed or the
# migration would have to restructure the gates it touches — and a migration that rewrites a gate's
# plumbing is a migration whose diff nobody can review for behaviour change.
lc_defines_text(){
    local t; t="$( mktemp )"
    printf '%s' "$1" >"$t"
    lc_defines "$t" "$2"
    local rc=$?
    rm -f "$t"
    return $rc
}

lc_assert_text(){
    local label="$1" text="$2" attr="$3"
    if lc_defines_text "$text" "$attr"; then
        ok "$label: ${attr}= is defined (in the answer's $LC_WHERE)"
    else
        no "$label: ${attr}= is defined NOWHERE — not in the answer's legend, not in --legend-dict"
    fi
}

lc_assert(){
    local label="$1" doc="$2" attr="$3"
    if lc_defines "$doc" "$attr"; then
        ok "$label: ${attr}= is defined (in the answer's $LC_WHERE)"
    else
        no "$label: ${attr}= is defined NOWHERE — not in the answer's legend, not in --legend-dict"
    fi
}

# Every verdict must be able to go red, or a migrated gate is weaker than the one it replaced and nobody
# can tell. Runs without a binary: the dictionary is stubbed.
lc_selftest(){
    local t; t="$( mktemp -d )"
    local keep="$LC_DICT" rc=0
    # A minified two-comment answer whose CDATA contains comment-shaped text — the case a greedy scan eats.
    # The CDATA carries `cdataonly=` INSIDE a comment-shaped string, and a SECOND head comment follows the
    # first — so a greedy `<!--.*-->` spans from the first `<!--` to the last `-->` and swallows the payload,
    # finding `cdataonly=` in what it calls the legend. An earlier version of this arm planted a bare word
    # with no `=`, which the lookup could never have matched either way: it passed without testing anything.
    printf '%s' '<!-- ripwire callers schema=x: sites_at= the call sites --><callers q="1"><b><![CDATA[s = "<!-- cdataonly=1 -->" + add;]]></b><z zzqq9="1"/></callers><!-- files=1 -->' >"$t/a.xml"
    LC_DICT='legend_only_row= a row only the dictionary holds.'
    lc_defines "$t/a.xml" "sites_at"    && [ "$LC_WHERE" = legend ] || { printf '  FAIL  lc_selftest: an attribute in the answer legend was not found there\n'; rc=1; }
    lc_defines "$t/a.xml" "legend_only_row" && [ "$LC_WHERE" = dict ] || { printf '  FAIL  lc_selftest: a dictionary-only attribute was not found in the dictionary\n'; rc=1; }
    lc_defines "$t/a.xml" "zzqq9"       && { printf '  FAIL  lc_selftest: an attribute defined NOWHERE passed — the verdict cannot go red\n'; rc=1; }
    lc_defines "$t/a.xml" "cdataonly"   && { printf '  FAIL  lc_selftest: payload inside CDATA was read as a legend definition (greedy scan)\n'; rc=1; }
    # And prove the fixture is adversarial: a greedy document-wide scan DOES find it, so the arm above is
    # testing the bound and not the absence of the string.
    grep -o '<!--.*-->' "$t/a.xml" | grep -qF 'cdataonly=' || { printf '  FAIL  lc_selftest: the fixture is not adversarial — a greedy scan would not have found cdataonly= either\n'; rc=1; }
    LC_DICT="$keep"
    rm -rf "$t"
    [ "$rc" = 0 ] && printf '  PASS  lc_selftest: all four verdicts fire correctly (legend hit, dict hit, nowhere, CDATA-safe)\n'
    return $rc
}
