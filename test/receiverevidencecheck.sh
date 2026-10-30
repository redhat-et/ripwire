#!/usr/bin/env bash
# receiverevidencecheck.sh — a call matched to a definition by NAME ALONE never presents as a single proven edge.
#
#   test/receiverevidencecheck.sh                          # uses build/ripwire on test/receiverevidencefix
#   RIPWIRE_BIN=asan/ripwire test/receiverevidencecheck.sh
#   test/receiverevidencecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. A member call `x.m()` (or, in a language with an implicit receiver, a bare `m()`) was bound to an
# in-repo definition of `m` because the NAME matched, with nothing proving the receiver is that definition's
# class. The answer then showed one confident row — and agents adopt a confident wrong row. Each shape below was
# a graded false row (paraphrased; the code is minimal and never built):
#   (Bm) a dynamic receiver bound to the wrong in-repo class: a request context's `ctx.onerror()` drawn to the
#        Application.onerror its file defines; an item's typed text field `item.text.Get()` drawn to Merger.Get;
#        a stored ASGI callable `self._send()` drawn to another class's nested `_send`; a constructor-assigned
#        field `this.bucket.listSchemas()` drawn to the caller's own class; a loop variable over inner routers
#        drawn to SmartRouter.add; `ctx.req.raw.headers.get()` drawn to Context.get because the file imports
#        Context; a member call `context.handler()` drawn to a same-named FREE function; an object-literal
#        module's `this.ctx.get()` drawn to that module's own `get`; a Go struct field or local named like a
#        package (`s.log.Errorf`) drawn to the in-repo `log.Errorf`.
#   (Bd) a builtin/library object behind a variable, in a file that names the class: WeakMap `.set/.get` → the
#        same file's accessors, Promise `.then` → Reply.prototype.then, a stream's `.on` → a TEST double,
#        `dict.get/keys/items` → StylesBase in a file that imports Styles, `list.append`/`str.split` →
#        Content.append/split, URLSearchParams `.append`, Set `.delete`, an outside router's `.all`, an asyncio
#        handle's `.cancel`, an outside parser's `.write`, an outside tcell screen's `.Size`, the globals
#        `Reflect.get` / `Atomics.add` beside in-repo `get` / `add`, a Python outside from-import
#        (`from json import dumps as stringify`) beside in-repo `stringify` / `dumps`.
#   (Bp) a parameter or local callable bound to a def elsewhere: `done()` (a parameter) → another file's
#        closure `done`; `read = os.read; read( fd )` → Stylesheet.read and `feed = parser.feed` → the base
#        class's feed when the parser is a constructed XTermParser (the rows FE-A's local-Keep rule restored);
#        `add_widget = widgets.append; add_widget( n )` → another class's nested add_widget; a JS alias
#        `const onerror = ctx.onerror` and a destructured `const { onerror } = ctx`, then `onerror( e )`.
#   (Bi) an implicit receiver (Java, Kotlin, C#, C++, Swift, Ruby): a bare `render()` / `flush()` inside a class
#        bound to an UNRELATED class's method, though the language reaches only the class's own members, its
#        superclasses and mixins, a free/top-level function, or an import.
#
# THE CONTRACT. Such a call either (a) RESOLVES WITH EVIDENCE — the receiver is `this`/`self`/`cls` inside the
# class or its cone, a construction in scope (`x = new Cls()`, `x = Cls()`, `m := &Merger{}`), a constructor-
# assigned field, a type annotation or declaration on the parameter/local (Go struct field, embedded field,
# aliased import), an import — and then shows one plain row; or (b) KEEPS ITS ROW WITH AN ON-ROW HEDGE:
# `via="name"` on the row itself (XML) / `"via":"name"` on the entry (MCP JSON), listing the by-name candidates
# — never a legend-only hedge, never a silent drop. Every surface shows the same row with the same hedge:
# --callees, --callers, --impact, --path, --connect, --expand <calls>, --for <calls>, the default map's <c> rows, and
# MCP find_symbol / find_referencing_symbols / analyze. A wrong candidate may also disappear (resolved elsewhere, or counted external/
# unresolved), but a TRUE target must stay visible, hedged or not. A SINGLE by-name candidate is hedged too:
# one candidate is not evidence (ruling D1). An --impact row at d>=2 that no all-proven path reaches inherits
# the hedge; a row with some all-proven path stays plain (ruling D3). Every surface's --legend=full (and the MCP
# tool description or answer) defines via="name" and says what it does NOT mean.
#
# PREDICATES (each over one answer; an answer about no symbol is NOROOT and never a pass; rows compare
# (kind, name, file[:line]) — the line only where a spec carries one):
#   notproven  — the named row is absent, or present WITH the hedge (the positive arms: red when unhedged)
#   proven     — the named row is present WITHOUT the hedge (evidence: a near miss a new rule could kill)
#   exactproven— the set of unhedged rows is exactly the given set (no false candidate rides along unhedged)
#   visible    — the named row is present, hedged or not (a true target is never dropped)
#   marked     — the named row is present WITH the hedge (a name-only true edge is kept and labelled)
#   ifacenamed — lane L6: the named row is a candidate of the answer's gate="iface" <dc> row (--legend=full cand=)
#
# ARMS (one fixture root per language under test/receiverevidencefix/; each root is indexed on its own).
#   (J) JS:  Bm ctx.onerror (plain, optional-chained, aliased, destructured), an object-literal module's
#            this.ctx.get, member call → free function; Bd WeakMap/Promise/stream/router/Set/URLSearchParams, the
#            globals Reflect/Atomics; Bp a `done` parameter. Evidence that must RESOLVE: a constructor-assigned field
#            (this.bucket → Schemas.listSchemas). Near misses: this.onerror, same-file bare call, relative module
#            receiver (also one bound to the name `Reflect`), a closure called in its own function, construction
#            in scope (`new Application()` / `new Schemas()` decide between same-named methods), super.m(), a
#            class-name (static) receiver; the name-only `reply.send()` / `reply.code()` on a parameter are kept
#            and marked.
#   (T) TS:  Bm a loop variable over Router<T>[] → SmartRouter.add; WHATWG Headers.get → Context.get/Cache.get;
#            the global Atomics.add. Near misses: an annotated parameter, construction through an import alias, a
#            constructed local.
#   (P) Python: Bd dict/set/list/str in a file that imports the class; an argument's .animate; asyncio handle;
#            an outside package's parser; an outside from-import (plain and aliased); Bm self._send → a nested
#            _send, a non-self receiver in the class's own file (mode_screen.refresh, the property self.screen);
#            Bp read = os.read, feed = parser.feed (base class and an unrelated class), add_widget =
#            widgets.append. Near misses: self.update, a constructor-assigned field (+ cone), a typed parameter
#            (+ cone), construction, an import alias, an imported function beside same-named methods,
#            cls.method(), a class-name receiver (Styles.copy), the XTermParser.feed the alias really reaches, a
#            proven and a name-only site to the same method (the merged row stays plain); a name-only parameter
#            call kept and marked.
#   (G) Go:  evidence that must RESOLVE (ruling D4): a typed struct field, a typed parameter, a typed local
#            through an aliased import, an embedded field's promoted method — each exactly the util.Chars row, never
#            Merger.Get/Length; Bd an outside screen's Size, an outside value's Runes, a field or local named `log`
#            of an outside type beside the in-repo log.Errorf. Near misses: a pointer-literal local, the method
#            receiver itself, a real import of the in-repo log package.
#   (G2) Go module aliases (gomod/, one tree per directory): an import path proves a package EXACTLY — the nearest
#            go.mod's module path plus the directory below it, or the path a local `replace L => ./D` gives D. Bm:
#            `replace github.com/up/lib => ./third/lib` beside an in-repo lib/ drew lib.Mark() to lib/ (a directory
#            that merely ends the path); `example.com/t/pkg/lib` proved both pkg/lib and lib/ (declined). Near misses:
#            a replace onto lib/ itself, a replaced legacy/ with and without its own go.mod, a nested module,
#            example.com/a vs example.com/ab, a vendored copy (never the in-repo lib/), a dot import (never the decoy),
#            and a path-less root lib/ beside a nested module that carries the path.
#   (T) Java/C#/Kotlin/Swift (review B3): a typed parameter, a typed / constructed / Java `var` local, a typed or
#            constructed field or property — read bare (implicit this) or through this/self — and a Kotlin `val`
#            constructor property RESOLVE to the declared class's member (Pump.*: Tank and Barrel both define spill).
#            Near misses stay hedged: an untyped local (a lower-case factory), a local that hides the field, an
#            interface/protocol-typed receiver with two implementors (both still listed). Every other binding form: (B).
#   (B) binding scope (review B4; scope/*: Tank and Barrel both define spill, the class's field / the outer binding is a
#            Tank). (a) A binding that HIDES the field or an outer typed local never lets the call prove the field's
#            class: Java for/lambda/catch/resource/instanceof/case/record-pattern variables, C# foreach/lambda/is/out
#            var/case/deconstruction/catch/LINQ, Kotlin for/destructuring/lambda/let/when/catch, Swift for-in/case let/
#            tuple/closure/if-guard-while let/catch, and the same shapes where FE-B reads TS/JS/Python/Go evidence
#            (arrow and catch parameters, for-of, a block const, a destructuring, a JS reassignment; a Python for/lambda/comprehension/
#            with/except/walrus/match/reassignment; a Go range/if/type-switch variable). Outside its block a local never
#            lends its class (a nested block, a lambda's typed parameter), and the field (or outer local) proves again.
#            (b) A generic's type parameter spelled like a class (`<Tank>`, `Box<Tank>`, `[Tank Spiller]`, `def f[Tank]`)
#            never proves that class. Kept: the field itself, a typed local, a typed loop / lambda variable's own class.
#   (I) implicit receiver: Java, Kotlin, C#, C++, Swift, Ruby — a bare call inside a class whose base is OUTSIDE
#            the tree (or that imports the name from outside) never proves an unrelated class's method. Near
#            misses: own members (private too), an in-repo superclass's member (the cone, and Java super.m()),
#            a free / top-level function and a Ruby top-level def; a Ruby included module is contract-only (resolved
#            or hedged, never a false proven row): Ruby's own lookup is separate work.
#   (S) the two sides of a class lookup: a JS/TS call on the CLASS object (`Gauge.read()`, `this` in a static member)
#            resolves to the static member only and an instance call never to it; a Kotlin companion member likewise;
#            a class-name call naming an instance-only member is never proven. A Python `__getattr__` changes nothing
#            for a member the class defines, and a name its lookup misses is never proven onto another class.
#   (H) propagation and parity: the name-only witness `respondWith → reply.send()` is marked in --callees,
#            --callers, --impact (d=1), --path, --connect, --expand <calls>, --for <calls>, the map's <c> rows, MCP
#            find_symbol, find_referencing_symbols and analyze; the false witness `respond → ctx.onerror()` is absent-or-marked on every
#            one of them; the --for HOP blocks (<h n=…><calls>) never prove encode → Response.append,
#            respond → Application.onerror, pipePayload → the test double's on, back → its own module's get;
#            --impact at d>=2 inherits the hedge (viaModule through respondWith → send; serve through
#            respond → onerror) unless some all-proven path reaches the row (both: direct → new Reply().send);
#            the legend of every surface defines via="name" with a NOT sentence; and the hedge bit is
#            VALUE-EQUAL between CLI --callees and MCP calls, CLI --callers and MCP calledBy, and --callees and
#            --expand <calls>, over a set of selectors.
#   (O) graded false callees seen on an earlier binary, as minimal repros: Go exec Cmd.Output → an in-repo
#            Output method (fmt.Errorf / strings.Split pinned clean), TS Date#getTime → an in-repo getTime (the
#            global Response pinned clean), Python list.append on a list literal → Content.append; each on
#            --callees and its --for hop block, with constructed-local near misses.
#   (R) the base-class receiver (CR 5469474915): C# `base` and `super` where it is a keyword (Java/Kotlin/Swift/JS/TS),
#            and Python's super() call, walk the bases only; a LOCAL spelled `base` (Python/JS/TS/Go/Java/Kotlin/Swift/C++/
#            Ruby) or `super` (Go, C#, a Python name shadowing the builtin) never proves the base class's method — a typed
#            one resolves to its own class, an untyped one is hedged. Twins: the keyword calls still prove the base.
#   (L) call-result typing (train 29 lane call-result-typing; roots callresult/<lang>/, unpacked from callresult.txt): a
#            binding initialised by a call — Go `x := f()` / `a, b := f()`, Rust `let x = f()?` / `let (a, _) = f()?` /
#            `.unwrap()`, C++ `auto x = f()`, Java `var`, Kotlin `val`/`var`, TS `const x = [await] f()` — takes the callee's
#            DECLARED return type when (1) the call commits exactly ONE target WITH evidence (a receiver rule, a resolved
#            qualifier, the language's own lookup, an import pin — never a pick by name alone, never a qualified written
#            type's final segment) and is not one of two nested same-named calls sharing its start (`h.get().get()`), and
#            (2) that type, after the language's wrapper rows (Go `*T`, `(T, error)` by position incl. named results, grouped
#            names `(a, b T)` one position per NAME; Rust Result/Option/Box/&T, tuples by position; C++ T&, T*,
#            std::unique_ptr<T> (its pointee under `->` only); TS Promise<T> under await), RESOLVES in the callee's file to
#            exactly ONE in-tree class: its imports (Java/Kotlin single-type imports, TS named / `import type` imports, Rust
#            `use`), its qualifier (Go import alias → an in-tree package; Rust crate/self/super/an in-tree crate or module;
#            C++ an in-tree namespace, std refused), else its own file, then its package (Go/Java/Kotlin: the directory) or
#            namespace (C++) — by ONE rule (fix round 3): walk the callee's lexical scopes innermost first and collect
#            EVERY binding of the spelling at each (a class declared there, an alias / typedef / `namespace a = b` /
#            Rust `type` / Kotlin `typealias` / TS `type` and `import A = n.T`, an import binding there (a Java single-
#            static-import too), a member type a base of an enclosing class declares, and (fix round 4) a declaration the
#            index keeps NO class for — a Java `record` / `@interface`, a C++ union or forward declaration (in the class's
#            own namespace it declares that class), a C++ block-scope binding in force in a local class — or a region the
#            parser cannot read that may declare ANY name: a C++ macro / parse error where a declaration must stand
#            (namespace, file or class scope), a Rust statement- or item-position macro in a block enclosing a nested fn);
#            the first scope with any binding decides — one in-tree class types,
#            an outside / unresolved binding, an alias, or two that disagree record nothing. A Rust `mod` is a fresh scope
#            (`super::` / `self::` inside it are relative to it); a package (the one the JVM files DECLARE) or module
#            contributes top-level classes only, then JVM on-demand imports (an outside one leaves the name unresolved);
#            a C++ unqualified result takes a using-declaration in force (its file or an included header) first, else a
#            class whose namespace encloses the callee's or a using-directive in force names; a type parameter of an
#            enclosing generic names no class. A JVM class-name receiver binds an in-tree class only where the CALLER's
#            file sees it by the same rule (`import ext.Util;` / `import ext.*;` alone: never the in-tree namesake). An outside import, an outside qualifier, a TS global, a name that resolves nowhere or twice
#            records NOTHING. The typed local carries that CLASS (not its name): a member call on it reaches that class's own
#            members (C++: a class name another in-tree class shares types nothing — Rule 2 keys members by name).
#            [P] RESOLVE (red before the lane); [N] near misses record NOTHING and stay as they were: an overloaded /
#            two-def callee, an outside callee (os.Open, String::new, std::async, List.of), a wrapper outside the list (Go
#            Ref[T], Rust Vec<T> / HashMap, C++ std::reference_wrapper, Java Optional<T>), a type-parameter result, a Go/Rust
#            alias (no alias record: floor), a callee with no written return type (Kotlin `= expr`, TS inference), and a
#            shadowing inner binding. A later reassignment `x = g()` keeps the declared type in these statically typed
#            languages (Go UseReassigned, Kotlin useVar: still proven). CHAINING: a call on a call-typed local, when proven,
#            types the next local in turn — in source order, inside the one resolve pass, no fixpoint (Rust use_path /
#            use_chain, Go/C++/Java/Kotlin/TS UseChain); a hop bound by name alone or split stops it. FLOORS (a typed shape
#            that proves no member, not gated): an INTERFACE result (Go UseIface — the bodyless signature is the ladder's,
#            L6) and an alias of an IN-TREE type (useAlias; every family's alias forms: the alias is not followed). An
#            alias of an OUTSIDE type spelled like an in-tree class is NOT a floor: it was a false proof before fix round 3
#            (D5) and is gated as a near miss (cpp3, matrix alias / typedef rows). Twins marked `# guard`
#            write the type and resolve before the lane (Rust has no such reader yet: no twin arm).
#            Proven-only near misses with a WRONG namesake in tree: an outside callee beside an in-tree def of the same name
#            (os.Open/model.Open, String::new/model::new, std::async/cfg::async, List.of/Configs.of, Object.freeze/freeze);
#            an outside result type whose last segment names an in-tree class (Go `*os.File`, Rust std::fs::File / `use
#            std::fs::File`, C++ ext::Config, Java/Kotlin `import java.io.File`, TS `ext-config` / `other-lib` / the global
#            Response) — the Go written/param/FIELD twins are held to the same qualifier rule; a nested same-named call; an
#            interface in one package beside a struct of the same name in another; a commit by name alone (C++
#            `ext::onlyOne()`) or by a written type's final segment (`ext::Factory f; f.make()`); a wrapper without its
#            operator (C++ `u.get()` on unique_ptr; Rust Option without `?`, one `?` on Result<Option<T>>, a trailing method
#            that is not unwrap/expect); a type parameter spelled like an in-tree class; both overloads of a C++ callee. Go
#            `pkg.F` (an import name, renamed or not) reaches package-level funcs only, never a method; a LOCAL spelled like
#            the import is not the package.
#            MATRIX (fix round 3, callresult_matrix.txt): language (Rust, C++, Java, Kotlin, TS, Go) x binding form x
#            scope level (file, namespace / module, nested, function body) x target (in-tree unique / outside /
#            unresolved / two in-tree), 222 cells + the N/A rows a language cannot write; a U cell proves exactly its
#            tagged row, every other cell proves none. FLOOR cells (U by the language, hedged here): an alias of an
#            in-tree type (Rust `type`, C++ alias / typedef, Kotlin `typealias`, TS `type` / `import A = n.T`, Go
#            `type A = t.T`), a Go dot import, a member type inherited from a base (Java, C++), two in-tree C++ classes of
#            one name (Rule 2 keys members by name). Fix round 4 adds the DECLARATION-KIND axis (recorded class /
#            unrecorded type-binding node "unrec:" / macro-unparsed "unparsed:"; the form column reads <kind>:<form>):
#            a Java record / @interface / single-static-import / static-import-on-demand, a C++ union / forward
#            declaration / macro (spelling the name, another name, or none) / block-scope using, alias, typedef, union
#            and forward declaration in force in a local class, a Rust macro in an enclosing fn body (and a guard each:
#            the callee's own body, a sibling fn), Java / Kotlin local classes — 268 cells in all. More FLOOR cells: a
#            Java record (in-tree, but the index keeps no class for it), a C++ local class beside a global namesake (two
#            classes of one name). A C++ macro at namespace / class scope that declares nothing hedges too (any macro
#            may declare the name: an honest loss, measured at 5 envoy sites). Fix round 5 (cells 269-288, arms cpp5 /
#            rust5): macros tree-sitter parses as WELL-FORMED code — a C++ class declaration only a macro can have
#            written (`class API S {…}`, `struct API S final {…}`, `struct API S;`, `API struct S {…}`, `MKSTRUCT S {…}`:
#            a bare-name function definition or class-key declaration — every name its head spells is a class the index
#            does not record, so no C++ result spelled so resolves), a class-body `MK(S);` (a type-less non-constructor
#            declaration: ANY name in that class), a C++ function-body statement beside a local class (any expression
#            statement: ANY name for that class's members), a Rust `impl` method in a fn body holding a macro; guards:
#            constructors / a destructor, a function-body macro with no local class, the own-namespace forward
#            declaration reached through a using-declaration. Fix round 6 (cells 289-294, arms rust6): a Rust `const` /
#            `static` item's value block is an item scope (a macro or `use` there decides for the impls written in it).
#            C++ OFF (owner 2026-10-17, fix round 6: model.h callResultFamilyOf maps C++ / ObjC to None): no C++ call
#            result is typed yet — every C++ [P] arm and U cell is a FLOOR that must HEDGE (`# [FLOOR] C++ off`; the
#            matrix prints them N … FLOOR), every C++ [N] stays; the C++ written-type twin (useWritten) stays proven.
#   (RS) Rust receiver evidence (lane rust-receivers; root rsrecv/, unpacked from rsrecv.txt): a receiver WRITTEN as a type
#            — a parameter (`&T`, `&mut T`, `Box<T>`, a `crate::` / module path, a user generic, an enum), `let x: T`, a
#            struct literal, `T::default()`, a closure's typed parameter — and a field path below one or below `self`
#            (`s.book.m()`, `self.book.m()`, `self.inner.book.m()`, each field by its own written type) proves exactly the
#            class the spelling resolves to at its site (the (L) resolution rule: item scopes, `use`s incl. a glob of a
#            module's own `use`, paths); a declared `-> Self` result types its call ((L)). [N]: an untyped `let x =
#            foo.bar()`, `dyn` / `impl` / generic-bound / bare-trait receivers (dispatch: lane L6), Option / Rc (a parameter,
#            a `let`, a field), a shadowing `let` / `for` / closure parameter, an outside `use std::fs::File` beside an
#            in-tree File, a tuple pattern, `String::default()`, a u32 / generic-`T` / tuple-struct field, a missing field,
#            a same-named owner whose field differs, a glob of a module that only globs (not followed: a floor). Early
#            gates review adds (src/adds.rs, alias.rs, samename.rs, consts.rs): self forms, lifetimes, `use … as`, same
#            names in two modules, Box<dyn> / Arc / RefCell / index / type-alias / element-type near misses, a const block.
#   (Q) qualified annotations and in-place rebinding (lane h1-annot; roots qualannot/<lang>/, unpacked from qualannot.txt).
#            A Python / TS parameter, annotated local or TS field written `q.T` / `q.T<…>` names the in-tree class T only when
#            the qualifier's ROOT `q` is an in-tree module or namespace as the file sees it: an import that resolves into the
#            tree (Python `import pkg.store`, `from pkg import store`, a relative import; TS a relative or tree-named specifier,
#            `import * as` / default / named / `require`), else — bound by no import — an in-tree class (`Outer.Inner`) or a TS
#            namespace. [N] (a false proven edge before the lane): `requests.Session`, `requests.Session = None`, an
#            annotation-only local, `import a.b as c` / `from outside import mod` / an outside class's nested `Holder.Session`,
#            an unbound or TYPE_CHECKING-imported outside qualifier, starlette's `request: httpx.Request` beside an in-tree
#            Request.read; TS `ext.Session<T>`, `ext.Session`, `s?: ext.Session`, a field `s: ext.Session`, an outside
#            default / named / require binding, the global `NodeJS.Session`. [P] guards: an in-tree module qualifier (Python
#            `model.Session`, `store.Store`, `pkg.store.Store`; TS `store.Store`, `store.Box<T>`, a default import of an
#            in-tree module, a file-local namespace `Local.Thing`), a bare imported T (plain and aliased), a nested class
#            `Outer.Inner`, a same-file class. Wrapped forms (`Optional[q.T]`, `q.T | None`, `list[q.T]`, a string
#            annotation) named no class before the lane and still name none.
#            A Python `x op= v` on a bare name rebinds x to what the operator returns: x keeps its class C only when the
#            ONE method Python calls — C's own (else the shallowest base's) in-place method (`+=` → `__iadd__` … `|=` →
#            `__ior__`), else, C defining none, its binary method (`__add__`: `x = x + v`) — returns its first parameter on
#            every `return` (starlette MutableHeaders `__ior__ … return self`), or declares `-> Self` or `-> C` (textual
#            Color `__add__ … -> Color`); otherwise — a return that is not provably C (7, a base's `-> Base` for a
#            subclass receiver), another operator's method — x is name-only. A JS `x op= v` rebinds as a plain JS reassignment does (JS has no operator methods).
#   (C) conservation: each root's census dispositions still sum to calls= with unaccounted=0 (no silent drop).
#   (K) the predicates can fail: a planted unhedged false row fails notproven, a planted hedged row passes it and
#            fails proven, marked rejects an unhedged row, a rootless or not-found answer is NOROOT, the MCP reader
#            reads the hedge, a non-zero or missing exit status fails the arm, a parser crash (a malformed defs=)
#            fails the arm, and a hop reader never reads another hop's <calls>.
#   GUARDS: arms marked `# guard` were already green on the pre-change binary; they pin a shape the change must
#            not break and are not evidence of the fix.
#
# FLOORS — named, not gated here:
#   * Objective-C (a method is only ever sent `[recv msg]`; a bare call is a C function — FE-A's ladder), PHP, Lua,
#     Zig, Dart, Elixir: no arm.
#   * a computed member `ctx['onerror']()` records no call at all (pinned notproven, trivially).
#   * return-type inference (`mode_screen = self.get_screen(); mode_screen.refresh()` → Screen.refresh, or a
#     property's return) is not required: only the false single row is gated. A DECLARED return type is (L)'s, for
#     Go/Rust/C++/Java/Kotlin/TS only; Python's `-> T` annotation, Swift, C# and PHP rows: not gated here yet.
#   * --uses / --dead-code / --safe-delete, and --for hop blocks of symbols other than the four named in (H): not
#     gated here.
#   * a Python `cls()` construction inside a classmethod is polymorphic (a subclass's override is a legitimate
#     candidate): no arm.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that indexes a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/receiverevidencefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "receiverevidencecheck: BIN=$BIN  CORPUS=$CORPUS"

