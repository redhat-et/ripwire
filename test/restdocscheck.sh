#!/usr/bin/env bash
# restdocscheck.sh — reST and Sphinx documents as real units (src/ingest_rest.h, docparse.h sphinxConfDeclaresTxt).
#
# Pins: titles in any punctuation with the level from first-seen order; object directives as units named by their target;
# labels, :ref: and :doc: as link edges; which .txt files are documents, decided by the conf.py and not by a name; the near
# misses that are not structure; and a pathological file that discloses instead of hanging. Red on the markdown-grammar base.
#
# Usage: test/restdocscheck.sh [BIN]    (BIN falls back to RIPWIRE_BIN, then build/ripwire)
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
arm_not(){ label="$1"; shift; if "$@"; then no "$label"; else ok "$label"; fi; }
echo "restdocscheck: BIN=$BIN"

FIX="$TMP/fix"; mkdir -p "$FIX/docs/ref/deep" "$FIX/notsphinx" "$FIX/defaultsuffix" "$FIX/commented" "$FIX/listform" "$FIX/src" "$FIX/plain"
cd "$TMP" || exit 2

cat >"$FIX/docs/conf.py" <<'X'
project = "fixture"
extensions = []
source_suffix = {
    ".txt": "restructuredtext",  # the declared format
}
X
cat >"$FIX/docs/titles.txt" <<'X'
#############
Over Top Name
#############

topprose qqtopword

Under One
=========

oneprose qqoneword

Under Two
---------

twoprose qqtwoword

Under Three
~~~~~~~~~~~

threeprose qqthreeword

Under Four
==========

fourprose qqfourword
X
cat >"$FIX/docs/order.txt" <<'X'
Order Outer
~~~~~~~~~~~

outerprose qqouterword

Order Inner
===========

innerprose qqinnerword

Order Sibling
~~~~~~~~~~~~~

siblingprose qqsiblingword
X
cat >"$FIX/docs/ref/options.txt" <<'X'
Options
=======

.. _option-label:

.. option:: -w, --qqwidth=<n>

    widthbody qqwidthword

.. option:: --qqheight

    heightbody qqheightword

.. confval:: qqconf_value

    confbody qqconfword

.. function:: pkg.qqfunc(a, b=1)

    funcbody qqfuncword

.. class:: QqKlass(x)

    klassbody qqklassword

    .. method:: qqmeth(self)

        methbody qqmethword

    .. py:attribute:: qqattr

        attrbody qqattrword

.. c:function:: int qq_cfunc(int x)

    cfuncbody qqcfuncword

.. note::

    .. option:: --qqinnote

        innotebody

.. setting:: QQ_SETTING

``QQ_SETTING``
--------------

settingbody qqsettingword

.. setting:: QQ_ABOVE

Another Name
------------

abovebody qqaboveword

.. setting:: QQ_PLAIN

plainbody qqplainword

Next Section
============

nextprose qqnextword
X
cat >"$FIX/docs/links.txt" <<'X'
Links
=====

See :ref:`the label <option-label>` and :ref:`bare-label` and :ref:`wrapped text
over a line <wrapped-label>`, then :doc:`ref/options`, :doc:`Absolute </ref/deep/page>`
and :ref:`widgetfn` and :ref:`near`, which name no label.

.. _bare-label:

Bare Target
-----------

barebody

.. _Wrapped-Label:

Wrapped Target
--------------

wrappedbody
X
printf 'Deep Page\n=========\n\nUp :doc:`/links` and :doc:`../options`.\n' >"$FIX/docs/ref/deep/page.txt"
cat >"$FIX/docs/near.txt" <<'X'
Near Misses
===========

abcdef
---

shortbody

abcdefgh
-----

longenoughbody

two line paragraph
qqparaline
----------

A literal block follows::

    Fake Literal Title
    ==================

    .. option:: --qqfakeliteral

::

    .. option:: --qqfakebare

.. code-block:: rst

    Fake Code Title
    ===============

    .. option:: --qqfakecode

.. a comment naming a thing

    .. option:: --qqfakecomment

.. |sub| replace:: text

- bullet qqbullet
-----------------

.. option::

.. function:: bad&<name>(x)

    escapebody

Title <With> & Markup
=====================

=====  =====
a      b
=====  =====

