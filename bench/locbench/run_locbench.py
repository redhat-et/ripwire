#!/usr/bin/env python3
# run_locbench.py — measure ripwire's code-LOCALIZATION accuracy on a public benchmark, honestly.
#
# WHAT THIS IS. LocAgent (arXiv 2503.09089, ACL'25) turned "given a GitHub issue, find the files/
# functions to edit" into a scored subfield: file-level Acc@k + function-level Acc@k over a public
# set of (issue text, repo@commit, gold edit locations). This harness runs ripwire as the localizer
# — one deterministic, $0, sub-second `ripwire <repo> --for="<issue>"` per instance — parses the
# ranked symbols out of its XML, and scores them against the gold `edit_functions`. It is the
# retrieval-proxy's (bench/ANSWERQUALITY.md §1) public-benchmark sibling: same LLM-free, deterministic,
# leave-nothing-out posture, but on an EXTERNAL scoreboard with the field's own metric definitions.
#
# HONESTY CONTRACT (house rule — publish the losses with the wins):
#   * ripwire is a deterministic ranker; LocAgent/SweRank are LLM/rerank agents. This measures the
#     $0 deterministic FLOOR, not parity — see README.md "honest comparison".
#   * `added_functions` (patch ADDS them; they do not exist at base_commit) are structurally
#     un-findable by ANY static localizer → reported apart, never silently folded into the wins.
#   * PARSE COVERAGE is reported as its own number: a gold function ripwire's parser never emitted is
#     an automatic miss, and we say how many there were rather than hiding them in the denominator.
#   * Non-Python gold (ripwire speaks Py/TS/Go/Rust/C++/Swift/ObjC) is skipped with a count.
#
# ARMS (all deterministic; same parse, same scoring):
#   for     — `ripwire <repo> --for="<title+body>"`   the flagship task lens (routed by default)
#   query   — `ripwire <repo> --query="<title+body>"` pure lexical BM25 (no compose/quality framing)
#   anchor  — `ripwire <repo> --for=... --anchor`      EXPERIMENTAL lexically-anchored graph expansion
# MATCHED-BUDGET CONTROL ARMS (PREREG_PLACEBO.md; derived from the `for` answer, all EXACTLY the same bytes —
# the production --for payload's size — and in the identical --format=candidates format):
#   for-matched     — ripwire's own --for rows, in ripwire's order, cut to the budget (the treatment)
#   placebo         — ripwire-rendered rows drawn (seeded) from files the real answer does NOT name
#   placebo-shuffle — the for-matched rows permuted (same bytes, same content, no order)
#   lexical         — file-level BM25 over whole files (identifier-split), each file's rows in universe order
#   --emit-payloads=DIR freezes every arm's payload + a sha256 manifest per instance for an agent round.
#
# METRICS (match the LocAgent paper's, arXiv 2503.09089 §4.1):
#   file-level     Acc@1 / Acc@5 / Acc@10   — a gold FILE within the top-k ranked files
#   function-level Acc@5 / Acc@10 + MRR      — a gold FUNCTION within the top-k ranked functions
#   parse-coverage — fraction of gold functions ripwire's parser emitted at all (the localizer's ceiling)
#
# REPRODUCE (validation slice, no auth needed — public HF datasets-server JSON API):
#   python3 bench/locbench/run_locbench.py --n 25 --work-dir /tmp/locbench
# FULL SET:
#   python3 bench/locbench/run_locbench.py --n 560 --work-dir /tmp/locbench
# SWE-bench-Lite fallback (gold = files/functions touched by the fix patch):
#   python3 bench/locbench/run_locbench.py --dataset swebench-lite --n 25 --work-dir /tmp/locbench
#
# Deterministic given (dataset, slice, ripwire binary): no LLM, no RNG, stable instance order.
import argparse, hashlib, json, math, os, re, statistics, subprocess, sys, time, urllib.request, urllib.error, urllib.parse, pathlib
import xml.etree.ElementTree as ET

CTX = os.environ.get("RIPWIRE", "ripwire")
ROWS_API = "https://datasets-server.huggingface.co/rows"
DATASETS = {
    "locbench":     ("czlll/Loc-Bench_V1",        "default", "test"),
    "swebench-lite":("princeton-nlp/SWE-bench_Lite","default","test"),
}

# ── dataset access ───────────────────────────────────────────────────────────
def fetch_rows( dataset, config, split, n, cache_dir ):
    # public datasets-server JSON API, paginated (<=100/call), cached to disk so re-runs are offline.
    cache = cache_dir / f"rows_{dataset.replace('/','__')}_{split}_{n}.json"
    if cache.exists():
        return json.loads( cache.read_text() )
    rows, off = [], 0
    while len( rows ) < n:
        length = min( 100, n - len( rows ) )
        url = f"{ROWS_API}?dataset={urllib.parse.quote(dataset)}&config={config}&split={split}&offset={off}&length={length}"
        page = None
        for attempt in range( 5 ):
            try:
                req = urllib.request.Request( url, headers={ "User-Agent": "ripwire-locbench/1.0" } )
                with urllib.request.urlopen( req, timeout=120 ) as r:
                    page = json.load( r )
                break
            except Exception as e:
                print( f"# fetch retry {attempt+1}/5 (offset={off}): {e}", file=sys.stderr )
                time.sleep( 3 * ( attempt + 1 ) )
        if page is None:
            raise RuntimeError( f"datasets-server fetch failed after retries: {url}" )
        batch = [ x["row"] for x in page.get( "rows", [] ) ]
        if not batch: break
        rows.extend( batch ); off += len( batch )
    rows = rows[:n]
    cache.parent.mkdir( parents=True, exist_ok=True )
    cache.write_text( json.dumps( rows ) )
    return rows

# ── gold extraction ──────────────────────────────────────────────────────────
def patch_files( patch ):
    # SWE-bench fallback: gold FILES = the files the fix diff touches.
    return sorted( set( re.findall( r'^\+\+\+ b/(.+)$', patch, re.M ) )
                 | set( re.findall( r'^--- a/(.+)$', patch, re.M ) ) )

def patch_funcs( patch ):
    # SWE-bench fallback: gold FUNCTIONS from Python hunk headers `@@ ... @@ def name(` / `class name`.
    out, cur = [], None
    for line in patch.splitlines():
        m = re.match( r'^\+\+\+ b/(.+)$', line )
        if m: cur = m.group( 1 ); continue
        m = re.match( r'^@@.*@@\s*(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)', line )
        if m and cur: out.append( ( cur, m.group( 1 ) ) )
    return out

def gold_for_instance( inst, dataset ):
    # returns (gold_files:set, gold_funcs:list[(file,name)], added_funcs:list[(file,name)])
    if dataset == "locbench":
        def split_ef( ef ):
            f, _, fn = ef.partition( ":" )
            parts = fn.split( "." ) if fn else []
            return ( f, "::".join( parts[:-1] ), parts[-1] if parts else "" )
        edit  = [ split_ef( e ) for e in inst.get( "edit_functions", [] ) if ":" in e ]
        added = [ split_ef( e ) for e in inst.get( "added_functions", [] ) if ":" in e ]
        files = { f for f, _, _ in edit }
        # also count files touched by patch (some gold files carry only added funcs)
        files |= set( patch_files( inst.get( "patch", "" ) ) )
        return files, edit, added
    else:  # swebench-lite
        patch = inst.get( "patch", "" )
        files = set( patch_files( patch ) )
        funcs = [ ( f, "", n ) for f, n in patch_funcs( patch ) ]
        return files, funcs, []

