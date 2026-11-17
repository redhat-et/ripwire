#!/usr/bin/env bash
# docsunitscheck.sh — DOCS-UNITS (D3 section-unit ranking, D5 HTML section tree, D4 Sphinx .txt as reST).
#
# What the lane promises, and the arm that pins each promise (every negative arm has a positive twin, and every
# arm reads an answer whose exit code was checked first, so a crash or an empty answer is a FAIL, never a pass):
#   A  UNITS     --recall ranks document UNITS: a preamble with the only occurrence of a word is served AS A UNIT
#                (section-granular, its own lines), not by falling back to the whole document; a heading's own prose
#                is a unit (a parent whose prose lacks the word is not served beside its child).
#   B  NO CODE   the unit corpus is the documents' units: adding a CODE file that repeats the query word leaves the
#                doc ranking's relevance byte-identical (the code lens's statistics no longer reach --recall).
#   C  CHROME    an HTML page's nav / sidebar / footer / search text never reaches the index; its body text does.
#   D  REGION    with a <main>, text outside it (a banner) is not page text; a page with no region keeps its body.
#   E  UNITS (HTML)  headings and <section id> are units, served with lines= naming the FILE's own lines; on a page
#                with section ids an h4 inside a member stays inside it.
#   F  MIRRORS   a directory whose documents mirror the level above (a version or language copy) is left out of the
#                ranking and DISCLOSED (mirror_skipped=, mirror_dirs=); a directory that only half-mirrors is kept.
#   G  SPHINX    a `.txt` under a Sphinx conf.py whose source_suffix names '.txt' is ranked as reST sections; a
#                `.txt` elsewhere is not indexed.
#   H  RECALL ONLY  an HTML page's section units are --recall's alone (model.h kRankFlagRecallOnly): a heading named like a code
#                symbol leaves --for, --callers and --defs on that name byte-identical to the same page with the heading
#                written as a paragraph (no unit), so the doc heading cannot displace or hedge the code definition; --recall
#                still serves the heading as a unit.
#   J  CR-572    one fixture per HTML shape the CodeRabbit round on #572 fixed: attribute values after a newline, a tag-like
#                attribute value, a <main> in a <template> or hidden, an upper-case </SCRIPT>, an omitted </head>, a
#                <section id="search">, nested section ids at one byte, a decoded &#10;, an h3 outside every section id, a blank
#                page, --expand of a unit, the map's rows, and the recall term cap's disclosure.
#   I  DOC BODY  --for's <doc_body> (FOR-DOC-BODY) picks an HTML page's sections with --recall's unit scores (recallLensScores is
#                recallUnitScores): the section it serves first is the unit --recall picks, not the page's head as a whole doc.
# Usage: test/docsunitscheck.sh [BIN]   (RIPWIRE_BIN works too)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
arm(){ label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }
echo "docsunitscheck: BIN=$BIN"

# recall DIR QUERY OUT [ARG…] — run --recall with the repo as root and cwd; FAIL (and an empty OUT) on a non-zero exit or an
# answer without the recall header, so no arm below can pass on a crash or on silence.
recall(){
    local dir="$1" q="$2" out="$3" rc
    shift 3
    ( cd "$dir" || exit 97; "$BIN" "$dir" --no-cache --recall="$q" "$@" ) >"$out" 2>"$out.err"; rc=$?
    if [ "$rc" -ne 0 ] || ! head -1 "$out" | grep -q '^ripwire recall — '; then
        no "recall '$q' in ${dir#"$TMP"/}: rc=$rc, header missing — the arms reading it cannot pass"; : >"$out"; return 1
    fi
    return 0
}
has(){ grep -qF -- "$2" "$1"; }
hasnt(){ [ -s "$1" ] && ! grep -qF -- "$2" "$1"; }   # absence counts only in a real answer
sep_of(){ grep -F -- "━━ $2 " "$1" | head -1; }      # the separator line of one served file

# ── A: units (markdown) ───────────────────────────────────────────────────────────────────────────────────────
A="$TMP/a"; mkdir -p "$A/docs"
{
    echo "This guide covers the zqpreambleword handshake in enough words to be real prose for a reader here."
    echo "It is the introduction, before any heading, and it is the only place that word occurs."
    echo
    for n in 1 2 3 4 5 6; do printf '## Topic %s\n\nFiller prose about unrelated matters number %s.\n\n' "$n" "$n"; done
} >"$A/docs/guide.md"
cat >"$A/docs/nest.md" <<'X'
# Parent heading