# arm (L)'s roots (callresult/<lang>) live in one text bundle unpacked into the temp dir: committed as source trees they
# joined the repo's own indexed map (readmedriftcheck G4's --max-tokens=3000 head lost two rows)
# (arm (RS)'s root rsrecv/ and arm (Q)'s roots qualannot/<lang> the same way, from rsrecv.txt and qualannot.txt)
for bundle in "$CORPUS/callresult.txt:$TMP/fix/callresult" "$CORPUS/qualannot.txt:$TMP/fix/qualannot" "$CORPUS/rsrecv.txt:$TMP/fix"; do
[ -f "${bundle%%:*}" ] || { echo "fixture missing: ${bundle%%:*}"; exit 2; }
python3 -I - "${bundle%%:*}" "${bundle#*:}" <<'PY' || { echo "could not unpack ${bundle%%:*}"; exit 2; }
import os, sys
out, cur, n = sys.argv[ 2 ], None, 0
for line in open( sys.argv[ 1 ], encoding="utf-8" ):
    if line.startswith( "@@@ " ):
        if cur: cur.close()
        path = os.path.join( out, line[ 4: ].strip() )
        os.makedirs( os.path.dirname( path ), exist_ok=True )
        cur = open( path, "w", encoding="utf-8" ); n += 1
    elif cur:
        cur.write( line )
if cur: cur.close()
sys.exit( 0 if n > 0 else 1 )
PY
done
# rw ROOT ARGS… — run against one fixture root (every selector below is relative to that root's `.`)
rw(){ local r="$1" d="$CORPUS/$1"; shift; case "$r" in callresult/*|qualannot/*|rsrecv) d="$TMP/fix/$r" ;; esac; ( cd "$d" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# ── the one reader every predicate shares ─────────────────────────────────────────────────────────────────────
# parse.py MODE FILE [ARGS] — prints one line per row; NOROOT when the document has no answer about a symbol.
# It EXITS NON-ZERO on malformed input (a non-numeric defs=/to_defs=/reachable=) or on any crash, and every call
# site goes through P, which FAILs the arm on a non-zero exit (a crash never reads as "no rows").
#   rows    <s> rows of a callees/callers/impact/path answer: "t n path line H d" (H = name | -, d = depth or -)
#   ecalls  <c> rows inside <calls> (all of them, or only those inside the <b> body named ARG): "n line H"
#           (a joined row `l="4,8"` prints one line per line number)
#   hcalls  <c> rows inside the --for HOP block <h n=ARG>: "n line H" (NOROOT when that hop is not shown)
#   edges   <e> rows of a connect answer: "f t H"
#   mcp     the entries of one array (ARG) of an MCP tools/call result: "name file line H"
#   map     <c> rows of the default MAP: "caller file callee H" (NOROOT without an <r> map root)
#   mcpmap  the same over the map an MCP tools/call (analyze) returned
#   legend  DEFINED when the answer's legend comments define via="name" — the mechanism ("name alone") and a
#           NOT sentence ("does NOT mean") within the definition — else UNDEFINED
#   mcplegend  the same over an MCP stream: the tools/list description of tool ARG, or the tools/call answer
cat >"$TMP/parse.py" <<'PY'
import json, re, sys
mode, path = sys.argv[ 1 ], sys.argv[ 2 ]
arg = sys.argv[ 3 ] if len( sys.argv ) > 3 else ""
doc = open( path, encoding="utf-8", errors="replace" ).read()
def attr( tag, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', tag )
    return m.group( 1 ) if m else None
def num( v, what ):
    if v is None:
        return None
    if not re.fullmatch( r"[0-9]+", v ):
        sys.stderr.write( "non-numeric %s=%r\n" % ( what, v ) )
        sys.exit( 3 )
    return int( v )
def hedge( tag ):
    return "name" if attr( tag, "via" ) == "name" else "-"
def crows( scope ):
    blocks = re.findall( r"<calls[ >].*?</calls>", scope, re.S )
    if not blocks:
        print( "NOROOT" ); sys.exit( 0 )
    for b in blocks:
        for c in re.findall( r"<c [^>]*>", b ):
            for l in ( attr( c, "l" ) or "-" ).split( "," ):
                print( attr( c, "n" ), l, hedge( c ) )
DEF = re.compile( r'via="name".{0,700}?name alone.{0,700}?does NOT mean', re.S )
if mode == "rows":
    root = re.search( r"<(callees|callers|impact|path) [^>]*>", doc )
    if not root:
        print( "NOROOT" ); sys.exit( 0 )
    head = root.group( 0 )
    found = num( attr( head, "defs" ), "defs" )
    if found is None:
        found = num( attr( head, "to_defs" ), "to_defs" )
    if root.group( 1 ) != "path" and ( found is None or found < 1 ):
        print( "NOROOT" ); sys.exit( 0 )
    depth = "-"
    for s in re.findall( r"<s [^>]*/>", doc[ root.start(): ] ):
        t, n, p = attr( s, "t" ), attr( s, "n" ), attr( s, "p" )
        if not ( t and n and p ):
            continue
        if attr( s, "d" ):
            depth = str( num( attr( s, "d" ), "d" ) )
        f, _, l = p.rpartition( ":" )
        print( t, n, f, l, hedge( s ), depth )
elif mode == "ecalls":
    scope = doc
    if arg:
        m = re.search( r'<b\b[^>]*\sn="' + re.escape( arg ) + r'"[^>]*>(.*?)</b>', doc, re.S )
        if not m:
            print( "NOROOT" ); sys.exit( 0 )
        scope = m.group( 1 )
    crows( scope )
elif mode == "hcalls":
    m = re.search( r'<h\b[^>]*\sn="' + re.escape( arg ) + r'"[^>]*>(.*?)</h>', doc, re.S )
    if not arg or not m:
        print( "NOROOT" ); sys.exit( 0 )
    crows( m.group( 1 ) )
elif mode == "edges":
    root = re.search( r"<connect [^>]*>", doc )
    if not root:
        print( "NOROOT" ); sys.exit( 0 )
    for e in re.findall( r"<e [^>]*/>", doc[ root.start(): ] ):
        print( attr( e, "f" ), attr( e, "t" ), hedge( e ) )
elif mode == "mcp":
    try:
        r = json.loads( doc.strip().splitlines()[ -1 ] )
        d = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
    except Exception:
        print( "NOROOT" ); sys.exit( 0 )
    if d.get( arg ) is None:
        print( "NOROOT" ); sys.exit( 0 )
    for e in d[ arg ]:
        print( e.get( "name" ), e.get( "file" ), e.get( "line" ), "name" if e.get( "via" ) == "name" else "-" )
elif mode in ( "map", "mcpmap" ):
    if mode == "mcpmap":
        try:
            r = json.loads( doc.strip().splitlines()[ -1 ] )
            doc = r[ "result" ][ "content" ][ 0 ][ "text" ]
        except Exception:
            print( "NOROOT" ); sys.exit( 0 )
    if not re.search( r"<r[ >]", doc ):
        print( "NOROOT" ); sys.exit( 0 )
    for f in re.finditer( r'<f [^>]*>(.*?)</f>', doc, re.S ):
        fp = attr( f.group( 0 )[ :f.group( 0 ).index( ">" ) + 1 ], "p" )
        for s in re.finditer( r'<s ([^>]*?)(?:/>|>(.*?)</s>)', f.group( 1 ), re.S ):
            for c in re.findall( r"<c [^>]*>", s.group( 2 ) or "" ):
                print( attr( "<s " + s.group( 1 ) + ">", "n" ), fp, attr( c, "n" ), hedge( c ) )
elif mode == "legend":
    text = " ".join( re.findall( r"<!--(.*?)-->", doc, re.S ) )
    print( "DEFINED" if DEF.search( text ) else "UNDEFINED" )
elif mode == "mcplegend":
    texts = []
    for line in doc.splitlines():
        try:
            r = json.loads( line )
        except Exception:
            continue
        res = r.get( "result" ) or {}
        for t in res.get( "tools" ) or []:
            if t.get( "name" ) == arg:
                texts.append( t.get( "description" ) or "" )
        for c in res.get( "content" ) or []:
            texts.append( c.get( "text" ) or "" )
    if not texts:
        print( "NOROOT" ); sys.exit( 0 )
    norm = " ".join( texts ).replace( '"via":"name"', 'via="name"' )
    print( "DEFINED" if DEF.search( norm ) else "UNDEFINED" )
else:
    sys.stderr.write( "unknown mode %s\n" % mode ); sys.exit( 2 )
PY
# P MODE FILE [ARG] — the reader's output into $PARSED; a non-zero exit (crash, malformed input) FAILs the arm
P(){
    PARSED="$( python3 "$TMP/parse.py" "$@" 2>"$TMP/parse.err" )"
    local rc=$?
    if [ "$rc" -ne 0 ]; then no "the reader exited rc=$rc on [$*]: $( head -c 300 "$TMP/parse.err" | tr '\n' ' ' )"; return 1; fi
    return 0
}

# answer ROOT VERB SEL [EXTRA…] — write the verb's answer to a per-call file, its exit status beside it (FILE.rc)
answer(){
    local r="$1" v="$2" s="$3"; shift 3
    local f; f="$TMP/$( printf '%s' "$r" | tr '/' '_' ).$v.$( printf '%s' "$s$*" | tr '/:.,= ' '______' ).xml"
    rw "$r" "--$v=$s" "$@" >"$f"; printf '%s' "$?" >"$f.rc"
    printf '%s' "$f"
}
# ran_ok LABEL FILE — the run behind FILE exited 0 (a non-zero or missing exit status FAILs the arm)
ran_ok(){
    local rc; rc="$( cat "$2.rc" 2>/dev/null )"
    if [ "$rc" = "0" ]; then return 0; fi
    no "$1 exited rc=${rc:-unknown}"; return 1
}
# rowsof LABEL FILE — the rows of FILE into $GOT; a reader failure or an answer about no symbol FAILs (returns 1)
rowsof(){
    GOT=""
    P rows "$2" || return 1
    GOT="$PARSED"
    if [ "$GOT" = "NOROOT" ]; then no "$1 produced no answer about a symbol"; return 1; fi
    return 0
}
# getrows ROOT VERB SEL — rows of the verb's answer into $GOT ("" on a failed run or reader, FAIL already printed)
getrows(){
    local f; f="$( answer "$1" "$2" "$3" )"; GOT=""
    ran_ok "($1) --$2=$3" "$f" || return 1
    rowsof "($1) --$2=$3" "$f"
}
# QUALNAME-1: a member row prints Owner::name / Owner.name / Owner#name (the owner is part of the spelling). Every arm below keys a row by
# (kind, BARE name, path[:line]) - the bare name matches the bare spelling AND any Owner-qualified one, so a notproven negative rejects both
# spellings (never a vacuous pass on a row that moved to its qualified name). The exact qualified spelling is pinned by the (Qs) arms.
AWKB='function bare( s ) { sub( /^.*(::|[.#])/, "", s ); return s }'
# match SPEC — the awk condition for "n path[:line]" over a rows line "t n path line H d"
specmatch(){   # prints the matching rows of $GOT for SPEC
    local n="${1%% *}" p="${1#* }" l=""
    case "$p" in *:[0-9]*) l="${p##*:}"; p="${p%:*}";; esac
    printf '%s\n' "$GOT" | awk -v n="$n" -v p="$p" -v l="$l" "$AWKB"' NF >= 5 && ( $2 == n || bare( $2 ) == n ) && $3 == p && ( l == "" || $4 == l )'
}
show(){ printf '%s' "$GOT" | awk 'NF >= 5 { printf "%s %s %s:%s%s; ", $1, $2, $3, $4, ( $5 == "name" ? " via=name" : "" ) }'; }