# ── repo checkout (shallow, per-commit, cached) ──────────────────────────────
def sh( args, timeout=1800, cwd=None ):
    return subprocess.run( args, capture_output=True, text=True, timeout=timeout, cwd=cwd )

def checkout( repo, base_commit, repos_dir, history_depth=1 ):
    # one dir per repo; fetch just the needed commit shallow (GitHub allows want-sha). Marker per sha.
    #
    # history_depth (B3): 1 (the default) is EXACTLY the historical behavior — a depth-1 shallow fetch
    # with zero commit history, which is what every artifact produced before this option existed saw.
    # N>1 deepens the cached shallow clone IN PLACE via `git fetch --deepen=N-1 origin <base_commit>`:
    # the only ref ever fetched is base_commit itself, so the added history is base_commit's OWN
    # ancestors — commits AFTER the base (the "future", including the fix being localized) are
    # unreachable by construction, so there is no leakage. Deepening FAILS CLOSED (returns None → the
    # caller's zero-silent-skip contract aborts the run) rather than silently scoring a shallower repo.
    #
    # COMPARABILITY CONTRACT: any two runs being compared (e.g. a boost-on/boost-off ablation pair) must
    # use the IDENTICAL --history-depth, and the value is recorded in the run header and JSON meta.
    # Deepening a cached clone is MONOTONIC — git cannot cheaply re-shallow it — so a true depth-1 rerun
    # after a deepened run needs a fresh --work-dir. Ancestors of a fixed sha are immutable, so a given
    # (base_commit, history_depth) always yields the same history regardless of when it is fetched.
    dst = repos_dir / repo.replace( "/", "__" )
    marker = dst / f".ripwire_at_{base_commit}"
    depth_marker = dst / f".ripwire_deepened_{history_depth}_at_{base_commit}"
    if not marker.exists():
        if not ( dst / ".git" ).exists():
            dst.mkdir( parents=True, exist_ok=True )
            sh( [ "git", "init", "-q" ], cwd=dst )
            sh( [ "git", "remote", "add", "origin", f"https://github.com/{repo}.git" ], cwd=dst )
        f = sh( [ "git", "fetch", "-q", "--depth", "1", "origin", base_commit ], cwd=dst )
        if f.returncode != 0:
            # fallback: unshallow fetch of the ref, then checkout (rarely needed)
            sh( [ "git", "fetch", "-q", "origin" ], cwd=dst )
        co = sh( [ "git", "checkout", "-q", "-f", base_commit ], cwd=dst )
        if co.returncode != 0:
            co = sh( [ "git", "checkout", "-q", "-f", "FETCH_HEAD" ], cwd=dst )
        sh( [ "git", "clean", "-qfdx" ], cwd=dst )
        if co.returncode != 0:
            return None
        for old in dst.glob( ".ripwire_at_*" ): old.unlink()
        for old in dst.glob( ".ripwire_deepened_*" ): old.unlink()   # depth markers are per-sha too
        marker.write_text( "" )
    if history_depth > 1 and not depth_marker.exists():
        if ( dst / ".git" / "shallow" ).exists():
            d = sh( [ "git", "fetch", "-q", f"--deepen={history_depth - 1}", "origin", base_commit ], cwd=dst, timeout=3600 )
            if d.returncode != 0:
                print( f"# DEEPEN FAIL {repo}@{base_commit}: {(d.stderr or '').strip()[:300]}", file=sys.stderr )
                return None   # fail closed — never silently score a shallower history than requested
        # else: the fallback path above already fetched full history — nothing to deepen
        depth_marker.write_text( "" )
    return dst

# ── ripwire run + parse ──────────────────────────────────────────────────────
def run_ctx( repo_path, flags, timeout=600 ):
    t0 = time.perf_counter()
    r = sh( [ CTX, str( repo_path ) ] + flags, timeout=timeout )
    return r.stdout, ( time.perf_counter() - t0 ), r.returncode

def frozen_partition( repo ):
    # Stable 50/50 REPOSITORY-DISJOINT split independent of dataset order. Hashing the repository avoids
    # training on one issue from the same checkout family later used for held-out acceptance.
    # The salt is part of the benchmark contract: changing it creates a different train/held-out set.
    digest = hashlib.sha256( ( "ripwire-a7-v2\0" + repo.lower() ).encode( "utf-8" ) ).digest()
    return "train" if digest[0] < 128 else "heldout"

def estimated_output_tokens( text ):
    # The repository's measured map calibration is 2.36-2.70 bytes/token. Task-lens XML is similarly
    # signature-dense; use the conservative densest rate so this is a COST CEILING, not fake tokenizer
    # precision. Report bytes beside it so a future tokenizer can rescore the immutable raw quantity.
    return int( math.ceil( len( text.encode( "utf-8" ) ) / 2.36 ) )

FILE_RE = re.compile( r'<f p="([^"]+)">' )
# `<r>` shape (--query / default map): explicit n="name"
S_RE    = re.compile( r'<s\b[^>]*\bn="([^"]+)"' )
# `<sigs>` shape (--for / --anchor): <d ...>signature</d>, name extracted from the signature text
D_RE    = re.compile( r'<d\b[^>]*>(.*?)</d>', re.S )
DOC_RE  = re.compile( r'<doc>.*?</doc>', re.S )

def name_from_sig( sig ):
    sig = DOC_RE.sub( "", sig )
    sig = re.sub( r'<[^>]+>', "", sig )                       # strip any nested tags
    sig = sig.replace( "&amp;", "&" ).replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&quot;", '"' )
    m = re.search( r'\b(?:async\s+)?def\s+([A-Za-z_]\w*)', sig )               # python fn/method
    if m: return m.group( 1 )
    m = re.search( r'\b(?:class|struct|enum|interface|trait|impl|type|fn|func)\s+([A-Za-z_]\w*)', sig )
    if m: return m.group( 1 )
    m = re.search( r'([A-Za-z_]\w*)\s*\(', sig )              # identifier before first '('
    if m: return m.group( 1 )
    ids = re.findall( r'[A-Za-z_]\w*', sig )
    return ids[-1] if ids else ""

def parse_ranked( xml ):
    # returns (ranked_files:list[str] unique-in-order, ranked_syms:list[(file,name)] in output order)
    ranked_files, seen = [], set()
    ranked_syms = []
    # split into per-file segments so a symbol is attributed to its enclosing <f>
    parts = FILE_RE.split( xml )   # [pre, path1, seg1, path2, seg2, ...]
    for i in range( 1, len( parts ), 2 ):
        path, seg = parts[i], parts[i + 1]
        if path not in seen:
            seen.add( path ); ranked_files.append( path )
        if "<s " in seg or "<s>" in seg:                      # <r> shape
            for name in S_RE.findall( seg ):
                ranked_syms.append( ( path, name ) )
        else:                                                 # <sigs> shape
            for sig in D_RE.findall( seg ):
                nm = name_from_sig( sig )
                if nm: ranked_syms.append( ( path, nm ) )
    return ranked_files, ranked_syms

