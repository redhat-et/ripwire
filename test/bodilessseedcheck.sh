#!/usr/bin/env bash
# bodilessseedcheck.sh — BODILESS-SEED: a selector naming a CONTRACT method (an interface or abstract member with no body of
# its own) never answers a confident zero (src/contractseed.h widenContractSeeds).
#
# THE BUG (found in the 0.7.0 comparison rehearsal, verified on main d624cff5f). A call through an interface-typed receiver
# binds to an implementor's BODY or declines with the implementors' bodies as candidates, never to the bodiless signature. So
# hono --impact=Router.match answered defs="1" reaches="0" beside 23 importers, --safe-delete=Router.match risk="none-found",
# --callers count="0"; Go nfpm --impact=Packager.Package reaches="0" with no hedge at all, while bare --impact=Package reached 100.
#
# THE CONTRACT. --impact, --callers, --safe-delete and --path on the qualified contract method seed from its implementors'
# same-named bodied methods and say so on the root (impls=K; path: to_impls=/from_impls=). Each answer then names the dispatch:
# a non-zero reach, a declined call site (<dc>, declined_calls=) or a hedged bridge. --safe-delete never says risk="none-found"
# on a contract. NEGATIVES: a bodied concrete method's answers carry no impls= and keep defs="1"; a bodiless method whose type
# has NO implementor answers its honest zero WITH impls="0". Every arm counts what it read and FAILS on a zero count.
# Fixtures are written at test time (TS: an interface with two `implements` classes, called through a typed field; Go: an
# interface two structs satisfy by method set, called through an interface parameter).
#
#   test/bodilessseedcheck.sh [BIN]          # default build/ripwire; RIPWIRE_BIN works too

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "bodilessseedcheck: BIN=$BIN"

TS="$TMP/ts"; GO="$TMP/go"; CPP="$TMP/cpp"; JAVA="$TMP/java"
mkdir -p "$TS/src" "$GO/pk" "$GO/cmd" "$CPP" "$JAVA"
# C++ (a pure virtual, one override out of line, one inline) and Java (an interface): the shared helper covers them too
cat > "$CPP/router.h" <<'EOF'
#pragma once
class Router {
public:
    virtual ~Router() = default;
    virtual int match( int path ) = 0;
};
class Linear : public Router {
public:
    int match( int path ) override;
};
class Trie : public Router {
public:
    int match( int path ) override { return path * 2; }
};
EOF
cat > "$CPP/router.cpp" <<'EOF'
#include "router.h"
int Linear::match( int path ) { return path + 1; }
int dispatch( Router& r, int p ) { return r.match( p ); }
int serve() { Linear l; return dispatch( l, 3 ); }
EOF
cat > "$JAVA/Router.java" <<'EOF'
interface Router { int match(int p); }
class Linear implements Router { public int match(int p) { return p + 1; } }
class Trie implements Router { public int match(int p) { return p * 2; } }
class App { Router r; int dispatch(int p) { return r.match(p); } int serve() { return dispatch(3); } }
EOF
cat > "$TS/src/router.ts" <<'EOF'
export interface Router<T> {
  add(method: string, path: string, handler: T): void
  match(method: string, path: string): T[]
}
export interface Quiet {
  hush(): void
}
EOF
cat > "$TS/src/linear.ts" <<'EOF'
import { Router } from './router'
export class LinearRouter<T> implements Router<T> {
  routes: T[] = []
  add(method: string, path: string, handler: T): void {
    this.routes.push(handler)
  }
  match(method: string, path: string): T[] {
    return this.routes.filter(() => method.length > 0)
  }
}
EOF
cat > "$TS/src/trie.ts" <<'EOF'
import { Router } from './router'
export class TrieRouter<T> implements Router<T> {
  items: T[] = []
  add(method: string, path: string, handler: T): void {
    this.items.push(handler)
  }
  match(method: string, path: string): T[] {
    return this.items.slice(0, path.length)
  }
}
EOF
cat > "$TS/src/app.ts" <<'EOF'
import { Router } from './router'
export class App {
  router: Router<string>
  constructor(r: Router<string>) {
    this.router = r
  }
  dispatch(method: string, path: string): string[] {
    return this.router.match(method, path)
  }
  handle(): number {
    return this.dispatch('GET', '/').length
  }
}
export function serve(app: App): number {
  return app.handle()
}
EOF
cat > "$GO/go.mod" <<'EOF'
module example.com/fx
go 1.21
EOF
cat > "$GO/pk/packager.go" <<'EOF'
package pk

