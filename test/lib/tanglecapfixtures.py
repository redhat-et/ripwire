#!/usr/bin/env python3
"""tanglecapfixtures.py STAGE DIR — write the tanglecapcheck.sh fixture tree (TANGLE-RULE, the R-D rule) for one stage.

STAGE: v1 (the committed baseline) or wt (the working tree the gate judges).

The R-D rule (tmp/orch-1124/tangle-fp/RESULT.md; model.h tangleScore10): S' = min( S, maxBlockS + 2 * crossLocals ), where
maxBlockS is the published formula applied to each top-level block (an if/else-if chain and a switch split into their arms, a bare
{ } scope transparent) and crossLocals counts the top-level locals written in one block and read in a later one; test code (a test
path or an in-file test scope) never gets a tangle row. Each shape below is a reduced copy of a row labelled blind in
tmp/orch-1124/tangle-fp/labels.tsv, one function per file so a row's p= names it alone.

FALSE POSITIVES the rule removes (their published S is over the bar; tangle_raw= shows it):
  famswitch   — ripwire harvest (src/ingest_valuerefs.h): a switch per language family whose fat arms are else-if chains of
                node-kind handlers; every write goes to the out-parameter, no state crosses an arm.
  twoarms     — ripwire sliceEmitBody (src/slice.h): an emitter with two independent arms, its depth from a lambda, a loop and
                attribute ifs.
  lambdasteps — envoy evictUnused (thread_local_store.cc): linear steps, each a call whose callback lambda nests; one list
                collected in the first step is consumed by the last (cross 1).
  resolver    — envoy build_resolver (hickory_dns.rs, Rust): three independent same-shape server loops whose depth is if-let
                guard syntax; the one config they all extend crosses (cross 1).
  addressarms — twoarms with three record locals that arm one only ASKS (`r0.address()`, a read whose name starts with the
                mutator verb `add`) and arm two reads: no write, no cross local (CodeRabbit #743: a verb prefix is a word, not a
                substring). Red when `address` counted as a write (cross 3 kept it over the bar).
  test code   — ripwire's test harness mains and envoy's onTick / mergeLoadStats / initializeFilter: under test/ (a harness, an
                integration *_test.cc, a test_data file), never a tangle row. benchmain is the same body under bench/: bench is
                source, so it keeps its row.
REAL controls the rule must keep over the bar:
  statethread — ripwire pathReachingPairs / renderForLiteral: a shallow state-threaded monolith (the shape R-A lost): many
                locals rewritten in one phase and read in later ones.
  deepmono    — ripwire captureTagsFacts / buildGraph: one top-level loop over 50 lines, deep throughout.
  hdrparse    — envoy parseHeader: a scanner loop whose state (header kind, offsets) a later block reads — the thin-margin row
                (RESULT.md caveat 4).
  refheader   — envoy parseHeader's own shape: a REFERENCE local (`std::string& header = raw;`) rewritten by three leading guard
                blocks and read by the scanner loop after them. The loop block alone is under the bar; the one cross local keeps it
                over. Red before the C++ wrapped-declarator slot fix (a `T&`/`T*` local had no slot: envoy lost parseHeader).
KNOWN residual false positives (out of scope; report-only, so a later rule can see them move):
  solelambda  — envoy forEachHostMetric: a callback lambda that is the whole body.
  initable    — envoy getKnownStreamInfoFormatterProviders: one initializer of name -> lambda entries.
HISTORY (v1 -> wt), the rise and ratchet arms:
  crossgrow   — REAL, over the bar with the cap not binding; wt threads one more local across blocks by editing an existing
                line (no line added): the score is unchanged, crossLocals +1 is the rise (a minor row, why= names cross).
  crossgrowgo — crossgrow in Go, the threaded local declared `var bias int` (CodeRabbit #743: a `var` spec starts after the
                keyword, so it was never a top-level slot and the rise went unseen; `:=` was).
  ruleonly    — the FP shape twoarms under another name, body unchanged between v1 and wt.
  ruleflat    — the FP shape lambdasteps under another name; wt edits a constant in its last step (the body changed, no input
                moved: the uncapped score is the same, the capped one stays 2.0).
  ruleworse   — a REAL over-bar shape; wt adds 6 deep lines: a regression that must gate under any baseline.
  capworse    — the FP shape twoarms under another name; wt adds 6 deep lines to one arm. Capped, it stays under the bar (no row
                against a floor with block facts); against a floor WITHOUT them both sides are scored uncapped, and it grew.
"""
import os
import sys