def parse_candidates( xml, repo_path ):
    # ElementTree, not regex: attributes may contain XML escapes and signatures may contain nested-looking
    # punctuation. Paths are made repository-relative by an exact prefix operation (never lstrip("./"),
    # whose character-set semantics corrupt names beginning with dots or slashes).
    root = ET.fromstring( xml )
    if root.tag != "candidates": raise ValueError( f"unexpected root <{root.tag}>" )
    base = os.path.realpath( repo_path )
    out = []
    for c in root.findall( "cand" ):
        raw = c.attrib.get( "p", "" )
        real = os.path.realpath( raw if os.path.isabs( raw ) else os.path.join( base, raw ) )
        path = os.path.relpath( real, base ).replace( os.sep, "/" )
        if path == ".." or path.startswith( "../" ): path = raw.replace( os.sep, "/" )
        out.append( dict( path=path, name=c.attrib.get( "n", "" ), canon=c.attrib.get( "id", "" ),
                          rank=int( c.attrib.get( "r", len(out)+1 ) ) ) )
    return out

# ── scoring ──────────────────────────────────────────────────────────────────
def norm_path( p ):
    while p.startswith( "./" ): p = p[2:]
    return p.replace( "\\", "/" )

def ranked_files_from_candidates( candidates ):
    out, seen = [], set()
    for c in candidates:
        if c["path"] not in seen: seen.add( c["path"] ); out.append( c["path"] )
    return out

def file_ranks( ranked_files, gold_files, universe_files ):
    # Exact relative path first. Basename fallback is allowed ONLY when that basename is unique in the
    # indexed universe; duplicate basenames must never silently credit the wrong directory.
    norm = [ norm_path( f ) for f in ranked_files ]
    counts = {}
    for f in universe_files: counts[os.path.basename( f )] = counts.get( os.path.basename( f ), 0 ) + 1
    out = []
    for g in gold_files:
        ng = norm_path( g ); gb = os.path.basename( ng ); r = None
        for i in range( len( norm ) ):
            if norm[i] == ng or ( counts.get( gb, 0 ) == 1 and os.path.basename( norm[i] ) == gb ):
                r = i; break
        out.append( r )
    return out

def func_ranks( candidates, gold_funcs, universe_files ):
    # Flat global candidate rank. Scoped gold requires the canonical-id suffix; a Class.run edit must not
    # be credited to another class's run method in the same file.
    counts = {}
    for f in universe_files: counts[os.path.basename( f )] = counts.get( os.path.basename( f ), 0 ) + 1
    out = []
    for gf, gs, gn in gold_funcs:
        ngf = norm_path( gf ); gbf = os.path.basename( ngf ); r = None
        for i, c in enumerate( candidates ):
            path_ok = c["path"] == ngf or ( counts.get( gbf, 0 ) == 1 and os.path.basename( c["path"] ) == gbf )
            scope_ok = not gs or c["canon"].endswith( "::" + gs + "::" + gn )
            if path_ok and c["name"] == gn and scope_ok:
                r = i; break
        out.append( r )
    return out

def acc_all_at( ranks, k ):
    # LocAgent Acc@k (strict): ALL gold locations must fall within top-k. Missing (None) -> fails.
    return 1 if ranks and all( r is not None and r < k for r in ranks ) else 0

def first_hit( ranks ):
    hits = [ r for r in ranks if r is not None ]
    return min( hits ) if hits else None

def covered( universe_candidates, gold_funcs, universe_files ):
    ranks = func_ranks( universe_candidates, gold_funcs, universe_files )
    return [ g for g, r in zip( gold_funcs, ranks ) if r is not None ]

# ── matched-budget control arms: placebo + fair lexical baseline (PREREG_PLACEBO.md) ──
#
# WHY. METHODOLOGY.md §8: a ranking win and a "having a tool answer at all" win raise the same number. The
# only way to tell them apart is an arm of the SAME FORMAT and the SAME BYTE COST that carries no ranking
# signal. Bellam (arXiv 2610.33958) ran that arm and found the graph added little; this is the replication.
#
# THE CONTRACT every derived arm keeps (gated by test/locbenchplacebocheck.sh):
#   * format-identical: the same `<!-- … -->` legend bytes, the same `<candidates …>` root attribute NAMES,
#     and every row is a `<cand>` that ripwire itself rendered (taken from the coverage-universe export),
#     with only r=, s= and the final row's <sig> text rewritten;
#   * byte-exact: every derived arm is EXACTLY `target` bytes (UTF-8), or construction raises
#     PlaceboUnbuildable — the run aborts or counts it; it never scores a near-miss silently;
#   * gold-blind: no builder takes gold as an argument. The unrelated placebo excludes the files the REAL
#     answer names (so it cannot be the real answer re-ordered), never the gold files (so its chance hit
#     rate is the honest chance rate);
#   * deterministic: every permutation is a sort on sha256(salt, instance, row identity) — no RNG state.
PLACEBO_SALT = "ripwire-placebo-v1"
DERIVED_ARMS = ( "for-matched", "placebo", "placebo-shuffle", "lexical" )
ROOT_RE = re.compile( r'<candidates\b[^>]*>' )
CAND_RE = re.compile( r'<cand\b.*?</cand>', re.S )
ATTR_RE = re.compile( r'\s([A-Za-z_][\w-]*)="([^"]*)"' )
ELLIPSIS = "…"

class PlaceboUnbuildable( Exception ):
    pass

def xml_text_escape( s ):
    return ( s.replace( "&", "&amp;" ).replace( "<", "&lt;" ).replace( ">", "&gt;" )
              .replace( '"', "&quot;" ).replace( "'", "&apos;" ) )

def xml_text_unescape( s ):
    return ( s.replace( "&lt;", "<" ).replace( "&gt;", ">" ).replace( "&quot;", '"' )
              .replace( "&apos;", "'" ).replace( "&amp;", "&" ) )

def nbytes( s ):
    return len( s.encode( "utf-8" ) )

def split_candidates_doc( xml ):
    # -> (head, root_open, rows, tail). head = legend comment; tail = `</candidates>` + trailing bytes.
    # Fails closed when the body between the root tags is not exactly a concatenation of <cand> rows.
    m = ROOT_RE.search( xml )
    end = xml.rfind( "</candidates>" )
    if not m or end < m.end():
        raise PlaceboUnbuildable( "not a --format=candidates document" )
    body = xml[m.end():end]
    rows = CAND_RE.findall( body )
    if "".join( rows ) != body:
        raise PlaceboUnbuildable( "candidates body is not a bare row sequence" )
    return xml[:m.start()], m.group( 0 ), rows, xml[end:]

