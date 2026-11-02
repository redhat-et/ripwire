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
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
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
and :ref:`widgetfn`, which names no label.

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
has_body "Over Top Name" "Over Top Name" qqtopword && ok "A1 overlined title" || no "A1 overlined title"
has_body "Under Three" "Under Three" qqthreeword && ok "A2 a third punctuation" || no "A2 a third punctuation"
body_lacks "Under Three" qqfourword && ok "A3 a same-level title ends the span" || no "A3 a same-level title ends the span"
out="$( run --expand="Under Two" --top-k=0 )"
case "$out" in *qqtwoword*) ok "A4 a title keeps its prose";; *) no "A4 a title keeps its prose";; esac
out="$( run --expand="Order Inner" --top-k=0 )"
case "$out" in *'sibs="Order Outer'*|*'Order Outer'*) ok "A5 level by first-seen order: = sits under ~ here";; *) no "A5 level by first-seen order: = sits under ~ here";; esac
body_lacks "Order Inner" qqsiblingword && ok "A6 the first-seen style closes the inner one" || no "A6 the first-seen style closes the inner one"

echo "B. directives as units, named by their target, body served"
has_body "--qqwidth" "--qqwidth" qqwidthword && ok "B1 option named by the long spelling, no =<n>" || no "B1 option named by the long spelling, no =<n>"
body_lacks "--qqwidth" qqheightword && ok "B2 the next option ends the unit" || no "B2 the next option ends the unit"
has_body "qqconf_value" "qqconf_value" qqconfword && ok "B3 confval" || no "B3 confval"
has_body "pkg.qqfunc" "pkg.qqfunc" qqfuncword && ok "B4 function, signature off" || no "B4 function, signature off"
has_body "QqKlass" "QqKlass" qqmethword && ok "B5 class holds its method" || no "B5 class holds its method"
has_body "qqmeth" "qqmeth" qqmethword && ok "B6 method nested in a class" || no "B6 method nested in a class"
has_body "qqattr" "qqattr" qqattrword && ok "B7 a domain prefix comes off" || no "B7 a domain prefix comes off"
has_body "qq_cfunc" "qq_cfunc" qqcfuncword && ok "B8 a C signature names the function" || no "B8 a C signature names the function"
is_unit "--qqinnote" && ok "B9 an option inside a note" || no "B9 an option inside a note"
has_body "QQ_SETTING" "QQ_SETTING" qqsettingword && ok "B10 a body-less setting covers the title below it" || no "B10 a body-less setting covers the title below it"
out="$( run --expand=QQ_SETTING --top-k=0 )"; [ "$( printf '%s' "$out" | grep -o 'n="QQ_SETTING"' | wc -l | tr -d ' ' )" = 1 ] && ok "B10b a setting above its own title is one unit" || no "B10b a setting above its own title is one unit"
has_body "QQ_ABOVE" "QQ_ABOVE" qqaboveword && ok "B10c a setting above another title covers it" || no "B10c a setting above another title covers it"
has_body "QQ_PLAIN" "QQ_PLAIN" qqplainword && ok "B11 a body-less setting with prose runs to the next unit" || no "B11 a body-less setting with prose runs to the next unit"
body_lacks "QQ_PLAIN" qqnextword && ok "B12 and stops at the next title" || no "B12 and stops at the next title"
has_body "--qqrstopt" "--qqrstopt" rstoptbody && ok "B13 a .rst outside any Sphinx root parses the same" || no "B13 a .rst outside any Sphinx root parses the same"
out="$( run --recall=qqheightword )"
case "$out" in *qqheightword*) case "$out" in *qqconfword*) no "B14 recall serves the unit, not the page";; *) ok "B14 recall serves the unit, not the page";; esac;; *) no "B14 recall serves the unit, not the page";; esac

echo "C. links"
link_from "_option-label" "docs/links.txt" && ok "C1 :ref: with text, to a label" || no "C1 :ref: with text, to a label"
link_from "_bare-label" "docs/links.txt" && ok "C2 bare :ref:" || no "C2 bare :ref:"
link_from "_wrapped-label" "docs/links.txt" && ok "C3 a :ref: wrapped over lines, label lowered" || no "C3 a :ref: wrapped over lines, label lowered"
out="$( run --callers=options )"
case "$out" in *'via="link"'*) ok "C4 relative :doc:";; *) no "C4 relative :doc:";; esac
out="$( run --callers=page )"
case "$out" in *'p="docs/links.txt:'*'via="link"'*) ok "C5 :doc:\`/abs\` from the Sphinx root";; *) no "C5 :doc:\`/abs\` from the Sphinx root";; esac
out="$( run --callers=links )"
case "$out" in *'via="link"'*) ok "C6 :doc:\`/abs\` from a deeper file";; *) no "C6 :doc:\`/abs\` from a deeper file";; esac
out="$( run --callers=widgetfn )"
case "$out" in *'via="link"'*) no "C7 a dangling :ref: does not land on a function of that name";; *'callit'*) ok "C7 a dangling :ref: does not land on a function of that name";; *) no "C7 no caller row at all";; esac
has_body "_bare-label" "_bare-label" barebody && ok "C8 a label serves the section it names" || no "C8 a label serves the section it names"