def write(d, rel, text):
    p = os.path.join(d, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def lines(n, pad, fmt):
    return "".join(" " * pad + fmt.format(k=k) + "\n" for k in range(n))


# ── false positives ─────────────────────────────────────────────────────────────────────────────────────────────────────────
def famswitch(name="famswitch"):
    # 3 arms of ~46 lines each (over kDispatchArmMaxRows 40, so not a short dispatch arm), each an else-if chain of handlers that
    # loop and test to depth 6; all writes go to the out-parameter.
    def arm(fam):
        h = ""
        for j, kw in enumerate(("if", "else if", "else if")):
            h += (f"            {kw}( t == {fam * 10 + j} )\n            {{\n"
                  f"                for( int k : kids )\n                {{\n"
                  f"                    if( k > {j} )\n                    {{\n"
                  f"                        for( int m = 0; m < k; ++m )\n                        {{\n"
                  + lines(3, 28, "out.push_back( m + {k} );") +
                  "                        }\n                    }\n                }\n            }\n")
        return f"        case {fam}:\n        {{\n" + h + "            break;\n        }\n"
    return (f"void {name}( int fam, int t, const std::vector<int>& kids, std::vector<int>& out )\n{{\n"
            "    switch( fam )\n    {\n" + arm(0) + arm(1) + arm(2) + "    }\n}\n")


def twoarms(name="twoarms", extra=0, deepx=0):
    def emitter(tag, more=0):
        return (f"        auto put = [ & ]( int v )\n        {{\n            out.push_back( v * {tag} );\n        }};\n"
                "        for( const Row& r : rows )\n        {\n"
                "            if( r.on )\n            {\n"
                "                for( int a : r.attrs )\n                {\n"
                "                    if( a > 0 )\n                    {\n"
                + lines(14 + more, 24, "put( a + {k} );") +
                "                    }\n                }\n            }\n"
                + lines(12, 12, "put( r.id + {k} );") +
                "        }\n")
    return (f"void {name}( const std::vector<Row>& rows, bool compact, std::vector<int>& out )\n{{\n"
            "    if( compact )\n    {\n" + emitter(2, deepx) + lines(extra, 8, "out.push_back( {k} );") + "    }\n    else\n    {\n" + emitter(3) +
            "    }\n}\n")


def addressarms(name="addressarms"):
    recs = ["r0", "r1", "r2"]
    body = twoarms(name)
    body = body.replace("{\n    if( compact )\n    {\n", "{\n" + "".join(f"    Rec {r};\n" for r in recs) + "    if( compact )\n    {\n", 1)
    body = body.replace("    }\n    else\n    {\n", "".join(f"        sink( {r}.address() );\n" for r in recs) + "    }\n    else\n    {\n", 1)
    body = body.replace("    }\n}\n", "".join(f"        out.push_back( {r}.id );\n" for r in recs) + "    }\n}\n", 1)
    return "struct Rec { int id; long address() const; };\nvoid sink( long );\n" + body


def lambdasteps(name="lambdasteps", extra=0):
    def step(fn, body_pad_lines, k0):
        return (f"    {fn}( [ & ]( Scope& s )\n    {{\n"
                "        for( auto& e : s.entries )\n        {\n"
                "            if( e.used == 0 )\n            {\n"
                "                for( auto& h : e.hist )\n                {\n"
                + lines(body_pad_lines, 20, "h.n += " + str(k0) + " + {k};") +
                "                }\n            }\n        }\n    } );\n")
    return (f"void {name}( Store& st )\n{{\n    std::vector<int> evicted;\n"
            + step("st.forEachScope", 10, 1)
            + "    st.forEachScope( [ & ]( Scope& s )\n    {\n        for( auto& e : s.entries )\n        {\n"
              "            if( e.used == 0 )\n            {\n                for( auto& h : e.hist )\n                {\n"
              "                    if( h.n > 2 )\n                    {\n"
            + lines(8, 24, "evicted.push_back( h.n + {k} );") +
              "                    }\n                }\n            }\n        }\n    } );\n"
            + step("st.forEachThread", 10, 3 + extra)
            + "    st.release( evicted );\n}\n")


def resolver(name="resolver"):
    def loop(field, port):
        return (f"    for addr in &config.{field} {{\n"
                "        if let Some(ref sa) = addr.socket_address {\n"
                f"            let port = sa.port_value.unwrap_or({port}) as u16;\n"
                "            if let Ok(ip) = sa.address.parse::<std::net::IpAddr>() {\n"
                "                if let Some(ref name) = addr.server_name {\n"
                "                    let mut conn = ConnectionConfig::udp();\n"
                "                    conn.port = port;\n"
                "                    if let Some(ref tls) = addr.tls {\n"
                + lines(14, 24, "conn.weight += tls.w + {k};") +
                "                    }\n"
                "                    resolver_config.add_name_server(NameServerConfig::new(ip, name, conn));\n"
                "                }\n            }\n        }\n    }\n\n")
    return (f"fn {name}(config: &Config) -> Result<Resolver, String> {{\n"
            "    let mut resolver_config = ResolverConfig::default();\n\n"
            + loop("resolvers", 53) + loop("tls_servers", 853) + loop("https_servers", 443) +
            "    let mut opts = ResolverOpts::default();\n    opts.timeout = config.timeout();\n    opts.attempts = config.tries();\n"
            "    Resolver::build(resolver_config, opts)\n}\n")


# ── REAL controls ───────────────────────────────────────────────────────────────────────────────────────────────────────────
def statethread(name="statethread"):
    # phase 1 (one loop) rewrites 6 locals; phases 2..4 branch on them far later: shallow, steer-heavy, state threaded
    locs = ["hits", "misses", "last", "width", "seen", "anyCut"]
    decl = "".join(f"    int {v} = 0;\n" for v in locs)
    ph1 = ("    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n            for( int y = 0; y < x; ++y )\n            {\n"
           "                if( y % 2 )\n                {\n"
           + "".join(f"                    {v} = y + {i};\n" for i, v in enumerate(locs)) +
           "                }\n            }\n        }\n    }\n")
    flat = lines(14, 4, "total = total * 3 + {k};")
    reads = "".join(f"    if( {v} == {i} )\n    {{\n        total += {v};\n    }}\n" + lines(3, 4, "total = total * 5 + {k};")
                    for i, v in enumerate(locs))
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n" + decl + ph1 + flat + reads + flat +
            "    return total;\n}\n")