def row_attr( row, name ):
    head = row[: row.index( ">" )]
    for k, v in ATTR_RE.findall( head ):
        if k == name: return v
    return ""

def set_attr( tag, name, value ):
    # Rewrite one attribute inside the FIRST tag only. Attribute values never hold a raw `"`, so a
    # space-anchored `name="…"` cannot match inside another attribute's value.
    cut = tag.index( ">" )
    head, rest = tag[:cut], tag[cut:]
    new, n = re.subn( r'(?<=\s)' + re.escape( name ) + r'="[^"]*"', f'{name}="{value}"', head, count=1 )
    if n != 1: raise PlaceboUnbuildable( f"row has no {name}= attribute" )
    return new + rest

def row_with_sig( row, text ):
    a, b = row.find( "<sig>" ), row.rfind( "</sig>" )
    if a < 0 or b < a: raise PlaceboUnbuildable( "row has no <sig> to trim" )
    return row[: a + 5] + xml_text_escape( text ) + row[b:]

def row_sig_text( row ):
    a, b = row.find( "<sig>" ), row.rfind( "</sig>" )
    return xml_text_unescape( row[a + 5:b] ) if 0 <= a < b else ""

def render_candidates( head, root_open, tail, rows, scores ):
    # r= is the 1-based position; s= is the arm's score list in position order (the last value repeats
    # past its end). count= tracks the row count, so its digit width is part of the byte arithmetic.
    out = []
    for i, row in enumerate( rows ):
        s = scores[min( i, len( scores ) - 1 )] if scores else row_attr( row, "s" )
        out.append( set_attr( set_attr( row, "r", str( i + 1 ) ), "s", s ) )
    return head + set_attr( root_open, "count", str( len( rows ) ) ) + "".join( out ) + tail

def ranked_row( row, i, scores ):
    s = scores[min( i, len( scores ) - 1 )] if scores else row_attr( row, "s" )
    return set_attr( set_attr( row, "r", str( i + 1 ) ), "s", s )

def trimmed_to( row, need ):
    # The prefix of `row`'s sig text (closed by an ellipsis, as ripwire's own truncations are) whose row is
    # exactly `need` bytes, or None. Byte length is non-decreasing in the prefix length, so bisect.
    if nbytes( row ) == need: return row
    full = row_sig_text( row )
    lo, hi = 0, len( full )
    while lo <= hi:
        mid = ( lo + hi ) // 2
        cand = row_with_sig( row, full[:mid] + ELLIPSIS )
        got = nbytes( cand )
        if got == need: return cand
        if got < need: lo = mid + 1
        else: hi = mid - 1
    return None

def fit_to_bytes( head, root_open, tail, pool, scores, target, tries=1 ):
    # Greedy prefix of `pool` (already in the arm's rank order), then close the residual gap EXACTLY by
    # trimming the next row's <sig>. `tries` > 1 lets an UNORDERED arm (the placebo) close with a later row;
    # ordered arms keep tries=1 so no row is ever skipped. If that fails, drop up to 3 tail rows; then trim
    # the last kept row too (escaped text grows in entity-sized steps, so one row can straddle the target).
    # Raises PlaceboUnbuildable rather than return a document of any other size.
    if not pool: raise PlaceboUnbuildable( "empty row pool" )
    fixed = lambda n: nbytes( head ) + nbytes( set_attr( root_open, "count", str( n ) ) ) + nbytes( tail )
    rendered = [ ranked_row( r, i, scores ) for i, r in enumerate( pool ) ]
    prefix = [ 0 ]
    for r in rendered: prefix.append( prefix[-1] + nbytes( r ) )
    finish = lambda rows: render_candidates( head, root_open, tail, rows, scores )
    k = 0
    while k < len( pool ) and fixed( k + 1 ) + prefix[k + 1] <= target: k += 1
    if k and fixed( k ) + prefix[k] == target: return finish( pool[:k] )
    def close( base, base_bytes, start ):
        need = target - fixed( len( base ) + 1 ) - base_bytes
        for j in range( start, min( len( pool ), start + tries ) ):
            fit = trimmed_to( ranked_row( pool[j], len( base ), scores ), need )
            if fit is not None: return finish( base + [ fit ] )
        return None
    for drop in range( 0, min( 3, k ) + 1 ):
        doc = close( pool[:k - drop], prefix[k - drop], k - drop )
        if doc is not None: return doc
    for keep in range( k, max( 0, k - 2 ), -1 ):
        last = rendered[keep - 1]; full = row_sig_text( last )
        for c in range( len( full ) - 1, -1, -1 ):
            short = row_with_sig( last, full[:c] + ELLIPSIS )
            base_bytes = prefix[keep - 1] + nbytes( short )
            if fixed( keep + 1 ) + base_bytes >= target: continue
            doc = close( pool[:keep - 1] + [ short ], base_bytes, keep )
            if doc is not None: return doc
    raise PlaceboUnbuildable( f"no exact {target}-byte closure (pool={len( pool )}, greedy={k})" )

def seeded_order( rows, instance_id, tag ):
    key = lambda r: hashlib.sha256( "\0".join( ( PLACEBO_SALT, tag, instance_id, row_attr( r, "id" ),
                                                 row_attr( r, "p" ), row_attr( r, "l" ) ) ).encode() ).hexdigest()
    return sorted( rows, key=key )

def build_for_matched( for_xml, target ):
    # A1 at the matched budget: ripwire's own --for rows, in ripwire's order, cut/closed to `target` bytes.
    head, root, rows, tail = split_candidates_doc( for_xml )
    return fit_to_bytes( head, root, tail, rows, [ row_attr( r, "s" ) for r in rows ], target )

def build_placebo_unrelated( for_xml, universe_xml, instance_id, target ):
    # Bellam's "random entities": ripwire-rendered rows drawn uniformly (seeded) from files the real answer
    # does NOT name. Score strings are the real answer's, in order — the score column carries no signal.
    head, root, real, tail = split_candidates_doc( for_xml )
    named = { row_attr( r, "p" ) for r in real }
    _, _, uni, _ = split_candidates_doc( universe_xml )
    pool = seeded_order( [ r for r in uni if row_attr( r, "p" ) not in named ], instance_id, "unrelated" )
    return fit_to_bytes( head, root, tail, pool, [ row_attr( r, "s" ) for r in real ], target, tries=64 )

def build_placebo_shuffle( matched_xml, instance_id ):
    # The real matched answer with its rows permuted and r=/s= re-dealt in position order: the same bytes
    # (same multiset of r and s strings), the same content, no ranking. Secondary control: ORDER only.
    head, root, rows, tail = split_candidates_doc( matched_xml )
    scores = [ row_attr( r, "s" ) for r in rows ]
    out = render_candidates( head, root, tail, seeded_order( rows, instance_id, "shuffle" ), scores )
    if nbytes( out ) != nbytes( matched_xml ): raise PlaceboUnbuildable( "shuffle changed the byte count" )
    return out

LEX_TOKEN_RE = re.compile( r'[A-Za-z][a-z]+|[A-Z]+(?![a-z])|[0-9]+' )