type Packager interface {
	Package(info string) error
	ConventionalFileName(info string) string
}

type Quiet interface {
	Hush()
}
EOF
cat > "$GO/pk/deb.go" <<'EOF'
package pk

type Deb struct{}

func (d *Deb) Package(info string) error {
	return nil
}

func (d *Deb) ConventionalFileName(info string) string {
	return info + ".deb"
}
EOF
cat > "$GO/pk/rpm.go" <<'EOF'
package pk

type Rpm struct{}

func (r *Rpm) Package(info string) error {
	return nil
}

func (r *Rpm) ConventionalFileName(info string) string {
	return info + ".rpm"
}
EOF
cat > "$GO/cmd/main.go" <<'EOF'
package main

import "example.com/fx/pk"

func run(p pk.Packager) error {
	return p.Package("x")
}

func main() {
	_ = run(&pk.Deb{})
}
EOF

python3 - "$BIN" "$TS" "$GO" "$CPP" "$JAVA" <<'PY'
import re, subprocess, sys
BIN, TS, GO, CPP, JAVA = sys.argv[ 1:6 ]
npass = nfail = 0
seen = { "pos": 0, "safe": 0, "neg": 0, "zero": 0 }

def say( good, tag, msg, why = "" ):
    global npass, nfail
    if good:
        npass += 1; print( "  PASS  %s: %s" % ( tag, msg ) )
    else:
        nfail += 1; print( "  FAIL  %s: %s%s" % ( tag, msg, ( " -- " + why ) if why else "" ) )

def run( root, *args ):
    p = subprocess.run( [ BIN, root, "--no-cache", "--legend=compact" ] + list( args ), capture_output = True, text = True, timeout = 240 )
    out = re.sub( r"<!--.*?-->", "", p.stdout, flags = re.S )
    return p.returncode, out

def root_attrs( out, tag ):
    m = re.search( r"<%s\b([^>]*)>" % tag, out )
    return dict( re.findall( r'(\w+)="([^"]*)"', m.group( 1 ) ) ) if m else None

def num( a, k ):
    try:
        return int( a.get( k, "0" ) )
    except ValueError:
        return -1

# ── positive arms: the qualified contract method, per language ─────────────────────────────────────────────────────────
for lang, root, sel, entry in ( ( "ts", TS, "Router.match", "serve" ), ( "go", GO, "Packager.Package", "main" ) ):
    rc, out = run( root, "--impact=" + sel ); a = root_attrs( out, "impact" ) or {}
    seen[ "pos" ] += 1 if a else 0
    say( a.get( "impls" ) == "2" and ( num( a, "reaches" ) > 0 or num( a, "declined_calls" ) > 0 ),
         "[%s] impact" % lang, "--impact=%s seeds the 2 implementor bodies (impls=2) and names the dispatch (reaches= or declined_calls=)" % sel,
         "impls=%s reaches=%s declined_calls=%s" % ( a.get( "impls" ), a.get( "reaches" ), a.get( "declined_calls" ) ) )

    rc, out = run( root, "--callers=" + sel ); a = root_attrs( out, "callers" ) or {}
    seen[ "pos" ] += 1 if a else 0
    say( a.get( "impls" ) == "2" and ( num( a, "count" ) > 0 or ( num( a, "declined_calls" ) > 0 and "<dc " in out ) ),
         "[%s] callers" % lang, "--callers=%s answers rows or the declined dispatch site (<dc>), impls=2" % sel,
         "impls=%s count=%s declined_calls=%s" % ( a.get( "impls" ), a.get( "count" ), a.get( "declined_calls" ) ) )

    rc, out = run( root, "--safe-delete=" + sel ); a = root_attrs( out, "safe-delete" ) or {}
    seen[ "pos" ] += 1 if a else 0; seen[ "safe" ] += 1 if a else 0
    say( a.get( "impls" ) == "2" and a.get( "risk" ) not in ( None, "none-found" ),
         "[%s] safe-delete" % lang, "--safe-delete=%s never says risk=none-found on a contract with implementors" % sel,
         "impls=%s risk=%s" % ( a.get( "impls" ), a.get( "risk" ) ) )

    rc, out = run( root, "--path=%s,%s" % ( entry, sel ) ); a = root_attrs( out, "path" ) or {}
    seen[ "pos" ] += 1 if a else 0
    say( a.get( "to_impls" ) == "2" and ( a.get( "reachable" ) == "1" or "<bridge" in out ),
         "[%s] path" % lang, "--path=%s,%s reaches an implementor or bridges the declined dispatch, to_impls=2" % ( entry, sel ),
         "to_impls=%s reachable=%s bridge=%s" % ( a.get( "to_impls" ), a.get( "reachable" ), "<bridge" in out ) )