Parent prose with nothing special in it at all.

## Child heading

Child prose holds zqchildword and nothing else of note.
X
if recall "$A" "zqpreambleword handshake" "$TMP/a1"; then
    s="$( sep_of "$TMP/a1" docs/guide.md )"
    arm "A1 a preamble holding the word is served as a UNIT (section-granular, lines=\"1-3\": it tiles up to the first heading)" grep -qF 'lines="1-3"' <<<"$s"
    arm "A1 twin: the guide is the file served" test -n "$s"
fi
if recall "$A" "zqchildword" "$TMP/a2"; then
    s="$( sep_of "$TMP/a2" docs/nest.md )"
    arm "A2 a child heading's own prose is a unit (lines=\"5-7\")" grep -qF 'lines="5-7"' <<<"$s"
    arm "A2 its parent, whose own prose lacks the word, is not served beside it" hasnt "$TMP/a2" "Parent prose with nothing"
fi

# ── B: code statistics do not reach the doc ranking ───────────────────────────────────────────────────────────
B="$TMP/b"; mkdir -p "$B/docs" "$B/src"
printf '# Notes\n\nThe zqcodeterm option tunes the cache.\n\n## Other\n\nUnrelated words here.\n' >"$B/docs/notes.md"
if recall "$B" "zqcodeterm cache" "$TMP/b1"; then
    rel1="$( sep_of "$TMP/b1" docs/notes.md )"
    for n in 1 2 3 4 5 6 7 8; do printf 'int zqcodeterm%s(int cache) { return cache + zqcodeterm_base; }\n' "$n"; done >"$B/src/code.c"
    printf 'void zqcodeterm(void) { /* zqcodeterm cache zqcodeterm cache */ }\n' >>"$B/src/code.c"
    if recall "$B" "zqcodeterm cache" "$TMP/b2"; then
        rel2="$( sep_of "$TMP/b2" docs/notes.md )"
        arm "B1 the doc's relevance is unchanged by a code file repeating the query words" test -n "$rel1" -a "$rel1" = "$rel2"
        arm "B1 twin: the doc is still served" test -n "$rel2"
        arm "B2 --recall never serves the code file" hasnt "$TMP/b2" "src/code.c"
    fi
fi

# ── C, D, E: HTML ─────────────────────────────────────────────────────────────────────────────────────────────
H="$TMP/h"; mkdir -p "$H/site"
cat >"$H/site/page.html" <<'X'
<!doctype html>
<html lang="en" class="sidebar-visible">
<head><title>Page title</title><style>.x{}</style></head>
<body>
<nav class="topbar">zqnavword home</nav>
<div class="announce">zqbannerword shown above the content</div>
<main>
<div class="md-sidebar"><ul><li>zqsidebarword link</li></ul></div>
<h1 id="intro">Introduction</h1>
<p>Intro prose with zqintroword in it.</p>
<h2 id="setup">Setup steps</h2>
<p>Run <code><span>re</span><span>.</span><span>compile</span></code> before zqsetupword.</p>
<p>A second line of setup prose.</p>
<div role="search">zqsearchword box</div>
</main>
<footer>zqfooterword copyright</footer>
</body>
</html>
X
cat >"$H/site/plain.html" <<'X'
<html><body>
<header>zqplainheaderword site title</header>
<div class="announce">zqplainbodyword is page text when there is no region</div>
<h2>Plain heading</h2>
<p>More plain text.</p>
</body></html>
X
cat >"$H/site/api.html" <<'X'
<html><body><main>
<section id="Dog">
<h2>class Dog</h2>
<p>A dog.</p>
</section>
<section id="Dog.bark">
<div class="signature">def bark(times)</div>
<p>Barks zqbarkword times.</p>
<h4>Arguments</h4>
<p>times: how many, zqbarkargword.</p>
</section>
</main></body></html>
X
for w in zqnavword zqsidebarword zqfooterword zqsearchword zqbannerword zqplainheaderword; do
    if recall "$H" "$w" "$TMP/c_$w"; then
        arm "C/D chrome or out-of-region word '$w' is not page text (0 relevant)" has "$TMP/c_$w" "— 0 relevant of"
    fi
done
if recall "$H" "zqsetupword" "$TMP/c2"; then
    s="$( sep_of "$TMP/c2" site/page.html )"
    arm "C twin: body text is page text, served as the h2 unit with the FILE's lines (lines=\"11-13\")" grep -qF 'lines="11-13"' <<<"$s"
    arm "C inline tags join their text (re.compile)" has "$TMP/c2" "re.compile"
    arm "C the search box inside the region is still chrome" hasnt "$TMP/c2" "zqsearchword"