notproven(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec hits
    for spec in "$@"; do
        hits="$( specmatch "$spec" | awk '$5 != "name"' )"
        if [ -n "$hits" ]; then no "($r) --$v=$s shows [$spec] as a PROVEN edge (no receiver evidence, no via=\"name\"): $( show )"
        else ok "($r) --$v=$s never proves [$spec] (absent or hedged)"; fi
    done
}
proven(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec t hits
    for spec in "$@"; do
        t="${spec%% *}"; hits="$( specmatch "${spec#* }" | awk -v t="$t" '$1 == t && $5 != "name"' )"
        if [ -n "$hits" ]; then ok "($r) --$v=$s keeps the proven row [$spec]"
        else no "($r) --$v=$s lost or hedged the proven row [$spec]: $( show )"; fi
    done
}
exactproven(){
    local r="$1" v="$2" s="$3" want="$4" got
    getrows "$r" "$v" "$s" || return
    got="$( printf '%s\n' "$GOT" | awk "$AWKB"' NF >= 5 && $5 != "name" { print $1 " " bare( $2 ) " " $3 }' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    want="$( printf '%s' "$want" | tr ';' '\n' | awk "$AWKB"' { n = $2; $2 = bare( n ); print }' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    if [ "$got" = "$want" ]; then ok "($r) --$v=$s unhedged rows are exactly [${want:-none}]"
    else no "($r) --$v=$s unhedged rows are [${got:-none}], want [${want:-none}]"; fi
}
visible(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec
    for spec in "$@"; do
        if [ -n "$( specmatch "$spec" )" ]; then ok "($r) --$v=$s shows the true target [$spec] (hedged or not)"
        else no "($r) --$v=$s does not show the true target [$spec]: $( show )"; fi
    done
}
# lane L6: the true targets are named as the candidates of a gate="iface" <dc> row (the call declined through its receiver's
# interface, ifacedispatch.h) — on --legend=full, where cand= lists them as file:line
ifacenamed(){
    local r="$1" v="$2" s="$3"; shift 3
    local f; f="$( answer "$r" "$v" "$s" --legend=full )"
    ran_ok "($r) --$v=$s --legend=full" "$f" || return
    local spec cands
    cands="$( grep -o '<dc [^>]*gate="iface"[^>]*>' "$f" | grep -o 'cand="[^"]*"' | sed 's/^cand="//; s/"$//' | tr ' ' '\n' )"
    for spec in "$@"; do
        if printf '%s\n' "$cands" | grep -qx "${spec#* }"; then ok "($r) --$v=$s names the true target [$spec] as a gate=\"iface\" candidate"
        else no "($r) --$v=$s does not name [$spec] among its gate=\"iface\" candidates: [$( printf '%s' "$cands" | tr '\n' ' ' )]"; fi
    done
}
marked(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec
    for spec in "$@"; do
        if [ -n "$( specmatch "$spec" | awk '$5 == "name"' )" ]; then ok "($r) --$v=$s keeps [$spec] marked via=\"name\""
        elif [ -n "$( specmatch "$spec" )" ]; then no "($r) --$v=$s shows the name-only [$spec] with no via=\"name\": $( show )"
        else no "($r) --$v=$s dropped the name-only true edge [$spec]: $( show )"; fi
    done
}
# hopnotproven ROOT QUERY HOP NAME LINE — the --for answer shows the hop block <h n=HOP>, and that hop's <calls> row
# NAME at l=LINE is absent or via="name". A hop with no block is read through the HOP-SLOT RULE (test/forsigspancheck.sh
# (H)): a hop candidate whose every callee edge is name-only gets no <h> row and counts in noedge=. Then the arm reads
# the same fact off --callees instead, and every premise is checked, so an absent hop is never an empty pass: HOP's <d>
# row is in the answer with r= within <hops total=> (it was a hop candidate), noedge= >= 1, and --callees=FILE:HOP lists
# NAME and proves no row at all (else the hop was dropped for another reason: FAIL).
hopnotproven(){
    local r="$1" q="$2" h="$3" n="$4" l="$5" f
    f="$( answer "$r" for "$q" )"
    ran_ok "($r) --for=\"$q\"" "$f" || return
    P hcalls "$f" "$h" || return
    if [ "$PARSED" = "NOROOT" ]; then
        local drow hp hr htot hne ft
        # head round-robin (lane hrr, train 31; PROCESS rule 4): the answer's shown r= is the reordered rank (<sigs files_first=N>),
        # while the hops walk the surface in SCORE order (<hops total=> counts score ranks), so the hop-candidate premise reads the
        # HOP row's r= off the RIPWIRE_NO_HEAD_RR=1 twin of the same call (score order). The hop block and noedge= read the answer.
        ft="$f.rrtwin"; RIPWIRE_NO_HEAD_RR=1 rw "$r" "--for=$q" >"$ft" || { no "($r) --for=\"$q\" [RIPWIRE_NO_HEAD_RR=1 twin] exited non-zero"; return; }
        drow="$( grep -o "<d [^>]*n=\"$h\"[^>]*>" "$ft" | head -1 )"
        hp="$( printf '%s' "$drow" | sed -n 's/.* p="\([^"]*\)".*/\1/p' )"
        hr="$( printf '%s' "$drow" | sed -n 's/.* r="\([0-9][0-9]*\)".*/\1/p' )"
        htot="$( grep -o '<hops [^>]*>' "$f" | head -1 | sed -n 's/.* total="\([0-9][0-9]*\)".*/\1/p' )"
        hne="$( grep -o '<hops [^>]*>' "$f" | head -1 | sed -n 's/.* noedge="\([0-9][0-9]*\)".*/\1/p' )"
        case "$hp|$hr|$htot|$hne" in
            *'||'*|'|'*|*'|') no "($r) --for=\"$q\" shows no hop <h n=\"$h\">, and the hop-slot premises are unreadable (d p=/r=: '$hp'/'$hr', hops total=/noedge=: '$htot'/'$hne')"; return ;;
        esac
        if [ "$hr" -gt "$htot" ] || [ "$hne" -lt 1 ]; then
            no "($r) --for=\"$q\" shows no hop <h n=\"$h\">, and it was no dropped hop candidate (score r=$hr on the RR-off twin, hops total=$htot, noedge=$hne)"; return
        fi
        getrows "$r" callees "$hp:$h" || return
        if [ -z "$( printf '%s\n' "$GOT" | awk -v n="$n" "$AWKB"' NF >= 5 && ( $2 == n || bare( $2 ) == n )' )" ]; then
            no "($r) --for=\"$q\" dropped hop $h, and --callees=$hp:$h does not list $n either: $( show )"
        elif [ -n "$( printf '%s\n' "$GOT" | awk 'NF >= 5 && $5 != "name"' )" ]; then
            no "($r) --for=\"$q\" dropped hop $h, yet --callees=$hp:$h proves a row (the hop-slot rule does not explain the drop): $( show )"
        else
            ok "($r) --for=\"$q\": hop $h takes no slot (every callee name-only: --callees=$hp:$h, noedge=$hne), so it never proves <c n=\"$n\">"
        fi
        return
    fi
    if [ -n "$( printf '%s\n' "$PARSED" | awk -v n="$n" -v l="$l" '$1 == n && $2 == l && $3 != "name"' )" ]; then
        no "($r) --for=\"$q\": hop $h proves <c n=\"$n\" l=\"$l\"> (no via=\"name\"): $( printf '%s' "$PARSED" | tr '\n' ';' )"
    else ok "($r) --for=\"$q\": hop $h never proves <c n=\"$n\" l=\"$l\"> (absent or hedged)"; fi
}

echo "=== (J) JS: receivers with no evidence never prove a same-named method ==="
notproven js callees lib/application.js:respond "onerror lib/application.js"
visible   js callees lib/application.js:respond "onerror lib/context.js"
notproven js callees lib/application.js:respondSafely "onerror lib/application.js"
notproven js callees lib/application.js:respondComputed "onerror lib/application.js"   # guard: no call recorded today
notproven js callees lib/application.js:respondAlias "onerror lib/application.js"     # guard
notproven js callees lib/application.js:respondDestructured "onerror lib/application.js"   # guard
notproven js callees lib/delegate/response.js:back "get lib/delegate/response.js"
visible   js callees lib/delegate/response.js:back "get lib/delegate/request.js"
notproven js callees lib/handle.js:run "handler lib/handle.js"
notproven js callees lib/request.js:compile "get lib/request.js" "set lib/request.js"
notproven js callees lib/reply.js:awaitResult "then lib/reply.js"
notproven js callees lib/reply.js:pipePayload "on test/server.test.js"
notproven js callees lib/routes.js:fallback "all lib/routes.js"
notproven js callees lib/routes.js:forget "delete lib/routes.js"
notproven js callees lib/search.js:encode "append lib/response.js"
notproven js callees lib/reply.js:writePayload "done lib/parser.js"
notproven js callees lib/meta.js:peek "get lib/meta.js" "get lib/reflect.js"   # guard
notproven js callees lib/meta.js:bump "add lib/meta.js"   # guard
echo "--- (J) evidence decides between same-named methods, and a constructor-assigned field RESOLVES"
exactproven js callees lib/uses.js:build "cls Application lib/application.js;method onerror lib/application.js;cls Schemas lib/schemas.js;method listSchemas lib/schemas.js"
notproven js callees lib/application.js:schemas "listSchemas lib/application.js"
exactproven js callees lib/application.js:schemas "method listSchemas lib/schemas.js"
echo "--- (J) near misses: true edges kept"
exactproven js callees lib/application.js:handle "method onerror lib/application.js;fn respond lib/application.js"
exactproven js callees lib/handle.js:wrapped "fn handler lib/handle.js"
exactproven js callees lib/uses.js:viaModule "fn respondWith lib/reply.js"
exactproven js callees lib/uses.js:make "method create lib/application.js"   # guard: a class-name (static) receiver
exactproven js callees lib/listing.js:list "method listSchemas lib/schemas.js"   # guard: super.listSchemas()
exactproven js callees lib/mirror.js:look "method get lib/reflect.js"   # guard: a relative module bound to `Reflect`
exactproven js callees lib/trailer.js:sendTrailer "fn send lib/trailer.js"
exactproven js callees lib/reply.js:direct "fn Reply lib/reply.js;method send lib/reply.js"
notproven js callees lib/reply.js:notFound "send lib/trailer.js"
marked    js callees lib/reply.js:notFound "code lib/reply.js" "send lib/reply.js"
marked    js callees lib/reply.js:respondWith "send lib/reply.js"

echo "=== (T) TS ==="
notproven ts callees src/router/smart.ts:match "add src/router/smart.ts"
notproven ts callees src/middleware/auth.ts:bearer "get src/context.ts" "get src/cache.ts"   # cache.ts: guard
notproven ts callees src/atomics.ts:bump "add src/atomics.ts" "add src/router/smart.ts" "add src/router/trie.ts"   # guard
echo "--- (T) near misses: annotation, alias construction, constructed local"
exactproven ts callees src/middleware/auth.ts:readUser "method get src/context.ts"
exactproven ts callees src/middleware/alias.ts:remember "cls Context src/context.ts;method set src/context.ts"
exactproven ts callees src/middleware/alias.ts:single "cls TrieRouter src/router/trie.ts;method add src/router/trie.ts;method match src/router/trie.ts"

echo "=== (P) Python ==="
notproven py callees src/tui/css/stylesheet.py:reparse "get src/tui/css/styles.py" "keys src/tui/css/styles.py" "items src/tui/css/styles.py" "update src/tui/css/stylesheet.py"   # update: guard
notproven py callees src/tui/css/stylesheet.py:refresh_rules "animate src/tui/css/styles.py"
notproven py callees src/tui/reactive.py:watch "append src/tui/content.py"
notproven py callees src/tui/reactive.py:toggle "split src/tui/content.py" "split src/tui/geometry.py"   # geometry.py: guard
notproven py callees src/tui/callback.py:invoke "call_later src/tui/message_pump.py" "cancel src/tui/worker.py"
notproven py callees src/web/formparsers.py:parse_form "write src/web/datastructures.py"
notproven py callees src/web/requests.py:send_json "_send src/web/errors.py"
notproven py callees src/web/render.py:render "stringify src/web/jsonutil.py" "dumps src/web/jsonutil.py"   # guard: outside from-import
notproven py callees src/tui/app.py:switch_mode "refresh src/tui/app.py"
notproven py callees src/tui/app.py:repaint_screen "refresh src/tui/app.py"
visible   py callees src/tui/app.py:repaint_screen "refresh src/tui/screen.py"
notproven py callees src/tui/drivers/linux.py:process_events "read src/tui/css/stylesheet.py" "feed src/tui/xterm_parser.py:2" "feed src/tui/byte_stream.py"
notproven py callees src/tui/screen.py:collect "add_widget src/tui/compositor.py"
echo "--- (P) near misses: self, constructor-assigned field, typed parameter, construction, alias, import, cls"
proven    py callees src/tui/drivers/linux.py:process_events "fn feed src/tui/xterm_parser.py:7"
exactproven py callees src/tui/css/stylesheet.py:own "fn update src/tui/css/stylesheet.py;fn get src/tui/css/styles.py"
# repaint: self.refresh() (proven) and self.screen.refresh() (a property: name-only) reach the same App.refresh;
# the merged row stays plain, and Screen.refresh may only ride along hedged
exactproven py callees src/tui/app.py:repaint "fn refresh src/tui/app.py"
exactproven py callees src/tui/uses.py:sync "fn update src/tui/css/stylesheet.py"
exactproven py callees src/tui/uses.py:apply "fn animate src/tui/css/styles.py"
exactproven py callees src/tui/uses.py:build "cls Stylesheet src/tui/css/stylesheet.py;fn update src/tui/css/stylesheet.py;fn read src/tui/css/stylesheet.py"
exactproven py callees src/tui/uses.py:clone "fn copy src/tui/css/styles.py"   # guard: a class-name receiver
exactproven py callees src/tui/css/stylesheet.py:parse_rules "fn parse src/tui/css/parse.py"
exactproven py callees src/tui/css/stylesheet.py:blank "fn default_rules src/tui/css/stylesheet.py"
marked    py callees src/tui/callback.py:schedule "call_later src/tui/message_pump.py"

echo "=== (G) Go: declared types RESOLVE (D4) ==="
notproven go callees src/result.go:buildResult "Get src/merger.go" "Length src/merger.go"
exactproven go callees src/result.go:buildResult "method Get src/util/chars.go;method Length src/util/chars.go"
exactproven go callees src/result.go:fromValue "method Get src/util/chars.go"
exactproven go callees src/embed.go:aliased "method Length src/util/chars.go"
notproven go callees src/embed.go:firstRune "Get src/merger.go"
exactproven go callees src/embed.go:firstRune "method Get src/util/chars.go"
notproven go callees src/tui/tcell.go:MaxY "Size src/tui/tcell.go"
notproven go callees src/tui/tcell.go:Graphemes "Runes src/tui/tcell.go"
notproven go callees src/service.go:Fail "Errorf src/internal/log/log.go"
notproven go callees src/service.go:Report "Errorf src/internal/log/log.go"
echo "--- (G) near misses: a pointer-literal local, the method receiver itself, a real package import"
exactproven go callees src/result.go:merged "method Length src/merger.go"
exactproven go callees src/merger.go:First "method Get src/merger.go"
exactproven go callees src/tui/tcell.go:Lines "method Size src/tui/tcell.go"
exactproven go callees src/cmd/run.go:Run "fn Errorf src/internal/log/log.go"   # guard

echo "=== (G2) Go module aliases: an import path proves a package exactly ==="
mkdir -p "$TMP/gomod"
exactproven gomod/fork2 callees app/app.go:Use "fn Mark third/lib/l.go"   # Bm: lib/ merely ends github.com/up/lib
notproven   gomod/fork2 callees app/app.go:Use "Mark lib/l.go"
exactproven gomod/tail  callees app/app.go:Use "fn Mark pkg/lib/l.go"     # Bm: lib/ ends example.com/t/pkg/lib too
exactproven gomod/tail  callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/fork  callees app/app.go:Use "fn Mark lib/l.go"         # near miss: the replace names lib/ itself
exactproven gomod/rep   callees app/app.go:Use "fn Mark legacy/lib/l.go"  # near miss: replaced, with its own go.mod
exactproven gomod/rep   callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/rep2  callees app/app.go:Use "fn Mark legacy/lib/l.go"  # near miss: replaced, under the root go.mod only
exactproven gomod/rep2  callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/nest  callees app/app.go:Use "fn Mark other/util/u.go"  # near miss: a nested module
exactproven gomod/pfx   callees app/app.go:Use "fn Mark ab/lib/l.go"      # near miss: example.com/a vs example.com/ab
exactproven gomod/pfx   callees app/near.go:Near "fn Mark lib/l.go"
notproven   gomod/vend  callees app/app.go:Use "Mark lib/l.go"            # near miss: the vendored copy is the package
notproven   gomod/dot   callees app/app.go:Use "Mark decoy/d.go"          # near miss: a dot import (lib/ unresolved: a floor)
exactproven gomod/mixed callees m/app/app.go:Use "fn Mark m/lib/l.go"     # near miss: a path-less lib/ never takes a carried path

echo "=== (T) Java/C#/Kotlin/Swift: declared receivers RESOLVE (review B3) ==="
exactproven java  callees src/main/java/app/Pump.java:param "method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:typedLocal "method spill src/main/java/app/Pump.java;method makeTank src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:ctorLocal "cls Tank src/main/java/app/Pump.java;method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:varLocal "cls Tank src/main/java/app/Pump.java;method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:implicitField "method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:thisField "method spill src/main/java/app/Pump.java"
proven      java  callees src/main/java/app/Pump.java:param "method spill src/main/java/app/Pump.java:7"
notproven   java  callees src/main/java/app/Pump.java:untyped "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"       # near miss: an untyped local
notproven   java  callees src/main/java/app/Pump.java:shadow "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"        # near miss: a local hides the field
notproven   java  callees src/main/java/app/Pump.java:viaIface "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"      # near miss: an interface, two implementors
ifacenamed  java  callees src/main/java/app/Pump.java:viaIface "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"   # lane L6: was `visible` as two via="name" rows; now one gate="iface" <dc> naming both
exactproven cs    callees App/Pump.cs:Param "method Spill App/Pump.cs"
exactproven cs    callees App/Pump.cs:TypedLocal "method Spill App/Pump.cs;method MakeTank App/Pump.cs"
exactproven cs    callees App/Pump.cs:CtorLocal "method Spill App/Pump.cs;cls Tank App/Pump.cs"
exactproven cs    callees App/Pump.cs:ImplicitField "method Spill App/Pump.cs"
exactproven cs    callees App/Pump.cs:ThisField "method Spill App/Pump.cs"
proven      cs    callees App/Pump.cs:ViaProperty "method Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:Untyped "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:Shadow "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:ViaIface "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
visible     cs    callees App/Pump.cs:ViaIface "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
exactproven kt    callees src/app/Pump.kt:param "fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:typedLocal "fn spill src/app/Pump.kt;fn makeTank src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:ctorLocal "cls Tank src/app/Pump.kt;fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:implicitField "fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:thisField "fn spill src/app/Pump.kt"
proven      kt    callees src/app/Pump.kt:ctorProperty "fn spill src/app/Pump.kt:8"
proven      kt    callees src/app/Pump.kt:constructedProperty "fn spill src/app/Pump.kt:7"
notproven   kt    callees src/app/Pump.kt:untyped "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
notproven   kt    callees src/app/Pump.kt:shadow "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
notproven   kt    callees src/app/Pump.kt:viaIface "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
ifacenamed  kt    callees src/app/Pump.kt:viaIface "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"   # lane L6: was `visible` as two via="name" rows; now one gate="iface" <dc> naming both
exactproven swift callees Sources/App/Pump.swift:param "fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:typedLocal "fn spill Sources/App/Pump.swift;fn makeTank Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:ctorLocal "cls Tank Sources/App/Pump.swift;fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:implicitField "fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:selfField "fn spill Sources/App/Pump.swift"
proven      swift callees Sources/App/Pump.swift:constructedProperty "fn spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:untyped "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:shadow "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:viaIface "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
visible     swift callees Sources/App/Pump.swift:viaIface "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"

echo "=== (B) binding scope (review B4): a binding that hides a field or an outer local, and a type parameter ==="
# hides ROOT FILE NAME OUTER BOUND FN… — at each FN's call, a binding of the receiver's name hides the field (or outer local)
# whose class defines NAME at line OUTER: that edge is never PROVEN, and the candidate at line BOUND (the binding's own
# class) stays visible, hedged or proven. Outside a binding's scope the roles swap (OUTER = the binding's class).
hides(){
    local r="$1" f="$2" n="$3" outer="$4" bound="$5" fn; shift 5
    for fn in "$@"; do
        notproven "$r" callees "$f:$fn" "$n $f:$outer"
        visible   "$r" callees "$f:$fn" "$n $f:$bound"
    done
}
J=src/app/Scope.java; C=App/Scope.cs; K=src/app/Scope.kt; W=Sources/App/Scope.swift
hides scope/java  $J spill 7 8 forEachLoop lambdaParam typedLambda catchUse tryRes patternVar negatedPattern switchPattern recordPattern
hides scope/java  $J spill 8 7 nestedBlock lambdaOutside                       # outside its block: never the binding's Barrel
hides scope/java  $J spill 7 7 methodTypeParam classTypeParam typeParamField   # <Tank>: any Spiller, never class Tank proven
proven scope/java callees $J:fieldUse "method spill $J:7"
proven scope/java callees $J:typedLocal "method spill $J:8"
hides scope/cs    $C Spill 7 8 ForEachLoop ForEachVar LambdaParam PatternVar OutVar SwitchCase Deconstruct CatchUse Linq
hides scope/cs    $C Spill 8 7 NestedBlock LambdaOutside
hides scope/cs    $C Spill 7 7 MethodTypeParam ClassTypeParam TypeParamField
proven scope/cs   callees $C:FieldUse "method Spill $C:7"
proven scope/cs   callees $C:NestedBlock "method Spill $C:7"                     # the field, past the block that hid it
proven scope/cs   callees $C:TypedLocal "method Spill $C:8"
proven scope/cs   callees $C:ForEachLoop "method Spill $C:8"                     # the loop variable's own declared class
hides scope/kt    $K spill 5 6 forLoop forDestructure lambdaParam letParam typedLambda destructure whenSubject catchUse
hides scope/kt    $K spill 6 5 nestedBlock lambdaOutside
hides scope/kt    $K spill 5 5 classTypeParam typeParamField
proven scope/kt   callees $K:fieldUse "fn spill $K:5"
proven scope/kt   callees $K:typedLocal "fn spill $K:6"
proven scope/kt   callees $K:typedLambda "fn spill $K:6"
hides scope/swift $W spill 3 4 forLoop forCaseLet forTuple closureParam typedClosure ifLet guardLet whileLet caseLet ifCaseLet catchLet
hides scope/swift $W spill 4 3 nestedBlock
hides scope/swift $W spill 3 3 classTypeParam typeParamField
proven scope/swift callees $W:fieldUse "fn spill $W:3"
proven scope/swift callees $W:typedLocal "fn spill $W:4"
echo "--- (B) the same shapes where FE-B reads TS / JS / Python / Go evidence (an outer typed or constructed binding hidden)"
hides scope/ts    scope.ts spill 4 5 arrowParam forOf blockLocal catchParam destructure
hides scope/ts    scope.ts spill 4 4 typeParam classTypeParam typeParamField
proven scope/ts   callees scope.ts:typedParam "method spill scope.ts:4"
hides scope/js    scope.js spill 2 3 arrowParam forOf catchParam reassign
proven scope/js   callees scope.js:blockOutside "method spill scope.js:2"         # the outer local, past the block that hid it
proven scope/js   callees scope.js:constructed "method spill scope.js:2"
hides scope/py    scope.py spill 3 6 for_loop lambda_param comprehension with_as except_as walrus reassign match_capture match_as
hides scope/py    scope.py spill 3 3 type_param
proven scope/py   callees scope.py:typed_param "fn spill scope.py:3"
hides scope/go    scope.go Spill 8 12 RangeLoop ShortIf TypeSwitch
hides scope/go    scope.go Spill 8 8 TypeParam TypeParamField
proven scope/go   callees scope.go:BlockOutside "method Spill scope.go:8"
proven scope/go   callees scope.go:TypedParam "method Spill scope.go:8"

echo "=== (I) implicit receiver: a bare call never proves an unrelated class's method ==="
notproven java callees src/main/java/app/Logger.java:line "render src/main/java/app/Exporter.java"
notproven java callees src/main/java/app/Logger.java:close "flush src/main/java/app/Buffer.java" "flush src/main/java/app/Exporter.java"
notproven java callees src/main/java/app/FileBuffer.java:sync "flush src/main/java/app/Exporter.java"
notproven kt callees src/app/Plain.kt:finish "flush src/app/Exporter.kt" "flush src/app/Logger.kt"
notproven cs callees App/Logger.cs:Line "Render App/Exporter.cs"
notproven cs callees App/Logger.cs:Finish "Flush App/Logger.cs" "Flush App/Exporter.cs"   # Exporter.cs: guard
notproven cpp callees src/plain.cpp:finish "flush src/exporter.cpp" "flush src/logger.cpp"
notproven swift callees Sources/App/Plain.swift:finish "flush Sources/App/Exporter.swift" "flush Sources/App/Logger.swift"
notproven rb callees lib/app/plain.rb:finish "render lib/app/exporter.rb" "flush lib/app/logger.rb"
echo "--- (I) near misses: own members, the in-repo superclass (cone, super.m()), free/top-level functions, mixins"
proven    java callees src/main/java/app/Logger.java:close "method reset src/main/java/app/Logger.java"
proven    java callees src/main/java/app/FileBuffer.java:sync "method flush src/main/java/app/Buffer.java"
exactproven java callees src/main/java/app/FileBuffer.java:drain "method flush src/main/java/app/Buffer.java"
exactproven java callees src/main/java/app/Buffer.java:write "method flush src/main/java/app/Buffer.java"
exactproven kt callees src/app/Logger.kt:line "fn render src/app/Logger.kt"
exactproven kt callees src/app/Logger.kt:close "fn flush src/app/Logger.kt;fn reset src/app/Logger.kt"
exactproven cs callees App/Logger.cs:Close "method Flush App/Logger.cs;method Reset App/Logger.cs"
exactproven cpp callees src/logger.cpp:line "fn render src/logger.cpp"
exactproven cpp callees src/logger.cpp:close "method flush src/logger.cpp;method reset src/logger.cpp"
exactproven swift callees Sources/App/Logger.swift:line "fn render Sources/App/Logger.swift"
exactproven swift callees Sources/App/Logger.swift:close "fn flush Sources/App/Logger.swift;fn reset Sources/App/Logger.swift"
# Ruby's own method lookup (mixins, typed and class receivers) is another lane's: these two arms state only the
# contract — a mixin's method is RESOLVED or HEDGED, never dropped and never beside a false proven row — so they hold
# whichever lands first
visible   rb callees lib/app/logger.rb:line "stamp lib/app/helpers.rb"
notproven rb callees lib/app/logger.rb:line "render lib/app/exporter.rb"
# Ruby's own lookup (RubySelfReach, PR #373) is PROOF: what it proves comes out resolved, never via="name" — a mixin's
# method, a concern's call to its includer's method, a template method's call to a subclass's hook
exactproven rb callees lib/app/logger.rb:line "method stamp lib/app/helpers.rb"
exactproven rb callees lib/app/auditable.rb:log_audit "method audit_target lib/app/order.rb"
exactproven rb callees lib/app/order.rb:render_report "method header_line lib/app/order.rb"
exactproven rb callees lib/app/logger.rb:close "method flush lib/app/logger.rb;method reset lib/app/logger.rb;method top_level_note lib/app/notes.rb"

echo "=== (O) graded false callees from an earlier binary (Go, TS, Python repros): red where still present, pinned clean otherwise ==="
notproven go callees src/gotool.go:runGo "Output src/gotool.go"
notproven go callees src/gotool.go:runGo "Errorf src/internal/log/log.go" "Split src/gotool.go"   # guard: fmt.Errorf, strings.Split
exactproven go callees src/gotool.go:runTool "method Output src/gotool.go;method Split src/gotool.go"   # guard
notproven ts callees src/http.ts:reply "getTime src/http.ts"
notproven ts callees src/http.ts:reply "Response src/response.ts"   # guard: the global Response
notproven ts callees src/http.ts:stamped "getTime src/http.ts"
exactproven ts callees src/http.ts:local "cls Clock src/http.ts;method getTime src/http.ts"
exactproven ts callees src/http.ts:wrap "cls Response src/response.ts"   # guard
notproven py callees src/tui/listing.py:gather "append src/tui/content.py"
exactproven py callees src/tui/listing.py:grow "cls Content src/tui/content.py;fn append src/tui/content.py"
hopnotproven go "how does runGo run the go command" runGo Output 14
hopnotproven ts "how does reply build a Response" reply getTime 5
hopnotproven ts "how does stamped get the time" stamped getTime 5
hopnotproven py "how does gather append nodes" gather append 5

echo "=== (S) the two SIDES of a class lookup, and a fallback hook only after a miss (#373's Ruby class-object rule) ==="
# JS: Gauge.read() is the static (line 3) and never the instance read (line 4); new Gauge().read() the reverse; `this` inside
# a static member is the class. Plain.read() names an instance-only member on the CLASS: never proven (hedged or absent).
proven    js callees lib/sides.js:onClass "method read lib/sides.js:3"
notproven js callees lib/sides.js:onClass "read lib/sides.js:4"
proven    js callees lib/sides.js:onInstance "method read lib/sides.js:4"
notproven js callees lib/sides.js:onInstance "read lib/sides.js:3"
proven    js callees lib/sides.js:make "method read lib/sides.js:3"
notproven js callees lib/sides.js:make "read lib/sides.js:4"
notproven js callees lib/sides.js:wrongSide "read lib/sides.js:8" "read lib/sides.js:4"
# TS: the same through a class-name receiver and a typed parameter
proven    ts callees src/sides.ts:onClass "method read src/sides.ts:3"
notproven ts callees src/sides.ts:onClass "read src/sides.ts:4"
proven    ts callees src/sides.ts:onTyped "method read src/sides.ts:4"
notproven ts callees src/sides.ts:onTyped "read src/sides.ts:3"
# Kotlin: Dial.read() is the companion's; Knob().read() never the companion's
exactproven kt callees src/app/Sides.kt:onClass "fn read src/app/Sides.kt"
notproven kt callees src/app/Sides.kt:onInstance "read src/app/Sides.kt:6"
# Python __getattr__ runs only after a miss: run()'s self.real() resolves to Proxyish.real (the hook changes nothing for a
# member the class defines); self.ghost() — a name the lookup misses — is never proven onto another class's ghost
proven    py callees src/tui/ghost.py:run "fn real src/tui/ghost.py:7"
notproven py callees src/tui/ghost.py:run "real src/tui/ghost.py:19" "ghost src/tui/ghost.py:16"
echo "=== (H) propagation: one hedge, every surface ==="
# the name-only TRUE witness respondWith → reply.send(): kept and marked everywhere
marked js callers lib/reply.js:send "respondWith lib/reply.js"
# impact_d3 — the d=1 row respondWith is marked; viaModule (d=2, reached ONLY through respondWith → send) inherits
# the hedge; both (d=2, also reached through direct → new Reply().send, all proven) and direct (d=1) stay plain
impact_send(){
    local f; f="$( answer js impact lib/reply.js:send )"
    ran_ok "(js) --impact=lib/reply.js:send" "$f" || return
    rowsof "(H) --impact=lib/reply.js:send" "$f" || return
    local d1 vm bo di
    d1="$( printf '%s\n' "$GOT" | awk '$2 == "respondWith" && $6 == "1" { print $5 }' )"
    if [ "$d1" = "name" ]; then ok "(H) --impact=lib/reply.js:send: the d=1 row respondWith is marked via=\"name\""
    else no "(H) --impact=lib/reply.js:send: the d=1 row respondWith is [${d1:-absent}], want via=\"name\": $( show )"; fi
    vm="$( printf '%s\n' "$GOT" | awk '$2 == "viaModule" && $6 == "2" { print $5 }' )"
    if [ "$vm" = "name" ]; then ok "(H) --impact=lib/reply.js:send: viaModule (d=2, only through the hedged edge) inherits via=\"name\""
    else no "(H) --impact=lib/reply.js:send: viaModule at d=2 is [${vm:-absent}], want via=\"name\" (D3): $( show )"; fi
    bo="$( printf '%s\n' "$GOT" | awk '$2 == "both" && $6 == "2" { print $5 }' )"
    if [ "$bo" = "-" ]; then ok "(H) --impact=lib/reply.js:send: both (d=2, an all-proven path through direct) stays plain"
    else no "(H) --impact=lib/reply.js:send: both at d=2 is [${bo:-absent}], want plain (an all-proven path reaches it): $( show )"; fi
    di="$( printf '%s\n' "$GOT" | awk '$2 == "direct" && $6 == "1" { print $5 }' )"
    if [ "$di" = "-" ]; then ok "(H) --impact=lib/reply.js:send: direct (d=1, new Reply().send) stays plain"
    else no "(H) --impact=lib/reply.js:send: direct at d=1 is [${di:-absent}], want plain: $( show )"; fi
}
impact_send
path_send(){
    local f last; f="$( answer js path lib/uses.js:viaModule,lib/reply.js:send )"
    ran_ok "(js) --path=viaModule,send" "$f" || return
    P rows "$f" || return
    GOT="$PARSED"
    last="$( printf '%s\n' "$GOT" | awk 'NF >= 5' | tail -1 )"
    case "$last" in
        "method send lib/reply.js 7 name"*) ok "(H) --path=viaModule,send: the hop into Reply.prototype.send is marked via=\"name\"";;
        *) no "(H) --path=viaModule,send: last hop is [${last:-none}], want Reply.prototype.send marked via=\"name\": $( show )";;
    esac
}
path_send
connect_send(){
    local f e; f="$( answer js connect lib/reply.js:respondWith,lib/reply.js:send )"
    ran_ok "(js) --connect=respondWith,send" "$f" || return
    P edges "$f" || return
    e="$( printf '%s\n' "$PARSED" | awk '$1 == "respondWith" && $2 == "send" { print $3 }' )"
    if [ "$e" = "name" ]; then ok "(H) --connect: the edge respondWith → send is marked via=\"name\""
    else no "(H) --connect: the edge respondWith → send is [${e:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
connect_send
expand_send(){
    local f c; f="$( answer js expand lib/reply.js:respondWith --top-k=0 --legend=full )"
    ran_ok "(js) --expand=respondWith" "$f" || return
    P ecalls "$f" || return
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "send" { print $3 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) --expand=respondWith: <calls> row send is marked via=\"name\""
    else no "(H) --expand=respondWith: <calls> row send is [${c:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
expand_send
for_send(){
    local f c; f="$( answer js for "how does respondWith send the reply" --legend=full )"
    ran_ok "(js) --for=respondWith" "$f" || return
    P ecalls "$f" respondWith || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) --for: no respondWith body with <calls> (the arm needs it)"; return; fi
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "send" { print $3 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) --for: respondWith's body <calls> row send is marked via=\"name\""
    else no "(H) --for: respondWith's body <calls> row send is [${c:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
for_send
# the FALSE witness respond → ctx.onerror(): absent or marked on every surface
notproven js callers lib/application.js:onerror "respond lib/application.js" "respondSafely lib/application.js"
impact_onerror(){
    local f se rs; f="$( answer js impact lib/application.js:onerror )"
    ran_ok "(js) --impact=lib/application.js:onerror" "$f" || return
    rowsof "(H) --impact=lib/application.js:onerror" "$f" || return
    if [ -n "$( printf '%s\n' "$GOT" | awk '$2 == "respond" && $6 == "1" && $5 != "name"' )" ]; then
        no "(H) --impact=lib/application.js:onerror proves respond at d=1: $( show )"
    else ok "(H) --impact=lib/application.js:onerror never proves respond at d=1"; fi
    # serve reaches onerror only through respond: when respond is shown (hedged), serve is shown at d=2 marked
    rs="$( printf '%s\n' "$GOT" | awk '$2 == "respond" { print $5 }' )"
    se="$( printf '%s\n' "$GOT" | awk '$2 == "serve" { print $5 "@" $6 }' )"
    if [ -n "$rs" ]; then
        if [ "$se" = "name@2" ]; then ok "(H) --impact=lib/application.js:onerror: serve (d=2, only through respond's name-only call) inherits via=\"name\""
        else no "(H) --impact=lib/application.js:onerror: serve is [${se:-absent}], want via=\"name\" at d=2 (D3): $( show )"; fi
    else
        case "$se" in ""|name@*) ok "(H) --impact=lib/application.js:onerror: respond is gone, serve is absent or marked";;
                       *) no "(H) --impact=lib/application.js:onerror: serve is PROVEN [$se] with respond gone: $( show )";; esac
    fi
}
impact_onerror
path_onerror(){
    local f last reach top; f="$( answer js path lib/application.js:respond,lib/application.js:onerror )"
    ran_ok "(js) --path=respond,onerror" "$f" || return
    P rows "$f" || return
    GOT="$PARSED"
    last="$( printf '%s\n' "$GOT" | awk 'NF >= 5' | tail -1 )"
    top="$( grep -oE '<path [^>]*>' "$f" | grep -oE ' to_p="[^"]*"' )"
    if [ "$top" != ' to_p="lib/application.js:12"' ]; then no "(H) --path=respond,onerror bound the target to [${top:-nothing}], want to_p=\"lib/application.js:12\""; return; fi
    reach="$( grep -oE '<path [^>]*>' "$f" | grep -oE ' reachable="[^"]*"' | sed 's/.*="//; s/"$//' )"
    case "$reach" in ''|*[!0-9]*) no "(H) --path=respond,onerror carries no numeric reachable= ([$reach])"; return;; esac
    if [ "$reach" = "0" ]; then ok "(H) --path=respond,onerror: unreachable (the false edge is gone)"
    else case "$last" in
        *" name "*|*" name") ok "(H) --path=respond,onerror: the hop into Application.onerror is marked via=\"name\"";;
        *) no "(H) --path=respond,onerror proves the hop into Application.onerror: [$last]";;
    esac; fi
}
path_onerror
expand_onerror(){
    local f; f="$( answer js expand lib/application.js:respond --top-k=0 --legend=full )"
    ran_ok "(js) --expand=respond" "$f" || return
    P ecalls "$f" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) --expand=respond emitted no <calls> block"
    elif [ -n "$( printf '%s\n' "$PARSED" | awk '$1 == "onerror" && $2 == "12" && $3 != "name"' )" ]; then
        no "(H) --expand=respond: <calls> proves onerror at application.js:12: $( printf '%s' "$PARSED" | tr '\n' ';' )"
    else ok "(H) --expand=respond: <calls> never proves Application.onerror"; fi
}
expand_onerror

