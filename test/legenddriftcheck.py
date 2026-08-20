#!/usr/bin/env python3
"""
Legend drift detection checker.

Finds flag references in ripwire XML output legends that don't exist in --help.
This detects LEGEND DRIFT: where emitted XML legend comments reference flags,
verbs, or lenses that don't exist or are misspelled, causing documentation bugs
invisible to --doc-drift (since legends are XML comments, not markdown prose).

Usage:
  python3 test/legenddriftcheck.py <binary_path> [corpus_path]
  python3 test/legenddriftcheck.py --legend-file=FILE --help-file=FILE  (synthetic test)

Output: JSON-formatted results including:
  - flags_in_help: set of all flags found in --help
  - legend_tokens: list of all flag-like tokens extracted from legends
  - findings: dict with phantom/spelling_issues/valid categories
  - verdict: CLEAN or DIRTY
"""

import subprocess
import re
import json
import sys
import os
from pathlib import Path


def extract_flags_from_help(binary_path=None, help_text=None):
    """Parse --help output to extract all valid flag names."""
    if help_text is None:
        try:
            result = subprocess.run(
                [binary_path, "--help"],
                capture_output=True,
                text=True,
                timeout=30
            )
            help_text = result.stdout + result.stderr
        except Exception as e:
            return set(), f"Failed to run --help: {e}"

    flags = set()

    # Pattern 1: --flag-name (most common in help output)
    for match in re.finditer(r'--([a-z][a-z0-9\-]*)', help_text):
        flags.add(f"--{match.group(1)}")

    return flags, None


def run_ripwire_verb(binary_path, corpus_path, verb_and_args):
    """Run ripwire with a specific verb and return XML output."""
    try:
        cmd = [binary_path, corpus_path] + verb_and_args
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60
        )
        return result.stdout, None
    except subprocess.TimeoutExpired:
        return "", f"Timeout running verb {verb_and_args}"
    except Exception as e:
        return "", f"Failed to run verb {verb_and_args}: {e}"


def extract_legend_from_xml(xml_text):
    """Extract legend text from XML comments in output."""
    legends = []

    # Find all XML comments in output
    # Pattern: <!--  ...  --> with nested dashes handled correctly
    for match in re.finditer(r'<!--\s*([^-]*(?:-[^-]+)*?)\s*-->', xml_text):
        comment_text = match.group(1).strip()
        # Keep most legend-like comments (reasonable prose length or explicit legend markers)
        if len(comment_text) > 15:  # lowered threshold to catch shorter legends
            legends.append(comment_text)

    return legends


