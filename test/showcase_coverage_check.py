#!/usr/bin/env python3
"""H16 (capture-audit 2026-09-04, lens0-orchestrator.md coverage finding) helper for
test/showcasecapturecheck.sh arms (D)/(E)/(F)/(G). NOT invoked directly by anything else — kept as a
separate file (not a `<<'PY'` heredoc) for the same bash-3.2-parser-bug reason arm (B) already documents
at the top of showcasecapturecheck.sh, and kept as a *_check.py module (not test/showcase_capture.py
itself, which this lane must not touch) so it can be pointed at either the real capture or a deliberately
mutated scratch copy — the SAME logic proves both that a real defect shape is caught (against the mutant)
and that the real capture is clean (or names exactly what remains uncovered).

Usage:  python3 test/showcase_coverage_check.py ROOT BIN CAPTURE_PATH

Prints one line per check, prefixed PASS/FAIL, in the same idiom as the bash arms above it:
  (D) coverage   — every --flag in `BIN --help` appears in a `## ` heading of CAPTURE_PATH, or in its
                    "Not run" header sentence (bracket-optional-suffix notation like `--baseline[-update]`
                    is expanded to both `--baseline` and `--baseline-update`, matching the two literal
                    rows --help actually prints for that pair).
  (E) caption-vs-error — a block whose caption does not DISCLOSE an exit (name it, say REFUSES, or say
                    "refusal/error shape") must not contain the MCP error shape `"error":{` or a
                    `**exit code:` line between its heading and body. A bare "error" in prose about
                    the subject matter does not exempt — see the note at REFUSAL_WORDS.
  (F) contrast-pair — two CONSECUTIVE `## ` headings where the second command is the first PLUS exactly
                    one added `--`-flag token must have DIFFERING blocks (the whole point of showing them
                    back to back is the contrast; a byte-identical pair demonstrates nothing).
  (G) header-clause — a caption naming a header clause (`[doc mentions`, `[mention anchor`, `[adaptive`)
                    as something the block DOES carry must find that literal clause text in the block.
                    Excludes a caption using the same bracket text to describe ABSENCE ("no [doc
                    mentions]...") — the negation is the caption correctly describing a --no-X contrast,
                    not a broken promise.
"""
import os
import re
import subprocess
import sys

ROOT, BIN, CAPTURE = sys.argv[1], sys.argv[2], sys.argv[3]

sys.path.insert(0, os.path.join(ROOT, 'docs'))
import docs_commands_build as dcb  # noqa: E402  (the flag/help/capture parser this doc's own generator uses)

results = []


def check(name, ok, detail=''):
    results.append((name, bool(ok), detail))


if not os.path.exists(CAPTURE):
    check('(D) coverage', False, 'capture file does not exist: %s' % CAPTURE)
    for name in ('(E) caption-vs-error', '(F) contrast-pair', '(G) header-clause'):
        check(name, False, 'skipped — no capture to read')
    for name, ok, detail in results:
        print(('PASS ' if ok else 'FAIL ') + name + (': ' + detail if detail else ''))
    sys.exit(0)

rawText = open(CAPTURE, encoding='utf-8', errors='replace').read()

# ── shared: one chunk per `## ` heading, spanning to the next heading (or EOF) ───────────────────────
heads = list(re.finditer(r'^## `(.+)`\s*$', rawText, re.M))


def chunk_of(i):
    start = heads[i].end()
    end = heads[i + 1].start() if i + 1 < len(heads) else len(rawText)
    return rawText[start:end]


def caption_of(rawChunk):
    for line in rawChunk.split('\n'):
        s = line.strip()
        if not s:
            continue
        return s.strip('*').strip() if (s.startswith('*') and s.endswith('*')) else ''
    return ''


def body_of(rawChunk):
    """Every fenced block's content (stdout, stderr, artifact, post-command) plus the `**exit code:` line —
    NOT the caption or the wall time — so two blocks whose CAPTIONS differ (as any two consecutive headings
    almost always do) but whose real OUTPUT is byte-identical are correctly seen as identical by (F).
    wave-3 close (2026-09-05): the first fence ALONE was the old reading, and it flagged the
    `--quality-baseline` -> `+--allow-dirty` pair as identical because both leave stdout empty — the whole
    contrast of a refusal-vs-consent pair lives in the exit code, stderr and the artifact it did or did not
    write. A refusal IS output."""
    lines = rawChunk.split('\n')
    body = []
    i = 0
    while i < len(lines):
        if lines[i].startswith('```'):
            fence = lines[i].rstrip()
            i += 1
            while i < len(lines) and lines[i].rstrip() != fence:
                body.append(lines[i])
                i += 1
            body.append('')   # fence boundary — two blocks are not one
        else:
            m = re.match(r'\*\*exit code: (\d+)\*\*', lines[i].strip())
            if m:
                body.append('exit code: ' + m.group(1))
        i += 1
    return '\n'.join(body).strip()


