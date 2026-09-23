#!/usr/bin/env python3
# crossctx_rater.py — the RATER-STAGE driver of the cross-context external-rate pre-registration
# (docs/research/cross-context-external-rate.md §6–§8; amendment 1, 2026-09-23, before any data).
#
# WHAT THIS IS. Everything between the mechanical stage (crossctx_sites.py) and the reported table, so that
# no packet is ever hand-assembled and no label is ever hand-transcribed — the two places blinding fails:
#   * build_packet   — R2: what one rater sees for one row. Carries a packet INDEX, never the instance_id, the
#                      repository name field or anything from §1/§2/§3.4/§9 of the note; the frozen brief
#                      (crossctx_rater_brief.md) is referenced by SHA-256 so the run can prove which wording
#                      the raters read.
#   * validate_label — R4/R6: the JSON schema every rater answer must satisfy; over-budget answers become
#                      UNDECIDED; a CROSS answer that names an external contract becomes LOCAL (§3.3).
#   * verify_second_site — F1: a CROSS answer must name a `path:definition` that EXISTS at base_commit and is
#                      distinct from the primary site, else it is downgraded to UNDECIDED and counted in the
#                      sub-bucket UNVERIFIED-SECOND-SITE. Whether the fix also edited that second site is
#                      recorded (second_site_edited), not penalised: in the MULTI strata the second site
#                      usually IS one the fix touched, and that is the cross-context case, not a defect of it.
#   * ingest         — R6: two raters' validated answers → one label per packet, with sub-buckets and flags.
#   * kappa_three_way / kappa_binary — R7.
#   * sensitivities, outcome_table — §7/§8, from the manifest and the ingested labels only.
#
# It reads no Loc-Bench data itself: rows, sites and the pre-fix tree are handed in by the caller. Nothing
# here has run on data; test_crossctx_rater.py is synthetic. Standard library only, no pytest dependency.
import collections, hashlib, json, os, re

import crossctx_sites as S

HERE = os.path.dirname( os.path.abspath( __file__ ) )
BRIEF_PATH = os.path.join( HERE, "crossctx_rater_brief.md" )

VERDICTS = ( "CROSS", "LOCAL", "UNDECIDED", "NOT-A-DEFECT" )
RELATIONS = ( "caller-callee-contract", "table-roster-registration", "constant-format-schema-elsewhere",
              "sibling-or-clone-must-agree", "mirror-parity-copy", "test-not-exercising-claim", "other" )
CONFIDENCE = ( "sure", "unsure" )
TREE_COMMANDS = ( "ls-tree", "show", "grep" )                     # R3: the only reads a rater may issue
# Words that must NOT appear in anything a rater is shown (F2). The brief and every packet are checked.
LEAK_WORDS = ( "88%", "STARK", "THIN", "INDETERMINATE", "internal arm", "internal rate", "bias", "roadmap",
               "instance_id", "hypothesis", "62%", "17–38", "17-38" )

def brief_sha256( path=BRIEF_PATH ):
    return hashlib.sha256( open( path, "rb" ).read() ).hexdigest()

def leaks( text ):
    """The LEAK_WORDS present in `text` (case-sensitive for the percentages and verdict names, which is what
    a rater would recognise). Empty means clean."""
    return [ w for w in LEAK_WORDS if w in text ]

# ── R2: the packet ────────────────────────────────────────────────────────────────────────────────────────
def build_packet( packet_index, row, site_result, read_base, brief_digest ):
    """One rater's view of one row. `row` is the Loc-Bench row (only problem_statement, patch and — when the
    dataset carries one — test_patch are read from it); `site_result` is crossctx_sites.sites_for_row's
    result; `read_base(path)` returns the pre-fix text at base_commit. The packet never carries the
    instance_id or the repo field: the driver keeps `packet_index -> instance_id` in a separate file."""
    sites = []
    for path, qual in sorted( site_result.sites ):
        text = read_base( path )
        body = None
        if text is not None and qual not in ( "<file>", "<unparsed>" ):
            try:
                spans = { s.qualname: s for s in S.python_definition_spans( text ) }
                if qual in spans:
                    sp = spans[ qual ]
                    body = "\n".join( text.splitlines()[ sp.start - 1 : sp.end ] )
                elif qual == "<module>":
                    body = text
            except SyntaxError:
                body = text
        elif text is not None:
            body = text
        sites.append( dict( site="%s:%s" % ( path, qual ), pre_fix_text=body ) )
    packet = dict(
        packet_index = packet_index,
        brief_sha256 = brief_digest,
        problem_statement = row.get( "problem_statement", "" ),
        patch = row.get( "patch", "" ),
        sites = sites,
        tree_access = dict( commands=list( TREE_COMMANDS ), read_budget=S.FROZEN[ "rater_tool_budget" ],
                            output_token_budget=S.FROZEN[ "rater_output_tokens" ], network=False ),
        answer_schema = ANSWER_SCHEMA,
    )
    if row.get( "test_patch" ):
        packet[ "test_patch" ] = row[ "test_patch" ]
    found = leaks( json.dumps( packet, ensure_ascii=False ) )
    if found:
        raise ValueError( "packet %d would leak %s" % ( packet_index, found ) )
    return packet