closingprose
X
printf 'Req\n---\n' >"$FIX/docs/requirements.txt"
printf 'Word Only\n=========\n\nqqplainrst\n\n.. option:: --qqrstopt\n\n    rstoptbody\n' >"$FIX/plain/page.rst"
printf 'def widgetfn():\n    return 1\n\ndef callit():\n    return widgetfn()\n' >"$FIX/src/widgetfn.py"
printf 'Refused One\n===========\n\nqqnotsphinx\n' >"$FIX/plain/loose.txt"
printf 'def get_urls():\n    return []\n' >"$FIX/notsphinx/conf.py"
printf 'Refused Two\n===========\n\nqqnotconf\n' >"$FIX/notsphinx/a.txt"
printf 'extensions = []\n' >"$FIX/defaultsuffix/conf.py"
printf 'Refused Three\n=============\n\nqqdefaultsuffix\n' >"$FIX/defaultsuffix/a.txt"
printf 'extensions = []\n# source_suffix = ".txt"\nsource_suffix = ".rst"\n' >"$FIX/commented/conf.py"
printf 'Refused Four\n============\n\nqqcommented\n' >"$FIX/commented/a.txt"
printf "source_suffix = ['.rst', '.txt']\n" >"$FIX/listform/conf.py"
printf 'List Form\n=========\n\nqqlistform\n' >"$FIX/listform/a.txt"

run(){ "$BIN" "$FIX" --no-cache "$@" 2>/dev/null </dev/null; }
# has_body NAME WORD: --expand NAME serves a unit named NAME whose body holds WORD
has_body(){
  out="$( run --expand="$1" --top-k=0 )"
  case "$out" in *" n=\"$2\""*) ;; *) return 1;; esac
  case "$out" in *"$3"*) return 0;; esac
  return 1
}
is_unit(){ out="$( run --expand="$1" --top-k=0 )"; case "$out" in *"<b t=\"sec\""*) return 0;; esac; return 1; }
body_lacks(){ out="$( run --expand="$1" --top-k=0 )"; case "$out" in *"$2"*) return 1;; esac; return 0; }
# The caller is the file node here: the one title's span ties it, as a markdown file's single top heading does.
link_from(){ out="$( run --callers="$1" )"; case "$out" in *"p=\"$2:"*"via=\"link\""*) return 0;; esac; return 1; }

echo "A. titles"
arm "A1 overlined title" has_body "Over Top Name" "Over Top Name" qqtopword
arm "A2 a third punctuation" has_body "Under Three" "Under Three" qqthreeword
arm "A3 a same-level title ends the span" body_lacks "Under Three" qqfourword
out="$( run --expand="Under Two" --top-k=0 )"
case "$out" in *qqtwoword*) ok "A4 a title keeps its prose";; *) no "A4 a title keeps its prose";; esac
out="$( run --expand="Order Inner" --top-k=0 )"
case "$out" in *'sibs="Order Outer'*|*'Order Outer'*) ok "A5 level by first-seen order: = sits under ~ here";; *) no "A5 level by first-seen order: = sits under ~ here";; esac
arm "A6 the first-seen style closes the inner one" body_lacks "Order Inner" qqsiblingword

echo "B. directives as units, named by their target, body served"
arm "B1 option named by the long spelling, no =<n>" has_body "--qqwidth" "--qqwidth" qqwidthword
arm "B2 the next option ends the unit" body_lacks "--qqwidth" qqheightword
arm "B3 confval" has_body "qqconf_value" "qqconf_value" qqconfword
arm "B4 function, signature off" has_body "pkg.qqfunc" "pkg.qqfunc" qqfuncword
arm "B5 class holds its method" has_body "QqKlass" "QqKlass" qqmethword
arm "B6 method nested in a class" has_body "qqmeth" "qqmeth" qqmethword
arm "B7 a domain prefix comes off" has_body "qqattr" "qqattr" qqattrword
arm "B8 a C signature names the function" has_body "qq_cfunc" "qq_cfunc" qqcfuncword
arm "B9 an option inside a note" is_unit "--qqinnote"
arm "B10 a body-less setting covers the title below it" has_body "QQ_SETTING" "QQ_SETTING" qqsettingword
out="$( run --expand=QQ_SETTING --top-k=0 )"
arm "B10b a setting above its own title is one unit" [ "$( printf '%s' "$out" | grep -o 'n="QQ_SETTING"' | wc -l | tr -d ' ' )" = 1 ]
arm "B10c a setting above another title covers it" has_body "QQ_ABOVE" "QQ_ABOVE" qqaboveword
arm "B11 a body-less setting with prose runs to the next unit" has_body "QQ_PLAIN" "QQ_PLAIN" qqplainword
arm "B12 and stops at the next title" body_lacks "QQ_PLAIN" qqnextword
arm "B13 a .rst outside any Sphinx root parses the same" has_body "--qqrstopt" "--qqrstopt" rstoptbody
out="$( run --recall=qqheightword )"
case "$out" in *qqheightword*) case "$out" in *qqconfword*) no "B14 recall serves the unit, not the page";; *) ok "B14 recall serves the unit, not the page";; esac;; *) no "B14 recall serves the unit, not the page";; esac