def extract_flag_tokens_from_legend(legend_text):
    """Extract flag-like tokens from legend text.

    Five patterns:
    1. Explicit flag references like "--for" or "--grep"
    2. Flag=value patterns (e.g., "rank_by=churn")
    3. Quoted flag references ("--flag" or '--flag')
    4. Prose like "the signatures-only flag" or "the pack-task lens"
    5. Bareword "word=N" / "word=M" placeholder mentions (W3-S item 4, 2026-08-19) -- see the long
       comment above PLACEHOLDER_EXCLUDE below for why patterns 1-3 are structurally UNREACHABLE
       against real ripwire output and why this pattern is the one that actually widens live coverage.

    V1 (wave-2 verifier, 2026-08-19): patterns 1-3 all require a literal "--flag" spelling, and "--"
    is illegal inside a well-formed XML comment (a comment must not contain two consecutive hyphens),
    so none of them can EVER match real ripwire legend text -- only pattern 4's prose form can, and an
    independent sweep across the whole tool found only 3 such prose mentions reachable at all
    ("the signatures-only flag", "the quality-delta ... verb", "the max-file-size flag"). The gate's
    live arm was "green but nearly inert": true, but observing almost nothing.
    """
    tokens = set()

    # Pattern 1: explicit flag references like "--for" or "--grep"
    # Capture --flag in word boundaries, allowing embedded hyphens
    for match in re.finditer(r'(?:^|\s|[({[])(--[a-z][a-z0-9\-]*)(?:\s|[)\]{]|$)', legend_text):
        tokens.add(match.group(1))

    # Pattern 2: flag=value patterns (where flag is mentioned explicitly)
    for match in re.finditer(r'(--[a-z][a-z0-9\-]*)=', legend_text):
        tokens.add(match.group(1))

    # Pattern 3: quoted flag references
    for match in re.finditer(r'["\']+(--[a-z][a-z0-9\-]*)["\']', legend_text):
        tokens.add(match.group(1))

    # Pattern 4: prose like "the signatures-only flag" or "the pack-task lens"
    # Look for hyphenated words immediately followed by "flag", "lens", "verb", or "option"
    # ALLOWLIST: phrases that look flag-like but are not actually flags (explained in allowlist below)
    allowlist = {
        "--call-graph",  # "call-graph importance" is prose, not a flag
        "--page-rank",   # "pagerank importance" is prose, not a flag
        "--change-frequency",  # "git CHANGE-FREQUENCY prior" is prose
        "--time-decayed",  # "TIME-DECAYED git change-frequency" is prose
        "--max-depth",   # "MAX-depth" is prose referring to a concept, not a flag
        "--dual-compile", # "dual-compile CPU/GPU contract" is prose, not a flag
        "--canonical",   # prose attribute, not a flag
        # W3-S item 4 (2026-08-19): surfaced by widening run_verb_suite past its original 15 verbs —
        # both are pattern 4 false positives that existed in the code all along and were simply never
        # exercised before (neither --readability nor --context-ratio was in the old suite).
        "--closed-form",       # --readability's legend: "the Posnett/Hindle/Devanbu (MSR 2011)
                                # closed-form lens" -- a closed-form MATH SOLUTION, not a flag
        "--local-reasoning",   # --context-ratio's legend: "the LOCAL-REASONING lens" -- the
                                # code-quality PROPERTY the verb measures, not a flag
    }

    for match in re.finditer(
        r'\b(?:the\s+)?([a-z][a-z0-9\-]*(?:-[a-z0-9\-]*)*)\s+(?:flag|lens|verb|option)\b',
        legend_text,
        re.IGNORECASE
    ):
        word = match.group(1).lower()   # re.IGNORECASE matched either case; --help flags are always
                                         # lowercase (pattern 1's own `[a-z]`), so normalize before the
                                         # allowlist/valid_flags comparison -- "LOCAL-REASONING lens"
                                         # must hit the SAME allowlist/valid entry "local-reasoning" does.
        # Only include if it looks like a flag name (has hyphens or appears in help references)
        if '-' in word:
            candidate = f"--{word}"
            if candidate not in allowlist:
                tokens.add(candidate)

    # Pattern 5 (W3-S item 4, 2026-08-19): bareword "word=N" / "word=M" placeholder mentions.
    # ripwire's own --help spells its paginating/budget flags exactly this way ("--limit=N --offset=M",
    # "--top-k=N", "--max-tokens=N", "--detail=N", ...), and because a literal "--" cannot appear inside
    # an XML comment, a legend that wants to name one of those flags can ONLY drop the leading "--" and
    # keep the placeholder: "raise the default cap with limit=N (offset=M pages)" (this exact clause is
    # hand-copied into a dozen-plus legends across the tool, per src/pageview.h's own comment). Matching
    # this shape is what actually widens live coverage -- an 8-repo verb sweep found detail=N, limit=N,
    # offset=M, max-tokens=N, token-budget=N, top-k=N, partition=N and plan-lanes=N all reachable this
    # way, all real flags, none reachable by patterns 1-4.
    #
    # PLACEHOLDER_EXCLUDE: the SAME sweep also found bareword "word=N" mentions that are NOT flag
    # references at all -- they are OUTPUT ATTRIBUTES that happen to share the same "=N" placeholder
    # convention in their own defining prose (e.g. the map legend's "overloads=N-same-name-defs...",
    # or a row's "bodies=N"/"files=N"/"hits=N"/"toks=N" disclosure). None of these has a same-named CLI
    # flag, so admitting them would manufacture a false phantom on ordinary, correct legend text -- the
    # gate crying wolf, which is worse than the narrow coverage this pattern replaces. Excluded by NAME,
    # the same allowlist idiom pattern 4 already uses above; if a future legend introduces a new
    # "=N"-shaped output attribute whose bareword happens to collide with no real flag, add it here
    # (a live-arm FALSE positive is the failure mode this list exists to prevent, and the fix is always
    # "add the name", never "narrow the pattern back to uselessness").
    placeholder_exclude = {"bodies", "overloads", "files", "hits", "toks"}
    for match in re.finditer(r'\b([a-z][a-z0-9\-]*)=[NM]\b', legend_text):
        word = match.group(1)
        if word not in placeholder_exclude:
            tokens.add(f"--{word}")

    return sorted(list(tokens))