def deepmono(name="deepmono", deep=40):
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n"
            "    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y % 3 )\n                {\n" + lines(deep, 20, "total += y * {k} + " + str(len(name)) + ";") +
            "                }\n            }\n        }\n" + lines(30, 8, "total = total * 7 + {k};") +
            "    }\n    return total;\n}\n")


def hdrparse(name="hdrparse"):
    return (f"int {name}( const std::string& s )\n{{\n    int kind = 0;\n    std::size_t start = 0;\n    std::size_t pos = 0;\n"
            "    int total = 0;\n"
            "    while( pos < s.size() )\n    {\n        if( s[ pos ] == ';' )\n        {\n"
            "            for( std::size_t q = pos; q < s.size(); ++q )\n            {\n"
            "                if( s[ q ] == '=' )\n                {\n"
            + lines(30, 20, "total = total * 3 + int( s[ q ] ) + {k};") +
            "                    kind = int( s[ q ] );\n"
            "                    start = q;\n                }\n            }\n        }\n"
            + lines(26, 8, "total = total * 5 + int( s[ pos ] ) + {k};") +
            "        ++pos;\n    }\n"
            + lines(14, 4, "total = total * 7 + {k};") +
            "    if( kind == 3 )\n    {\n        total += kind;\n    }\n"
            + lines(14, 4, "total = total * 11 + {k};") +
            "    if( start == 2 )\n    {\n        total += int( start );\n    }\n    return total;\n}\n")


def refheader(name="refheader", deep=26, flat=20):
    # envoy parseHeader's shape: a REFERENCE local rewritten by three leading guard blocks, then read by the scanner loop that
    # follows. Its own block scores under the bar; the reference crossing the blocks is what keeps it over (cap = block + 2).
    trims = "".join(f"    if( std::size_t f = header.find( '{c}' ); f != std::string::npos )\n    {{\n        header = header.substr( f + 1 );\n    }}\n"
                    for c in ":<;")
    return (f"void {name}( std::string& raw, std::vector<std::string>& params )\n{{\n"
            "    if( !params.empty() )\n    {\n        return;\n    }\n    std::size_t pos = 0;\n    std::string& header = raw;\n"
            "    bool first = true;\n" + trims +
            "    while( pos < header.size() )\n    {\n        std::string str = header.substr( pos );\n"
            "        if( str.find( '=' ) == std::string::npos )\n        {\n            if( first )\n            {\n"
            "                if( !str.empty() )\n                {\n                    if( str[ 0 ] == '@' )\n                    {\n"
            + lines(deep, 24, "str = str.substr( 1 ) + \"{k}\";") +
            "                    }\n                }\n                params.push_back( str );\n                first = false;\n            }\n        }\n"
            + lines(flat, 8, "params.push_back( str + \"{k}\" );") +
            "        pos = pos + str.size() + 1;\n    }\n}\n")


# ── known residual (out of scope) ───────────────────────────────────────────────────────────────────────────────────────────
def solelambda(name="solelambda"):
    return (f"void {name}( Cluster& c, const Cb& cb )\n{{\n    c.forEachPriority( [ & ]( Priority& p )\n    {{\n"
            "        for( auto& host : p.hosts )\n        {\n            if( host.healthy )\n            {\n"
            "                for( auto& m : host.metrics )\n                {\n                    if( m.used )\n                    {\n"
            + lines(40, 24, "cb( m.name, m.value + {k} );") +
            "                    }\n                }\n            }\n        }\n"
            + lines(20, 8, "cb( p.name, p.level + {k} );") +
            "    } );\n}\n")