echo "C. links"
arm "C1 :ref: with text, to a label" link_from "_option-label" "docs/links.txt"
arm "C2 bare :ref:" link_from "_bare-label" "docs/links.txt"
arm "C3 a :ref: wrapped over lines, label lowered" link_from "_wrapped-label" "docs/links.txt"
out="$( run --callers=options )"
case "$out" in *'via="link"'*) ok "C4 relative :doc:";; *) no "C4 relative :doc:";; esac
out="$( run --callers=page )"
case "$out" in *'p="docs/links.txt:'*'via="link"'*) ok "C5 :doc:\`/abs\` from the Sphinx root";; *) no "C5 :doc:\`/abs\` from the Sphinx root";; esac
out="$( run --callers=links )"
case "$out" in *'via="link"'*) ok "C6 :doc:\`/abs\` from a deeper file";; *) no "C6 :doc:\`/abs\` from a deeper file";; esac
out="$( run --callers=widgetfn )"
case "$out" in *'via="link"'*) no "C7 a dangling :ref: does not land on a function of that name";; *'callit'*) ok "C7 a dangling :ref: does not land on a function of that name";; *) no "C7 no caller row at all";; esac
out="$( run --callers=near )"
case "$out" in *'<callers '*'defs="'[1-9]*) case "$out" in *'p="docs/links.txt:'*) no "C7b a dangling :ref: does not land on a document of that name";; *) ok "C7b a dangling :ref: does not land on a document of that name";; esac;; *) no "C7b --callers=near answered no <callers> with a def (crash or no document named near)";; esac
printf 'Same Stem\n=========\n\nwrongstem\n' >"$FIX/docs/ref/deep/links.txt"
# The page.txt row's of_def must be the def whose p is the root's docs/links.txt, not the neighbour's.
out="$( run --callers=links )"
rootix="$( printf '%s' "$out" | grep -o '<def ix="[0-9]*" t="sec" p="docs/links.txt:1"' | grep -o 'ix="[0-9]*"' | grep -o '[0-9][0-9]*' )"
nearix="$( printf '%s' "$out" | grep -o '<def ix="[0-9]*" t="sec" p="docs/ref/deep/links.txt:1"' | grep -o 'ix="[0-9]*"' | grep -o '[0-9][0-9]*' )"
rowdef="$( printf '%s' "$out" | grep -o '<s t="sec" n="page" p="docs/ref/deep/page.txt:1" via="link" of_def="[0-9]*"' | grep -o 'of_def="[0-9]*"' | grep -o '[0-9][0-9]*' )"
if [ -z "$rootix" ] || [ -z "$nearix" ]; then no "C6b both links.txt files are defs of --callers=links (got root='$rootix' near='$nearix')"
elif [ "$rowdef" = "$rootix" ]; then ok "C6b a root :doc: goes to the Sphinx root's file (def $rootix), not the same-named neighbour (def $nearix)"
else no "C6b a root :doc: goes to the Sphinx root's file (def $rootix), not the same-named neighbour (def $nearix): page.txt row of_def='$rowdef'"; fi
rm -f "$FIX/docs/ref/deep/links.txt"
arm "C8 a label serves the section it names" has_body "_bare-label" "_bare-label" barebody

echo "D. which .txt is a document"
map="$( run --top-k=1 )"
arm "D1 a .txt under a conf.py declaring it" is_unit "Over Top Name"
arm "D2 source_suffix as a list" is_unit "List Form"
for pair in "Refused One:no conf.py" "Refused Two:a conf.py that is not Sphinx" "Refused Three:Sphinx default suffix" "Refused Four:a commented .txt"; do
  name="${pair%%:*}"; why="${pair#*:}"
  arm_not "D3 stays out: $why" is_unit "$name"