ANSWER_SCHEMA = dict(
    packet_index = "int — copied from the packet",
    primary_site = "str `path:definition` from the packet's site list, or null when verdict is NOT-A-DEFECT",
    verdict = "one of %s" % list( VERDICTS ),
    second_site = "str `path:definition` that exists in the repository at the pre-fix commit — required when verdict is CROSS, else null",
    relation = "one of %s — required when verdict is CROSS, else null" % list( RELATIONS ),
    external_contract = "bool — true when the only 'second site' is outside the repository (a library, an HTTP API, a language version)",
    confidence = "one of %s" % list( CONFIDENCE ),
    tool_calls = "int — tree reads you issued for this packet",
    output_tokens = "int — as reported by your runtime, or 0 if unknown",
    note = "str — free text, optional",
)
_SITE_RE = re.compile( r"^[^:\s]+:[^\s]+$" )

# ── R4/R6: validate one answer ────────────────────────────────────────────────────────────────────────────
def validate_label( obj ):
    """Normalise one rater's JSON answer. Raises ValueError on a schema violation (the driver records the
    packet as UNDECIDED with flag `schema_error`, never repairs it by hand). Applies two registered
    downgrades mechanically: over-budget → UNDECIDED (`budget_exceeded`); CROSS with external_contract →
    LOCAL (`external_contract`, §3.3)."""
    if not isinstance( obj, dict ):
        raise ValueError( "answer is not an object" )
    out = dict( flags=set() )
    try:
        out[ "packet_index" ] = int( obj[ "packet_index" ] )
    except ( KeyError, TypeError, ValueError ):
        raise ValueError( "packet_index missing or not an int" )
    v = obj.get( "verdict" )
    if v not in VERDICTS:
        raise ValueError( "verdict %r not in %s" % ( v, VERDICTS ) )
    out[ "verdict" ] = v
    ps = obj.get( "primary_site" )
    if v != "NOT-A-DEFECT" and not ( isinstance( ps, str ) and _SITE_RE.match( ps ) ):
        raise ValueError( "primary_site must be `path:definition` unless NOT-A-DEFECT" )
    out[ "primary_site" ] = ps if isinstance( ps, str ) else None
    ss = obj.get( "second_site" )
    rel = obj.get( "relation" )
    if v == "CROSS":
        if not ( isinstance( ss, str ) and _SITE_RE.match( ss ) ):
            raise ValueError( "a CROSS verdict needs second_site as `path:definition`" )
        if rel not in RELATIONS:
            raise ValueError( "a CROSS verdict needs relation in %s" % ( RELATIONS, ) )
    out[ "second_site" ] = ss if isinstance( ss, str ) else None
    out[ "relation" ] = rel if rel in RELATIONS else None
    if obj.get( "confidence" ) not in CONFIDENCE:
        raise ValueError( "confidence not in %s" % ( CONFIDENCE, ) )
    out[ "confidence" ] = obj[ "confidence" ]
    out[ "external_contract" ] = bool( obj.get( "external_contract", False ) )
    try:
        calls = int( obj.get( "tool_calls", 0 ) ); toks = int( obj.get( "output_tokens", 0 ) )
    except ( TypeError, ValueError ):
        raise ValueError( "tool_calls / output_tokens must be ints" )
    out[ "tool_calls" ], out[ "output_tokens" ] = calls, toks
    out[ "note" ] = str( obj.get( "note", "" ) )
    if calls > S.FROZEN[ "rater_tool_budget" ] or toks > S.FROZEN[ "rater_output_tokens" ]:
        out[ "verdict" ] = "UNDECIDED"; out[ "flags" ].add( "budget_exceeded" )
    if out[ "verdict" ] == "CROSS" and out[ "external_contract" ]:
        out[ "verdict" ] = "LOCAL"; out[ "flags" ].add( "external_contract" )
    return out