def initable(name="initable"):
    entries = "".join(f"        {{ \"F{k}\", [ & ]( const Ctx& c ) {{ if( c.on ) {{ for( int i : c.v ) {{ if( i > {k} ) {{ return i; }} }} }} return {k}; }} }},\n"
                      for k in range(70))
    return f"const Table& {name}()\n{{\n    static const Table t{{\n" + entries + "    };\n    return t;\n}\n"


# ── history arms ────────────────────────────────────────────────────────────────────────────────────────────────────────────
def crossgrow(stage, name="crossgrow"):
    # deepmono's interleaved body, plus a local `bias` written in the loop and (in wt) read by an existing tail line
    tail_last = "    total = total * 9 + bias;\n" if stage == "wt" else "    total = total * 9 + 1;\n"
    return (f"int {name}( const std::vector<int>& xs )\n{{\n    int total = 0;\n    int bias = 0;\n"
            "    for( int x : xs )\n    {\n        if( x > 0 )\n        {\n            for( int y = 0; y < x; ++y )\n            {\n"
            "                if( y % 3 )\n                {\n" + lines(40, 20, "total += y * {k};") +
            "                    bias = y;\n"
            "                }\n            }\n        }\n" + lines(30, 8, "total = total * 7 + {k};") +
            "    }\n" + lines(6, 4, "total = total * 9 + {k};") + tail_last + "    return total;\n}\n")


def crossgrowgo(stage, name="crossgrowgo"):
    tail_last = "\ttotal = total*9 + bias\n" if stage == "wt" else "\ttotal = total*9 + 1\n"
    return (f"package main\n\nfunc {name}(xs []int) int {{\n\ttotal := 0\n\tvar bias int\n"
            "\tfor _, x := range xs {\n\t\tif x > 0 {\n\t\t\tfor y := 0; y < x; y++ {\n\t\t\t\tif y%3 != 0 {\n"
            + "".join(f"\t\t\t\t\ttotal += y * {k}\n" for k in range(40)) +
            "\t\t\t\t\tbias = y\n\t\t\t\t}\n\t\t\t}\n\t\t}\n"
            + "".join(f"\t\ttotal = total*7 + {k}\n" for k in range(30)) + "\t}\n"
            + "".join(f"\ttotal = total*9 + {k}\n" for k in range(6)) + tail_last + "\treturn total\n}\n")


def main():
    stage, d = sys.argv[1], sys.argv[2]
    hdr = ("#include <string>\n#include <vector>\n"
           "struct Row { bool on; int id; std::vector<int> attrs; };\n")
    write(d, "src/crossgrow.cpp", hdr + crossgrow(stage))
    write(d, "src/crossgrowgo.go", crossgrowgo(stage))
    write(d, "src/ruleonly.cpp", hdr + twoarms("ruleonly"))
    write(d, "src/ruleflat.cpp", hdr + lambdasteps("ruleflat", extra=4 if stage == "wt" else 0))
    write(d, "src/ruleworse.cpp", hdr + deepmono("ruleworse", deep=46 if stage == "wt" else 40))
    write(d, "src/capworse.cpp", hdr + twoarms("capworse", deepx=7 if stage == "wt" else 1))
    if stage != "wt":
        return
    write(d, "src/famswitch.cpp", hdr + famswitch())
    write(d, "src/twoarms.cpp", hdr + twoarms())
    write(d, "src/addressarms.cpp", hdr + addressarms())
    write(d, "src/lambdasteps.cpp", hdr + lambdasteps())
    write(d, "src/resolver.rs", resolver())
    write(d, "src/statethread.cpp", hdr + statethread())
    write(d, "src/deepmono.cpp", hdr + deepmono())
    write(d, "src/hdrparse.cpp", hdr + hdrparse())
    write(d, "src/refheader.cpp", hdr + refheader())
    write(d, "src/solelambda.cpp", hdr + solelambda())
    write(d, "src/initable.cpp", hdr + initable())
    # test code: the same REAL body (statethread) under three test paths, and under bench/ (source)
    write(d, "test/regexlines_harness.cpp", hdr + statethread("harnessmain"))
    write(d, "test/integration/load_stats_integration_test.cc", hdr + statethread("mergeLoadStats"))
    write(d, "test/extensions/wasm/test_data/test_cpp.cc", hdr + statethread("onTick"))
    write(d, "bench/tokenaudit/loop_ledger.cpp", hdr + statethread("benchmain"))


if __name__ == "__main__":
    main()