fi
if recall "$H" "zqplainbodyword" "$TMP/d2"; then
    arm "D twin: a page with no region keeps its body text" has "$TMP/d2" "site/plain.html"
fi
if recall "$H" "zqbarkargword" "$TMP/e1"; then
    s="$( sep_of "$TMP/e1" site/api.html )"
    arm "E a <section id> is a unit, and its h4 stays inside it (lines=\"6-10\")" grep -qF 'lines="6-10"' <<<"$s"
    arm "E the member's signature is served with it" has "$TMP/e1" "def bark(times)"
fi
if recall "$H" "zqintroword" "$TMP/e2"; then
    s="$( sep_of "$TMP/e2" site/page.html )"
    arm "E twin: an h1 is a unit of its own (lines=\"9-10\")" grep -qF 'lines="9-10"' <<<"$s"
fi

# ── F: mirror trees ───────────────────────────────────────────────────────────────────────────────────────────
M="$TMP/m"; mkdir -p "$M/book/v1" "$M/book/fr" "$M/book/half"
for p in alpha beta gamma delta; do
    printf '# %s\n\nThe %s page explains zqmirrorword in its own words.\n' "$p" "$p" >"$M/book/$p.md"
    cp "$M/book/$p.md" "$M/book/v1/$p.md"
    printf '# %s\n\nLa page %s explique zqmirrorword.\n' "$p" "$p" >"$M/book/fr/$p.md"
done
for p in alpha beta solo1 solo2; do printf '# %s\n\nHalf tree %s, zqmirrorword too.\n' "$p" "$p" >"$M/book/half/$p.md"; done
if recall "$M" "zqmirrorword" "$TMP/f1" --top-k=20; then   # room for every copy: a skip must not hide behind the cut
    arm "F1 the version copy is not served" hasnt "$TMP/f1" "book/v1/"
    arm "F1 the language copy is not served" hasnt "$TMP/f1" "book/fr/"
    arm "F1 the skip is disclosed: mirror_skipped=8 mirror_dirs=\"book/fr,book/v1\"" has "$TMP/f1" 'mirror_skipped=8 mirror_dirs="book/fr,book/v1"'
    arm "F1 twin: the parent pages are served" has "$TMP/f1" "━━ book/alpha.md "
    arm "F2 a half-mirroring directory is kept" has "$TMP/f1" "book/half/"
fi
if recall "$A" "zqpreambleword" "$TMP/f3"; then
    arm "F3 no mirror, no attribute" hasnt "$TMP/f3" "mirror_skipped="
fi

# ── G: Sphinx .txt as reST ────────────────────────────────────────────────────────────────────────────────────
G="$TMP/g"; mkdir -p "$G/docs" "$G/notes"
printf 'project = "x"\nextensions = []\nsource_suffix = ".txt"\n' >"$G/docs/conf.py"
printf 'Topic Title\n===========\n\nIntro prose.\n\nDeep Section\n------------\n\nThe zqrestword lives here.\n' >"$G/docs/topic.txt"
printf 'Plain notes with zqplaintxtword.\n' >"$G/notes/readme.txt"
if recall "$G" "zqrestword" "$TMP/g1"; then
    s="$( sep_of "$TMP/g1" docs/topic.txt )"
    arm "G1 a Sphinx-declared .txt is ranked as reST sections (lines=\"6-9\")" grep -qF 'lines="6-9"' <<<"$s"
fi
if recall "$G" "zqplaintxtword" "$TMP/g2"; then
    arm "G2 twin: a .txt outside a Sphinx tree is not indexed" has "$TMP/g2" "— 0 relevant of"
fi