# ── F1: verify the second site against the pre-fix tree ───────────────────────────────────────────────────
def verify_second_site( label, read_base, edited_sites ):
    """For a CROSS label: the named second site must (a) parse as `path:definition`, (b) name a file that
    exists at base_commit, (c) name a definition that exists in that file (`<module>` and `<file>` are
    accepted when the file exists; any definition is accepted in a file that does not parse), and (d) differ
    from the primary site. Failing any → verdict UNDECIDED, flag `unverified_second_site`. Records
    `second_site_edited` (the fix touched that site too) as information, not as a downgrade."""
    if label[ "verdict" ] != "CROSS":
        return label
    ss = label[ "second_site" ]
    path, _, qual = ss.partition( ":" )
    ok = bool( path and qual ) and ss != label[ "primary_site" ]
    text = read_base( path ) if ok else None
    if text is None:
        ok = False
    elif qual not in ( "<module>", "<file>" ):
        try:
            ok = qual in { s.qualname for s in S.python_definition_spans( text ) }
        except SyntaxError:
            ok = True
    if not ok:
        label[ "verdict" ] = "UNDECIDED"; label[ "flags" ].add( "unverified_second_site" )
        return label
    if ss in edited_sites:
        label[ "flags" ].add( "second_site_edited" )
    return label

# ── R6: ingest ────────────────────────────────────────────────────────────────────────────────────────────
Record = collections.namedtuple( "Record", "packet_index a b label sub flags a_second b_second" )

def ingest( answers_a, answers_b, read_base_for, edited_sites_for ):
    """answers_* = {packet_index: raw JSON answer}; read_base_for(packet_index) → read_base callable for that
    packet's tree; edited_sites_for(packet_index) → the fix's site spellings. Returns [Record] for every
    packet either rater answered. A missing or malformed answer is UNDECIDED with flag `schema_error`."""
    out = []
    for idx in sorted( set( answers_a ) | set( answers_b ) ):
        sides, flags = [], set()
        for raw in ( answers_a.get( idx ), answers_b.get( idx ) ):
            try:
                lab = validate_label( raw )
                lab = verify_second_site( lab, read_base_for( idx ), edited_sites_for( idx ) )
            except ValueError:
                lab = dict( verdict="UNDECIDED", flags={ "schema_error" }, second_site=None )
            flags |= lab[ "flags" ]
            sides.append( lab )
        a, b = sides
        lab = S.row_label( a[ "verdict" ], b[ "verdict" ] )
        if isinstance( lab, tuple ):
            label, sub = lab
            if sub == "UNDECIDED" and "unverified_second_site" in flags:
                sub = "UNVERIFIED-SECOND-SITE"
        else:
            label, sub = lab, None
        out.append( Record( idx, a[ "verdict" ], b[ "verdict" ], label, sub, frozenset( flags ),
                            a.get( "second_site" ), b.get( "second_site" ) ) )
    return out

# ── R7: agreement ─────────────────────────────────────────────────────────────────────────────────────────
def kappa_three_way( records ):
    return S.cohen_kappa( [ S.three_way( r.a ) for r in records ], [ S.three_way( r.b ) for r in records ] )

def kappa_binary( records ):
    both = [ r for r in records if r.a in ( "CROSS", "LOCAL" ) and r.b in ( "CROSS", "LOCAL" ) ]
    if not both:
        return None, 0
    return S.cohen_kappa( [ r.a for r in both ], [ r.b for r in both ] ), len( both )

# ── §7: the estimate and its sensitivities, from manifest + records ───────────────────────────────────────
def strata_from( manifest_rows, records, stratum_of, class_key="mclass" ):
    """manifest_rows = [dict(MANIFEST_COLUMNS)]; records = [Record]; stratum_of(packet_index) → instance_id.
    Builds crossctx_sites.post_stratified_estimate's input with N from the whole manifest under `class_key`
    (mclass, or mclass_collapsed for the moves sensitivity) and labels from the tagged records."""
    by_id = { m[ "instance_id" ]: m for m in manifest_rows }
    strata = { s: dict( N=0, labels=[] ) for s in S.SCOREABLE }
    for m in manifest_rows:
        if m[ class_key ] in strata:
            strata[ m[ class_key ] ][ "N" ] += 1
    for r in records:
        if r.label in ( "CROSS", "LOCAL" ):
            cls = by_id[ stratum_of( r.packet_index ) ][ class_key ]
            if cls in strata:
                strata[ cls ][ "labels" ].append( r.label )
    return strata