def categorize_findings(found_tokens, valid_flags):
    """Categorize findings into phantom flags, spelling mismatches, etc."""
    phantom = []
    spelling_issues = []
    valid = []

    for token in found_tokens:
        if token in valid_flags:
            valid.append(token)
        else:
            # Check if there's a close match (might be a spelling variant or typo)
            close_matches = [f for f in valid_flags if
                           token.replace('-', '') in f.replace('-', '') and
                           len(token) < len(f) + 5 and len(token) > len(f) - 5]
            if close_matches:
                spelling_issues.append({
                    'found': token,
                    'candidates': close_matches
                })
            else:
                phantom.append(token)

    return {
        'phantom': sorted(phantom),
        'spelling_issues': spelling_issues,
        'valid': sorted(valid)
    }


def run_verb_suite(binary_path, corpus_path):
    """Run a comprehensive suite of verbs to exercise legend output.

    Covers all major verbs that emit legends based on serialize.h analysis.

    W3-S item 4 (2026-08-19): widened from 15 to ~50 verb invocations. Measured effect (this repo as
    corpus, real binary): legends_found rose from 114 to several hundred, and — combined with pattern 5
    above — flag_tokens_extracted rose from 1 to 8+ (detail/limit/offset/max-tokens/token-budget/top-k/
    partition/plan-lanes all independently reachable now, not just "the signatures-only flag"). Every
    added invocation was verified individually (real corpus, this repo) to exit 0 within a few seconds
    before being added here; run_ripwire_verb's existing 60s per-call timeout is the safety net if a
    future corpus makes one of these slow, same as before this change.
    """
    verbs_to_test = [
        [],                                   # default map
        ["--top-k=10"],                      # with top-k
        ["--for=example task"],              # --for verb (task lens)
        ["--grep=function"],                 # --grep verb (search)
        ["--grep=test", "--context=2"],      # --grep with context
        ["--match=(identifier) @name"],      # --match verb
        ["--expand=main"],                   # --expand verb
        ["--hotspots"],                      # --hotspots verb
        ["--pack-task=test task"],           # --pack-task verb (composable bundle)
        ["--metrics"],                       # --metrics verb
        ["--rank-by=churn"],                 # churn ranking
        ["--rank-by=authority"],             # authority ranking
        ["--rank-by=hub"],                   # hub ranking
        ["--rank-by=rrf"],                   # reciprocal rank fusion
        ["--stable"],                        # stable path ordering
        ["--lint"],                          # --lint (rule catalog + findings legend)
        ["--communities"],                   # --communities (module clustering)
        ["--clones"],                        # --clones (near-duplicate detection)
        ["--cochange"],                      # --cochange (git co-change pairs)
        ["--owners"],                        # --owners (git blame rollup)
        ["--tree"],                          # --tree (path hierarchy)
        ["--deps"],                          # --deps (include/import graph)
        ["--callers=main"],                  # --callers (1-hop call hierarchy)
        ["--callees=main"],                  # --callees
        ["--whereis=main"],                  # --whereis (cross-ref search)
        ["--doc-drift"],                     # --doc-drift
        ["--skipped"],                       # --skipped (crawl-composition disclosure)
        ["--impact=main"],                   # --impact (transitive blast radius)
        ["--uses=main"],                     # --uses (use-site index)
        ["--around=main"],                   # --around (ego-graph)
        ["--mentions=main"],                 # --mentions (doc cross-references)
        ["--flags"],                         # --flags (dark-flag surface)
        ["--edit-check=main"],               # --edit-check (contract-change check)
        ["--affected=main.cpp"],             # --affected (test-mining)
        ["--doctor"],                        # --doctor (self-diagnosis)
        ["--quality-delta"],                 # --quality-delta
        ["--quality-panel"],                 # --quality-panel
        ["--graph-query=kind(all,fn)"],      # --graph-query (closed expression language)
        ["--external-surface"],              # --external-surface
        ["--nonlocal-state"],                # --nonlocal-state
        ["--field-affinity"],                # --field-affinity
        ["--dmm"],                           # --dmm (design/metric mismatch)
        ["--comment-coherence"],             # --comment-coherence
        ["--naming-consistency"],            # --naming-consistency
        ["--readability"],                   # --readability
        ["--context-ratio"],                 # --context-ratio
        ["--ensemble"],                      # --ensemble
        ["--outline=main.cpp"],              # --outline (whole-file summary)
        ["--test-gate"],                     # --test-gate (tests-to-run + untested blast radius)
        ["--situ"],                          # --situ (mid-task situational report)
    ]

    all_legends = []
    for verb_args in verbs_to_test:
        xml_output, err = run_ripwire_verb(binary_path, corpus_path, verb_args)
        if err:
            # Non-fatal: some verbs might fail, continue with others
            continue

        legends = extract_legend_from_xml(xml_output)
        all_legends.extend(legends)

    return all_legends