echo "--- (H) --for HOP blocks: the graded false rows were hop <calls>, not only body <calls>"
hopnotproven js "how does handle report an error" encode append 3
hopnotproven js "how does respond report an error on ctx" respond onerror 12
hopnotproven js "how does pipePayload handle payload end" pipePayload on 4
hopnotproven js "how does the response go back to the referrer" back get 4

echo "--- (H) the legend defines via=\"name\" and says what it does NOT mean, on every surface"
legend_arm(){
    local label="$1" f="$2"
    ran_ok "(H) legend $label" "$f" || return
    P legend "$f" || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) legend $label defines via=\"name\" (by name alone) with a NOT sentence"
    else no "(H) legend $label: no definition of via=\"name\" naming the mechanism (\"name alone\") and a \"does NOT mean\" sentence"; fi
}
legend_arm "--callees" "$( answer js callees lib/reply.js:respondWith --legend=full )"
legend_arm "--callers" "$( answer js callers lib/reply.js:send --legend=full )"
legend_arm "--impact"  "$( answer js impact lib/reply.js:send --legend=full )"
legend_arm "--path"    "$( answer js path lib/uses.js:viaModule,lib/reply.js:send --legend=full )"
legend_arm "--connect" "$( answer js connect lib/reply.js:respondWith,lib/reply.js:send --legend=full )"
legend_arm "--expand"  "$( answer js expand lib/reply.js:respondWith --top-k=0 --legend=full )"
legend_arm "--for"     "$( answer js for "how does respondWith send the reply" --legend=full )"

echo "--- (H) the MAP's <c> rows carry the same bit (the orient map is a surface too)"
# map_c FILE CALLER FILE CALLEE — the hedge column of that map <c> row ("" when absent; NOROOT FAILs the arm)
map_c(){
    P map "$1" || return 1
    if [ "$PARSED" = "NOROOT" ]; then no "(H) map: no <r> map document to read"; return 1; fi
    MAPC="$( printf '%s\n' "$PARSED" | awk -v n="$2" -v f="$3" -v c="$4" '$1 == n && $2 == f && $3 == c { print $4 }' | sort -u | tr '\n' ' ' | sed 's/ $//' )"
}
map_arms(){
    local f="$TMP/js.map.xml"
    rw js --top-k=500 --legend=full >"$f"; printf '%s' "$?" >"$f.rc"
    ran_ok "(js) the default map" "$f" || return
    map_c "$f" respondWith lib/reply.js send || return
    if [ "$MAPC" = "name" ]; then ok "(H) map: respondWith's <c n=\"send\"> is marked via=\"name\""
    else no "(H) map: respondWith's <c n=\"send\"> is [${MAPC:-absent}], want via=\"name\""; fi
    map_c "$f" direct lib/reply.js send || return
    if [ "$MAPC" = "-" ]; then ok "(H) map: near miss — direct's <c n=\"send\"> (new Reply().send) stays plain"
    else no "(H) map: direct's <c n=\"send\"> is [${MAPC:-absent}], want plain (a constructed receiver proves it)"; fi
    map_c "$f" respond lib/application.js onerror || return
    case "$MAPC" in *-*) no "(H) map: respond's <c n=\"onerror\"> is PROVEN (the false witness ctx.onerror())";;
                   *) ok "(H) map: respond's <c n=\"onerror\"> is absent or marked";; esac
    legend_arm "map" "$f"
    # near miss for the legend: a map whose rows carry no name-only <c> pays nothing for it — a bare call to a function
    # its own file defines is proven by scope, so its <c> is plain and the comment must not ride
    local g="$TMP/plainmap" gf="$TMP/plainmap.xml"
    mkdir -p "$g" && printf 'function a() { return b(); }\nfunction b() { return 1; }\nmodule.exports = { a };\n' >"$g/m.js"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=full >"$gf" 2>/dev/null ); printf '%s' "$?" >"$gf.rc"
    ran_ok "(H) the plain-call map" "$gf" || return
    map_c "$gf" a m.js b || return
    if [ "$MAPC" != "-" ]; then no "(H) map near miss: a's <c n=\"b\"> is [${MAPC:-absent}], want a plain row (the premise of this arm)"; return; fi
    P legend "$gf" || return
    if [ "$PARSED" = "UNDEFINED" ]; then ok "(H) map near miss: a scope-proven <c n=\"b\"> stays plain and the via legend does not ride"
    else no "(H) map near miss: the via legend rides a map whose rows carry no via=\"name\""; fi
}
map_arms

# (H) the map's MERGED hedged rows (fix round 1): N byte-identical via="name" rows of one symbol print ONCE with x="N"; the
# full legend and the compact legend define x=; --callees on the caller lists every candidate (the cut is recoverable).
# Near misses: a lone hedged candidate carries no x=, a PROVEN row is never merged into a hedged one, and two different
# names stay two rows.
merge_arms(){
    local g="$TMP/mergemap"
    mkdir -p "$g"
    { printf 'class A { get() { return 1; } put() { return 1; } }\nclass B { get() { return 2; } }\nclass C { get() { return 3; } }\n'
      printf 'function use(o) { return o.get() + o.put(); }\nfunction proven() { return new A().get(); }\nmodule.exports = { A, B, C, use, proven };\n'; } >"$g/u.js"
    local full="$TMP/mergemap.full.xml" comp="$TMP/mergemap.compact.xml" cal="$TMP/mergemap.callees.xml"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=full >"$full" 2>/dev/null ); printf '%s' "$?" >"$full.rc"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=compact >"$comp" 2>/dev/null ); printf '%s' "$?" >"$comp.rc"
    ( cd "$g" && "$BIN" . --no-cache --callees=u.js:use >"$cal" 2>/dev/null ); printf '%s' "$?" >"$cal.rc"
    ran_ok "(H) merge: the full-legend map" "$full" || return
    ran_ok "(H) merge: the compact-legend map" "$comp" || return
    ran_ok "(H) merge: --callees=u.js:use" "$cal" || return
    local use proven
    use="$( sed 's/<s /\n<s /g' "$full" | grep -m1 '<s t="fn" n="use"' )"
    proven="$( sed 's/<s /\n<s /g' "$full" | grep -m1 '<s t="fn" n="proven"' )"
    if [ -z "$use" ] || [ -z "$proven" ]; then no "(H) merge: the map has no row for use/proven (the premise): $( head -c 400 "$full" )"; return; fi
    [ "$( printf '%s' "$use" | grep -o '<c n="get"[^>]*>' | wc -l | tr -d ' ' )" = 1 ] && printf '%s' "$use" | grep -qE '<c n="get"( prov="split")? via="name" x="3"/>' \
        && ok "(H) merge: use's three same-named hedged get candidates print ONE row <c n=\"get\" via=\"name\" x=\"3\"/>" \
        || no "(H) merge: use's get rows are not one x=\"3\" row: $use"
    printf '%s' "$use" | grep -q '<c n="put"[^>]* x="' \
        && no "(H) merge near miss: use's lone put candidate carries x=: $use" \
        || ok "(H) merge near miss: a lone hedged candidate (put) carries no x="
    printf '%s' "$proven" | grep -q 'x="' \
        && no "(H) merge near miss: proven's evidence-bound get row was merged: $proven" \
        || ok "(H) merge near miss: a proven row is never merged (proven's get carries no x=)"
    [ "$( grep -oE '<s [^>]*n="([A-Za-z]+\.)?get"' "$cal" | wc -l | tr -d ' ' )" = 3 ] \
        && ok "(H) merge: --callees=u.js:use lists all three get candidates (the merged row is recoverable)" \
        || no "(H) merge: --callees=u.js:use does not list three get candidates: $( head -c 600 "$cal" )"
    grep -q 'x=N' "$full" && P legend "$full" && [ "$PARSED" = "DEFINED" ] \
        && ok "(H) merge: the full map legend defines via=\"name\" and x=" \
        || no "(H) merge: the full map legend does not define via=\"name\" (name alone + does NOT mean) and x="
    grep -q '<c x=N>' "$comp" && grep -qE '<c n="get"( prov="split")? via="name" x="3"/>' "$comp" \
        && ok "(H) merge: the compact map defines <c x=N> and keeps the merged row" \
        || no "(H) merge: the compact map does not define <c x=N> beside the merged row"
}
merge_arms

echo "--- (H) MCP twins (fresh TMPDIR: the MCP cache lives there)"
mkdir -p "$TMP/mcp"
# mcp ROOT TOOL SELECTOR OUT — one tools/call (then tools/list); the raw stream into OUT, the exit status into OUT.rc
mcp(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","symbol":"%s"}}}' "$2" "$CORPUS/$1" "$3" )" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$4" 2>/dev/null
    printf '%s' "$?" >"$4.rc"
}
# mcp_hedge ROOT TOOL SEL FIELD NAME FILE WANT — WANT = name (marked) | notproven (absent or marked)
mcp_hedge(){
    local r="$1" tool="$2" sel="$3" field="$4" n="$5" file="$6" want="$7" out h
    out="$TMP/mcp.$r.$tool.$( printf '%s' "$sel" | tr '/:.' '___' )"
    mcp "$r" "$tool" "$sel" "$out"
    ran_ok "(H) MCP $tool $sel" "$out" || return
    P mcp "$out" "$field" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) MCP $tool $sel: no JSON answer with $field"; return; fi
    h="$( printf '%s\n' "$PARSED" | awk -v n="$n" -v f="$file" '$1 == n && $2 == f { print $4 }' | sort -u | tr '\n' ' ' | sed 's/ $//' )"
    if [ "$want" = "name" ]; then
        if [ "$h" = "name" ]; then ok "(H) MCP $tool $sel: $field entry $n@$file is marked via=name"
        else no "(H) MCP $tool $sel: $field entry $n@$file is [${h:-absent}], want via=name"; fi
    else
        case " $h " in *" - "*) no "(H) MCP $tool $sel: $field entry $n@$file is PROVEN (no via=name)";;
                       *) ok "(H) MCP $tool $sel: $field entry $n@$file is absent or marked";; esac
    fi
}
mcp_hedge js find_symbol lib/reply.js:respondWith calls send lib/reply.js name
mcp_hedge js find_referencing_symbols lib/reply.js:send calledBy respondWith lib/reply.js name
mcp_hedge js find_symbol lib/application.js:respond calls onerror lib/application.js notproven
mcp_hedge js find_referencing_symbols lib/application.js:onerror calledBy respond lib/application.js notproven
mcp_hedge py find_symbol src/tui/callback.py:schedule calls call_later src/tui/message_pump.py name
# mcp_legend TOOL SEL — tools/call then tools/list: the tool's description or its answer defines "via":"name"
mcp_legend(){
    local tool="$1" sel="$2" out="$TMP/mcplegend.$1"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","symbol":"%s"}}}' "$tool" "$CORPUS/js" "$sel" )" \
        '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$out" 2>/dev/null
    printf '%s' "$?" >"$out.rc"
    ran_ok "(H) MCP legend $tool" "$out" || return
    P mcplegend "$out" "$tool" || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) MCP $tool: the tool description or answer defines \"via\":\"name\" with a NOT sentence"
    elif [ "$PARSED" = "NOROOT" ]; then no "(H) MCP $tool: no tools/list or tools/call answer to read"
    else no "(H) MCP $tool: neither the tool description nor the answer defines \"via\":\"name\" (\"name alone\" + \"does NOT mean\")"; fi
}
mcp_legend find_symbol lib/reply.js:respondWith
mcp_legend find_referencing_symbols lib/reply.js:send
# the MAP's MCP twin (analyze): the same <c> rows, the same bit, the same legend
mcp_map(){
    local out="$TMP/mcp.js.analyze" c d
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"%s"}}}' "$CORPUS/js" )" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$out" 2>/dev/null
    printf '%s' "$?" >"$out.rc"
    ran_ok "(H) MCP analyze" "$out" || return
    P mcpmap "$out" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) MCP analyze: no map in the answer"; return; fi
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "respondWith" && $2 == "lib/reply.js" && $3 == "send" { print $4 }' | sort -u )"
    d="$( printf '%s\n' "$PARSED" | awk '$1 == "direct" && $2 == "lib/reply.js" && $3 == "send" { print $4 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) MCP analyze: respondWith's <c n=\"send\"> is marked via=\"name\" (the CLI map's bit)"
    else no "(H) MCP analyze: respondWith's <c n=\"send\"> is [${c:-absent}], want via=\"name\""; fi
    if [ "$d" = "-" ]; then ok "(H) MCP analyze: near miss — direct's <c n=\"send\"> stays plain"
    else no "(H) MCP analyze: direct's <c n=\"send\"> is [${d:-absent}], want plain"; fi
    P mcplegend "$out" analyze || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) MCP analyze: the answer defines via=\"name\" with a NOT sentence"
    else no "(H) MCP analyze: the answer does not define via=\"name\" (\"name alone\" + \"does NOT mean\")"; fi
}
mcp_map