done
case "$map" in *'unindexed="'*txt*) ok "D4 the refused .txt files stay disclosed in unindexed=";; *) no "D4 the refused .txt files stay disclosed in unindexed=";; esac

echo "E. near misses"
arm_not "E1 a 3-char underline shorter than its title is text" is_unit "abcdef"
arm "E2 a 5-char underline shorter than its title is a title" is_unit "abcdefgh"
arm_not "E3 a paragraph's last line is no title" is_unit "qqparaline"
arm_not "E4 title in a literal block" is_unit "Fake Literal Title"
arm_not "E5 directive in a literal block" is_unit "--qqfakeliteral"
arm_not "E5b directive after a bare ::" is_unit "--qqfakebare"
arm_not "E6 directive in code-block" is_unit "--qqfakecode"
arm_not "E7 directive in a comment" is_unit "--qqfakecomment"
arm_not "E8 a bullet above a rule" is_unit "bullet qqbullet"
# E9 reads the answer in this shell (a pipeline into arm would lose a FAIL in its subshell); no xmllint is a SKIP, not a FAIL
"$BIN" "$FIX" --no-cache >"$TMP/e9.xml" 2>/dev/null </dev/null; e9rc=$?
if command -v xmllint >/dev/null 2>&1; then
  e9(){ [ "$e9rc" = 0 ] && [ -s "$TMP/e9.xml" ] && xmllint --noout "$TMP/e9.xml" 2>/dev/null; }; arm "E9 names with markup stay well-formed" e9
else echo "  SKIP  E9 names with markup stay well-formed (no xmllint)"; fi
arm "E10 that title is a unit" is_unit "Title <With> & Markup"

echo "F. pathological files disclose rather than hang"
PATH_FIX="$TMP/path"; mkdir -p "$PATH_FIX"
awk 'BEGIN{ for(i=0;i<40000;i++) printf ".. option:: --o%d\n\n    b\n\n", i }' >"$PATH_FIX/flat.rst"
awk 'BEGIN{ for(i=0;i<300;i++){ s=""; for(j=0;j<i;j++) s=s " "; printf "%s.. function:: f%d()\n\n", s, i; printf "%s    body%d\n\n", s, i } }' >"$PATH_FIX/deep.rst"
awk 'BEGIN{ for(i=0;i<20000;i++) print "" ; print "::"; print ""; for(i=0;i<20000;i++) print "  x"; for(i=0;i<20000;i++) print "====" }' >"$PATH_FIX/odd.rst"
: >"$PATH_FIX/empty.rst"
printf '====' >"$PATH_FIX/eof1.rst"; printf 'Title\n' >"$PATH_FIX/eof2.rst"; printf '====\nTitle\n' >"$PATH_FIX/eof3.rst"; printf '.. ' >"$PATH_FIX/eof4.rst"; printf ':ref:`' >"$PATH_FIX/eof5.rst"
LC_ALL=C printf 'Caf\303\251\n=====\n\n\377\376 bad bytes\n' >"$PATH_FIX/bytes.rst"
start=$( date +%s )
timeout_cmd=(); command -v timeout >/dev/null && timeout_cmd=(timeout 120); command -v gtimeout >/dev/null && timeout_cmd=(gtimeout 120)
${timeout_cmd[@]+"${timeout_cmd[@]}"} "$BIN" "$PATH_FIX" --no-cache --skipped >"$TMP/skip.xml" 2>/dev/null </dev/null; rc=$?
took=$(( $( date +%s ) - start ))
arm "F1 finished in ${took}s, rc=$rc" [ "$rc" = 0 ]
for f in flat deep; do
  arm "F2 $f.rst reports extract-partial" grep -q "$f.rst[^>]*extract-partial\|extract-partial[^>]*$f.rst" "$TMP/skip.xml"
done
arm_not "F3 odd.rst is whole, no false partial" grep -q 'odd.rst[^>]*extract-partial' "$TMP/skip.xml"
FIXC="$PATH_FIX"; out="$( "$BIN" "$FIXC" --no-cache --expand=--o19000 --top-k=0 2>/dev/null )"; case "$out" in *'n="--o19000"'*) ok "F4 units below the cap are served";; *) no "F4 units below the cap are served";; esac

