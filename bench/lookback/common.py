#!/usr/bin/env python3
# common.py — the FROZEN constants of the M1 look-back measurement (docs: bench/lookback/README.md) and the
# small stdlib helpers every module shares (git runner, hashing, the product-source rule).
#
# Every threshold, regex, word list, salt, window and path rule the pre-registration names lives HERE and
# nowhere else, and each one is pinned by a synthetic unit test (test_lookback.py). Changing a value after
# the registration is frozen is an amendment (dated, appended), never a quiet edit.
#
# Stdlib only. Deterministic: no clock reads inside any computation, no unseeded randomness, every
# iteration over a set is sorted first.
import hashlib, os, re, subprocess

# ── population (§2) ─────────────────────────────────────────────────────────────────────────────────────
SELECTION_SALT = "m1-lookback-2026-09"             # §2 main hash order: sha256(SALT + "|" + owner/name)
SD_PILOT_SALT = "m1-lookback-sdpilot-2026-09"      # the out-of-sample SD pilot's own order (never the main salt)

# stratum -> the GitHub search `language:` qualifiers pooled into it
STRATA = {
    "cpp": ( "C", "C++" ),
    "python": ( "Python", ),
    "typescript": ( "TypeScript", ),
    "go": ( "Go", ),
    "java": ( "Java", ),
    "rust": ( "Rust", ),
}
STRATUM_ORDER = ( "cpp", "python", "typescript", "go", "java", "rust" )

MIN_STARS = 1000
CREATED_ON_OR_BEFORE = "2019-12-31"
FIRST_COMMIT_ON_OR_BEFORE = "2019-12-31T23:59:59Z"
MIN_COMMITS = 3000
MIN_AUTHORS_2024_2025 = 20
AUTHORS_SINCE, AUTHORS_UNTIL = "2024-01-01T00:00:00Z", "2025-12-31T23:59:59Z"
MIN_PRODUCT_FILES, MAX_PRODUCT_FILES = 100, 20000
MAX_REPO_KB = 2 * 1024 * 1024                      # 2 GB, GitHub's diskUsage is in KB
ROUTE_A_MIN_BUG_ISSUES_2025 = 50
ROUTE_A_MIN_LINKED_FRACTION = 0.30
ROUTE_B_MIN_CC_FRACTION = 0.70
YEAR_2025 = ( "2025-01-01T00:00:00Z", "2025-12-31T23:59:59Z" )
PICKS_PER_STRATUM = 5                              # first 4 analysed, 5th sealed hold-out

# OSI-approved SPDX ids GitHub reports (licenceInfo.spdxId). NOASSERTION / other / null never qualify.
OSI_SPDX = frozenset( """
0BSD AFL-3.0 AGPL-3.0 Apache-2.0 APSL-2.0 Artistic-2.0 BSD-1-Clause BSD-2-Clause BSD-2-Clause-Patent BSD-3-Clause
BSD-3-Clause-Clear BSL-1.0 CDDL-1.0 CECILL-2.1 ECL-2.0 EPL-1.0 EPL-2.0 EUPL-1.1 EUPL-1.2 GPL-2.0 GPL-3.0 ISC
LGPL-2.1 LGPL-3.0 LPPL-1.3c MIT MIT-0 MPL-2.0 MS-PL MS-RL MulanPSL-2.0 NCSA OFL-1.1 OSL-3.0 PostgreSQL UPL-1.0
Unlicense Vim Zlib
""".split() )

# ── T and the windows (§3) ──────────────────────────────────────────────────────────────────────────────
# (k, cutoff D_k inclusive 23:59:59 UTC, window end inclusive)
WINDOWS = (
    ( 1, "2024-12-31T23:59:59Z", "2025-06-30T23:59:59Z" ),
    ( 2, "2025-06-30T23:59:59Z", "2025-12-31T23:59:59Z" ),
    ( 3, "2025-12-31T23:59:59Z", "2026-06-30T23:59:59Z" ),
)
LOOKBACK_MONTHS = 12                               # CHURN/PRIOR look-back, ripwire's own 12mo window
EVENT_FLOOR = 10                                   # §4.2: < 10 FIXED units in a (repo, window) -> dropped