echo "--- (H) parity: the hedge bit is value-equal across CLI and MCP, and across --callees and --expand"
# cli_set ROOT VERB SEL — "name@file#H" lines of the CLI answer; mcp_set ROOT TOOL SEL FIELD — the same from MCP
# (a run or reader failure prints RUNFAIL, which parity FAILs)
cli_set(){ local f rc rows; f="$( answer "$1" "$2" "$3" )"; rc="$( cat "$f.rc" 2>/dev/null )"
           if [ "$rc" != "0" ]; then echo "RUNFAIL --$2=$3 rc=${rc:-unknown}"; return; fi
           rows="$( python3 "$TMP/parse.py" rows "$f" 2>/dev/null )" || { echo "RUNFAIL reader on --$2=$3"; return; }
           printf '%s\n' "$rows" | awk 'NF >= 5 { n = $2; sub(/^[A-Za-z_]+\./, "", n); print n "@" $3 "#" $5 } $0 == "NOROOT" { print }' | sort -u; }   # js-def-naming: the CLI XML row names a JS/TS method by its class (Application.onerror); the MCP JSON key stays bare (QUALNAME-1), so the parity reads the leaf
mcp_set(){ local out rc rows; out="$TMP/mcpset.$1.$2.$( printf '%s' "$3" | tr '/:.' '___' )"; mcp "$1" "$2" "$3" "$out"
           rc="$( cat "$out.rc" 2>/dev/null )"
           if [ "$rc" != "0" ]; then echo "RUNFAIL MCP $2 $3 rc=${rc:-unknown}"; return; fi
           rows="$( python3 "$TMP/parse.py" mcp "$out" "$4" 2>/dev/null )" || { echo "RUNFAIL reader on MCP $2 $3"; return; }
           printf '%s\n' "$rows" | awk 'NF >= 4 { print $1 "@" $2 "#" $4 } $0 == "NOROOT" { print }' | sort -u; }
parity(){
    local label="$1" a="$2" b="$3"
    case "$a$b" in *RUNFAIL*) no "(H) parity $label: a run or reader failed ([$a] [$b])"; return;; esac
    if [ -z "$a" ] || [ "$a" = "NOROOT" ] || [ "$b" = "NOROOT" ]; then no "(H) parity $label: an empty or rootless side ([$a] vs [$b])"; return; fi
    if [ "$a" = "$b" ]; then ok "(H) parity $label: $( printf '%s' "$a" | tr '\n' ' ' )"
    else no "(H) parity $label: CLI [$( printf '%s' "$a" | tr '\n' ' ' )] vs [$( printf '%s' "$b" | tr '\n' ' ' )]"; fi
}
for sel in lib/application.js:respond lib/reply.js:respondWith lib/reply.js:notFound lib/request.js:compile lib/uses.js:build lib/application.js:handle lib/delegate/response.js:back; do
    parity "callees/find_symbol.calls $sel" "$( cli_set js callees "$sel" )" "$( mcp_set js find_symbol "$sel" calls )"
done
for sel in lib/reply.js:send lib/application.js:onerror lib/schemas.js:listSchemas; do
    parity "callers/find_referencing_symbols.calledBy $sel" "$( cli_set js callers "$sel" )" "$( mcp_set js find_referencing_symbols "$sel" calledBy )"
done
# --callees vs --expand <calls>: compared by name + hedge (a <c> row names no file)
for sel in lib/reply.js:respondWith lib/reply.js:notFound lib/request.js:compile lib/delegate/response.js:back; do
    fc="$( answer js callees "$sel" )"; fe="$( answer js expand "$sel" --top-k=0 --legend=full )"
    if ran_ok "(H) --callees=$sel" "$fc" && ran_ok "(H) --expand=$sel" "$fe"; then
        if ra="$( python3 "$TMP/parse.py" rows "$fc" 2>/dev/null )" && rb="$( python3 "$TMP/parse.py" ecalls "$fe" 2>/dev/null )"; then
            a="$( printf '%s\n' "$ra" | awk 'NF >= 5 { print $2 "#" $5 }' | sort -u )"
            b="$( printf '%s\n' "$rb" | awk 'NF >= 3 { print $1 "#" $3 }' | sort -u )"
            parity "callees/expand-calls $sel" "$a" "$b"
        else no "(H) parity callees/expand-calls $sel: the reader failed"; fi
    fi
done

echo "=== (R) the base-class receiver is a KEYWORD, never a local spelled like one (CR 5469474915, receiverevidence.h:124) ==="
# superroot/<lang>: Panel extends Base; Base and Widget both define render. A local `base` (C#/Go: `super`) holding a
# Widget, or an untyped value, never proves Base's render through the bases-only lookup: the typed local resolves to its
# own class, the untyped one is hedged. The keyword twins (`super.render()`, Python `super().render()`, Go's promoted
# p.Render()) still prove Base's render. C# `base.Render()` is pinned as visible only: no C# tree reaches the base-class
# receiver today (the grammar's `base` node is not read as a receiver root — a disclosed floor, never a false row).
SR=superroot
notproven $SR/py callees pkg/panel.py:untyped "render pkg/shapes.py:2"
notproven $SR/py callees pkg/panel.py:shadowed "render pkg/shapes.py:2"
visible   $SR/py callees pkg/panel.py:untyped "render pkg/shapes.py:2" "render pkg/shapes.py:7"
exactproven $SR/py callees pkg/panel.py:typed "cls Widget pkg/shapes.py;fn render pkg/shapes.py"   # guard: Rule 2 types it first
proven    $SR/py callees pkg/panel.py:typed "fn render pkg/shapes.py:7"   # guard
proven    $SR/py callees pkg/panel.py:real_super "fn render pkg/shapes.py:2"   # guard: super() walks the bases
for l in js ts; do
    f="$( [ "$l" = js ] && echo lib/panel.js || echo src/panel.ts )"; d="$( [ "$l" = js ] && echo lib/shapes.js || echo src/shapes.ts )"
    notproven $SR/$l callees "$f:typed" "render $d:2"
    proven    $SR/$l callees "$f:typed" "method render $d:6"
    notproven $SR/$l callees "$f:untyped" "render $d:2"
    visible   $SR/$l callees "$f:untyped" "render $d:2" "render $d:6"
    proven    $SR/$l callees "$f:realSuper" "method render $d:2"   # guard: super.render()
done
notproven $SR/go callees src/panel.go:Typed "Render src/shapes.go:5"
proven    $SR/go callees src/panel.go:Typed "method Render src/shapes.go:9"
notproven $SR/go callees src/panel.go:Untyped "Render src/shapes.go:5"
notproven $SR/go callees src/panel.go:Super "Render src/shapes.go:5"
visible   $SR/go callees src/panel.go:Super "Render src/shapes.go:5" "Render src/shapes.go:9"
proven    $SR/go callees src/panel.go:Promoted "method Render src/shapes.go:5"   # guard: the embedded Base's promoted method
notproven $SR/java callees src/app/Panel.java:typed "render src/app/Base.java"
proven    $SR/java callees src/app/Panel.java:typed "method render src/app/Widget.java"
notproven $SR/java callees src/app/Panel.java:untyped "render src/app/Base.java"
proven    $SR/java callees src/app/Panel.java:realSuper "method render src/app/Base.java"   # guard
notproven $SR/kt callees src/app/Panel.kt:typed "render src/app/Shapes.kt:4"
proven    $SR/kt callees src/app/Panel.kt:typed "fn render src/app/Shapes.kt:8"
notproven $SR/kt callees src/app/Panel.kt:untyped "render src/app/Shapes.kt:4"
proven    $SR/kt callees src/app/Panel.kt:realSuper "fn render src/app/Shapes.kt:4"   # guard
notproven $SR/swift callees Sources/App/Panel.swift:typed "render Sources/App/Shapes.swift:2"
proven    $SR/swift callees Sources/App/Panel.swift:typed "fn render Sources/App/Shapes.swift:6"
notproven $SR/swift callees Sources/App/Panel.swift:untyped "render Sources/App/Shapes.swift:2"
proven    $SR/swift callees Sources/App/Panel.swift:realSuper "fn render Sources/App/Shapes.swift:2"   # guard
notproven $SR/cs callees App/Panel.cs:Typed "Render App/Shapes.cs:5"
proven    $SR/cs callees App/Panel.cs:Typed "method Render App/Shapes.cs:10"
notproven $SR/cs callees App/Panel.cs:Untyped "Render App/Shapes.cs:5"
visible   $SR/cs callees App/Panel.cs:RealBase "Render App/Shapes.cs:5"   # guard (floor above)
notproven $SR/cpp callees src/panel.cpp:untyped "render src/shapes.h:6"
proven    $SR/cpp callees src/panel.cpp:typed "method render src/shapes.h:11"   # guard: Rule 2 types it first
notproven $SR/rb callees lib/panel.rb:untyped "render lib/shapes.rb:2"
proven    $SR/rb callees lib/panel.rb:typed "method render lib/shapes.rb:8"   # guard

echo "=== (L) call-result typing (lane call-result-typing): a binding initialised by a call takes the callee's DECLARED return type ==="
# [P] arms are RED before the lane (the receiver is name-only: hedged or declined); [N] arms are near misses that must
# stay green — the rule records NOTHING for them (honest floor). Roots: callresult/<lang>/ (one tree each).
# An [N] arm forbids only a WRONG namesake. Where the true edge is a floor (the rule records nothing, so the call stays
# name-only), the arm's comment names it and it is NOT gated either way: a later lane may prove it.
CR=callresult
# Go — model.go: Config.Get :7, Other.Get :13, Config.Close :9, Other.Close :15, Packager.Package :18, func Get :54;
#      extra.go: File.Close :8, Ref.Get :17, Deb.Package :31, Rpm.Package :35.
for f in UseValue UsePtr UseOne UseMethod UseReassigned UseGrouped; do   # (T, error) named results, (*T, error), *T, a method callee, a reassignment (Go's static type stays), grouped names `(a, b *Config, o *Other)` element 1
    proven    $CR/go callees "src/app/app.go:$f" "method Get src/model/model.go:7"      # [P]
    notproven $CR/go callees "src/app/app.go:$f" "Get src/model/model.go:13"            # [N] the namesake is never proven
done
for f in UsePair UseGroupedLast; do   # the second result types the second name; grouped names count one position per NAME (element 2)
    proven    $CR/go callees "src/app/app.go:$f" "method Get src/model/model.go:13"     # [P]
    notproven $CR/go callees "src/app/app.go:$f" "Get src/model/model.go:7"             # [N]
done
# An interface result types the binding as the interface: `pkg.Package( … )` then answers exactly as the written twin
# UseIfaceWritten does — the interface's bodyless signature (Packager.Package :18) is a dispatch contract FE-B leaves to the
# ladder (declined on base for the written type too), so that row is a floor shared with the twin (interface dispatch: L6),
# and an implementor is never proven.
for f in UseIface UseQualifiedFn UseIfaceWritten; do
    notproven $CR/go callees "src/app/app.go:$f" "Package src/model/extra.go:31" "Package src/model/extra.go:35"   # [N] never an implementor
done
proven    $CR/go callees src/app/app.go:UseQualifiedFn "fn Get src/model/model.go:54"   # [P] `model.Get` reaches the package func, never a method (nfpm.Get)
notproven $CR/go callees src/app/app.go:UseQualifiedFn "Get src/model/model.go:7" "Get src/model/model.go:13"   # [N]
proven    $CR/go callees src/app/renamed.go:UseRenamedImport "fn Get src/model/model.go:54"   # [P] a renamed import `m.Get` is the same package rule
notproven $CR/go callees src/app/renamed.go:UseRenamedImport "Get src/model/model.go:7" "Get src/model/model.go:13"   # [N]
notproven $CR/go callees src/app/app.go:NearShadowPkg "Get src/model/model.go:54" "Get src/model/model.go:13"   # [N] a local `model := …` is not the package (truth Config.Get :7)
notproven $CR/go callees src/app/app.go:NearExternal "Close src/model/model.go:9" "Close src/model/model.go:15" "Close src/model/extra.go:8"   # [N] outside callee os.Open beside the in-tree model.Open
notproven $CR/go callees src/app/app.go:NearTwoDefs "Get src/model/model.go:7" "Get src/model/model.go:13"   # [N] a two-def callee (truth unknown)
notproven $CR/go callees src/app/app.go:NearWrapper "Get src/model/model.go:7" "Get src/model/model.go:13"   # [N] Ref[T] is outside the list (truth Ref.Get extra.go:17)
for f in NearAlias NearGeneric; do   # a Go alias (no alias record); a type-parameter result Generic[model.Config] — truth Config.Get :7 (floor, not gated)
    notproven $CR/go callees "src/app/app.go:$f" "Get src/model/model.go:13"           # [N]
done
notproven $CR/go callees src/app/app.go:NearTypeParamNamed "Get src/model/model.go:7"   # [N] a type parameter spelled Config, instantiated with Other (truth Other.Get :13: floor)
notproven $CR/go callees src/app/app.go:NearShadow "Close src/model/model.go:9" "Close src/model/model.go:15"    # [N] an inner `c :=` hides the typed outer c
notproven $CR/go callees src/app/app.go:NearQualified "Close src/model/extra.go:8"      # [N] `(*os.File, error)`: the qualifier names no in-tree package
notproven $CR/go callees src/app/app.go:NearOSParam "Close src/model/extra.go:8"        # [N] the written/param twin `f *os.File` (a false proven edge before the lane)
proven    $CR/go callees src/app/app.go:UseWritten "method Get src/model/model.go:7"    # guard: the written-type twin
# Rust — model.rs: Config::get :6, Other::get :13, Config::len :7, Other::len :14, Book::build :46, Config::iter :66;
#        osfile.rs: File::sync_all :5.
for f in use_try use_option use_box use_ref use_plain use_self use_unwrap; do   # Result<T,_> + ?, Option<T> + ?, Box<T>, &T, T, a self-method callee's tuple element 0, .unwrap() / .expect(..)
    proven    $CR/rust callees "src/app.rs:$f" "method get src/model.rs:6"             # [P]
    notproven $CR/rust callees "src/app.rs:$f" "get src/model.rs:13"                   # [N]
done
proven    $CR/rust callees src/app.rs:use_tuple "method get src/model.rs:13"           # [P] `let (_, o) = pair()?` — tuple element 1
notproven $CR/rust callees src/app.rs:use_tuple "get src/model.rs:6"                   # [N]
proven    $CR/rust callees src/app.rs:use_path "method build src/model.rs:46"          # [P] `let book = Book::load(..)?; book.build()` (mdbook-14 hop 1)
notproven $CR/rust callees src/app.rs:use_path "get src/model.rs:13"                   # [N] (c = book.build() types c in turn: the chaining arms below)
for f in near_external near_wrapper near_shadow; do   # String::new() beside the in-tree model::new; Vec<T> outside the list (the slice's len); a later `let c` rebinds c
    notproven $CR/rust callees "src/app.rs:$f" "len src/model.rs:7" "len src/model.rs:14"   # [N]
done
for f in near_std_get near_two_defs; do   # a std HashMap result's get; a two-def callee (truth unknown)
    notproven $CR/rust callees "src/app.rs:$f" "get src/model.rs:6" "get src/model.rs:13"   # [N]
done
for f in near_alias near_generic; do   # a Rust alias (no alias record); generic::<Config>() — truth Config::get :6 (floor, not gated)
    notproven $CR/rust callees "src/app.rs:$f" "get src/model.rs:13"                   # [N]
done
for f in near_method_tail near_type_param_named; do   # `.into_other()` is not stripped like unwrap (truth Other::get: floor); a type parameter spelled Config, instantiated with Other
    notproven $CR/rust callees "src/app.rs:$f" "get src/model.rs:6"                    # [N]
done
for f in near_no_try near_nested; do   # Option<T> with no `?`; Result<Option<T>> with one `?` — both leave an Option: Option::iter
    notproven $CR/rust callees "src/app.rs:$f" "iter src/model.rs:66"                  # [N]
done
notproven $CR/rust callees src/app.rs:near_qualified "sync_all src/osfile.rs:5"        # [N] io::Result<std::fs::File> / std::fs::File: the qualifier names std
# C++ — Config::get model.cpp:5, Other::get :7.
for f in usePlain useRef usePtr useUnique useMethod; do   # T, const T&, T* (->), std::unique_ptr<T> (->), a method callee
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:5"                   # [FLOOR] C++ off (fix round 6): hedges — was [P]
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:7"                   # [N]
done
# a `using` alias result answers as its written twin does: Rule 2 proves no member through the alias (Config::get :5 is a
# floor shared by useAlias and useAliasWritten, not gated); Other::get is never proven
for f in useAlias useAliasWritten; do
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:7"                   # [N]
done
for f in nearOverload nearGeneric; do   # pick(1) of an overloaded callee; create<cfg::Config>() — truth Config::get :5 (floor, not gated)
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:7"                   # [N] (a last-definition bug)
done
for f in nearOverloadName nearTypeParamNamed; do   # pick("name") — truth Other::get :7 (floor); a template parameter spelled Config, instantiated with Other
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:5"                   # [N] (a first-definition bug)
done
for f in nearExternal nearWrapper nearShadow nearUniqueDot; do   # std::async beside the in-tree cfg::async; std::reference_wrapper (its own get); an inner `auto c`; `u.get()` on a unique_ptr (unique_ptr::get)
    notproven $CR/cpp callees "src/app.cpp:$f" "get src/model.cpp:5" "get src/model.cpp:7"   # [N]
done
proven    $CR/cpp callees src/app.cpp:useWritten "method get src/model.cpp:5"          # guard: the written-type twin
# Java / Kotlin / TS (cheap rows) — Config.get vs Other.get.
proven    $CR/java callees src/app/Use.java:useVar "method get src/app/Config.java:4"  # [P] `var c = Configs.make()`
notproven $CR/java callees src/app/Use.java:useVar "get src/app/Other.java:4"          # [N]
for f in nearExternal nearWrapper; do   # List.of(..) beside the in-tree Configs.of, then l.get(0); Optional<T> (its own get)
    notproven $CR/java callees "src/app/Use.java:$f" "get src/app/Config.java:4" "get src/app/Other.java:4"   # [N]
done
notproven $CR/java callees src/app/Use.java:nearGeneric "get src/app/Other.java:4"     # [N] <Config>create() — truth Config.get (floor, not gated)
notproven $CR/java callees src/app/Use.java:nearTypeParamNamed "get src/app/Config.java:4"   # [N] a type parameter spelled Config, instantiated with Other
proven    $CR/java callees src/app/Use.java:useWritten "method get src/app/Config.java:4"   # guard
for f in useVal useVar; do   # `val c = makeConfig()`; `var c = …; c = …` (Kotlin's declared type stays)
    proven    $CR/kt callees "src/app/Use.kt:$f" "fn get src/app/Model.kt:4"           # [P]
    notproven $CR/kt callees "src/app/Use.kt:$f" "get src/app/Model.kt:8"              # [N]
done
notproven $CR/kt callees src/app/Use.kt:nearInferred "get src/app/Model.kt:8"          # [N] no written return type — truth Config.get :4 (floor, not gated)
proven    $CR/kt callees src/app/Use.kt:useWritten "fn get src/app/Model.kt:4"         # guard
for f in useConst useAwait; do   # `const c = makeConfig()`; `await loadConfig()` through Promise<T>
    proven    $CR/ts callees "src/use.ts:$f" "method get src/model.ts:2"               # [P]
    notproven $CR/ts callees "src/use.ts:$f" "get src/model.ts:6"                      # [N]
done
notproven $CR/ts callees src/use.ts:nearUntyped "get src/model.ts:6"                   # [N] no written return type (TS inference is not modelled) — truth Config.get :2 (floor)
notproven $CR/ts callees src/use.ts:nearMap "get src/model.ts:2" "get src/model.ts:6"  # [N] Object.freeze beside the in-tree freeze(): Map.get
proven    $CR/ts callees src/use.ts:useWritten "method get src/model.ts:2"             # guard
# ── fix round 1 (rv-/rv2-call-result-typing): the typed fact carries the ONE in-tree class the result type resolves to ──
# B1 a nested same-named call: `x = h.get().get()` types x from the OUTER call only — never from the inner call, whose
#    (file, start byte, name) it shares. The outer call's own receiver is a call, so x stays untyped: the truth (Leaf /
#    Other's size) is a floor, not gated.
notproven $CR/go   callees src/app/fix1.go:NearNestedSame   "Size src/nest/nest.go:13"                  # [N] (*Config).Size, the inner result's
notproven $CR/rust callees src/fix1.rs:near_nested_same     "size src/nest.rs:11"                       # [N] Config::size
for f in nearNestedSame nearNestedWritten; do
    notproven $CR/cpp callees "src/fix1.cpp:$f"             "size src/nest.cpp:7"                       # [N] Item::size
done
notproven $CR/java callees src/app/Use2.java:nearNestedSame "size src/app/Item.java:5"                  # [N] Item.size
notproven $CR/kt   callees src/app/Use2.kt:nearNestedSame   "size src/app/Model2.kt:14"                 # [N] Item.size
notproven $CR/ts   callees src/use2.ts:nearNestedSame       "size src/nest.ts:7"                        # [N] Item.size
# B2 an unqualified result type the callee's file IMPORTS from outside (Java/Kotlin single-type import, TS named and
#    `import type` import, a TS global, Rust `use std::…`) or an outside qualifier (C++ `ext::Config`) never names the
#    in-tree namesake: nothing is recorded (the outside class's own member is a floor).
notproven $CR/java callees src/app/Use2.java:nearImported   "delete src/app/File.java:5"                # [N] java.io.File, not app.File
notproven $CR/kt   callees src/app/Use2.kt:nearImported     "delete src/app/File.kt:5"                  # [N] java.io.File, not app.File
notproven $CR/ts   callees src/use2.ts:nearLoadExt          "get src/model.ts:2" "get src/model.ts:6"   # [N] ext-config's Config
notproven $CR/ts   callees src/use2.ts:nearTypeOnly         "get src/holder.ts:2"                       # [N] `import type { Holder } from 'other-lib'`
notproven $CR/ts   callees src/use2.ts:nearGlobal           "json src/response.ts:2"                    # [N] the global Response
for f in near_plain_use near_plain_use_result; do   # `use std::fs::File; fn f() -> File` / `-> std::io::Result<File>` + unwrap
    notproven $CR/rust callees "src/fix1.rs:$f"             "sync_all src/osfile.rs:5"                  # [N] std's File, not osfile::File