def file_grain( records, primary_of ):
    """§7 sensitivity: a CROSS whose second site (both raters) lies in the PRIMARY site's file is LOCAL."""
    out = []
    for r in records:
        if r.label == "CROSS" and r.a_second and r.b_second:
            pf = primary_of( r.packet_index ).split( ":", 1 )[ 0 ]
            if r.a_second.split( ":", 1 )[ 0 ] == pf and r.b_second.split( ":", 1 )[ 0 ] == pf:
                out.append( r._replace( label="LOCAL" ) ); continue
        out.append( r )
    return out

def unedited_second_site_only( records ):
    """§7 lower bound: a CROSS whose second site (either rater's) the fix ALSO edited is counted as LOCAL, so only
    CROSS rows whose second site needed no edit remain CROSS. Closes the MULTI-row gameability (naming any other
    edited site passes verification) from below; the primary estimate keeps them CROSS, as §3.3 says."""
    return [ r._replace( label="LOCAL" ) if r.label == "CROSS" and "second_site_edited" in r.flags else r for r in records ]

def second_site_edited_count( records ):
    return sum( 1 for r in records if r.label == "CROSS" and "second_site_edited" in r.flags )

def resolve_disagreements( records, toward ):
    return [ r._replace( label=toward, sub=None ) if r.sub == "DISAGREE" else r for r in records ]

def untagged_share( records ):
    return sum( 1 for r in records if r.label == "UNTAGGED" ) / float( len( records ) ) if records else 0.0

def sub_buckets( records ):
    return collections.Counter( r.sub for r in records if r.label == "UNTAGGED" )