def lexical_tokens( text ):
    # Whole-word + camelCase/snake_case subtokens, lower-cased: the identifier-aware split a fair code BM25
    # needs (Xue et al., arXiv 2611.20455: a BM25 that cannot split identifiers is the handicapped one).
    return [ t.lower() for t in LEX_TOKEN_RE.findall( text ) ]

def bm25_rank_files( repo_path, files, query, k1=1.2, b=0.75, max_bytes=2_000_000 ):
    # FILE-LEVEL BM25 over whole files (not chunks — the artefact 2611.20455 names). Files over max_bytes
    # are scored as empty and COUNTED, never dropped from the ranking silently. -> (ranked [(path, score)], n_oversize)
    docs, oversize = {}, 0
    for f in files:
        p = pathlib.Path( repo_path ) / f
        try:
            if p.stat().st_size > max_bytes: oversize += 1; docs[f] = []; continue
            docs[f] = lexical_tokens( p.read_text( encoding="utf-8", errors="replace" ) )
        except OSError:
            docs[f] = []
    n = len( docs ) or 1
    avgdl = ( sum( len( d ) for d in docs.values() ) / n ) or 1.0
    q = sorted( set( lexical_tokens( query ) ) )
    df = { t: 0 for t in q }
    tfs = {}
    for f, toks in docs.items():
        tf = {}
        for t in toks:
            if t in df: tf[t] = tf.get( t, 0 ) + 1
        tfs[f] = tf
        for t in tf: df[t] += 1
    scored = []
    for f, toks in docs.items():
        s = 0.0
        for t, c in tfs[f].items():
            idf = math.log( 1.0 + ( n - df[t] + 0.5 ) / ( df[t] + 0.5 ) )
            s += idf * c * ( k1 + 1 ) / ( c + k1 * ( 1 - b + b * len( toks ) / avgdl ) )
        scored.append( ( f, s ) )
    scored.sort( key=lambda x: ( -x[1], x[0] ) )
    return scored, oversize

def build_lexical( for_xml, universe_xml, ranked_files, target ):
    # A3: files in BM25 order; within a file, its symbols in the universe export's own order. Rows are
    # ripwire-rendered universe rows, so the format is identical; s= is the file's BM25 score.
    head, root, _, tail = split_candidates_doc( for_xml )
    _, _, uni, _ = split_candidates_doc( universe_xml )
    by_file = {}
    for r in uni: by_file.setdefault( row_attr( r, "p" ), [] ).append( r )
    pool, scores = [], []
    for f, s in ranked_files:
        for r in by_file.get( f, [] ):
            pool.append( r ); scores.append( f"{s:.6f}" )
    return fit_to_bytes( head, root, tail, pool, scores, target )

def format_signature( xml ):
    # What "format-identical" means, as a value two documents can be compared on: the legend bytes, the
    # root tag and its attribute NAMES in order, and the set of per-row (tag, attribute-names, child tags)
    # shapes. Well-formedness is part of it (ElementTree must parse the document).
    head, root_open, rows, tail = split_candidates_doc( xml )
    ET.fromstring( xml[len( head ):] )
    shapes = set()
    for r in rows:
        el = ET.fromstring( r )
        shapes.add( ( el.tag, tuple( el.attrib ), tuple( c.tag for c in el ) ) )
    return dict( head=head, root=tuple( k for k, _ in ATTR_RE.findall( root_open ) ), tail=tail, shapes=frozenset( shapes ) )

def build_derived_arms( for_xml, universe_xml, production_bytes, instance_id, repo_path, query, universe_files, wanted=DERIVED_ARMS ):
    # -> {arm: xml}, target, meta. target = min(production --for bytes, the full --for candidates export):
    # the matched budget is what the shipped answer COSTS, never more than ripwire can fill. for-matched is
    # always built (it is the reference the others are checked against); the rest only when `wanted`.
    target = min( production_bytes, nbytes( for_xml ) )
    matched = build_for_matched( for_xml, target )
    docs, meta = { "for-matched": matched }, dict( target_bytes=target )
    if "placebo" in wanted: docs["placebo"] = build_placebo_unrelated( for_xml, universe_xml, instance_id, target )
    if "placebo-shuffle" in wanted: docs["placebo-shuffle"] = build_placebo_shuffle( matched, instance_id )
    if "lexical" in wanted:
        ranked, meta["bm25_oversize_files"] = bm25_rank_files( repo_path, universe_files, query )
        docs["lexical"] = build_lexical( for_xml, universe_xml, ranked, target )
    ref = format_signature( matched )
    for arm, doc in docs.items():
        sig = format_signature( doc )
        if nbytes( doc ) != target or sig["head"] != ref["head"] or sig["root"] != ref["root"] or sig["tail"] != ref["tail"]:
            raise PlaceboUnbuildable( f"{arm}: byte/format contract broken ({nbytes( doc )} vs {target})" )
    return docs, target, meta

def emit_payloads( out_dir, instance_id, docs, production_xml ):
    # Freeze every arm's payload to disk with its sha256 BEFORE any model sees one; the manifest is the seal
    # an agent round verifies (PREREG_PLACEBO.md "seal"). Production --for is kept beside, unmatched.
    d = pathlib.Path( out_dir ) / instance_id.replace( "/", "__" )
    d.mkdir( parents=True, exist_ok=True )
    manifest = {}
    for arm, doc in sorted( list( docs.items() ) + [ ( "for-production", production_xml ) ] ):
        data = doc.encode( "utf-8" )
        ( d / f"{arm}.xml" ).write_bytes( data )
        manifest[arm] = dict( bytes=len( data ), sha256=hashlib.sha256( data ).hexdigest() )
    ( d / "manifest.json" ).write_text( json.dumps( manifest, indent=2, sort_keys=True ) )
    return manifest

def score_accuracy( m, candidates, primary_files, gold_files, universe_files, cov ):
    # One arm's ranked candidates -> accumulate strict/lenient Acc@k + first-hit MRR into `m`; return the
    # per-instance rank record. Shared by the shipped arms and the derived control arms (same scoring).
    rf = ranked_files_from_candidates( candidates )
    franks = file_ranks( rf, primary_files, universe_files )
    all_franks = file_ranks( rf, gold_files, universe_files )
    nranks = func_ranks( candidates, cov, universe_files ) if cov else []
    m["primary_gold_files"] += len( primary_files ); m["all_gold_files"] += len( gold_files )
    m["f1"] += acc_all_at( franks, 1 ); m["f3"] += acc_all_at( franks, 3 )      # file-level Acc@k (strict ALL)
    m["f5"] += acc_all_at( franks, 5 ); m["f10"] += acc_all_at( franks, 10 )
    m["allf10"] += acc_all_at( all_franks, 10 )
    m["fn5"] += acc_all_at( nranks, 5 ); m["fn10"] += acc_all_at( nranks, 10 )  # function-level strict + MRR
    fh = first_hit( nranks )
    if fh is not None: m["mrr"] += 1.0 / ( fh + 1 )
    ff = first_hit( franks )                                                    # lenient any-hit@10, apart
    m["anyf10"]  += ( ff is not None and ff < 10 )
    m["anyfn10"] += ( fh is not None and fh < 10 )
    complete = lambda rk: max( rk ) if rk and all( r is not None for r in rk ) else None
    return dict( file_first=ff, file_worst=complete( franks ), all_file_worst=complete( all_franks ), func_first=fh )