done
notproven $CR/cpp  callees src/fix1.cpp:nearLoadExt         "get src/model.cpp:5" "get src/model.cpp:7" # [N] ext::Config, not cfg::Config
# B3 the typed fact is the CLASS, not its name: package a's interface Client never reaches package b's struct Client.Do
#    (an interface result proves no member at all: the bodyless signature is the ladder's, L6), and the in-repo shape
#    (declinedsitefix's `pkg, err := pkgr.Get(..)` → the pkgr.Packager interface, beside forbodyslotfix's struct Packager)
#    is pinned on a temp copy of those two trees.
notproven $CR/go   callees src/app/fix1.go:NearIfaceNamesake "Do src/b/b.go:5"                          # [N]
mkdir -p "$TMP/b3real" && cp -R "$ROOT/test/declinedsitefix/go" "$TMP/b3real/dsf" && cp -R "$ROOT/test/forbodyslotfix/src/go" "$TMP/b3real/fbs"
( cd "$TMP/b3real" && "$BIN" . --no-cache --callees=doPackage 2>/dev/null ) >"$TMP/b3real.xml"
if P rows "$TMP/b3real.xml"; then
    if [ "$PARSED" = "NOROOT" ] || [ -z "$PARSED" ]; then no "(L) B3 real: --callees=doPackage gave no rows"
    elif printf '%s\n' "$PARSED" | awk '$2=="Package" && $3=="fbs/packager.go" && $5=="-"' | grep -q .; then no "(L) B3 real: pkg.Package proves forbodyslotfix's struct Packager.Package (another package's namesake)"
    else ok "(L) B3 real: pkg.Package (pkgr.Packager interface) never proves another package's struct Packager"; fi
fi
# B5 typing needs a commit WITH evidence: `ext::onlyOne()` binds the in-tree cfg::onlyOne by name alone, and
#    `ext::Factory f; f.make()` reaches cfg::Factory::make by its final segment only (prov="final-segment", itself a
#    disclosed base floor) — neither types its local.
for f in nearExtCall nearExtSubCall; do
    notproven $CR/cpp callees "src/fix1.cpp:$f"             "size src/model.cpp:6" "size src/model.cpp:8"   # [N]
done
notproven $CR/cpp  callees src/fix1.cpp:nearExtWritten      "get src/model.cpp:5" "get src/model.cpp:7" # [N]
# The written/param twin's sibling, a struct FIELD written `*os.File` beside the in-tree model.File (a base false claim the
# same qualifier rule fixes): `s.f.Close()` is os.File's.
notproven $CR/go   callees src/app/fix1.go:NearOSField      "Close src/model/extra.go:8"                # [N]
# CHAINING (kept): a local typed by a call result is a typed receiver, so the call on it — proven — types the next local,
# in source order, in the one resolve pass (no fixpoint). [P] pins it; [N] a hop that binds by name alone (an untyped
# receiver) or splits (an overloaded callee) stops the chain.
proven    $CR/rust callees src/app.rs:use_path              "method get src/model.rs:6"                 # [P] `let c = book.build(); c.get(..)`
proven    $CR/rust callees src/fix1.rs:use_chain            "method get src/nest.rs:10"                 # [P] nest's Config, not model's
notproven $CR/rust callees src/fix1.rs:use_chain            "get src/model.rs:6" "get src/model.rs:13"  # [N]
proven    $CR/go   callees src/app/fix1.go:UseChain         "method Get src/nest/nest.go:11"            # [P] nest's Config, not model's
notproven $CR/go   callees src/app/fix1.go:UseChain         "Get src/model/model.go:7"                  # [N]
notproven $CR/cpp  callees src/fix1.cpp:useChain            "get src/model.cpp:5"                       # [FLOOR] C++ off (fix round 6): hedges — was [P]
notproven $CR/cpp  callees src/fix1.cpp:useChain            "get src/model.cpp:7"                       # [N]
proven    $CR/java callees src/app/Use2.java:useChain       "method size src/app/Item.java:5"           # [P]
notproven $CR/java callees src/app/Use2.java:useChain       "size src/app/Leaf.java:4"                  # [N]
proven    $CR/kt   callees src/app/Use2.kt:useChain         "fn size src/app/Model2.kt:14"              # [P]
notproven $CR/kt   callees src/app/Use2.kt:useChain         "size src/app/Model2.kt:18"                 # [N]
proven    $CR/ts   callees src/use2.ts:useChain             "method size src/nest.ts:7"                 # [P]
notproven $CR/ts   callees src/use2.ts:useChain             "size src/nest.ts:2"                        # [N]
notproven $CR/rust callees src/fix1.rs:near_hedged_hop      "get src/model.rs:6" "get src/model.rs:13"  # [N] `g.build()` on an untyped g
# Shapes the identity rule keeps (census-driven, fix round 1): a named non-struct result type (Go `type Shape int`), a field
# path below a call-typed local whose class name no other in-tree class shares, a result type named through a re-export.
proven    $CR/go   callees src/app/fix1.go:UseNamedType     "method HasTop src/nest/nest.go:22"         # [P]
proven    $CR/go   callees src/app/fix1.go:UseFieldPath     "method Size src/nest/nest.go:13"           # [P]
proven    $CR/rust callees src/fix1.rs:use_reexport         "method get src/nest.rs:4"                  # [P]
notproven $CR/cpp  callees src/fix1.cpp:nearOverloadHop     "size src/nest.cpp:5" "size src/nest.cpp:7" # [N] `p.pick( 1 )` is overloaded
# ── fix round 2 (rv-call-result-typing-delta D1–D3): the written type resolves in the callee's LEXICAL scope ──
# D1 a class is in scope at the callee only when every scope enclosing it — an indexed class / module / function, or a
#    namespace that is no symbol (TS `namespace`, C++ `namespace`) — also holds the callee; from another file (the package,
#    the module) only a class at file scope is. A nested namesake never wins over the class the name really reaches.
notproven $CR/rust2 callees src/user.rs:near_inline_mod     "size src/scoped.rs:6"                      # [N] helpers::Config (truth other_crate's)
notproven $CR/rust2 callees src/user2.rs:near_module_nested "size src/reexp.rs:6"                       # [N] reexp's item is the re-export, not helpers::Config
proven    $CR/java2 callees src/scoped/Use.java:nearNestedOther "method size src/scoped/Config.java:4"  # [P] the package's Config
notproven $CR/java2 callees src/scoped/Use.java:nearNestedOther "size src/scoped/Util.java:8"           # [N] Util.Fixtures.Config
proven    $CR/java2 callees src/scoped/Use2.java:useNestedInScope "method weight src/scoped/Util2.java:5"   # [P] Util2.Entry encloses make() # guard
notproven $CR/java2 callees src/scoped/Use2.java:useNestedInScope "weight src/scoped/Entry.java:4"     # [N] # guard
notproven $CR/java2 callees src/scoped2/Use3.java:nearNestedPackage "size src/scoped2/Holder.java:5"  # [N] a nested class is no bare package name
notproven $CR/java2 callees src/inh/Use4.java:nearInheritedNested "size src/inh/Config.java:4"         # [N] Util4 inherits Base.Config # guard
proven    $CR/kt2  callees src/app/Use.kt:nearNestedOther   "fn size src/app/Model.kt:4"                # [P] the package's Config
notproven $CR/kt2  callees src/app/Use.kt:nearNestedOther   "size src/app/Util.kt:7" "size src/app/Registry.kt:5"   # [N] Fixtures.Config, object Registry's Config
proven    $CR/kt2  callees src/app/Use2.kt:useCompanion     "fn weight src/app/Maker.kt:9"              # [P] a companion's callee sees Maker.Part # guard
notproven $CR/kt2  callees src/app/Use2.kt:useCompanion     "weight src/app/Part.kt:4"                  # [N] # guard
notproven $CR/ts2  callees src/use.ts:nearNamespaced        "json src/globals.ts:7"                     # [N] mock.Response (truth the global Response)
# D2 a C++ unqualified result: a using-declaration of the name visible at the callee (its file or a header it includes)
#    decides; else the class's namespace must enclose the callee's, or a visible using-directive name it. An outside
#    `using` never hands the result to the in-tree namesake.
for f in nearUsingNs nearUsingDecl; do   # `using namespace ext;` / `using ext::Config;` beside the in-tree other::Config
    notproven $CR/cpp2 callees "src/app.cpp:$f"             "get src/model.cpp:3" "get src/model.cpp:4" # [N]
done
notproven $CR/cpp2 callees src/app2.cpp:nearUsingDeclGlobal "load src/decl.cpp:3"                       # [N] `using ext::Settings;` hides the global ::Settings
for f in useDirective useEnclosing; do   # `using namespace parts;` in the callee's namespace (its header); the callee's own namespace
    notproven $CR/cpp2 callees "src/app2.cpp:$f"            "weight src/pos.cpp:3"                      # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard
done
# a using-declaration written fully qualified (`using ::net::wire::Frame;`) names the class its own namespace records place
# there, though that header declares no free function in the namespace (envoy's `using ::Envoy::Http::Http2::Http2Frame;`).
# FLOOR (not gated): a callee whose file's parse lost its namespace nesting (envoy's TRY_NEEDS_AUDIT … END_TRY macros end
# the namespace early) is in no namespace that encloses the class: it types nothing, as on base.
notproven $CR/cpp2 callees src/app3.cpp:useQualifiedUsingDecl "kind src/helper.cpp:3"                   # [FLOOR] C++ off (fix round 6): hedges — was [P]
# D3 a JVM class-name receiver the caller IMPORTS from outside (`import ext.Util; Util.open()`) is not the in-tree
#    namesake: the call is not bound to lib.Util.open as proven, and its result types nothing.
notproven $CR/java3 callees src/app/Use.java:nearOutsideClassReceiver "size src/lib/Config.java:4" "size src/lib/Other.java:4"   # [N]
notproven $CR/java3 callees src/app/Use.java:nearOutsideClassReceiver "open src/lib/Util.java:4"      # [N] the base false claim
notproven $CR/java3 callees src/app/Use.java:nearOutsideMethodRef "open src/lib/Util.java:4"          # [N] the method-reference sibling (base false claim)
# … and "outside" is read from the packages the tree DECLARES, not its directories: a Kotlin file's package need not match
# its directory (envoy mobile: package io.envoyproxy.envoymobile in …/envoymobile/filters/), so its import stays in tree.
proven    $CR/kt3  callees src/app/Use.kt:useImportedPackage "fn open src/core/impl/Util.kt:4"         # [P] # guard (green on base)

# ── fix round 3 (rv-call-result-typing-delta2 D4–D6): every binding of the spelling visible at the callee counts ──
# D4 a Rust `mod` is a fresh scope: the file's items are not in scope inside it, and its own `use` / items decide there;
#    `super::` / `self::` written inside an inline mod are relative to that mod (rust3: the reviewer's rs2 / rs1 shapes).
notproven $CR/rust3 callees src/use_it.rs:r_inline_use_outside "spin src/n2.rs:3" "spin src/other.rs:3"  # [N] `use ext_crate::Gadget;` in `mod outer`
notproven $CR/rust3 callees src/use_it.rs:r_nested_bare        "width src/n.rs:2" "width src/n.rs:7"     # [N] nothing in `mod bare` binds Top (the split)
notproven $CR/rust3 callees src/use_it.rs:r_nested_use_in_mod  "width src/n.rs:2" "width src/n.rs:7"     # [N] # guard
proven    $CR/rust3 callees src/use_it.rs:r_super_path         "method spin src/n2.rs:3"                 # [P] `super::Gadget` from `mod plain`: the file's own
proven    $CR/rust3 callees src/use_it.rs:r_own_mod_item       "method turn src/n3.rs:9"                 # [P] the mod's own Widget hides nothing
notproven $CR/rust3 callees src/use_it.rs:r_own_mod_item       "turn src/n3.rs:3"                        # [N] the file's Widget is not in scope in `mod own`
# D5 a C++ alias-declaration / typedef is a binding of the spelling (file, namespace or class scope): an outside target names
#    nothing; an in-tree target is a FLOOR (Rule 2 keys members by the written name, so the alias's target is not followed).
#    An alias in a namespace that does not hold the callee is not in force (callElsewhere: the global Settings, a guard).
notproven $CR/cpp3 callees src/use.cpp:callAlias               "count src/list.cpp:2" "count src/list.cpp:5" "count src/list.cpp:8"   # [N] `using List = ext::IntList;`
notproven $CR/cpp3 callees src/use.cpp:callTypedef             "count src/list.cpp:2" "count src/list.cpp:5" "count src/list.cpp:8"   # [N] `typedef ext::IntList List2;`
notproven $CR/cpp3 callees src/use.cpp:callNsAlias             "count src/ns.cpp:2"                      # [N] cfg5's alias hides ::Settings
notproven $CR/cpp3 callees src/use.cpp:callNsTypedef           "count src/ns.cpp:2"                      # [N] cfg6's typedef twin
notproven $CR/cpp3 callees src/use.cpp:callElsewhere           "count src/ns.cpp:2"                      # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard: cfg8's alias is not in force in cfg7
# D6 a JVM class-name receiver binds the in-tree class only where the caller's file SEES it (its package, a single-type import
#    naming it, an on-demand import of its package); `import ext.*` alone leaves lib.Util unseen. An in-tree on-demand import
#    is a binding of the result type too (Java `import lib.*`, Kotlin `import lib.*`).
notproven $CR/java4 callees src/app3/UseWild.java:d6Wildcard   "open src/lib/Util.java:3" "size src/lib/Thing.java:2" "size src/lib/Other.java:2"   # [N] (open: a base false claim)
notproven $CR/java4 callees src/app5/UseBoth.java:d6WildPlusExplicit "open src/lib/Util.java:3" "size src/lib/Thing.java:2"   # [N] # guard
proven    $CR/java4 callees src/app6/UseLib.java:pLibWild      "method open src/lib/Util.java:3" "method size src/lib/Thing.java:2"   # [P] # guard
proven    $CR/java4 callees src/app7/UseLoader.java:pOnDemandResult "method size src/lib/Thing.java:2"   # [P] the callee's `import lib.*`
notproven $CR/kt4  callees src/app2/Use.kt:d6KotlinWild        "open src/lib/Util.kt:4" "size src/lib/Util.kt:8" "size src/lib/Util.kt:12"   # [N] (open: a base false claim)
proven    $CR/kt4  callees src/app/Use.kt:pStarResult          "fn size src/lib/Util.kt:8"               # [P] the callee's `import lib.*`
# ── fix round 4 (rv-call-result-typing-delta3 E1–E3): a declaration the index keeps no class for still binds the spelling ──
# E1 a Java nested `record` (and an `@interface`) is a type declared at that level: it hides the package's namesake.
notproven $CR/java5 callees src/app/C4.java:cell4 "hit4 src/app/S4.java:3"                       # [N] `record S4` nested in C4
notproven $CR/java5 callees src/app/C9.java:cell9 "hit9 src/app/S9.java:3"                       # [N] `@interface S9` nested in C9
proven    $CR/java5 callees src/app/C3.java:cell3 "method hit3 src/app/C3.java:3"                # [P] # guard: a nested enum is a class
# E2 a Java single-static-import of a type (JLS 6.4.1: it shadows the package's types) names that member, never the package's.
notproven $CR/java5 callees src/app/C1.java:cell1 "hit1 src/app/S1.java:3"                       # [N] `import static ext.Holder.S1;`
proven    $CR/java5 callees src/app/C7.java:cell7 "method hit7 src/app/S7.java:3"                # [P] a static import of ANOTHER name, and a static
#                                                                                                       on-demand import (never shadows the package) hide nothing
# the Kotlin nested forms the index records (companion member, enum class, object, data class): guards
proven    $CR/kt5  callees src/app/C1.kt:cell1  "fn hit1 src/app/C1.kt:4"                        # [P] # guard
proven    $CR/kt5  callees src/app/C3.kt:cell3  "fn hit3 src/app/C3.kt:3"                        # [P] # guard
proven    $CR/kt5  callees src/app/C4.kt:cell4  "fn hit4 src/app/C4.kt:3"                        # [P] # guard
proven    $CR/kt5  callees src/app/C5.kt:cell5  "fn hit5 src/app/C5.kt:3"                        # [P] # guard
# E3 C++: a union, a bodiless (forward) declaration, a macro (any: the parser cannot see what it declares), a block-scope
#    using in force in a local class — each binds the spelling in its scope and hides the global namesake; a forward
#    declaration of the in-tree class itself and a local class with nothing in its block stay proven.
notproven $CR/cpp4 callees src/use.cpp:cell1  "hit1 src/traps.h:2"                               # [N] `struct S1;` in a1
notproven $CR/cpp4 callees src/use.cpp:cell2  "hit2 src/fwd2.h:3"                                # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard: the forward-declared class is in tree
notproven $CR/cpp4 callees src/use.cpp:cell12 "hit12 src/traps.h:7"                              # [N] `union S12` in a12
notproven $CR/cpp4 callees src/use.cpp:cell5  "hit5 src/traps.h:4"                               # [N] `DECL5(S5)` in a5
notproven $CR/cpp4 callees src/use.cpp:cell3  "hit3 src/traps.h:3"                               # [N] ANY macro in force may declare it (`REG3(Other3)` does not: an honest loss)
notproven $CR/cpp4 callees src/use.cpp:cell6  "hit6 src/traps.h:5"                               # [N] block `using ext::S6;` + local class
notproven $CR/cpp4 callees src/use.cpp:cell7  "hit7 src/traps.h:6"                               # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard: a local class, nothing in its block
# E3 Rust: a statement-position macro in an enclosing fn body may declare the item there (`mk14!()` does): the module's
#    namesake is not proven; the same nested fn with no macro in its enclosing block stays proven.
notproven $CR/rust4 callees src/c14.rs:cell14 "hit14 src/c14.rs:3"                               # [N] `mk14!();` in cell14's body
proven    $CR/rust4 callees src/c15.rs:cell15 "method hit15 src/c15.rs:3"                        # [P] # guard
# fix round 5 (rv-call-result-typing-delta4 B1–B4 + M4): C++ — a macro the parser reads as a well-formed declaration: an
#    export / annotation macro between the class-key and the name (`class API S {…}`, `struct API S final {…}`, `struct
#    API S;`, `API struct S {…}`), a class-body invocation ending in `;` (`MK(S);`, read as a constructor), a function-body
#    macro beside a local class — each hides EVERY name in its scope (the parser cannot see what it declares); guards: real
#    constructors / a destructor, a function-body macro with no local class (namespace scope unaffected), and a forward
#    declaration in the class's own namespace reached through a using-declaration (the M4 exemption).
notproven $CR/cpp5 callees src/use.cpp:cell6  "hit6 src/traps.h:2"                               # [N] `class API6 S6 {…}` in a6
notproven $CR/cpp5 callees src/use.cpp:cell7  "hit7 src/traps.h:3"                               # [N] `struct API6 S7 final {…}` in a7
notproven $CR/cpp5 callees src/use.cpp:cell18 "hit18 src/traps.h:4"                              # [N] `struct API6 S18;` in a18
notproven $CR/cpp5 callees src/use.cpp:cell23 "hit23 src/traps.h:5"                              # [N] `API6 struct S23 {…}` in a23
notproven $CR/cpp5 callees src/use.cpp:cell27 "hit27 src/traps.h:6"                              # [N] `MK(S27);` in O27's body
notproven $CR/cpp5 callees src/use.cpp:cell29 "hit29 src/traps.h:7"                              # [N] `MK2(S29, int);` in O29's body
notproven $CR/cpp5 callees src/use.cpp:cell12 "hit12 src/traps.h:8"                              # [N] `DECL12(S12)` beside the local class
notproven $CR/cpp5 callees src/use.cpp:cell40 "hit40 src/traps.h:9"                              # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard: constructors, a destructor
notproven $CR/cpp5 callees src/use.cpp:cell41 "hit41 src/traps.h:10"                             # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard: a fn-body macro, no local class
notproven $CR/cpp5 callees src/use.cpp:cell32 "hit32 src/f32.h:3"                                # [FLOOR] C++ off (fix round 6): hedges — was [P] # guard (M4): own-namespace forward decl via using a32::S32
# fix round 5 Rust (B1): a method of an `impl` written inside a fn body sees that body's items, so a macro there hides the
#    module's namesake — the impl directly in the block, after an item-position macro, in an inner block, and an impl of
#    a module-level struct; guard: an impl in a block with no macro.
notproven $CR/rust5 callees src/c1.rs:cell1   "hit1 src/c1.rs:3"                                 # [N] `mk1!();` + impl in the block
notproven $CR/rust5 callees src/c3.rs:cell3   "hit3 src/c3.rs:3"                                 # [N] `mk3! {}` + impl in the block
notproven $CR/rust5 callees src/c4.rs:cell4   "hit4 src/c4.rs:3"                                 # [N] `mk4!();` + impl in an inner block
notproven $CR/rust5 callees src/c5.rs:cell5   "hit5 src/c5.rs:3"                                 # [N] `mk5!();` + impl of a module-level struct
proven    $CR/rust5 callees src/c6.rs:cell6   "method hit6 src/c6.rs:3"                          # [P] # guard: impl in a block, no macro
# fix round 6 (rv-call-result-typing-delta5 B3): a `const` / `static` item's value block is an item scope too — the impl
#    methods written in it see the block's items, so a macro there hides the module's namesake (at module level, in a
#    static, in a fn body); the block's own `use` decides there; guard: a const block with neither.
notproven $CR/rust6 callees src/c50.rs:cell50 "hit50 src/c50.rs:3"                               # [N] `mk50!();` in `const _: () = {…}`
notproven $CR/rust6 callees src/c51.rs:cell51 "hit51 src/c51.rs:3"                               # [N] `mk51!();` in `static X51: () = {…}`
notproven $CR/rust6 callees src/c52.rs:cell52 "hit52 src/c52.rs:3"                               # [N] `mk52!();` in a const block in a fn body
notproven $CR/rust6 callees src/c56.rs:cell56 "hit56 src/c56.rs:3"                               # [N] the const block's `use … as S56` (outside)
proven    $CR/rust6 callees src/c53.rs:cell53 "method hit53 src/c53.rs:3"                        # [P] # guard: a const block, no macro
# ── the BINDING-FORM MATRIX (fix round 3: close the class, not the shapes) ──
# callresult_matrix.txt writes one tree per language (mx_rust, mx_cpp, mx_java, mx_kt, mx_ts, mx_go) and lists its cells:
# language x binding form x scope level x target (header of that file). Each cell is one --callees run on `cell<k>`: a U cell
# must show its tagged hit<k> as the ONE proven row; an O / X / 2 / FLOOR cell must prove no hit<k> at all. NA rows (a
# shape the language cannot write) are listed, never run.
MXCELLS="$TMP/mx.cells.txt"
if ! python3 -I "$CORPUS/callresult_matrix.txt" "$TMP/fix/$CR" >"$MXCELLS" 2>"$TMP/mx.err"; then no "(L) matrix: the generator failed: $( head -c 300 "$TMP/mx.err" )"; fi
mxn=0; mxred=0
while read -r tag id lang form scope target root sel verdict a b c; do
    [ "$tag" = "CELL" ] || continue
    mxn=$(( mxn + 1 ))
    label="(L) matrix #$id $lang $form @$scope target=$target"
    if ! getrows "$CR/$root" callees "$sel"; then mxred=$(( mxred + 1 )); continue; fi
    if [ "$verdict" = "P" ]; then
        f="${c%:*}"; l="${c##*:}"
        want="$( printf '%s\n' "$GOT" | awk -v t="$a" -v n="$b" -v f="$f" -v l="$l" "$AWKB"' $1 == t && ( $2 == n || bare( $2 ) == n ) && $3 == f && $4 == l && $5 != "name"' )"
        extra="$( printf '%s\n' "$GOT" | awk -v n="$b" -v f="$f" -v l="$l" "$AWKB"' ( $2 == n || bare( $2 ) == n ) && $5 != "name" && !( $3 == f && $4 == l )' )"
        if [ -n "$want" ] && [ -z "$extra" ]; then ok "$label proves exactly [$b $c]"
        else no "$label: expected exactly the proven row [$a $b $c]: $( show )"; mxred=$(( mxred + 1 )); fi
    else
        hits="$( printf '%s\n' "$GOT" | awk -v n="$a" "$AWKB"' ( $2 == n || bare( $2 ) == n ) && $5 != "name"' )"
        if [ -z "$hits" ]; then ok "$label proves no [$a]${b:+ ($b)}"
        else no "$label shows [$a] as a PROVEN edge${b:+ (a $b cell must hedge)}: $( show )"; mxred=$(( mxred + 1 )); fi
    fi