# ── the same helper, C++ (pure virtual) and Java (interface): impact and safe-delete ─────────────────────────────────────
for lang, root in ( ( "cpp", CPP ), ( "java", JAVA ) ):
    rc, out = run( root, "--impact=Router.match" ); a = root_attrs( out, "impact" ) or {}
    seen[ "pos" ] += 1 if a else 0
    say( a.get( "impls" ) == "2" and ( num( a, "reaches" ) > 0 or num( a, "declined_calls" ) > 0 ), "[%s] impact" % lang,
         "--impact=Router.match seeds the 2 overrides (impls=2) and names the dispatch", "attrs=%s" % a )
    rc, out = run( root, "--safe-delete=Router.match" ); a = root_attrs( out, "safe-delete" ) or {}
    seen[ "pos" ] += 1 if a else 0; seen[ "safe" ] += 1 if a else 0
    say( a.get( "impls" ) == "2" and a.get( "risk" ) not in ( None, "none-found" ), "[%s] safe-delete" % lang,
         "--safe-delete=Router.match never says risk=none-found", "attrs=%s" % a )
    rc, out = run( root, "--impact=Linear.match" ); a = root_attrs( out, "impact" ) or {}
    seen[ "neg" ] += 1 if a else 0
    want = "2" if lang == "cpp" else "1"   # C++: the in-class declaration beside its out-of-line definition, as on main (own body: no contract)
    say( a != {} and "impls" not in a and a.get( "defs" ) == want, "[%s] concrete impact" % lang,
         "--impact=Linear.match: an override keeps defs=%s and carries no impls=" % want, "attrs=%s" % a )

# ── negative arms: a bodied concrete method is no contract (no impls=, defs stays 1) ──────────────────────────────────────
for lang, root, sel, entry in ( ( "ts", TS, "LinearRouter.match", "serve" ), ( "go", GO, "Deb.Package", "main" ) ):
    for verb, tag in ( ( "--impact=", "impact" ), ( "--callers=", "callers" ), ( "--safe-delete=", "safe-delete" ) ):
        rc, out = run( root, verb + sel ); a = root_attrs( out, tag ) or {}
        seen[ "neg" ] += 1 if a else 0
        say( a != {} and "impls" not in a and a.get( "defs" ) == "1", "[%s] concrete %s" % ( lang, tag ),
             "%s%s: a bodied method keeps defs=1 and carries no impls=" % ( verb, sel ), "attrs=%s" % a )
    rc, out = run( root, "--path=%s,%s" % ( entry, sel ) ); a = root_attrs( out, "path" ) or {}
    seen[ "neg" ] += 1 if a else 0
    say( a != {} and "to_impls" not in a and "from_impls" not in a and a.get( "to_defs" ) == "1", "[%s] concrete path" % lang,
         "--path to a bodied method: no to_impls=, to_defs=1", "attrs=%s" % a )

# ── negative arms: a contract with NO implementor answers its honest zero, disclosed (impls=0) ─────────────────────────────
for lang, root, sel in ( ( "ts", TS, "Quiet.hush" ), ( "go", GO, "Quiet.Hush" ) ):
    rc, out = run( root, "--impact=" + sel ); a = root_attrs( out, "impact" ) or {}
    seen[ "zero" ] += 1 if a else 0
    say( a.get( "impls" ) == "0" and a.get( "reaches" ) == "0" and a.get( "defs" ) == "1", "[%s] zero impact" % lang,
         "--impact=%s: reaches=0 beside impls=0 (no implementor in the tree)" % sel, "attrs=%s" % a )
    rc, out = run( root, "--safe-delete=" + sel ); a = root_attrs( out, "safe-delete" ) or {}
    seen[ "zero" ] += 1 if a else 0; seen[ "safe" ] += 1 if a else 0
    say( a.get( "impls" ) == "0" and a.get( "risk" ) == "contract", "[%s] zero safe-delete" % lang,
         "--safe-delete=%s: risk=contract, never none-found, beside impls=0" % sel, "attrs=%s" % a )

# ── premise: every arm read an answer ───────────────────────────────────────────────────────────────────────────────────
for k, n in seen.items():
    say( n > 0, "[premise] %s" % k, "%d answers read" % n )
print( "bodilessseedcheck: %d pass, %d fail" % ( npass, nfail ) )
sys.exit( 1 if nfail else 0 )
PY