# ── §8: the table every outcome fills ─────────────────────────────────────────────────────────────────────
def outcome_table( manifest_rows, records, stratum_of, primary_of, fingerprint_counts, fingerprint_ok, m8_recall, m8_ok,
                   manifest_digest, brief_digest, transcript_digests, rater_families, enlargement_used=False ):
    classes = collections.Counter( m[ "mclass" ] for m in manifest_rows )
    strata = strata_from( manifest_rows, records, stratum_of )
    est = S.post_stratified_estimate( strata )
    k3 = kappa_three_way( records ) if records else None
    kb, nb = kappa_binary( records ) if records else ( None, 0 )
    U = untagged_share( records )
    verdict, clause = S.decision( est[ "lo" ], est[ "hi" ], kb if kb is not None else 0.0, U, fingerprint_ok, m8_ok )
    lines = [ "%d rows  (manifest %s; brief %s; enlargement %s)" % ( len( manifest_rows ), manifest_digest[ :16 ], brief_digest[ :16 ],
                                                                        "USED (second pass, offset k//2)" if enlargement_used else "not used" ) ]
    for c in S.EXCLUDED:
        lines.append( "  %-22s %d" % ( c, classes[ c ] ) )
    lines.append( "  scoreable N            %d" % sum( classes[ s ] for s in S.SCOREABLE ) )
    per_stratum_records = collections.defaultdict( list )
    by_id = { m[ "instance_id" ]: m for m in manifest_rows }
    for r in records:
        per_stratum_records[ by_id[ stratum_of( r.packet_index ) ][ "mclass" ] ].append( r )
    for s in S.SCOREABLE:
        rs = per_stratum_records[ s ]
        c = collections.Counter( r.label for r in rs )
        subs = sub_buckets( rs )
        lines.append( "    %-22s N=%-4d sampled %-4d CROSS %-3d LOCAL %-3d UNTAGGED %d (%s)" % (
            s, classes[ s ], len( rs ), c[ "CROSS" ], c[ "LOCAL" ], c[ "UNTAGGED" ],
            "/".join( "%s %d" % kv for kv in sorted( subs.items() ) ) or "-" ) )
    lines.append( "  fingerprint (legacy)   %s  [%s]" % ( fingerprint_counts, "pass" if fingerprint_ok else "FAIL" ) )
    lines.append( "  M8 gold recall         %s  [%s]" % ( "%.3f" % m8_recall if m8_recall is not None else "n/a", "pass" if m8_ok else "FAIL" ) )
    lines.append( "  kappa                  3-way %s, binary %s over n=%d  [%s]" % (
        "%.3f" % k3 if k3 is not None else "n/a", "%.3f" % kb if kb is not None else "n/a", nb,
        S.kappa_verdict( kb ) if kb is not None else "n/a" ) )
    lines.append( "  P (post-stratified)    %s  U = %.3f  dropped strata: %s" % (
        "%.3f [%.3f, %.3f]" % ( est[ "point" ], est[ "lo" ], est[ "hi" ] ) if est[ "point" ] is not None else "n/a", U, est[ "dropped" ] or "-" ) )
    sens = {}
    sens[ "file-grain" ] = S.post_stratified_estimate( strata_from( manifest_rows, file_grain( records, primary_of ), stratum_of ) )
    sens[ "moves-collapsed" ] = S.post_stratified_estimate( strata_from( manifest_rows, records, stratum_of, "mclass_collapsed" ) )
    no_ol = [ r for r in records if "otherlang" not in by_id[ stratum_of( r.packet_index ) ][ "flags" ].split( "," ) ]
    sens[ "otherlang-dropped" ] = S.post_stratified_estimate( strata_from( manifest_rows, no_ol, stratum_of ) )
    sens[ "disagree->CROSS" ] = S.post_stratified_estimate( strata_from( manifest_rows, resolve_disagreements( records, "CROSS" ), stratum_of ) )
    sens[ "disagree->LOCAL" ] = S.post_stratified_estimate( strata_from( manifest_rows, resolve_disagreements( records, "LOCAL" ), stratum_of ) )
    sens[ "unedited-second-site-only" ] = S.post_stratified_estimate( strata_from( manifest_rows, unedited_second_site_only( records ), stratum_of ) )
    tagged = [ r for r in records if r.label in ( "CROSS", "LOCAL" ) ]
    unw = sum( 1 for r in tagged if r.label == "CROSS" ) / float( len( tagged ) ) if tagged else None
    lines.append( "  sensitivities          " + "  ".join( "%s %s" % ( k, "%.3f" % v[ "point" ] if v[ "point" ] is not None else "n/a" )
                                                          for k, v in sens.items() ) + "  unweighted %s" % ( "%.3f" % unw if unw is not None else "n/a" ) )
    lines.append( "  second_site_edited     %d CROSS rows whose second site the fix also edited (kept CROSS in P; LOCAL in the unedited-second-site-only lower bound)"
                  % second_site_edited_count( records ) )
    n_tdo = sum( 1 for m in manifest_rows if "test_dir_only" in m[ "flags" ].split( "," ) )
    lines.append( "  TEST-ONLY by dir-rule  %d rows (bound: unrated; would enter the denominator at 0%%..100%% CROSS)" % n_tdo )
    ic, icc = S.internal_comparator(), S.internal_comparator( S.INTERNAL_CHAIN_CODE_ONLY )
    lines.append( "  internal               %d/%d = %.1f%% [%.1f, %.1f]; code-only %d/%d = %.1f%% [%.1f, %.1f]" % (
        ic[ "cross" ], ic[ "tagged" ], 100 * ic[ "rate" ], 100 * ic[ "lo" ], 100 * ic[ "hi" ],
        icc[ "cross" ], icc[ "tagged" ], 100 * icc[ "rate" ], 100 * icc[ "lo" ], 100 * icc[ "hi" ] ) )
    if est[ "point" ] is not None:
        lines.append( "  contrast               internal - P = %.3f  [%.3f, %.3f]; code-only - P = %.3f  [%.3f, %.3f]" % (
            ic[ "rate" ] - est[ "point" ], ic[ "lo" ] - est[ "hi" ], ic[ "hi" ] - est[ "lo" ],
            icc[ "rate" ] - est[ "point" ], icc[ "lo" ] - est[ "hi" ], icc[ "hi" ] - est[ "lo" ] ) )
    pair = tuple( rater_families )
    independence = "two model families" if pair == tuple( S.FROZEN[ "rater_families" ] ) else \
                   ( "FALLBACK pair: one family, two generations — WEAKER independence, kappa is within-family" if pair == tuple( S.FROZEN[ "rater_families_fallback" ] )
                     else "UNREGISTERED pair" )
    lines.append( "  raters                 %s (%s); transcripts %s" % ( ", ".join( pair ), independence, ", ".join( d[ :16 ] for d in transcript_digests ) or "none" ) )
    lines.append( "  decision (§9)          %s — %s" % ( verdict, clause ) )
    return "\n".join( lines ), dict( verdict=verdict, clause=clause, estimate=est, kappa3=k3, kappa_binary=kb, n_binary=nb, U=U, sensitivities=sens )