done <"$MXCELLS"
if [ "$mxn" -ge 200 ]; then ok "(L) matrix: $mxn cells run, $mxred red, $( grep -c '^NA ' "$MXCELLS" ) N/A rows listed"
else no "(L) matrix: only $mxn cells were generated (expected >= 200)"; fi
# (L-objc) train 30 (N3): the ObjC FLOOR (callresult_matrix.txt objcfloor.mm) — ObjC is off (model.h callResultFamilyOf), so the
# Objective-C++ call result is not typed and the call keeps BOTH included namesakes; one proven SObjc row alone means ObjC is
# typed now: make it a P cell (the macro-aware C++ card) instead of loosening this arm.
if getrows "$CR/mx_cpp" callees "src/objcfloor.mm:cellObjc"; then
    if [ -n "$( specmatch "hitObjc src/objcfloor.h:3" )" ] && [ -n "$( specmatch "hitObjc src/objcdecoy.h:3" )" ]; then
        ok "(L-objc) ObjC floor: the .mm call result is not typed (hitObjc keeps both included namesakes)"
    else no "(L-objc) ObjC floor: want hitObjc on objcfloor.h:3 AND objcdecoy.h:3 (ObjC untyped): $( show )"; fi
fi

echo "=== (RS) Rust receiver evidence (lane rust-receivers): a written or constructed type proves the receiver's class ==="
# rsrecv/: model.rs Book::new :4, Book::spin :5, Book::iter :6, Other::spin :10, Other::iter :11, Cfg::tune :16, Knob::tune :20,
# Stack::spin :24; other.rs other::Book::spin :4, File::sync_all :8; kinds.rs Shape::spin :4, the Render trait's default spin :7.
# [P] a parameter (`&T`, `&mut T`, `Box<T>`, a path `crate::other::T` / `other::T`, a user generic `Stack<u8>`, an enum), a
# `let x: T` / `let x: &T`, a struct literal (`T { .. }`, `other::T {}`), `T::new()` (its declared `-> Self`: the call-result
# rows, which now read `Self`), `T::default()`, a closure's typed parameter, and a field path (`s.book.m()`, `self.book.m()`,
# `self.boxed.m()`, `self.inner.book.m()`, a `Self { .. }` local's field) RESOLVE to exactly that class's method.
RSA="src/app.rs"; RSM="src/model.rs"
RSSPIN="spin $RSM:5|spin $RSM:10|spin $RSM:24|spin src/other.rs:4|spin src/kinds.rs:4|spin src/kinds.rs:7"
for f in typed_param typed_param_mut typed_param_box let_typed let_typed_ref let_struct let_new closure_param field_chain; do
    want="method spin $RSM"
    case "$f" in let_typed|let_typed_ref|closure_param) want="$want;fn make $RSA" ;; let_new) want="$want;method new $RSM" ;; esac
    exactproven rsrecv callees "$RSA:$f" "$want"                                                                # [P]
    proven      rsrecv callees "$RSA:$f" "method spin $RSM:5"                                                   # [P] Book's
    notproven   rsrecv callees "$RSA:$f" "spin $RSM:10" "spin $RSM:24"                                          # the same file's decoys
done
for f in typed_param_path typed_param_module let_struct_path; do
    exactproven rsrecv callees "$RSA:$f" "method spin src/other.rs"                                             # [P] other::Book, never model's
done
proven      rsrecv callees "$RSA:typed_param_generic" "method spin $RSM:24"                                     # [P] Stack<u8> is a Stack
exactproven rsrecv callees "$RSA:typed_param_generic" "method spin $RSM"
exactproven rsrecv callees "$RSA:typed_param_enum" "method spin src/kinds.rs"                                    # [P] an enum's own impl
proven      rsrecv callees "$RSA:typed_param_enum" "method spin src/kinds.rs:4"
proven      rsrecv callees "$RSA:let_default" "method tune $RSM:16"                                             # [P] Cfg::default(): Cfg's
notproven   rsrecv callees "$RSA:let_default" "tune $RSM:20"                                                    # never Knob's
proven      rsrecv callees "$RSA:std_named" "method iter $RSM:6"                                                 # [P] book.iter() on &Book (std-named)
for f in Shelf::self_field Shelf::self_boxed Shelf::self_two_hops Shelf::self_literal Shelf::self_param; do
    want="method spin $RSM"; [ "$f" = Shelf::self_literal ] && want="$want;method new $RSM"
    exactproven rsrecv callees "$RSM::$f" "$want"                                                               # [P] through the field table
    proven      rsrecv callees "$RSM::$f" "method spin $RSM:5"
done
proven      rsrecv callees "$RSM::Shelf::iter" "method iter $RSM:6"                                              # [P] self.book.iter() (mdbook's MDBook::iter)
# [N] near misses record nothing and stay as they were: an untyped `let x = foo.bar()`, `dyn Trait` / `impl Trait` / a
# generic `T: Trait` / a trait written as a type (dispatch: lane L6), Option<T> (a parameter and a `let`), Rc<T> (its own
# members), an inner binding hiding the typed one (`let`, `for`, a closure parameter), an outside type named like an in-tree
# class (`use std::fs::File`), a tuple pattern, an outside `String::default()`; a field typed Option / Rc / u32, a missing
# field, a generic struct's `T` field, a tuple-struct field `self.0`, and a same-named owner (other::Shelf) whose `book` is a Vec.
rs_none(){   # rs_none SELECTOR — no spin candidate is proven
    local specs; IFS='|' read -r -a specs <<<"$RSSPIN"
    notproven rsrecv callees "$1" "${specs[@]}"
}
for f in near_call near_dyn near_impl near_generic near_bare_trait near_option near_let_option near_rc near_shadow near_for near_closure_shadow near_tuple; do
    rs_none "$RSA:$f"                                                                                          # [N]
done
notproven rsrecv callees "$RSA:near_outside" "sync_all src/other.rs:8"                                           # [N] std::fs::File
notproven rsrecv callees "$RSA:near_default_outside" "tune $RSM:16" "tune $RSM:20"                                # [N] String::default()
for f in Shelf::near_self_maybe Shelf::near_self_shared Shelf::near_self_count Shelf::near_self_unknown Holder::near_generic_field Pair::near_tuple_field; do
    rs_none "$RSM::$f"                                                                                         # [N]
done
rs_none "src/other.rs::Shelf::near_same_named_owner"                                                             # [N]
# the callers side reads the same edges (Cfg::tune: few enough callers that the answer is never capped, unlike Book::spin):
# --callers lists the [P] caller unhedged and never the [N] one; Knob::tune's callers are the typed Knob locals only
proven      rsrecv callers "$RSM::Cfg::tune" "fn let_default $RSA"
notproven   rsrecv callers "$RSM::Cfg::tune" "near_default_outside $RSA" "glob_default src/nest/inner.rs" "glob_of_glob_default src/glob2/leaf.rs"
proven      rsrecv callers "$RSM::Knob::tune" "fn glob_default src/nest/inner.rs"
notproven   rsrecv callers "$RSM::Knob::tune" "let_default $RSA" "near_default_outside $RSA" "glob_of_glob_default src/glob2/leaf.rs"
# a glob `use super::*` brings in what the parent module's own `use` names (Rust: a glob imports the module's imports
# too); a glob of a module that only globs in turn is not followed (stated floor: names nothing, proves nothing) — and
# (fix round 1, rv-l3 M1) neither does its `T::default()`: a callee's declared `-> Self` types the local only through a
# qualifier that resolves at the site, so glob_of_glob_default is declined exactly as on base
exactproven rsrecv callees "src/nest/inner.rs:glob_param" "method spin $RSM"                                     # [P]
proven      rsrecv callees "src/nest/inner.rs:glob_param" "method spin $RSM:5"
proven      rsrecv callees "src/nest/inner.rs:glob_default" "method tune $RSM:20"                                # [P] Knob's
notproven   rsrecv callees "src/nest/inner.rs:glob_default" "tune $RSM:16"
rs_none "src/glob2/leaf.rs:glob_of_glob"                                                                        # [N] floor
notproven   rsrecv callees "src/glob2/leaf.rs:glob_of_glob_default" "tune $RSM:20" "tune $RSM:16"                # [N] floor (= base)
# early gates review (rv-l3-gates A1-A12; src/adds.rs, alias.rs, samename.rs, kinds.rs's trait). [P]: the field below
# `&mut self`, by-value `self`, `&'a self`, a field written `&'a Book`, a `&Self` parameter's field, a `Self::new()` local's
# field, a `&'a Book` parameter, a `use … as` alias (by the path it names: other::Book, never the in-tree model::Other its
# alias spells), the same name in two modules (each scope's own Book), a block-scoped `let b: Other` beside a `&Book`
# parameter (each call its own class). [N]: `Box<dyn Render>` (a parameter and a field), `&mut dyn Render`, `Arc<Book>`, a
# `RefCell<Book>` field, an index receiver `self.books[0]`, a `type Tome = Book` alias (a floor: the alias is not
# followed), a generic parameter spelled `Book`, a struct pattern parameter, `Book::try_new()` / `maybe_new()` (Result /
# Option without its operator), the element type of `Vec<Book>` / `&[Book]` / `HashMap<_, Book>` (never Book::iter).
RSD="src/adds.rs"
for f in Rack::mut_self Rack::value_self Rack::life_self Rack::borrowed_field Rack::self_param Rack::self_new; do
    proven      rsrecv callees "$RSD::$f" "method spin $RSM:5"                                                  # [P]
    notproven   rsrecv callees "$RSD::$f" "spin $RSM:10" "spin $RSM:24" "spin src/other.rs:4" "spin src/kinds.rs:4" "spin src/kinds.rs:7"
done
exactproven rsrecv callees "$RSD:life_param" "method spin $RSM"                                                 # [P]
proven      rsrecv callees "$RSD:life_param" "method spin $RSM:5"
exactproven rsrecv callees "src/alias.rs:alias_collides" "method spin src/other.rs"                              # [P] never model's Other
exactproven rsrecv callees "src/alias.rs:alias_plain" "method spin $RSM"                                         # [P]
proven      rsrecv callees "src/alias.rs:alias_plain" "method spin $RSM:5"
exactproven rsrecv callees "src/samename.rs:other_book" "method spin src/other.rs"                               # [P] the use'd other::Book
exactproven rsrecv callees "src/samename.rs:nested_book" "method spin src/samename.rs"                           # [P] the mod's own Book
proven      rsrecv callees "$RSD:block_shadow" "method spin $RSM:5" "method spin $RSM:10"                       # [P] each call its own class
# CodeRabbit #424: a Rust local or parameter named `this` is an ordinary name, read by its own binding — never the enclosing
# impl's `self` (the pin-project idiom `let this = self.project()`). Mine.book is other::Book, Shelf.book is model::Book:
# `self.book.spin()` stays other::Book's; `this.book.spin()` follows the `this` binding's type, or proves nothing when it has none
RST="src/thisname.rs"
exactproven rsrecv callees "$RST::Mine::real_self" "method spin src/other.rs"                                   # [P] the real `self`
for f in Mine::this_param Mine::this_let; do
    exactproven rsrecv callees "$RST::$f" "method spin $RSM"                                                    # [P] Shelf's book: model::Book
    proven      rsrecv callees "$RST::$f" "method spin $RSM:5"
    notproven   rsrecv callees "$RST::$f" "spin src/other.rs:4"                                                 # never the enclosing impl's field
done
exactproven rsrecv callees "$RST::Mine::this_direct" "method spin $RSM"                                         # [P] `this: &Book` -> Book::spin
rs_none "$RST::Mine::this_untyped"                                                                              # [N] an untyped `this` local proves nothing (no spin, not other::Book's)
notproven rsrecv callees "$RST:near_ufcs_cast" "tune $RSM:20" "tune $RSM:16"                                   # [N] a UFCS cast's `-> Self` types nothing (a pin: by-name today)
for f in Rack::near_box_dyn_field Rack::near_refcell_field Rack::near_index_recv; do rs_none "$RSD::$f"; done       # [N]
for f in near_box_dyn near_mut_dyn near_arc near_type_alias near_generic_named near_struct_pattern near_try_new near_maybe_new; do
    rs_none "$RSD:$f"                                                                                          # [N]
done
for f in near_vec_iter near_slice_iter near_map_get Rack::near_vec_field_iter Rack::near_chain_recv; do
    sel="$RSD:$f"; case "$f" in Rack::*) sel="$RSD::$f" ;; esac
    notproven rsrecv callees "$sel" "iter $RSM:6" "iter $RSM:11"                                                # [N] the element type is no receiver
done
proven      rsrecv callees "$RSD::Rack::near_chain_recv" "method spin $RSM:5"                                   # its inner call stays proven
proven      rsrecv callees "$RSD:make_book_local" "method spin $RSM:5"                                           # guard: a call result (L)
notproven   rsrecv callees "$RSD:make_book_local" "spin $RSM:10"                                                 # never Other's (the path's type)
# FLOOR, unchanged from base (not this lane's rule): `self.spin()` inside a trait's default method is Rule 1's and proves
# the trait's own default body (kinds.rs:7) — an implementor may override it (dispatch: lane L6, carded); a blanket
# `impl<T: Render> Extra for T` stays hedged. Pinned so a change here is seen: exactly the base answer.
exactproven rsrecv callees "src/kinds.rs:twice" "method spin src/kinds.rs"
rs_none "src/kinds.rs:go"
# a `let` / a typed closure parameter in a `const` / `static` initializer (no enclosing fn: the first cut of this lane
# crashed reading a null fn's generics there — nushell): typed like any other, and the run exits 0 (ran_ok)
proven      rsrecv callees "src/consts.rs:SPUN" "method spin $RSM:5"                                               # [P]
proven      rsrecv callees "src/consts.rs:SPIN_FN" "method spin $RSM:5"                                            # [P]
notproven   rsrecv callees "src/consts.rs:SPIN_FN" "spin $RSM:10" "spin $RSM:24" "spin src/other.rs:4"
# `Path::new( p )` where `use std::path::Path` names std's: the canonical tier still matches the in-tree other::Path's `new`
# by its scope name (a base edge, not this lane's), but that call's declared `-> &Self` never types the local when the
# file imports the qualifier from outside the tree (nushell's Open::run: path.is_dir() was proven onto nu-path's Path at
# 89f236b0); twins: with `use crate::other::Path` in scope it does, and so does a path-qualified `crate::other::Path::new( p )`
# in that same file (fix round 1: the qualifier is resolved as a WRITTEN path at the call site, not by its last segment).
notproven   rsrecv callees "src/stdpath.rs:std_path_new" "probe src/other.rs:17"                                   # [N]
proven      rsrecv callees "src/stdpath.rs:own_path_new" "method probe src/other.rs:17"                             # [P]
proven      rsrecv callees "src/ownpath.rs:own_path_use" "method probe src/other.rs:17"                             # [P]
# fix round 1 (rv-l3 M1): the std / external class, closed for every spelling. A qualified `T::f()` types its local only
# when its qualifier, read as a WRITTEN type at the call site, resolves to the in-tree class owning `f`. [N] (each proven
# at bb93a270, hedged on base): `use std::fs; fs::File::open()` / `create()`, fully qualified `std::fs::File::create()`,
# `std::path::Path::new()`, `std::path::PathBuf::from()` (nushell misc/run.rs, nu-lsp symbols.rs), a glob of a std module
# (`use std::collections::*; HashMap::new()` / `with_capacity()`), prelude `String::from()` / `String::new()` with no
# in-tree String in scope, `use std::time; time::Instant::now()`, a child's `use super::*` of a parent's std `use`, and an
# external crate's glob (`use serde::*; Book::new()`, crate::model::Book never imported). [P] twins: the in-tree class by
# its `use`, by `crate::other::T::f()`, by a `use`d module `other::T::f()`.
QO="src/other.rs"
for f in fs_path_open fs_path_create full_path_create; do notproven rsrecv callees "src/stdq.rs:$f" "sync_all $QO:8"; done   # [N]
notproven   rsrecv callees "src/stdq.rs:full_path_new" "probe $QO:17"                                              # [N]
notproven   rsrecv callees "src/stdq.rs:full_pathbuf_from" "as_pb $QO:44"                                          # [N]
for f in glob_std_new glob_std_capacity; do notproven rsrecv callees "src/stdq.rs:$f" "get_it $QO:28"; done        # [N]
for f in prelude_from prelude_new; do notproven rsrecv callees "src/stdq.rs:$f" "lenx $QO:34"; done                 # [N]
notproven   rsrecv callees "src/stdq.rs:module_now" "elapsed_x $QO:39"                                             # [N]
for f in glob_open glob_create; do notproven rsrecv callees "src/stdqp/child.rs:$f" "sync_all $QO:8"; done          # [N]
notproven   rsrecv callees "src/stdqp/child.rs:glob_now" "elapsed_x $QO:39"                                        # [N]
rs_none "src/extglob.rs:ext_glob_new"                                                                           # [N]
proven      rsrecv callees "src/stdqown.rs:own_open" "method sync_all $QO:8"                                       # [P]
proven      rsrecv callees "src/stdqown.rs:own_new" "method get_it $QO:28"                                         # [P]
proven      rsrecv callees "src/stdqown.rs:own_full_create" "method sync_all $QO:8"                                # [P]
proven      rsrecv callees "src/stdqown.rs:own_module_now" "method elapsed_x $QO:39"                               # [P]
proven      rsrecv callees "src/stdqown.rs:own_full_from" "method lenx $QO:34"                                     # [P]
# fc1 (rv-l3-delta check 2 / N-c): the same class for a result written by the TYPE'S OWN NAME (`-> OsString`, a path
# `-> crate::nsown::OsString`, `Result<OsString, ()>` / `Option<..>` + unwrap, `Box<..>`), not `Self`. A qualified member
# call `T::f()` types its local only when T, read as a written type at the call site, reaches f's in-tree class, whatever
# the result spelling. [N] (each proven on base dd378171): std's fully qualified, a `use`d std module, core's, std::time's,
# an external crate's (`serde::`), an unknown root's, a re-export of std's (`crate::stdnre::OsString`), a `use` of std's
# type, a std glob, the prelude's String. Hedged on base too (kept): UFCS `<std::ffi::OsString>::from()`, a renamed std
# re-export, a type alias of std's, a free function std::fs::read_to_string / fs::read_to_string beside an in-tree namesake.
NS="src/nsown.rs"
for f in full_from full_from_q full_try full_opt full_box mod_from ext_from unknown_from re_path ufcs_from re_alias_path free_full free_mod; do
    notproven rsrecv callees "src/stdn.rs:$f" "as_os $NS:10"                                                   # [N]
done
for f in core_secs std_secs; do notproven rsrecv callees "src/stdn.rs:$f" "as_dur $NS:15"; done                    # [N]
notproven   rsrecv callees "src/stdnuse.rs:use_from" "as_os $NS:10"                                                # [N]
notproven   rsrecv callees "src/stdnuse.rs:glob_secs" "as_dur $NS:15"                                              # [N]
notproven   rsrecv callees "src/stdnuse.rs:prelude_with" "lenx $QO:34"                                             # [N]
for f in re_alias ty_alias; do notproven rsrecv callees "src/stdnre.rs:$f" "as_os $NS:10"; done                    # [N]
# [P] twins (proven on base, kept): crate::nsown::T, its path result, Result / Option + unwrap, Box, a `use`d module, a
# `use`d type, a re-export reaching the in-tree type (`crate::nsre::OsString`, `self::OsString` inside nsre), the in-tree
# String by its `use`, the free function by its module path. An in-tree `mod std` (nshadow.rs): a non-import path's first
# segment is an item of the module before the extern prelude, so `std::ffi::OsStr::new()` there IS the in-tree one [P].
for f in own_full own_q own_try own_opt own_box own_use own_free own_free_full own_reexp; do
    proven  rsrecv callees "src/nsownuse.rs:$f" "method as_os $NS:10"                                          # [P]
