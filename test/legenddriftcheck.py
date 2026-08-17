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

    Four patterns:
    1. Explicit flag references like "--for" or "--grep"
    2. Flag=value patterns (e.g., "rank_by=churn")
    3. Quoted flag references ("--flag" or '--flag')
    4. Prose like "the signatures-only flag" or "the pack-task lens"
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
    }

    for match in re.finditer(
        r'\b(?:the\s+)?([a-z][a-z0-9\-]*(?:-[a-z0-9\-]*)*)\s+(?:flag|lens|verb|option)\b',
        legend_text,
        re.IGNORECASE
    ):
        word = match.group(1)
        # Only include if it looks like a flag name (has hyphens or appears in help references)
        if '-' in word:
            candidate = f"--{word}"
            if candidate not in allowlist:
                tokens.add(candidate)

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