# ── H: HTML units are --recall's alone ────────────────────────────────────────────────────────────────────────
# Two trees: the same page with its headings as <h1>/<h2> (units) or as same-length unknown tags <x1>/<x2> (no unit). The pages'
# whole-text readings are identical, so every answer but --recall's must be too (root=, at= and the tag letter in a served page body
# masked: the raw page bytes differ in that letter alone).
mkh(){
    mkdir -p "$1/src" "$1/site"
    printf 'def parseWidgetConfig(path):\n    """Read the widget config file."""\n    with open(path) as f:\n        return loadSettings(f.read())\n\n\ndef loadSettings(text):\n    return dict(l.split("=", 1) for l in text.splitlines() if "=" in l)\n\n\ndef renderWidget(settings):\n    return "<div>" + settings.get("title", "") + "</div>"\n' >"$1/src/widget.py"
    printf '<html><head><title>Widget guide</title></head>\n<body>\n<nav><a href="index.html">Home</a></nav>\n<main>\n<%s>Widget guide</%s>\n<p>How the widget reads its settings.</p>\n<%s>parseWidgetConfig</%s>\n<p>The parseWidgetConfig step reads the config file, parses each line, and returns the widget settings.</p>\n<%s>renderWidget</%s>\n<p>Rendering turns the settings into markup.</p>\n</main>\n</body></html>\n' "$2" "$2" "$3" "$3" "$3" "$3" >"$1/site/guide.html"
}
mkh "$TMP/hu" h1 h2; mkh "$TMP/hp" x1 x2
# verb TREE OUT ARG — run one answer; FAIL and an empty OUT on a non-zero exit or an empty answer
verb(){
    local dir="$1" out="$2" rc
    shift 2
    ( cd "$dir" || exit 97; "$BIN" "$dir" --no-cache "$@" ) | sed -E -e "s#$dir#ROOT#g" -e 's/ at="[^"]*"//g' -e 's#(<|&lt;)(/?)[hx]([12])(>|&gt;)#\1\2T\3\4#g' >"$out"; rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then no "$* in ${dir#"$TMP"/}: rc=$rc or empty — the arms reading it cannot pass"; : >"$out"; return 1; fi
    return 0
}
for v in "--for=parseWidgetConfig" "--callers=parseWidgetConfig" "--defs=parseWidgetConfig" "--for=how is the widget config parsed into settings"; do
    k="$( printf '%s' "$v" | tr -c 'a-zA-Z0-9' '_' )"
    if verb "$TMP/hu" "$TMP/h_u_$k" "$v" && verb "$TMP/hp" "$TMP/h_p_$k" "$v"; then
        arm "H $v: a heading unit leaves the answer byte-identical to the heading-free page" cmp -s "$TMP/h_u_$k" "$TMP/h_p_$k"
    fi
done
if [ -s "$TMP/h_u___for_parseWidgetConfig" ]; then
    # the FIRST row inside <sigs>, not any later one: two trees that agree on a wrong order would still pass the cmp above
    arm "H twin: --for serves the code definition first (the first <sigs> row)" grep -qE '<sigs><d [^>]*n="parseWidgetConfig" p="src/widget.py"' "$TMP/h_u___for_parseWidgetConfig"
fi
if recall "$TMP/hu" "parseWidgetConfig" "$TMP/h_r"; then
    s="$( sep_of "$TMP/h_r" site/guide.html )"
    arm "H twin: --recall still serves the heading as a unit (section-granular, lines 7-8)" grep -qE 'section-granular.*lines="[^"]*7-8' <<<"$s"
fi

# ── I: --for's doc_body serves --recall's HTML units ──────────────────────────────────────────────────────────
# Two pages (two doc files in the tail fire the block on a prose task); only guide.html's "Cache eviction" section holds the task's
# words "evicts stale entries" (the other units share fewer of its words), so it is --recall's top unit there and doc_body's first section on
# that page must be the same heading and lines; under lexicalScores the units score 0 and the page's head is served as t="doc".
I="$TMP/i"; mkdir -p "$I/site" "$I/src"
printf 'def loadSettings(text):\n    return dict(l.split("=", 1) for l in text.splitlines() if "=" in l)\n' >"$I/src/widget.py"
printf '<html><head><title>Widget guide</title></head>\n<body>\n<nav><a href="index.html">Home</a></nav>\n<main>\n<h1>Widget guide</h1>\n<p>An overview of the widget pages.</p>\n<h2>Install</h2>\n<p>Copy the widget folder into the plugins directory and restart.</p>\n<h2>Cache eviction</h2>\n<p>The cache evicts stale entries when its timer fires, oldest entries first.</p>\n<h2>Colors</h2>\n<p>Pick a palette for the widget.</p>\n</main>\n</body></html>\n' >"$I/site/guide.html"
printf '<html><head><title>Widget tuning</title></head>\n<body>\n<main>\n<h1>Widget tuning</h1>\n<p>Tune the widget cache size and its timer.</p>\n<h2>Limits</h2>\n<p>A larger cache keeps more entries.</p>\n</main>\n</body></html>\n' >"$I/site/tuning.html"
iq="how does the cache evict stale entries"
if verb "$I" "$TMP/i_for" "--for=$iq" && verb "$I" "$TMP/i_json" "--for=$iq" --json; then
    arm "I --for serves a doc_body block on the prose task (positive twin of every arm below)" grep -q '<doc_body ' "$TMP/i_for"
    ib="$( grep -oE '<b t="[a-z]+" p="site/guide.html"[^>]*>' "$TMP/i_for" | head -1 )"
    arm "I doc_body's first guide.html passage is --recall's unit: t=\"section\" n=\"Cache eviction\" l=9 e=10 rank=1 (got: ${ib:-none})" \
        grep -qE 't="section" p="site/guide.html" l="9" e="10" n="Cache eviction" rank="1"' <<<"$ib"
    arm "I --json: the doc_body key serves the same heading" grep -qE '"doc_body".*"Cache eviction"' "$TMP/i_json"