done
proven      rsrecv callees "src/nsownuse.rs:own_mod" "method as_dur $NS:15"                                        # [P]
proven      rsrecv callees "src/nsownuse.rs:own_prelude_twin" "method lenx $QO:34"                                 # [P]
proven      rsrecv callees "src/nsre.rs:re_own_self" "method as_os $NS:10"                                         # [P]
for f in shadow_bare shadow_self; do proven rsrecv callees "src/nshadow.rs:$f" "method as_sh src/nshadow.rs:7"; done   # [P]
# [P] a T the walk cannot follow keeps the base row: the in-tree glob re-export `pub use crate::nsown::*;` (nsglob.rs) by a
# `use`, by its path and by the file's own glob of it (nsglobstar.rs), and a bench file outside every crate's module tree
# (`use rsrecv::nsown::OsString`). [N] there: a std root (`std::ffi::OsString::from()`) leads out of the tree from any file.
for f in glob_reexp_own glob_reexp_path; do proven rsrecv callees "src/nsglobuse.rs:$f" "method as_os $NS:10"; done # [P]
proven      rsrecv callees "src/nsglobstar.rs:glob_star_own" "method as_os $NS:10"                                # [P]
proven      rsrecv callees "benches/nsb.rs:bench_own" "method as_os $NS:10"                                         # [P]
notproven   rsrecv callees "benches/nsb.rs:bench_std" "as_os $NS:10"                                                # [N]
# fc1 fix 1 (rv-fc1 B1-B3, N4): the walk's "cannot follow" exits no longer fire on code that provably leaves the tree.
# B1: a glob brings a root only when its TARGET module declares or re-exports an item of that name, and only a glob at the
# level the call sits in (a fn body, then its module): `mod tests { use super::*; }` beside and around a std call, a glob of
# a module with no `std` / `core`, an explicit `use std::ffi::OsString` beside an in-tree glob (it shadows the glob). B2:
# cfg-gated duplicate `use`s lead out when every one does. B3: an inline module's re-export of std's type. N4: an extern
# crate named like an in-tree module. [N] each proven on dd378171 and 5cd18c99; [P] twins reach the in-tree type.
for f in rvtests.rs:t_full rvtests.rs:inner rvglob.rs:g_full rvexpl.rs:expl_from rvcfg.rs:cfg_from rvinl.rs:inl_path \
         rvinl.rs:inl_self rvinluse.rs:inl_cross rvext.rs:ext_mod rvext.rs:ext_mod_q; do
    notproven rsrecv callees "src/$f" "as_os $NS:10"                                                           # [N]
done
notproven   rsrecv callees "src/rvglob.rs:g_core" "as_dur $NS:15"                                                  # [N]
for f in rvtests.rs:t_own rvtests.rs:inner_own rvglob.rs:g_own rvgtuse.rs:gt_own rvinl.rs:inl_own rvinluse.rs:inl_cross_own \
         rvext.rs:ext_own; do
    proven  rsrecv callees "src/$f" "method as_os $NS:10"                                                      # [P]
done
for f in rvexpl.rs:expl_glob rvcfg.rs:cfg_own; do proven rsrecv callees "src/$f" "method as_dur $NS:15"; done     # [P]
# fc1 fix 2 (rv-fc1-delta1 C1, C2): a glob CYCLE (parent `pub use self::kid::*` + kid's `use super::*`, two files globbing each
# other, an inline mod globbing its parent) and a 7-deep acyclic glob chain end with the true answer — no module brings `std`,
# so the std call leads out [N] (each proven before); a private `use std::ffi::OsString` a `use super::*` sees is std's [N]
# (`#[cfg(test)] mod tests`, a plain child mod), and so is a std name at the end of a glob chain of named re-exports [N];
# [P] twins: the in-tree path on every cycle, a parent's `use crate::nsown::OsString`, a chain ending in the in-tree re-export.
for f in gcpar.rs:gcpar_full gcpar/kid.rs:gckid_full gcabuse.rs:gcab_full gcinl.rs:gcinl_kid_full gcinl.rs:gcinl_full gcdeep.rs:gcdeep_full \
         gutu.rs:gutu_in gutu.rs:gutu_bare gutu.rs:gutu_top gususe.rs:gus_bare; do
    notproven rsrecv callees "src/$f" "as_os $NS:10"                                                           # [N]
done
for f in gcpar.rs:gcpar_own gcpar/kid.rs:gckid_own gcabuse.rs:gcab_own gcinl.rs:gcinl_kid_own gcinl.rs:gcinl_own gcdeep.rs:gcdeep_own \
         gutuown.rs:gutuown_top gutuown.rs:gutuown_in gutuown.rs:gutuown_bare gususeown.rs:gusown_bare; do
    proven  rsrecv callees "src/$f" "method as_os $NS:10"                                                      # [P]
done
# fc1 fix 3 (rv-fc1-delta2 D1, D2): a named `use` of the name shadows the level's globs (so `use std::ffi::OsString;` beside
# `use crate::nsown::*;` is std's name for a child's `use super::*;` and for a glob of that module) [N]; a glob chain 4 deep
# ending in a named std re-export is cut at the path walk's depth cap, and a cut is never a proof onto the in-tree type [N]
# (3 deep is followed out, still [N]); [P] twins: a std glob + an explicit in-tree `use`, the same chain ending in the in-tree type.
for f in gsh.rs:gsh_in gsreuse.rs:gsre_bare gdqx4.rs:gdq4_bare gsh.rs:gsh_top gdqx3.rs:gdq3_bare gczuse.rs:gcz_bare; do
    notproven rsrecv callees "src/$f" "as_os $NS:10"                                                           # [N]
done
for f in gshown.rs:gsho_top gshown.rs:gsho_in gdox4.rs:gdo4_bare; do
    proven  rsrecv callees "src/$f" "method as_os $NS:10"                                                      # [P]
done
# fc1 fix 4 (rv-fc1-delta3 E1): a named re-export chain longer than the depth cap, with NO glob in between, is cut in the TOP-LEVEL
# walk (bare `use` and a written full path), and a cut is hedged, never proven onto the in-tree namesake [N]; [P] twin: a short chain in-tree
for f in gctn.rs:gctn_bare gctq.rs:gctq_full; do
    notproven rsrecv callees "src/$f" "as_os $NS:10"                                                           # [N]
done
proven      rsrecv callees "src/gcto.rs:gcto_bare" "method as_os $NS:10"                                      # [P]
# guard: `Book::new()` is a path call the canonical tier answers (rustqualcheck's shape), unchanged
proven      rsrecv callees "$RSA:let_new" "method new $RSM:4"

echo "=== (Q) qualified annotations and in-place rebinding (lane h1-annot) ==="
QA=qualannot
# Python — model.py: Session.close :2, Other.close :4, Other.read :5, Request.read :7, Outer.Inner.close :10; pkg/store.py:
#          Store.close :2; keep.py: Local.close :39. Every [N] call has 4 in-tree `close` namesakes (by name: hedged).
for f in use_param use_default use_declared use_dotted use_member_mod use_nested_outside use_unbound use_type_checking; do
    notproven $QA/py callees "app.py:$f" "close model.py:2"                       # [N] an outside qualifier's T beside an in-tree T
done
for f in use_optional use_union use_list use_string use_local; do   # wrapped / string / call-initialised: no class before or after
    notproven $QA/py callees "app.py:$f" "close model.py:2"                       # guard
done
notproven $QA/py callees app.py:handle_request "read model.py:7"                  # [N] starlette testclient's `request: httpx.Request`
proven    $QA/py callees keep.py:keep_mod       "fn close model.py:2"             # [P] guard: `import model` → model.Session
for f in keep_from_mod keep_dotted keep_bare keep_alias; do                       # `from pkg import store`, `import pkg.store`, a bare / aliased import
    proven    $QA/py callees "keep.py:$f" "fn close pkg/store.py:2"               # [P] guard
done
proven    $QA/py callees keep.py:keep_nested    "fn close model.py:10"            # [P] guard: an in-tree class qualifier `Outer.Inner`
proven    $QA/py callees keep.py:keep_same_file "fn close keep.py:39"             # [P] guard: a same-file class
proven    $QA/py callees keep.py:keep_nested_same_file "fn close keep.py:48"      # [P] guard (fix round 1, mutant MA): a same-file `Wrap.Part`, no import
# TS — model.ts: Session.close :1, Other.close :2; store.ts: Store.close :1, Box.close :2; keep.ts: Local.Thing.close :14.
for f in useParam usePlain useOptional useDefault useNamed useRequire useGlobal useDeclared useLocal; do
    notproven $QA/ts callees "app.ts:$f" "close model.ts:1"                       # [N] (useDeclared / useLocal: guards, name-only before)
done
notproven $QA/ts callees app.ts:run "close model.ts:1"                     # [N] a field `s: ext.Session`
notproven $QA/ts callees app.ts:useDup "close store.ts:1"                  # [N] (fix round 1, mutant MD): `dup` bound in-tree AND foreign
for f in keepNs keepBare keepDefault; do
    proven    $QA/ts callees "keep.ts:$f" "method close store.ts:1"               # [P] guard: `import * as store`, `import { Store }`, a default import
done
proven    $QA/ts callees keep.ts:keepGeneric  "method close store.ts:2"           # [P] guard: `store.Box<number>`
proven    $QA/ts callees keep.ts:keepLocalNs  "method close keep.ts:14"           # [P] guard: a file-local namespace `Local.Thing`
proven    $QA/ts callees keep.ts:run "method close store.ts:1"         # [P] guard: a field `s: store.Store`
# Python in-place rebinding — aug.py: Num.bump :4 (`__iadd__` returns 7), Acc.bump :11 (`__iadd__` returns self), Headers.bump :19
# (`__ior__` raises or returns self), Plain.bump :23 (no in-place method), Sub(Acc) inherits Acc's, Spare.bump :31.
notproven $QA/py callees aug.py:aug_notself  "bump aug.py:4"                      # [N] `x += 1` where __iadd__ returns 7
notproven $QA/py callees aug.py:aug_nodunder "bump aug.py:23"                     # [N] no __iadd__: `x = x + 1`
notproven $QA/py callees aug.py:aug_other_op "bump aug.py:11"                     # [N] `x |= 1`: Acc defines __iadd__ only
proven    $QA/py callees aug.py:aug_self      "fn bump aug.py:11"                 # [P] guard: __iadd__ returns self
proven    $QA/py callees aug.py:aug_ior_self  "fn bump aug.py:19"                 # [P] guard: the MutableHeaders shape `h |= {…}`
proven    $QA/py callees aug.py:aug_inherited "fn bump aug.py:11"                 # [P] guard: Sub inherits Acc.__iadd__
proven    $QA/py callees aug.py:aug_none      "fn bump aug.py:11"                 # guard: no augmented assignment
proven    $QA/py callees aug.py:aug_binary_annotated "fn bump aug.py:91"          # [P] guard: no __iadd__, but `__add__( … ) -> Tint` (textual Color)
notproven $QA/py callees aug.py:aug_binary_base_annotated "bump aug.py:95"        # [N] Shade inherits `__add__ -> Tint`: x becomes a Tint
notproven $QA/py callees aug.py:aug_fallthrough "bump aug.py:114"                # [N] (fix round 1) `if o: return self`, then an implicit None
proven    $QA/py callees aug.py:aug_both_branches "fn bump aug.py:123"            # [P] guard: if / else, both return self
notproven $QA/js callees aug.js:augJs  "bump aug.js:1"                            # [N] JS `x += 1` leaves a primitive
proven    $QA/js callees aug.js:augNone "method bump aug.js:1"                    # guard

echo "=== (C) conservation: no call silently disappears ==="
ROOTS="js ts py go java kt cs cpp swift rb qualannot/py qualannot/ts qualannot/js callresult/go callresult/rust callresult/cpp callresult/java callresult/kt callresult/ts callresult/cpp2 callresult/java2 callresult/java3 callresult/kt2 callresult/rust2 callresult/ts2 callresult/kt3 callresult/rust3 callresult/cpp3 callresult/java4 callresult/kt4 callresult/java5 callresult/kt5 callresult/cpp4 callresult/rust4 callresult/cpp5 callresult/rust5 callresult/rust6 callresult/mx_rust callresult/mx_cpp callresult/mx_java callresult/mx_kt callresult/mx_ts callresult/mx_go rsrecv"
for r in $ROOTS; do
    rf="$( printf '%s' "$r" | tr '/' '_' )"   # a nested root (callresult/go) writes a flat file name
    if ! rw "$r" --pin-census="$TMP/$rf.tsv" >"$TMP/$rf.map.xml"; then no "(C) ($r) the census run exited non-zero"; continue; fi
    DL="$( grep -m1 '^# dispositions ' "$TMP/$rf.tsv" 2>/dev/null )"
    if [ -z "$DL" ]; then no "(C) ($r) the census carries no '# dispositions' line"; continue; fi
    if python3 - "$DL" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[ 1 ] ) )
if "calls" not in kv or "unaccounted" not in kv or kv[ "calls" ] < 1:
    sys.exit( 1 )
total = kv.pop( "calls" )
sys.exit( 0 if kv[ "unaccounted" ] == 0 and sum( kv.values() ) == total else 1 )
PY
    then ok "(C) ($r) dispositions sum to calls= with unaccounted=0"
    else no "(C) ($r) conservation broken: $DL"; fi
done

echo "=== (Qs) the exact Owner-qualified spelling of the unhedged callee rows (QUALNAME-1; the arms above key by bare name) ==="
# exactnames ROOT VERB SEL "kind QualName path;..." - the unhedged rows are exactly these, spelled exactly (a bare name FAILs here)
exactnames(){
    local r="$1" v="$2" s="$3" want="$4" got
    getrows "$r" "$v" "$s" || return
    got="$( printf '%s\n' "$GOT" | awk 'NF >= 5 && $5 != "name" { print $1 " " $2 " " $3 }' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    want="$( printf '%s' "$want" | tr ';' '\n' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    if [ "$got" = "$want" ]; then ok "(Qs) ($r) --$v=$s spells its unhedged rows exactly [$want]"
    else no "(Qs) ($r) --$v=$s unhedged rows spelled [${got:-none}], want exactly [$want]"; fi
}
exactnames py    callees src/tui/uses.py:clone     "fn Styles.copy src/tui/css/styles.py"
exactnames go    callees src/result.go:fromValue   "method Chars.Get src/util/chars.go"
exactnames kt    callees src/app/Pump.kt:param     "fn Tank.spill src/app/Pump.kt"
exactnames cpp   callees src/logger.cpp:close      "method Base::flush src/logger.cpp;method Logger::reset src/logger.cpp"
exactnames rb    callees lib/app/logger.rb:line    "method Helpers#stamp lib/app/helpers.rb"
exactnames rsrecv callees src/app.rs:typed_param   "method Book::spin src/model.rs"

echo "=== (K) the predicates can fail ==="
kread(){ P rows "$1" && GOT="$PARSED"; }
printf '<callees of="x" defs="1"><s t="method" n="Application#onerror" p="lib/application.js:12"/></callees>' >"$TMP/kq.xml"; kread "$TMP/kq.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ] && [ -z "$( specmatch "other lib/application.js" )" ]; then ok "(K) an unhedged planted Owner#name row reads as PROVEN under the bare spelling (notproven would fail it), and only that name"
else no "(K) the reader missed an unhedged planted qualified row: [$GOT]"; fi
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12"/></callees>' >"$TMP/k1.xml"; kread "$TMP/k1.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then ok "(K) an unhedged planted row reads as PROVEN (notproven would fail it)"
else no "(K) the reader missed an unhedged planted row: [$GOT]"; fi
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12" via="name"/></callees>' >"$TMP/k2.xml"; kread "$TMP/k2.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 == "name"' )" ] && [ -z "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then
    ok "(K) a hedged planted row reads as marked (notproven passes it, proven fails it)"
else no "(K) the reader did not read via=\"name\": [$GOT]"; fi
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12" via="import"/></callees>' >"$TMP/k3.xml"; kread "$TMP/k3.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then ok "(K) via=\"import\" is not the hedge"
else no "(K) the reader took via=\"import\" for the hedge: [$GOT]"; fi
printf 'nothing here' >"$TMP/k4.xml"
if P rows "$TMP/k4.xml" && [ "$PARSED" = "NOROOT" ]; then ok "(K) an answer with no root element is NOROOT"
else no "(K) a rootless document read as an answer"; fi
printf '<callers of="x" found="0"/>' >"$TMP/k5.xml"
if P rows "$TMP/k5.xml" && [ "$PARSED" = "NOROOT" ]; then ok "(K) an answer about no symbol (no defs=) is NOROOT"
else no "(K) a not-found answer read as an empty answer"; fi
printf '<ctx><b n="other"><calls total="1"><c n="send" l="7">sig</c></calls></b></ctx>' >"$TMP/k6.xml"
if P ecalls "$TMP/k6.xml" respondWith && [ "$PARSED" = "NOROOT" ]; then ok "(K) a --for answer without the named body is NOROOT, never an empty pass"
else no "(K) ecalls read another body's <calls> as respondWith's"; fi
printf '<ctx><b n="respondWith"><calls total="1"><c n="send" l="7" via="name">sig</c></calls></b></ctx>' >"$TMP/k7.xml"
if P ecalls "$TMP/k7.xml" respondWith && [ "$PARSED" = "send 7 name" ]; then ok "(K) ecalls reads a marked <c> row"
else no "(K) ecalls missed a marked <c> row: [$PARSED]"; fi
printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"calls\":[{\"name\":\"send\",\"file\":\"lib/reply.js\",\"line\":7,\"via\":\"name\"},{\"name\":\"code\",\"file\":\"lib/reply.js\",\"line\":12}]}"}]}}' >"$TMP/k8.json"
if P mcp "$TMP/k8.json" calls && [ "$( printf '%s' "$PARSED" | tr '\n' ';' )" = "send lib/reply.js 7 name;code lib/reply.js 12 -" ]; then ok "(K) the MCP reader reads the hedge bit per entry"
else no "(K) the MCP reader misread: [$( printf '%s' "$PARSED" | tr '\n' ';' )]"; fi
if P mcp "$TMP/k8.json" calledBy && [ "$PARSED" = "NOROOT" ]; then ok "(K) an MCP answer without the field is NOROOT"
else no "(K) the MCP reader invented a missing field"; fi
printf '1' >"$TMP/k9.rc"
if ( ran_ok k "$TMP/k9" ) >/dev/null; then no "(K) ran_ok accepted a run that exited 1"
else ok "(K) ran_ok fails a run that exited non-zero"; fi
rm -f "$TMP/k10.rc"
if ( ran_ok k "$TMP/k10" ) >/dev/null; then no "(K) ran_ok accepted a run with no recorded exit status"
else ok "(K) ran_ok fails a run with no recorded exit status"; fi
if ( parity k "a#-" "a#name" ) | grep -q FAIL; then ok "(K) parity fails when the hedge bit differs"
else no "(K) parity accepted differing hedge bits"; fi
if ( parity k "" "" ) | grep -q FAIL; then ok "(K) parity fails on two empty sides (never a vacuous pass)"
else no "(K) parity accepted two empty sides"; fi
if ( parity k "RUNFAIL --callees=x rc=1" "RUNFAIL --callees=x rc=1" ) | grep -q FAIL; then ok "(K) parity fails when a run exited non-zero"
else no "(K) parity accepted a failed run"; fi
# change 1: a reader crash or malformed defs= FAILs the arm; it never reads as "no rows" (the old fall-through)
printf '<callees of="x" defs="x"><s t="method" n="onerror" p="lib/application.js:12"/></callees>' >"$TMP/k11.xml"
if python3 "$TMP/parse.py" rows "$TMP/k11.xml" >/dev/null 2>&1; then no "(K) the reader accepted a non-numeric defs="
else ok "(K) the reader exits non-zero on a non-numeric defs="; fi
if ( rowsof k "$TMP/k11.xml" ) | grep -q FAIL; then ok "(K) a reader failure FAILs the arm (never an empty pass)"
else no "(K) a reader failure fell through to PASS"; fi
if ( fail=0; rowsof k "$TMP/k11.xml" >/dev/null; [ "$fail" -eq 1 ] ); then ok "(K) a reader failure sets the gate's failure flag"
else no "(K) a reader failure left the failure flag clear"; fi
printf '<ctx><hops><h n="encode"><calls total="1"><c n="append" l="3" via="name"/></calls></h><h n="respond"><calls total="1"><c n="onerror" l="12"/></calls></h></hops></ctx>' >"$TMP/k12.xml"
if P hcalls "$TMP/k12.xml" encode && [ "$PARSED" = "append 3 name" ] && P hcalls "$TMP/k12.xml" respond && [ "$PARSED" = "onerror 12 -" ]; then
    ok "(K) a hop reader reads only its own hop's <calls>"
else no "(K) the hop reader crossed hops: [$PARSED]"; fi
if P hcalls "$TMP/k12.xml" pipePayload && [ "$PARSED" = "NOROOT" ]; then ok "(K) a hop that is not shown is NOROOT, never an empty pass"
else no "(K) the hop reader invented a hop: [$PARSED]"; fi
printf '<ctx><calls total="1"><c n="get" l="4,8"/></calls></ctx>' >"$TMP/k13.xml"
if P ecalls "$TMP/k13.xml" && [ "$( printf '%s' "$PARSED" | tr '\n' ';' )" = "get 4 -;get 8 -" ]; then ok "(K) a joined <c l=\"4,8\"> row reads as one row per line"
else no "(K) a joined <c> row misread: [$PARSED]"; fi
printf '<impact of="x" defs="1"><!-- via="name": a row matched by name alone. It does NOT mean the edge is false. --></impact>' >"$TMP/k14.xml"
printf '<impact of="x" defs="1"><!-- via="import" by name alone; it does NOT mean much. via="name" is a hedge. --></impact>' >"$TMP/k15.xml"
if P legend "$TMP/k14.xml" && [ "$PARSED" = "DEFINED" ] && P legend "$TMP/k15.xml" && [ "$PARSED" = "UNDEFINED" ]; then
    ok "(K) the legend reader needs the mechanism and the NOT sentence AFTER via=\"name\""
else no "(K) the legend reader misread a planted legend"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; exit 1; fi