def run_for_pair( repo_path, query, top_k, rich_cache, extra_args ):
    # The shipped `for` arm's (candidates export, production payload) when only derived arms were requested.
    flags = [ f"--for={query}", f"--top-k={top_k}", f"--cache={rich_cache}" ] + extra_args
    cand, _, rc1 = run_ctx( repo_path, flags + [ "--format=candidates" ] )
    prod, _, rc2 = run_ctx( repo_path, flags )
    if rc1 != 0 or rc2 != 0 or not cand or not prod:
        raise SystemExit( f"for-pair run failed rc={rc1}/{rc2} (zero-silent-skip contract)" )
    return cand, prod

def score_derived_arms( acc, arms, shipped_for, uni_xml, instance_id, repo_path, query, universe_files, gold, emit_dir ):
    # Build the matched-budget control arms from the `for` answer and score them with the same scorer. An
    # unbuildable placebo aborts the run (zero-silent-skip): a control that quietly went missing on the
    # hard instances would bias exactly the comparison it exists to make.
    primary_files, gold_files, cov = gold
    for_xml, production_xml = shipped_for
    try:
        docs, target, meta = build_derived_arms( for_xml, uni_xml, nbytes( production_xml ), instance_id,
                                                 repo_path, query, universe_files, set( arms ) )
    except PlaceboUnbuildable as e:
        raise SystemExit( f"{instance_id}: PLACEBO UNBUILDABLE: {e} (zero-silent-skip contract)" )
    if emit_dir: emit_payloads( emit_dir, instance_id, docs, production_xml )
    out = {}
    for arm in ( x for x in arms if x in DERIVED_ARMS ):
        m = acc[arm]; m["n"] += 1
        m["output_bytes"] += target; m["candidate_bytes"] += target
        m["output_tokens_ceiling"] += estimated_output_tokens( docs[arm] )
        out[arm] = dict( **score_accuracy( m, parse_candidates( docs[arm], repo_path ), primary_files, gold_files,
                                           universe_files, cov ), output_bytes=target, **meta )
    return out