# ── labels (§4.1) ───────────────────────────────────────────────────────────────────────────────────────
BUG_LABEL_WORDS = frozenset( ( "bug", "defect", "regression", "crash" ) )
BUG_LABEL_VETO = frozenset( ( "not", "feature", "enhancement", "docs", "question", "invalid", "wontfix" ) )
LINK_RE = re.compile( r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+#(\d+)\b", re.I )
ROUTE_B_RE = re.compile( r"^fix(\([^)]*\))?!?:\s" )
ROUTE_B_SCOPE_VETO = frozenset( ( "docs", "doc", "ci", "build", "chore", "test", "tests", "deps", "style", "lint", "typo" ) )
KEYWORD_RE = re.compile( r"\bfix(e[sd])?\b|\bbug(s|fix(e[sd])?)?\b|\bcrash(e[sd])?\b|\bregression(s)?\b", re.I )
KEYWORD_VETO_RE = re.compile( r"\b(typo|docs?|readme|changelog|lint|format(ting)?|ci)\b", re.I )
CONVENTIONAL_RE = re.compile( r"^[A-Za-z]+(\([^)\n]*\))?!?: \S" )  # route-B eligibility: any CC type

# ── metrics (§5/§6) ─────────────────────────────────────────────────────────────────────────────────────
RECALL_AT = 0.20
BOOTSTRAP_SEED = 20260926
BOOTSTRAP_RESAMPLES = 10000
MARGIN_M = 0.05
DELTA_SIMPLER = 0.03
SIGN_CONSISTENCY = 0.60
SIMPLICITY_ORDER = ( "CCX", "FANIN", "HOT", "CHURN", "HOTFN", "PRIOR" )

# ── health floors (§4.3) ────────────────────────────────────────────────────────────────────────────────
PARSE_FLOOR, JOIN_FLOOR, CCX_FLOOR = 0.95, 0.90, 0.95
JOIN_LINE_SLACK = 3
RIPWIRE_VERSION = "0.6.4"

# ── product source (§1) ─────────────────────────────────────────────────────────────────────────────────
STRATUM_EXTS = {
    "cpp": ( ".c", ".h", ".cc", ".cpp", ".cxx", ".c++", ".hpp", ".hh", ".hxx", ".h++", ".ipp", ".inl", ".tcc" ),
    "python": ( ".py", ),
    "typescript": ( ".ts", ".tsx", ".mts", ".cts" ),
    "go": ( ".go", ),
    "java": ( ".java", ),
    "rust": ( ".rs", ),
}
# a path with ANY of these directory segments (case-insensitive) is not product source
NON_PRODUCT_DIRS = frozenset( """
test tests testing __tests__ __test__ __mocks__ spec specs testdata test_data test-data testsuite testsuites
fixture fixtures mock mocks bench benches benchmark benchmarks perf example examples sample samples demo demos
doc docs documentation vendor vendored third_party thirdparty third-party 3rdparty external externals extern
node_modules site-packages .github
""".split() )
# a basename matching any of these is not product source
NON_PRODUCT_NAME_RE = re.compile( r"""(?ix)
    ( ^test_.*\.py$ | .*_test\.py$ | ^conftest\.py$ | .*_tests?\.go$ | .*(Test|Tests|IT|TestCase)\.java$
    | .*\.(test|spec)\.(ts|tsx|mts|cts)$ | .*\.d\.ts$ | ^tests?\.rs$ | .*_tests?\.rs$
    | ^test_.*\.(c|cc|cpp|cxx)$ | .*_(unit)?tests?\.(c|cc|cpp|cxx|h|hpp)$ | .*_pb2(_grpc)?\.py$ | .*\.pb\.(go|h|cc)$
    | .*\.generated\.\w+$ | .*_generated\.\w+$ )""" )
GENERATED_RE = re.compile( r"(?i)(@generated|do not edit|auto-?generated|generated by|code generated)" )
GENERATED_HEAD_LINES = 5


def stratum_of_path( path ):
    """The stratum whose extension set owns this path, or None."""
    low = path.lower()
    for stratum in STRATUM_ORDER:
        if low.endswith( STRATUM_EXTS[ stratum ] ):
            return stratum
    return None


def is_product_path( path, stratum ):
    """§1's frozen path+name rule (the generated-marker half needs the blob; see is_generated_head)."""
    if not path.lower().endswith( STRATUM_EXTS[ stratum ] ):
        return False
    parts = path.split( "/" )
    for seg in parts[ :-1 ]:
        if seg.lower() in NON_PRODUCT_DIRS:
            return False
    return not NON_PRODUCT_NAME_RE.match( parts[ -1 ] )


def is_generated_head( text ):
    head = "\n".join( text.split( "\n", GENERATED_HEAD_LINES )[ :GENERATED_HEAD_LINES ] )
    return bool( GENERATED_RE.search( head ) )


def salted_rank( salt, name ):
    return hashlib.sha256( ( salt + "|" + name.lower() ).encode() ).hexdigest()


def sha256_file( path ):
    h = hashlib.sha256()
    with open( path, "rb" ) as fh:
        for block in iter( lambda: fh.read( 1 << 20 ), b"" ):
            h.update( block )
    return h.hexdigest()


def git( repo, *args, check=True, text=True ):
    """Run git in `repo` with a fixed, config-independent environment (no pager, no user config, C locale)."""
    env = dict( os.environ, GIT_PAGER="cat", LC_ALL="C", GIT_CONFIG_NOSYSTEM="1", HOME=os.environ.get( "HOME", "/" ) )
    for k in ( "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE" ):
        env.pop( k, None )
    out = subprocess.run( [ "git", "-C", repo, "-c", "core.quotepath=off", "-c", "diff.renames=true", *args ],
                          capture_output=True, env=env, text=text, errors="replace" if text else None )
    if check and out.returncode != 0:
        raise RuntimeError( "git %s failed rc=%d: %s" % ( " ".join( args[ :3 ] ), out.returncode, out.stderr[ :400 ] ) )
    return out.stdout