echo "G. determinism, CRLF, cache"
"$BIN" "$FIX" --no-cache >"$TMP/a" 2>/dev/null </dev/null; "$BIN" "$FIX" --no-cache >"$TMP/b" 2>/dev/null </dev/null
sed -E 's/ at="[^"]*"//g' "$TMP/a" >"$TMP/a2"; sed -E 's/ at="[^"]*"//g' "$TMP/b" >"$TMP/b2"
arm "G1 two runs byte-identical" cmp -s "$TMP/a2" "$TMP/b2"
CR="$TMP/cr"; mkdir -p "$CR"; printf 'Crlf Title\r\n==========\r\n\r\n.. option:: --qqcr\r\n\r\n    crbody\r\n' >"$CR/a.rst"
out="$( "$BIN" "$CR" --no-cache --expand=--qqcr --top-k=0 2>/dev/null )"; case "$out" in *crbody*) ok "G2 CRLF file";; *) no "G2 CRLF file";; esac
CF="$TMP/cache"; "$BIN" "$FIX" --cache="$CF" --expand=--qqheight --top-k=0 >"$TMP/c1" 2>/dev/null </dev/null; "$BIN" "$FIX" --cache="$CF" --expand=--qqheight --top-k=0 >"$TMP/c2" 2>/dev/null </dev/null
case "$(cat "$TMP/c2")" in *qqheightword*) ok "G3 warm run serves the unit";; *) no "G3 warm run serves the unit";; esac
sed -i.bak 's/".txt"/".rst"/' "$FIX/docs/conf.py"
# G4 is an absence: it passes only on the verb's own miss (rc 1, nothing on stdout, "matched no symbol"), never on a crash
"$BIN" "$FIX" --cache="$CF" --expand="Over Top Name" --top-k=0 >"$TMP/g4.out" 2>"$TMP/g4.err" </dev/null; g4rc=$?
g4(){ [ "$g4rc" = 1 ] && [ ! -s "$TMP/g4.out" ] && grep -q 'matched no symbol' "$TMP/g4.err"; }; arm "G4 a warm run follows a conf.py that drops .txt" g4
sed -i.bak 's/".rst"/".txt"/' "$FIX/docs/conf.py"
out="$( "$BIN" "$FIX" --cache="$CF" --expand="Over Top Name" --top-k=0 2>/dev/null </dev/null )"; case "$out" in *qqtopword*) ok "G5 and one that declares it again";; *) no "G5 and one that declares it again";; esac

echo "H. a code question: Sphinx .txt pages move no code row (filter.h sphinxTxtStatsExclusion, forpage.h code-first tail)"
# 31 code files where `frob` is common and `widget` rare; 120 Sphinx .txt pages say `widget`. With the pages in the BM25
# statistics, `widget` turns common and frob_thing climbs past frob_1 (the old pass); out of them, the code ranks as without them.
mkh(){ H="$1"; mkdir -p "$H/docs" "$H/src"
  printf 'project = "h"\nextensions = []\nsource_suffix = [".rst", ".txt"]\n' >"$H/docs/conf.py"
  printf 'def frob_thing(widget):\n    return widget\n\n\ndef widget_thing(frob):\n    return frob\n' >"$H/src/core.py"
  for i in $(seq 1 30); do printf 'def helper_%d(x):\n    return frob_%d(x) + 1\n\n\ndef frob_%d(x):\n    return x\n' $i $i $i >"$H/src/mod$i.py"; done
  [ "${2:-}" = nodocs ] && return 0
  for i in $(seq 1 120); do printf '.. _page-%d:\n\nWidget Page %d\n=============\n\nThe widget frob guide %d: widget widget widget.\n' $i $i $i >"$H/docs/page$i.txt"; done; }
HX="$TMP/h"; HN="$TMP/hn"; mkh "$HX"; mkh "$HN" nodocs
# codesigs DIR TASK: the code rows of the ranked head (name per line, rank order); fails when the call fails or prints none
codesigs(){ o="$( "$BIN" "$1" --no-cache --for="$2" 2>/dev/null </dev/null )" || return 1
  printf '%s' "$o" | tr '<' '\n' | grep '^d ' | grep -v 'p="docs/' | sed 's/.* n="\([^"]*\)".*/\1/' | grep . ; }