echo "D. which .txt is a document"
map="$( run --top-k=1 )"
is_unit "Over Top Name" && ok "D1 a .txt under a conf.py declaring it" || no "D1 a .txt under a conf.py declaring it"
is_unit "List Form" && ok "D2 source_suffix as a list" || no "D2 source_suffix as a list"
for pair in "Refused One:no conf.py" "Refused Two:a conf.py that is not Sphinx" "Refused Three:Sphinx default suffix" "Refused Four:a commented .txt"; do
  name="${pair%%:*}"; why="${pair#*:}"
  is_unit "$name" && no "D3 stays out: $why" || ok "D3 stays out: $why"
done
case "$map" in *'unindexed="'*txt*) ok "D4 the refused .txt files stay disclosed in unindexed=";; *) no "D4 the refused .txt files stay disclosed in unindexed=";; esac

echo "E. near misses"
is_unit "abcdef" && no "E1 a 3-char underline shorter than its title is text" || ok "E1 a 3-char underline shorter than its title is text"
is_unit "abcdefgh" && ok "E2 a 5-char underline shorter than its title is a title" || no "E2 a 5-char underline shorter than its title is a title"
is_unit "qqparaline" && no "E3 a paragraph's last line is no title" || ok "E3 a paragraph's last line is no title"
is_unit "Fake Literal Title" && no "E4 title in a literal block" || ok "E4 title in a literal block"
is_unit "--qqfakeliteral" && no "E5 directive in a literal block" || ok "E5 directive in a literal block"
is_unit "--qqfakecode" && no "E6 directive in code-block" || ok "E6 directive in code-block"
is_unit "--qqfakecomment" && no "E7 directive in a comment" || ok "E7 directive in a comment"
is_unit "bullet qqbullet" && no "E8 a bullet above a rule" || ok "E8 a bullet above a rule"
"$BIN" "$FIX" --no-cache 2>/dev/null </dev/null | xmllint --noout - 2>/dev/null && ok "E9 names with markup stay well-formed" || no "E9 names with markup stay well-formed"
is_unit "Title <With> & Markup" && ok "E10 that title is a unit" || no "E10 that title is a unit"

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
[ "$rc" = 0 ] && ok "F1 finished, rc=0 in ${took}s" || no "F1 rc=$rc after ${took}s"
for f in flat deep; do
  grep -q "$f.rst[^>]*extract-partial\|extract-partial[^>]*$f.rst" "$TMP/skip.xml" && ok "F2 $f.rst reports extract-partial" || no "F2 $f.rst reports extract-partial"
done
grep -q 'odd.rst[^>]*extract-partial' "$TMP/skip.xml" && no "F3 odd.rst is whole, no false partial" || ok "F3 odd.rst is whole, no false partial"
FIXC="$PATH_FIX"; out="$( "$BIN" "$FIXC" --no-cache --expand=--o19000 --top-k=0 2>/dev/null )"; case "$out" in *'n="--o19000"'*) ok "F4 units below the cap are served";; *) no "F4 units below the cap are served";; esac

echo "G. determinism, CRLF, cache"
"$BIN" "$FIX" --no-cache >"$TMP/a" 2>/dev/null </dev/null; "$BIN" "$FIX" --no-cache >"$TMP/b" 2>/dev/null </dev/null
sed -E 's/ at="[^"]*"//g' "$TMP/a" >"$TMP/a2"; sed -E 's/ at="[^"]*"//g' "$TMP/b" >"$TMP/b2"
cmp -s "$TMP/a2" "$TMP/b2" && ok "G1 two runs byte-identical" || no "G1 two runs byte-identical"
CR="$TMP/cr"; mkdir -p "$CR"; printf 'Crlf Title\r\n==========\r\n\r\n.. option:: --qqcr\r\n\r\n    crbody\r\n' >"$CR/a.rst"
out="$( "$BIN" "$CR" --no-cache --expand=--qqcr --top-k=0 2>/dev/null )"; case "$out" in *crbody*) ok "G2 CRLF file";; *) no "G2 CRLF file";; esac
CF="$TMP/cache"; "$BIN" "$FIX" --cache="$CF" --expand=--qqheight --top-k=0 >"$TMP/c1" 2>/dev/null </dev/null; "$BIN" "$FIX" --cache="$CF" --expand=--qqheight --top-k=0 >"$TMP/c2" 2>/dev/null </dev/null
case "$(cat "$TMP/c2")" in *qqheightword*) ok "G3 warm run serves the unit";; *) no "G3 warm run serves the unit";; esac
sed -i.bak 's/".txt"/".rst"/' "$FIX/docs/conf.py"
out="$( "$BIN" "$FIX" --cache="$CF" --expand="Over Top Name" --top-k=0 2>/dev/null </dev/null )"; case "$out" in *qqtopword*) no "G4 a warm run follows a conf.py that drops .txt";; *) ok "G4 a warm run follows a conf.py that drops .txt";; esac
sed -i.bak 's/".rst"/".txt"/' "$FIX/docs/conf.py"
out="$( "$BIN" "$FIX" --cache="$CF" --expand="Over Top Name" --top-k=0 2>/dev/null </dev/null )"; case "$out" in *qqtopword*) ok "G5 and one that declares it again";; *) no "G5 and one that declares it again";; esac

[ "$fail" = 0 ] && echo "restdocscheck: ALL PASS" || { echo "restdocscheck: FAILED"; exit 1; }