fi
if recall "$I" "$iq" "$TMP/i_r"; then
    s="$( sep_of "$TMP/i_r" site/guide.html )"
    arm "I twin: --recall serves guide.html as units, the Cache eviction one among them (section-granular, lines 9-10)" grep -qE 'section-granular.*lines="[^"]*9-10' <<<"$s"
fi

# ── J: the CodeRabbit round on #572 — one fixture per fixed shape, each a negative arm with a positive twin ─────
served(){ test -n "$( sep_of "$1" "$2" )"; }
unserved(){ [ -s "$1" ] && test -z "$( sep_of "$1" "$2" )"; }   # absence counts only in a real answer
# jpage CASE — the page body on stdin becomes $TMP/j/CASE/site/p.html
jpage(){ mkdir -p "$TMP/j/$1/site"; cat >"$TMP/j/$1/site/p.html"; }
# jpair CASE OUTWORD INWORD LABEL — OUTWORD's text must not reach --recall, INWORD's (the twin) must
jpair(){
    if recall "$TMP/j/$1" "$2" "$TMP/j_$1_out"; then arm "J $4: '$2' is not page text" unserved "$TMP/j_$1_out" site/p.html; fi
    if recall "$TMP/j/$1" "$3" "$TMP/j_$1_in"; then arm "J $4 twin: '$3' is" served "$TMP/j_$1_in" site/p.html; fi
}
printf '<html><body><main>\n<div class=\n"sidebar">zqjattrside chrome words</div>\n<p>zqjattrbody prose of the page</p>\n</main></body></html>\n' | jpage attr
jpair attr zqjattrside zqjattrbody "a class value on the line after its = is read (sidebar chrome)"
printf '<html><body>\n<div title="see <main> below">x</div>\n<article><p>zqjtagart article prose</p></article>\n<p>zqjtagbanner banner text</p>\n</body></html>\n' | jpage tagattr
jpair tagattr zqjtagbanner zqjtagart "a <main> inside an attribute value is no region (the article is)"
printf '<html><body>\n<template><main><p>template text</p></main></template>\n<article><p>zqjtplart article prose</p></article>\n<p>zqjtplbanner banner text</p>\n</body></html>\n' | jpage tpl
jpair tpl zqjtplbanner zqjtplart "a <main> only inside a <template> gives way to the visible article"
printf '<html><head><SCRIPT>var a = 1;</SCRIPT></head><body>\n<main><p>zqjcasemain main prose</p></main>\n<p>zqjcasebanner banner text</p>\n</body></html>\n' | jpage case
jpair case zqjcasebanner zqjcasemain "an upper-case </SCRIPT> ends the script, so the <main> after it is the region"
printf '<html><body>\n<main hidden><p>zqjhidmain hidden text</p></main>\n<article><p>zqjhidart article prose</p></article>\n</body></html>\n' | jpage hidden
jpair hidden zqjhidmain zqjhidart "a hidden <main> is no page text, and the visible article is"
printf '<html><head><title>T</title>\n<body>\n<main><p>zqjnohead body prose without a closing head tag</p></main>\n</body></html>\n' | jpage nohead
if recall "$TMP/j/nohead" "zqjnohead" "$TMP/j_nohead"; then arm "J a <body> closes a head whose </head> is omitted" served "$TMP/j_nohead" site/p.html; fi
printf '<html><body><main>\n<section id="search">\n<p>zqjsearchsec member prose</p>\n</section>\n<div id="search"><p>zqjsearchbox box text</p></div>\n</main></body></html>\n' | jpage secid
jpair secid zqjsearchbox zqjsearchsec "a <div id=search> is chrome, a <section id=search> (a member) is not"
printf '<html><body><main>\n<section id="outer"><section id="zqjnestmember">\n<p>member prose here</p>\n</section></section>\n</main></body></html>\n' | jpage nest
if recall "$TMP/j/nest" "zqjnestmember" "$TMP/j_nest"; then arm "J nested section ids opened at one byte are two units: the inner id is scored" served "$TMP/j_nest" site/p.html; fi
printf '<html><body><main>\n<p>zqjentity line one&#10;still line two of the file</p>\n<h2>Later</h2>\n<p>zqjentlater prose</p>\n</main></body></html>\n' | jpage ent
if recall "$TMP/j/ent" "zqjentlater" "$TMP/j_ent"; then
    arm "J a decoded &#10; adds no line: the served unit ends on the file's line 4, not 5" grep -qF 'lines="1-4"' <<<"$( sep_of "$TMP/j_ent" site/p.html )"