hx="$( codesigs "$HX" "how does frob widget" )"; rx=$?; hn="$( codesigs "$HN" "how does frob widget" )"; rn=$?
h1a(){ [ "$rx" = 0 ] && [ "$rn" = 0 ] && [ -n "$hx" ] && [ -n "$hn" ]; }; arm "H1a both answers print code rows" h1a
# the .txt rows may take ranked rows (docs after code moves them down, never out), so the code rows compare over the shorter list
h1(){ h1a || return 1; k="$( printf '%s\n' "$hx" | wc -l )"; kn="$( printf '%s\n' "$hn" | wc -l )"; [ "$kn" -lt "$k" ] && k="$kn"
  [ "$k" -ge 3 ] && [ "$( printf '%s\n' "$hx" | head -n "$k" )" = "$( printf '%s\n' "$hn" | head -n "$k" )" ]; }
arm "H1 the code rows rank as they do without the .txt pages" h1
# tailrows DIR TASK: the <tail> rows' paths, in order; fails on a failed call or an empty tail
tailrows(){ o="$( "$BIN" "$1" --no-cache --for="$2" 2>/dev/null </dev/null )" || return 1
  printf '%s' "$o" | tr '<' '\n' | grep '^t p=' | sed 's/^t p="\([^"]*\)".*/\1/' | grep . ; }
tc="$( tailrows "$HX" "how does frob widget" )"; rc=$?
lastcode="$( printf '%s\n' "$tc" | grep -n '^src/' | tail -1 | cut -d: -f1 )"; firstdoc="$( printf '%s\n' "$tc" | grep -n '^docs/' | head -1 | cut -d: -f1 )"
h2a(){ [ "$rc" = 0 ] && [ -n "$lastcode" ] && [ -n "$firstdoc" ]; }; arm "H2a the code question's tail holds code and .txt rows" h2a
h2(){ h2a && [ "$lastcode" -lt "$firstdoc" ]; }; arm "H2 every code row comes before every doc row" h2
td="$( tailrows "$HX" "docs for the frob widget guide" )"; rd=$?
h3(){ [ "$rd" = 0 ] && [ "$( printf '%s\n' "$td" | head -1 | cut -d/ -f1 )" = docs ]; }; arm "H3 a docs question keeps the plain order (a doc row first)" h3
ts="$( "$BIN" "$HX" --no-cache --for="how does frob widget" 2>/dev/null </dev/null )"; rs=$?
h4a(){ [ "$rs" = 0 ] && printf '%s' "$ts" | grep -q '<t p="docs/page[0-9]*\.txt" sym="[^"]'; }; arm "H4a .txt tail rows carry sym=" h4a
arm_not "H4 no label (_name) takes a sym= slot" sh -c '[ "$1" != 0 ] || printf "%s" "$2" | grep -q "sym=\"_\|sym=\"[^\"]*,_"' _ "$rs" "$ts"
arm "H4b the label is still a unit" sh -c 'out="$( "$1" "$2" --no-cache --expand=_page-7 --top-k=0 2>/dev/null </dev/null )" && case "$out" in *"<b t=\"sec\""*) exit 0;; esac; exit 1' _ "$BIN" "$HX"
arm "H5 the extract_partial legend names the reST bound" grep -q 'reST/Sphinx units past 20000 per file or titles and directives nested past 64 levels' "$TMP/skip.xml"

# H6: --match walks an admitted .txt with the grammar a .rst gets (ingest_astquery.h lookupLangOfCrawledFile); b.rst is the twin
MX="$TMP/mx"; mkdir -p "$MX/docs"; printf 'project = "m"\nextensions = []\nsource_suffix = [".rst", ".txt"]\n' >"$MX/docs/conf.py"
printf 'Match Title\n===========\n\nbody\n' >"$MX/docs/a.txt"; cp "$MX/docs/a.txt" "$MX/docs/b.rst"
"$BIN" "$MX" --no-cache --match='(setext_heading) @h' >"$TMP/mx.out" 2>/dev/null </dev/null; mxrc=$?
h6b(){ [ "$mxrc" = 0 ] && grep -q 'docs/b\.rst' "$TMP/mx.out"; }; arm "H6b --match finds the .rst title" h6b
h6(){ h6b && grep -q 'docs/a\.txt' "$TMP/mx.out"; }; arm "H6 --match finds the admitted .txt title" h6