# ── (D) flag coverage ─────────────────────────────────────────────────────────────────────────────
helpText = subprocess.run([BIN, '--help=all'], capture_output=True, text=True, timeout=120).stdout
_preamble, sections = dcb.parse_help(helpText)
allFlags = {f for f in dcb.binary_flags(sections) if f.startswith('--')}

headingFlags = set()
for hm in heads:
    headingFlags |= dcb.flag_tokens_of(hm.group(1))

mNotRun = re.search(r'\*\*Not run \(and why\):\*\*(.*?)(?:\n\n|\Z)', rawText, re.S)
notRunText = mNotRun.group(1) if mNotRun else ''
NOT_RUN_FLAG_RE = re.compile(r'--[A-Za-z0-9][A-Za-z0-9-]*(?:\[-[A-Za-z0-9]+\])?')
notRunFlags = set()
for m in NOT_RUN_FLAG_RE.finditer(notRunText):
    tok = m.group(0)
    if '[' in tok:
        base = tok.split('[')[0]
        suffix = tok[tok.index('[') + 1:-1]
        notRunFlags.add(base)
        notRunFlags.add(base + suffix)
    else:
        notRunFlags.add(tok)

covered = headingFlags | notRunFlags
missing = sorted(allFlags - covered)
check('(D) coverage', not missing,
      ('%d/%d flags uncovered: %s' % (len(missing), len(allFlags), ', '.join(missing))) if missing
      else ('%d/%d flags covered (heading or Not-run)' % (len(allFlags), len(allFlags))))

# ── (E) caption vs error/exit-code shape ──────────────────────────────────────────────────────────
# A caption EXEMPTS its block from this arm only when it DISCLOSES the exit, and the caption is read
# with its --flag tokens REMOVED first. Both halves are scars.
#
# The word half: the seed demo `--at=FILE:LINE` was captioned "...(a compiler error, a diff hunk, a
# stack frame)...", which matched a bare /error/ and hid a real exit 1. Matching a subject-matter word
# is CONTRIBUTING §2 shape 1 — shape where a value was meant. Flag-stripping is the same bug one word
# smaller: without it "Pairs with --run-timeout to cap the command" exempts on the flag's NAME.
#
# The number half: a caption may NAME an exit, and then the name must be true. "exits 0: a minimal
# success record" over a block that exits 4 is worse than saying nothing — it is a wrong answer with a
# confident shape. So when the caption names any exit number, one of them must be the block's own.
#
# Deliberately NOT accepted as a disclosure: a bare "non-zero exit" with no number. That is what the
# --run-trace caption said while the block exited 4, and it was describing the WRAPPED command's exit,
# not ripwire's. Accepting it would re-cut the hole this arm exists to close.
FLAG_TOKEN   = re.compile(r'--[A-Za-z0-9][A-Za-z0-9-]*')
# These two must agree on what an exit LOOKS like, or the arm contradicts itself: round 5 found
# "ripwire exited 1" flagged (CAPTION_EXIT read it, DISCLOSE did not) while "exit code: 1" over a
# block that exits 4 was exempt (DISCLOSE read it, CAPTION_EXIT's [-\s]* did not admit the colon, so
# the number rule never fired). One shared spelling of the number, used by both.
_EXIT_N      = r'exit(?:s|ed)?[-\s]*(?:code|status)?[-\s:]*(\d+)'
DISCLOSE     = re.compile(r'refus|' + _EXIT_N + r'|exit[-\s]?(?:code|status)|timed[ -]?out|timeout|error shape|error form', re.I)
CAPTION_EXIT = re.compile(_EXIT_N, re.I)
BLOCK_EXIT   = re.compile(r'^\*\*exit code:\s*(\d+)', re.M)

# A number is only a claim about THIS block when it is asserted. "exit 2 on violation" / "exit 2 =
# CRITICAL, 1 = WARN" state the verb's CONTRACT and stay true whichever way the recorded run went;
# enforcing them would turn two honest captions red. "exits 0: a minimal success record" over a block
# that exits 4 asserts, and is wrong. So the number rule fires on assertive numbers only.
CONDITIONAL = re.compile(r'\s*(?:if|when(?:ever)?|unless|on\b|=|or\b|,\s*\d)', re.I)