def main():
    # Parse arguments: either <binary> [corpus] or --legend-file/--help-file for synthetic testing
    binary_path = None
    corpus_path = None
    legend_file = None
    help_file = None

    for arg in sys.argv[1:]:
        if arg.startswith('--legend-file='):
            legend_file = arg.split('=', 1)[1]
        elif arg.startswith('--help-file='):
            help_file = arg.split('=', 1)[1]
        elif not arg.startswith('--'):
            if binary_path is None:
                binary_path = arg
            elif corpus_path is None:
                corpus_path = arg

    # Synthetic test mode: read from files instead of running binary
    if legend_file and help_file:
        try:
            with open(legend_file, 'r') as f:
                legends = [f.read()]
            with open(help_file, 'r') as f:
                help_text = f.read()
            valid_flags, help_error = extract_flags_from_help(help_text=help_text)
        except Exception as e:
            print(json.dumps({
                'status': 'error',
                'message': f'Failed to read synthetic test files: {e}'
            }))
            sys.exit(1)
    else:
        # Normal mode: run the binary
        if not binary_path:
            print("Usage: python3 legenddriftcheck.py <binary_path> [corpus_path]", file=sys.stderr)
            print("   or: python3 legenddriftcheck.py --legend-file=FILE --help-file=FILE", file=sys.stderr)
            sys.exit(1)

        corpus_path = corpus_path or os.getcwd()

        if not os.path.exists(binary_path):
            print(f"Error: Binary not found: {binary_path}", file=sys.stderr)
            sys.exit(1)

        if not os.path.isdir(corpus_path):
            print(f"Error: Corpus not found: {corpus_path}", file=sys.stderr)
            sys.exit(1)

        # Extract valid flags from --help
        valid_flags, help_error = extract_flags_from_help(binary_path)
        if help_error:
            print(f"Warning: {help_error}", file=sys.stderr)

        # Run verb suite to collect legends
        legends = run_verb_suite(binary_path, corpus_path)

    if not legends:
        print(json.dumps({
            'status': 'error',
            'message': 'No legends found in output'
        }))
        sys.exit(1)

    # Extract all flag tokens from all legends
    all_tokens = []
    legend_texts = {}  # store legend text snippets for each token (for debugging)
    for i, legend in enumerate(legends):
        tokens = extract_flag_tokens_from_legend(legend)
        for token in tokens:
            if token not in legend_texts:
                legend_texts[token] = []
            # Extract a snippet around the token
            idx = legend.find(token)
            if idx >= 0:
                start = max(0, idx - 50)
                end = min(len(legend), idx + len(token) + 50)
                snippet = legend[start:end].replace('\n', ' ')
                legend_texts[token].append(snippet)
        all_tokens.extend(tokens)

    all_tokens = list(set(all_tokens))  # deduplicate

    # Categorize findings
    findings = categorize_findings(all_tokens, valid_flags)

    # Determine verdict
    has_phantom = len(findings['phantom']) > 0
    has_spelling = len(findings['spelling_issues']) > 0

    result = {
        'binary': os.path.basename(binary_path or "synthetic").split()[0] if binary_path else "synthetic",
        'corpus': os.path.basename(corpus_path) if corpus_path else "synthetic",
        'stats': {
            'help_flags_count': len(valid_flags),
            'legends_found': len(legends),
            'flag_tokens_extracted': len(all_tokens),
            'phantom_flags': len(findings['phantom']),
            'spelling_issues': len(findings['spelling_issues']),
        },
        'findings': {
            'phantom_flags': findings['phantom'],
            'spelling_mismatches': findings['spelling_issues'],
            'valid_references': findings['valid']
        },
        'legend_text_samples': legend_texts,
        'verdict': 'CLEAN' if (not has_phantom and not has_spelling) else 'DIRTY'
    }

    print(json.dumps(result, indent=2))
    return 0 if result['verdict'] == 'CLEAN' else 1


if __name__ == '__main__':
    sys.exit(main())
