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

if [ "$fail" -ne 0 ]; then
    echo "docsunitscheck: FAIL"
    exit 1
fi
echo "docsunitscheck: PASS"