echo "I. a doc unit spelled like code never hides the code (graph.h preferCodeOverDocUnits, pathgaps.h pathDocEndpoints)"
# `.. method:: Model.save` is a unit named `Model.save`; the code's Model.save is reached by the dotted-scope tier only. A nested
# `.. method:: save_base` under `.. class:: Model` is the Scope::name shape; `only_in_docs` has no code at all.
IX="$TMP/ix"; mkdir -p "$IX/docs" "$IX/src"; printf 'project = "i"\nextensions = []\n' >"$IX/docs/conf.py"
printf 'def helper():\n    return 1\n\n\nclass Model:\n    def save(self):\n        return self.save_base()\n\n    def save_base(self):\n        return helper()\n\n\ndef run():\n    return Model().save()\n' >"$IX/src/m.py"
printf 'Model reference\n===============\n\n.. method:: Model.save(force=False)\n\n   Saves qqsaveword.\n\n.. function:: only_in_docs(x)\n\n   No code qqdoconly.\n\n.. class:: Model\n\n   .. method:: save_base()\n\n      Nested qqnested.\n' >"$IX/docs/ref.rst"
# root VERB: the verb's root element (exit code checked: a crash or an empty answer fails every arm that reads it)
root(){ o="$( "$BIN" "$IX" --no-cache "$1" 2>/dev/null </dev/null )" || return 1; printf '%s' "$o" | grep -o "<$2 [^>]*>" | head -1 | grep . ; }
i1="$( root --path=Model.save,helper path )"; arm "I1 --path from a dotted name a directive also spells starts at the code" sh -c 'case "$1" in *from_p=\"src/m.py:6\"*reachable=\"1\"*) exit 0;; esac; exit 1' _ "$i1"
i2="$( root --callers=Model.save callers )"; arm "I2 --callers counts the code's caller" sh -c 'case "$1" in *defs=\"1\"*count=\"1\"*) exit 0;; esac; exit 1' _ "$i2"
i3="$( root --callees=Model.save callees )"; arm "I3 --callees counts the code's callee" sh -c 'case "$1" in *count=\"1\"*) exit 0;; esac; exit 1' _ "$i3"
i4="$( root --impact=Model.save impact )"; arm "I4 --impact reaches the code's caller" sh -c 'case "$1" in *reaches=\"1\"*) exit 0;; esac; exit 1' _ "$i4"
i5="$( root --path=Model::save_base,helper path )"; arm "I5 a nested directive is no second definition (Scope::name tier: from_defs=1)" sh -c 'case "$1" in *from_p=\"src/m.py:9\"*from_defs=\"1\"*reachable=\"1\"*) exit 0;; esac; exit 1' _ "$i5"
i6="$( root --path=save_base,helper path )"; arm "I6 nor under its bare name" sh -c 'case "$1" in *from_defs=\"1\"*reachable=\"1\"*) exit 0;; esac; exit 1' _ "$i6"
i7="$( root --path=only_in_docs,helper path )"; ri7=$?
arm "I7 a doc-only endpoint says so" sh -c '[ "$1" = 0 ] && case "$2" in *"hint=\"from= names only documentation"*) exit 0;; esac; exit 1' _ "$ri7" "$i7"
arm_not "I7b and never prints a no-path verdict" sh -c '[ "$1" != 0 ] && exit 0; case "$2" in *"no directed call path"*) exit 0;; esac; exit 1' _ "$ri7" "$i7"
i8="$( root --path=helper,only_in_docs path )"; arm "I8 the to= side too" sh -c 'case "$1" in *"hint=\"to= names only documentation"*) exit 0;; esac; exit 1' _ "$i8"
i9="$( root --path=helper,run path )"; arm "I9 twin: a code pair with no path keeps the no-path hint" sh -c 'case "$1" in *"no directed call path"*) exit 0;; esac; exit 1' _ "$i9"
arm "I10 the doc-only unit still expands" sh -c 'o="$( "$1" "$2" --no-cache --expand=only_in_docs --top-k=0 2>/dev/null </dev/null )" && case "$o" in *qqdoconly*) exit 0;; esac; exit 1' _ "$BIN" "$IX"
arm "I11 a file:name spelling still picks the nested directive" sh -c 'o="$( "$1" "$2" --no-cache --expand=docs/ref.rst:save_base --top-k=0 2>/dev/null </dev/null )" && case "$o" in *qqnested*) exit 0;; esac; exit 1' _ "$BIN" "$IX"

[ "$fail" = 0 ] && echo "restdocscheck: ALL PASS" || { echo "restdocscheck: FAILED"; exit 1; }