def caption_exits( bare ):
    """Exit numbers the caption ASSERTS about this block (conditional/contract numbers excluded)."""
    out = set()
    for m in CAPTION_EXIT.finditer( bare ):
        if not CONDITIONAL.match( bare[m.end():m.end() + 12] ):
            out.add( m.group( 1 ) )
    return out

def caption_discloses( caption, chunk ):
    """True when the caption tells the reader this block exits non-zero, and any exit it ASSERTS is right."""
    bare = FLAG_TOKEN.sub( ' ', caption )
    if not DISCLOSE.search( bare ):
        return False
    named = caption_exits( bare )
    # A block with no `**exit code:` line exited 0 — the renderer prints the line only for rc != 0. That
    # is why the empty case is 0 and not "unknown": a caption asserting "REFUSES (exit 1)" over a block
    # that quietly succeeded is a refusal that REGRESSED, and reading the absence as unknown would make
    # this arm green for exactly that.
    actual = set( BLOCK_EXIT.findall( chunk ) ) or { '0' }
    if named and not ( named & actual ):
        return False        # it asserted an exit, and asserted the wrong one
    return True

eBad = []
for i, hm in enumerate(heads):
    rawChunk = chunk_of(i)
    caption = caption_of(rawChunk)
    if caption_discloses(caption, rawChunk):
        continue
    hasErrorShape = '"error":{' in rawChunk
    hasExitLine = re.search(r'^\*\*exit code:', rawChunk, re.M) is not None
    if hasErrorShape or hasExitLine:
        why = []
        if hasErrorShape:
            why.append('"error":{ in block')
        if hasExitLine:
            why.append('**exit code: line present')
        eBad.append('%s [%s]' % (hm.group(1)[:70], ', '.join(why)))
check('(E) caption-vs-error', not eBad,
      ('%d block(s) whose caption does not DISCLOSE an exit (name it, or say REFUSES / refusal shape) but the block has one: %s'
       % (len(eBad), '; '.join(eBad[:5]) + (' ...' if len(eBad) > 5 else ''))) if eBad
      else 'every block that exits non-zero says so in its caption; no undisclosed MCP error shape either')

# ── (F) contrast pairs: consecutive headings differing by exactly one added --flag token ───────────
fBad = []
fChecked = 0
for i in range(len(heads) - 1):
    a, b = heads[i].group(1).split(), heads[i + 1].group(1).split()
    if len(b) == len(a) + 1 and b[:len(a)] == a and b[len(a)].startswith('--'):
        fChecked += 1
        ca, cb = body_of(chunk_of(i)), body_of(chunk_of(i + 1))
        if ca == cb:
            fBad.append('%s -> +%s' % (heads[i].group(1)[:60], b[len(a)]))
check('(F) contrast-pair', not fBad,
      ('%d/%d contrast pair(s) byte-identical (no contrast at all): %s'
       % (len(fBad), fChecked, '; '.join(fBad[:5]))) if fBad
      else ('%d contrast pair(s) checked, all differ' % fChecked))

# ── (G) a caption naming a header clause must find it in the block, unless the caption is describing
#        the clause's ABSENCE (a "no [clause]"/"without [clause]" negation — a correct --no-X caption) ──
MARKERS = ('doc mentions', 'mention anchor', 'adaptive')


def positive_claims(caption, marker):
    """True if `caption` asserts the block CARRIES `[marker` (not "no [marker" / "without [marker")."""
    needle = '[' + marker
    idx = caption.find(needle)
    found = []
    while idx != -1:
        prefixWord = re.search(r'(\w+)\s*$', caption[:idx])
        if not (prefixWord and prefixWord.group(1).lower() in ('no', 'without')):
            found.append(True)
        idx = caption.find(needle, idx + 1)
    return any(found)


gBad = []
gChecked = 0
for i, hm in enumerate(heads):
    rawChunk = chunk_of(i)
    caption = caption_of(rawChunk)
    for marker in MARKERS:
        if positive_claims(caption, marker):
            gChecked += 1
            if ('[' + marker) not in rawChunk[len(caption):] if caption else ('[' + marker) not in rawChunk:
                gBad.append('%s: caption claims [%s but the block has no such clause' % (hm.group(1)[:60], marker))
check('(G) header-clause', not gBad,
      ('%d/%d header-clause claim(s) unfulfilled: %s' % (len(gBad), gChecked, '; '.join(gBad[:5]))) if gBad
      else ('%d header-clause claim(s) checked, all fulfilled' % gChecked))

for name, ok, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (': ' + detail if detail else ''))