fi
{
    printf '<html><body><main>\n<section id="api"><h2>api</h2><p>api member prose</p></section>\n<h3>Chapter one</h3>\n'
    for n in 1 2 3 4 5 6 7 8; do printf '<p>Filler prose about unrelated matters number %s.</p>\n' "$n"; done
    printf '<h3>Chapter two</h3>\n<p>zqjchapter prose of the second chapter</p>\n</main></body></html>\n'
} | jpage chapter
if recall "$TMP/j/chapter" "zqjchapter" "$TMP/j_chapter"; then
    arm "J an h3 outside every section id keeps its boundary: Chapter two is its own unit (lines 12-13)" grep -qF 'lines="12-13"' <<<"$( sep_of "$TMP/j_chapter" site/p.html )"
fi
mkdir -p "$TMP/j/blank/site" && printf '\n' >"$TMP/j/blank/site/zqjblank.html" && printf '<p>zqjblank twin prose</p>\n' >"$TMP/j/blank/site/twin.html"
if recall "$TMP/j/blank" "zqjblank" "$TMP/j_blank"; then
    arm "J a blank HTML page is no document" unserved "$TMP/j_blank" site/zqjblank.html
    arm "J twin: a page holding the word is served" served "$TMP/j_blank" site/twin.html
fi
# the unit's own text through --expand: its offsets index the extracted text, not the page's bytes
if verb "$TMP/hu" "$TMP/j_expand" "--expand=site/guide.html:parseWidgetConfig" --top-k=0; then
    arm "J --expand of an HTML unit serves its extracted text" has "$TMP/j_expand" "The parseWidgetConfig step reads the config file"
    arm "J --expand twin: none of the page's markup" hasnt "$TMP/j_expand" '<nav>'
fi
# the map never prints a recall-only unit, and shown= never exceeds symbols=
if verb "$TMP/hu" "$TMP/j_map" --top-k=1000; then
    st="$( grep -oE 'symbols=[0-9]+ edges=[0-9]+ shown=[0-9]+' "$TMP/j_map" | head -1 )"
    sy="$( sed -E 's/symbols=([0-9]+).*/\1/' <<<"$st" )"; sh="$( sed -E 's/.*shown=([0-9]+)/\1/' <<<"$st" )"
    arm "J map --top-k past the ranked symbols: shown=$sh <= symbols=$sy" test -n "$st" -a "${sh:-1}" -le "${sy:-0}"
    arm "J map twin: the code definition is a row" grep -qE 'n="parseWidgetConfig"[^>]*' "$TMP/j_map"
fi
# a query past the term cap says so; a short one does not
jq="$( for a in a b c d e f g h i j k l m n o p q r s t u v w x y z; do for b in a b c d e f g h i j k l m n o p q r s t u v w x y z; do printf 'zq%s%sx zq%s%sy ' "$a" "$b" "$a" "$b"; done; done )"
if recall "$TMP/hu" "$jq" "$TMP/j_terms"; then arm "J a 1352-term query discloses its cut: terms_capped=1 terms_total=1352" grep -qF 'terms_capped=1 terms_total=1352' <(head -1 "$TMP/j_terms"); fi
if [ -s "$TMP/h_r" ]; then arm "J twin: a short query has no terms_capped" hasnt "$TMP/h_r" 'terms_capped='; fi

if [ "$fail" -ne 0 ]; then
    echo "docsunitscheck: FAIL"
    exit 1
fi
echo "docsunitscheck: PASS"