# ── main ─────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser( description="ripwire localization accuracy on LocBench / SWE-bench-Lite" )
    ap.add_argument( "--dataset", default="locbench", choices=list( DATASETS ) )
    ap.add_argument( "--n", type=int, default=25, help="slice size (instances, stable order)" )
    ap.add_argument( "--work-dir", required=True, help="scratch dir for dataset cache + cloned repos (NOT the ripwire repo)" )
    ap.add_argument( "--top-k", type=int, default=200, help="symbols per --for/--anchor arm run (they self-limit to a ~40-symbol focused bundle)" )
    ap.add_argument( "--query-chars", type=int, default=1200, help="chars of the issue problem_statement used as the query (deterministic prefix)" )
    ap.add_argument( "--arms", default="for,query,anchor",
                     help="shipped: for,query,anchor,subtoken,subtoken-anchor; matched-budget controls: " + ",".join( DERIVED_ARMS ) )
    ap.add_argument( "--split", default="all", choices=[ "all", "train", "heldout" ],
                     help="frozen A7 repository-disjoint split selected by salted SHA-256(repo), independent of row order" )
    ap.add_argument( "--max-scored", type=int, default=0,
                     help="stop after this many rows in the selected split (0 = all); useful for train-only ablations" )
    ap.add_argument( "--latency-samples", type=int, default=1,
                     help="identical warm runs per arm; release evidence requires >=5" )
    ap.add_argument( "--history-depth", type=int, default=1,
                     help="git history depth per checkout (B3). 1 = the historical depth-1 behavior (all pre-existing "
                          "artifacts). N>1 deepens each cached clone to N ancestors of base_commit (no future leakage; "
                          "fail-closed). Compared runs MUST use identical values; recorded in header + JSON meta." )
    ap.add_argument( "--ctx-extra-args", default="",
                     help="extra whitespace-separated ripwire flags appended to every ARM invocation (candidates + "
                          "production + cold), e.g. --ctx-extra-args=--no-cochange-boost for a boost-off ablation arm. "
                          "NOT applied to the index build or the --query coverage-universe run, so both arms of an "
                          "ablation share an identical universe. Recorded in JSON meta." )
    ap.add_argument( "--measure-cold", action="store_true", help="also time one production-bundle --no-cache run per arm" )
    ap.add_argument( "--measure-index", action="store_true", help="also rebuild/time a throwaway rich index per instance" )
    ap.add_argument( "--json-out", default="", help="write per-instance results JSON here" )
    ap.add_argument( "--emit-payloads", default="",
                     help="with a derived arm (for-matched/placebo/placebo-shuffle/lexical): write every arm's payload "
                          "+ a sha256 manifest per instance under this dir — the seal an agent round verifies" )
    ap.add_argument( "--instances", default="",
                     help="comma-separated instance_ids (or @FILE, one per line): score ONLY these rows, in dataset order "
                          "(the agent pilot's train selection, bench/locbench/agent_loc.py --select-pilot); every named id "
                          "must be found or the run stops (zero-silent-skip)" )
    ap.add_argument( "--verbose", action="store_true" )
    a = ap.parse_args()

    work = pathlib.Path( a.work_dir ); work.mkdir( parents=True, exist_ok=True )
    repos_dir = work / "repos"; ds_cache = work / "datasets"
    ds_name, cfg, split = DATASETS[a.dataset]
    arms = [ x.strip() for x in a.arms.split( "," ) if x.strip() ]

    extra_args = a.ctx_extra_args.split()
    print( f"# LocBench harness — dataset={a.dataset} ({ds_name}) n={a.n} top-k={a.top_k} arms={arms}"
           f" history-depth={a.history_depth} extra-args={extra_args}", file=sys.stderr )
    rows = fetch_rows( ds_name, cfg, split, a.n, ds_cache )
    if a.dataset == "locbench" and a.n == 560:
        raw = ds_cache / "rows_czlll__Loc-Bench_V1_test_560.json"
        expected = "5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97"
        actual = hashlib.sha256( raw.read_bytes() ).hexdigest() if raw.exists() else "missing"
        if actual != expected: raise SystemExit( f"frozen LocBench rows hash mismatch: expected {expected}, got {actual}" )
    print( f"# fetched {len(rows)} instances", file=sys.stderr )
    if a.instances:
        spec = pathlib.Path( a.instances[1:] ).read_text() if a.instances.startswith( "@" ) else a.instances
        wanted_ids = [ x.strip() for x in spec.replace( ",", "\n" ).splitlines() if x.strip() ]
        missing = sorted( set( wanted_ids ) - { r["instance_id"] for r in rows } )
        if missing: raise SystemExit( f"--instances: {len( missing )} id(s) not in the dataset (zero-silent-skip contract)" )
        rows = [ r for r in rows if r["instance_id"] in set( wanted_ids ) ]
        print( f"# --instances kept {len(rows)} rows", file=sys.stderr )

    # accumulators per arm (Acc@k = strict ALL-gold-within-top-k, per LocAgent; anyf* = lenient any-gold recall)
    def zero(): return dict( n=0, f1=0, f3=0, f5=0, f10=0, allf10=0, fn5=0, fn10=0, mrr=0.0,
                             anyf10=0, anyfn10=0, wall=0.0, p95=0.0, output_bytes=0,
                             output_tokens_ceiling=0, candidate_bytes=0, cold_wall=0.0, index_wall=0.0,
                             primary_gold_files=0, all_gold_files=0 )
    acc = { arm: zero() for arm in arms }
    gold_total = cov_total = added_total = 0
    skipped_nonpy = skipped_checkout = skipped_ctx = skipped_unindexable = 0
    per_instance = []

    for idx, inst in enumerate( rows ):
        partition = frozen_partition( inst["repo"] )
        if a.split != "all" and partition != a.split: continue
        if a.max_scored > 0 and acc[arms[0]]["n"] >= a.max_scored: break
        repo, bc = inst["repo"], inst["base_commit"]
        title_body = inst.get( "problem_statement", "" )
        query = " ".join( title_body.split() )[: a.query_chars]
        gold_files, gold_funcs, added = gold_for_instance( inst, a.dataset )

        # skip instances whose gold files aren't a ripwire language (LocBench is all-Python; guard anyway)
        exts = { os.path.splitext( f )[1] for f in gold_files }
        ctx_exts = { ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".cpp", ".cc", ".h", ".hpp",
                     ".swift", ".m", ".mm", ".java", ".rb", ".sh", ".bash", ".json", ".md", ".markdown",
                     ".ipynb", ".html", ".htm", ".csv" }
        if gold_files and not ( exts & ctx_exts ):
            skipped_nonpy += 1; continue

        repo_path = checkout( repo, bc, repos_dir, a.history_depth )
        if repo_path is None:
            raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: CHECKOUT FAIL (zero-silent-skip contract)" )

        # Build one rich cache outside timing; every arm consumes the same immutable index. This removes
        # arm-order parse/cache bias from latency while retaining the exact shipping rankers.
        index_base = work / "indexes" / inst["instance_id"].replace( "/", "__" )
        index_base.parent.mkdir( parents=True, exist_ok=True )
        rich_cache = pathlib.Path( str(index_base) + ".rich.ripwirecache" )
        if not rich_cache.exists():
            _, _, irc = run_ctx( repo_path, [ f"--index-out={index_base}", "--top-k=1", "--no-cache" ] )
            if irc != 0 or not rich_cache.exists():
                raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: INDEX FAIL rc={irc} (zero-silent-skip contract)" )
        index_wall = 0.0
        if a.measure_index:
            measure_base = work / "measure-index" / inst["instance_id"].replace( "/", "__" )
            measure_base.parent.mkdir( parents=True, exist_ok=True )
            for suffix in ( ".lean.ripwirecache", ".rich.ripwirecache" ):
                artifact = pathlib.Path( str(measure_base) + suffix )
                if artifact.exists(): artifact.unlink()
            _, index_wall, irc = run_ctx( repo_path, [ f"--index-out={measure_base}", "--top-k=1", "--no-cache" ] )
            if irc != 0 or not pathlib.Path( str(measure_base) + ".rich.ripwirecache" ).exists():
                raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: MEASURED INDEX FAIL rc={irc}" )

        # Coverage universe: flat globally-ranked candidates, not grouped <f>/<sigs> output. The CLI
        # deliberately rejects --top-k=0 (it used to be an accidental "emit all" trap), so use the largest
        # maximum accepted positive ceiling to include every emitted symbol through the public candidates seam.
        uni_xml, _, rc = run_ctx( repo_path, [ f"--query={query}", "--format=candidates", "--top-k=1000000000",
                                                   f"--cache={rich_cache}" ] )
        try: uni_candidates = parse_candidates( uni_xml, repo_path )
        except Exception as e: uni_candidates = []; parse_error = str(e)
        if rc != 0 or not uni_candidates:
            raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: CTX FAIL rc={rc} parse={locals().get('parse_error','')} (zero-silent-skip contract)" )
        universe_files = sorted( { c["path"] for c in uni_candidates } )
        primary_files = { f for f in gold_files if norm_path( f ) in universe_files }
        cov = covered( uni_candidates, gold_funcs, universe_files )
        gold_total += len( gold_funcs ); cov_total += len( cov ); added_total += len( added )
        if not primary_files:
            skipped_unindexable += 1
            print( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: NO INDEXABLE GOLD FILE (all-patch secondary only)", file=sys.stderr )
            continue

        arm_out = {}; shipped_for = None
        # Rotate the measured arm order by instance hash. Each arm still runs the requested sample count.
        rot = hashlib.sha256( inst["instance_id"].encode() ).digest()[0] % len( arms )
        run_arms = arms[rot:] + arms[:rot]
        for arm in run_arms:
            flags = [ f"--top-k={a.top_k}", "--format=candidates", f"--cache={rich_cache}" ]
            if arm == "query": flags.insert( 0, f"--query={query}" )
            elif arm == "for": flags.insert( 0, f"--for={query}" )
            elif arm == "subtoken": flags[0:0] = [ f"--for={query}", "--no-route" ]
            elif arm == "anchor": flags[0:0] = [ f"--for={query}", "--anchor" ]
            elif arm == "subtoken-anchor": flags[0:0] = [ f"--for={query}", "--no-route", "--anchor" ]
            else: continue
            flags += extra_args   # ablation-arm extras (see --ctx-extra-args); flow into production + cold runs below
            candidate_xml, _, arm_rc = run_ctx( repo_path, flags )
            if arm_rc != 0: raise SystemExit( f"candidate scoring failed arm={arm} rc={arm_rc}" )
            production_flags = [ f for f in flags if f != "--format=candidates" ]
            payloads, walls = [], []
            for _ in range( max( 1, a.latency_samples ) ):
                xml, wall, arm_rc = run_ctx( repo_path, production_flags )
                if arm_rc != 0: break
                payloads.append( xml ); walls.append( wall )
            if arm_rc != 0 or not payloads or any( p != payloads[0] for p in payloads[1:] ):
                raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: ARM FAIL arm={arm} rc={arm_rc} deterministic={len(set(payloads))<=1} (zero-silent-skip contract)" )
            try: candidates = parse_candidates( candidate_xml, repo_path )
            except Exception as e:
                raise SystemExit( f"[{idx+1}/{len(rows)}] {inst['instance_id']}: XML FAIL arm={arm}: {e} (zero-silent-skip contract)" )
            if arm == "for": shipped_for = ( candidate_xml, payloads[0] )
            wall_med = statistics.median( walls )
            wall_p95 = sorted( walls )[ max( 0, math.ceil( 0.95 * len( walls ) ) - 1 ) ]
            m = acc[arm]; m["n"] += 1; m["wall"] += wall_med; m["p95"] += wall_p95
            m["output_bytes"] += len( payloads[0].encode( "utf-8" ) )
            m["output_tokens_ceiling"] += estimated_output_tokens( payloads[0] )
            m["candidate_bytes"] += len( candidate_xml.encode( "utf-8" ) ); m["index_wall"] += index_wall
            cold_wall = 0.0
            if a.measure_cold:
                cold_flags = [ f for f in production_flags if not f.startswith( "--cache=" ) ] + [ "--no-cache" ]
                cold_payload, cold_wall, cold_rc = run_ctx( repo_path, cold_flags )
                if cold_rc != 0 or not cold_payload: raise SystemExit( f"cold production run failed arm={arm} rc={cold_rc}" )
                m["cold_wall"] += cold_wall
            arm_out[arm] = dict( **score_accuracy( m, candidates, primary_files, gold_files, universe_files, cov ),
                                 wall_median=round( wall_med, 4 ), wall_p95=round( wall_p95, 4 ),
                                 cold_wall=round( cold_wall, 4 ), index_wall=round( index_wall, 4 ),
                                 output_bytes=len( payloads[0].encode( "utf-8" ) ), output_tokens_ceiling=estimated_output_tokens( payloads[0] ),
                                 candidate_bytes=len( candidate_xml.encode( "utf-8" ) ) )

        if any( x in DERIVED_ARMS for x in arms ):
            if shipped_for is None: shipped_for = run_for_pair( repo_path, query, a.top_k, rich_cache, extra_args )
            arm_out.update( score_derived_arms( acc, arms, shipped_for, uni_xml, inst["instance_id"], repo_path, query,
                                                universe_files, ( primary_files, gold_files, cov ), a.emit_payloads ) )

        if not arm_out: continue

        per_instance.append( dict( instance_id=inst["instance_id"], partition=partition, repo=repo,
                                   gold_files=sorted( gold_files ), primary_files=sorted( primary_files ), gold_funcs=gold_funcs,
                                   added_funcs=added, covered=cov, n_files=len( universe_files ),
                                   n_syms=len( uni_candidates ), arms=arm_out,
                                   # the agent driver scores a submission with the same file_ranks/func_ranks,
                                   # whose basename fallback needs the indexed universe; only kept for a seal run
                                   **( dict( universe_files=universe_files ) if a.emit_payloads else {} ) ) )
        if a.verbose:
            print( f"[{idx+1}/{len(rows)}] {inst['instance_id']} files={len(primary_files)}/{len(gold_files)} "
                   f"funcs={len(gold_funcs)} cov={len(cov)}/{len(gold_funcs)} "
                   + " ".join( f"{k}:Ff{v['file_first']}/Fw{v['file_worst']}/Nf{v['func_first']}" for k, v in arm_out.items() ),
                   file=sys.stderr )

    # ── report ───────────────────────────────────────────────────────────────
    def pct( x, d ): return f"{100.0*x/d:5.1f}%" if d else "   n/a"
    scored = acc[arms[0]]["n"] if arms else 0
    print( "\n" + "=" * 78 )
    print( f"LocBench validation slice — dataset={a.dataset}  split={a.split}  n_scored={scored}"
           f"  (excluded-with-reason: nonpy={skipped_nonpy} checkout={skipped_checkout} ctx={skipped_ctx} unindexable={skipped_unindexable})" )
    print( "=" * 78 )
    print( f"parse coverage: {cov_total}/{gold_total} gold functions emitted by ripwire's parser "
           f"= {pct(cov_total, gold_total)}   (added_functions excluded, structurally absent: {added_total})" )
    print()
    print( "Acc@k = STRICT (all gold locations within top-k), per LocAgent arXiv 2503.09089 §4.1." )
    hdr = ( f"{'arm':7} | {'file@1':>7} {'file@3':>7} {'file@5':>7} {'file@10':>7} | "
            f"{'func@5':>7} {'func@10':>7} {'fn-MRR':>7} | {'wall/inst':>9} {'tok-ceil/inst':>13}" )
    print( hdr ); print( "-" * len( hdr ) )
    for arm in arms:
        m = acc[arm]; n = m["n"] or 1
        print( f"{arm:7} | {pct(m['f1'],n):>7} {pct(m['f3'],n):>7} {pct(m['f5'],n):>7} {pct(m['f10'],n):>7} | "
               f"{pct(m['fn5'],n):>7} {pct(m['fn10'],n):>7} {m['mrr']/n:7.3f} | {m['wall']/n:8.2f}s {m['output_tokens_ceiling']/n:13.0f}" )
    print()
    print( "lenient any-gold-within-top-10 (recall flavor; NOT the paper's strict Acc):" )
    for arm in arms:
        m = acc[arm]; n = m["n"] or 1
        print( f"  {arm:7} file(any)@10 {pct(m['anyf10'],n)}   func(any)@10 {pct(m['anyfn10'],n)}" )
    print()
    print( "all-patch secondary strict file@10 (includes non-indexable patch locations):" )
    for arm in arms:
        m = acc[arm]; n = m["n"] + skipped_unindexable or 1
        print( f"  {arm:7} {pct(m['allf10'],n)}" )
    print()
    for stratum in ( "single", "multi" ):
        rows_s = [ r for r in per_instance if ( len( r["primary_files"] ) == 1 ) == ( stratum == "single" ) ]
        print( f"{stratum}-file primary stratum n={len(rows_s)}:" )
        for arm in arms:
            strict = sum( r["arms"][arm]["file_worst"] is not None and r["arms"][arm]["file_worst"] < 10 for r in rows_s )
            anyhit = sum( r["arms"][arm]["file_first"] is not None and r["arms"][arm]["file_first"] < 10 for r in rows_s )
            print( f"  {arm:7} strict@10 {pct(strict,len(rows_s))} any@10 {pct(anyhit,len(rows_s))}" )
    print()
    print( "Notes: primary file denominator contains only exact-path, indexed gold; all-patch is reported separately." )
    print( "       candidates are globally rank-ordered flat rows; scoped methods require canonical-id scope matches." )
    print( "       token cost is a conservative 2.36-byte/token ceiling; raw output bytes are retained in JSON." )

    if a.json_out:
        pathlib.Path( a.json_out ).write_text( json.dumps(
            dict( dataset=a.dataset, split=a.split, split_contract="repo-disjoint sha256(ripwire-a7-v2\\0 + lowercase(repo)), byte0<128=train",
                  history_depth=a.history_depth, ctx_extra_args=a.ctx_extra_args,
                  n_scored=scored,
                  skipped=dict( nonpy=skipped_nonpy, checkout=skipped_checkout, ctx=skipped_ctx, unindexable=skipped_unindexable ),
                  coverage=dict( covered=cov_total, gold=gold_total, added=added_total ),
                  arms={ arm: acc[arm] for arm in arms }, instances=per_instance ), indent=2 ) )
        print( f"\nwrote {a.json_out}" )

if __name__ == "__main__":
    main()
