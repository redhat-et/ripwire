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
  (E) caption-vs-error — a block whose caption does NOT mention refus/error/exit/timeout must not contain
                    the MCP error shape `"error":{` or a `**exit code:` line between its heading and body.
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
    """The FIRST fenced block's content only — not the caption or the `**exit code:` line, so two
    blocks whose CAPTIONS differ (as any two consecutive headings almost always do) but whose real
    OUTPUT is byte-identical are correctly seen as identical by (F)."""
    lines = rawChunk.split('\n')
    i = 0
    while i < len(lines) and not lines[i].startswith('```'):
        i += 1
    if i >= len(lines):
        return ''
    fence = lines[i].rstrip()
    i += 1
    body = []
    while i < len(lines) and lines[i].rstrip() != fence:
        body.append(lines[i])
        i += 1
    return '\n'.join(body).strip()


# ── (D) flag coverage ─────────────────────────────────────────────────────────────────────────────
helpText = subprocess.run([BIN, '--help'], capture_output=True, text=True, timeout=120).stdout
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
REFUSAL_WORDS = re.compile(r'refus|error|exit|timeout', re.I)
eBad = []
for i, hm in enumerate(heads):
    rawChunk = chunk_of(i)
    caption = caption_of(rawChunk)
    if REFUSAL_WORDS.search(caption):
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
      ('%d block(s) whose caption never says refus/error/exit/timeout but the block does: %s'
       % (len(eBad), '; '.join(eBad[:5]) + (' ...' if len(eBad) > 5 else ''))) if eBad
      else 'every non-refusal-captioned block is free of the MCP error shape and an exit-code line')

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
