#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_cache.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_cache.h — the raw-facts model + incremental cache, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: RawDef (the pre-id-assignment definition record), the extraction identity
// (kCacheVersion + kParserVer + parserVerFor), content/blob hashing, FileFacts, the ByteW/ByteR
// codecs with every def/ref/bind/ffi/route record writer/reader and their record-minima tripwire,
// and loadCache/saveCache themselves. The one place the on-disk cache blob's shape is spelled out.
// Same contract as every ingest_*.h: reopens `namespace rw` and the unnamed namespace inside it —
// one TU, one unnamed namespace, internal linkage unchanged, zero new API surface — under the
// RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// ---- a raw definition pulled from one query match (pre-id-assignment) ----
struct RawDef
{
    std::uint32_t fileId    = 0;
    std::uint32_t line      = 0;   // 1-based
    std::uint32_t startByte = 0;   // span start of the @definition node
    std::uint32_t endByte   = 0;   // span end   of the @definition node
    std::uint32_t nameByte  = 0;   // start byte of the @name identifier (dedup identity)
    std::uint32_t bodyByte  = 0;   // start of the def's "body" field = signature end (0 ⇒ none → endByte)
    std::uint32_t cx        = 0;   // cyclomatic complexity (1 + decision points); functions/methods only
    std::uint32_t ccx       = 0;   // cognitive complexity (nesting-weighted); functions/methods only
    std::uint32_t loc       = 0;   // Q4: physical line span of the def (end line − start line + 1)
    std::uint32_t locals    = 0;   // Phase 1 (local-variable-indexing, PLAN.md 2026-08-06 evening): local-decl
                                   // count from cc_walk; C/C++ only (see model.h localsCountedLang), 0 elsewhere
    std::uint16_t ppAlt     = 0;   // preproc alternative branches (#else/#elif) inside the def (see model.h Symbol::ppAlt)
    std::uint16_t humps     = 0;   // nesting profile: regions reaching quality::kNestBar (see model.h Symbol::humps)
    std::uint16_t deepLoc   = 0;   // nesting profile: lines inside them, a FLOOR (see model.h Symbol::deepLoc)
    std::uint16_t ev        = 0;   // essential complexity, a FLOOR (see model.h Symbol::ev); 0 outside evCountedLang
    std::array<std::uint8_t, kEvWhyTagCount> evWhy{};   // per-tag contributing-jump counts (model.h kEvWhyTagTable)
    std::uint16_t params    = 0;   // Q4: parameter count (from the def's parameter-list child); fns/methods
    std::uint8_t  maxNest   = 0;   // Q4: max control-structure nesting depth inside the def (from cc_walk)
    std::uint8_t  arityExact = 0;  // B2.2: 1 ⇒ params is a fixed call-comparable arity (no variadic/default, not implicit-self)
    std::uint8_t  testScope = 0;   // L8: 1 ⇒ an IN-FILE test convention encloses this def (see inFileTestScope)
    SymKind       kind      = SymKind::Other;
    Lang          lang      = Lang::Unknown;
    std::string   name;
    std::string   scope;               // enclosing class/namespace name (C++), for canonical scope::name
    RawDefLex     lex;                 // B0.2: doc+body weighted subtoken stats (rich ingests only; rides the
                                       //   cache record so a warm --for never re-reads/re-tokenizes the file)
};

struct RawRef
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // span start of the @reference node (for enclosing lookup)
    std::uint32_t line      = 0;   // 1-based line of the use site (ABS-3: --uses p="file:line")
    Lang          lang      = Lang::Unknown;
    bool          isInherit = false;   // true ⇒ base-class/implements edge (derived → base), not a call
    bool          isDocLink = false;   // true ⇒ doc→code mention (markdown `backtick` identifier), not a call
    bool          isCompose = false;   // true ⇒ HAS-A member-variable type edge (S5-E); stays OUT of call graph
    RefRole       role      = RefRole::Call;    // ABS-3 use-site role (call/read/write/import/extends); see RefRole
    RecvKind      recv      = RecvKind::None;   // call-site receiver shape (P2-D narrowing)
    std::uint16_t argCount     = 0;             // B2.2: call-site positional arg count when countable; 0 otherwise
    bool          argCountKnown = false;        // B2.2: true ⇒ argCount is reliable (no spread/splat/apply)
    std::string   name;
    std::string   qualifier;           // explicit scope at a call site (`A` in `A::b()`); C++; "" if bare/method
    std::string   recvVar;             // receiver variable when recv==NamedVar/FieldOfVar (`x` in `x->m()`); Rule 2 fuel
    std::string   fieldName;           // member variable name when isCompose (e.g. "m_pool"); ALSO the intermediate
                                       //   field of a depth-2 chained receiver (recv FieldOfThis/FieldOfVar); "" otherwise
    std::string   composeRel;          // "creates" (value/inline) or "uses" (reference/pointer) when isCompose; "" otherwise
};

// P2-D Rule 2 raw local-variable type binding (pre-attribution). startByte sits inside the enclosing
// function body so the enclosing-def attribution (the same byte-span scan as RawRef) assigns the binding's
// scope. `var : typeName` — e.g. `Foo x;` → { "x", "Foo" }. typeName is the written type's final segment.
struct RawBind
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // position inside the enclosing function (for enclosing-def attribution)
    Lang          lang      = Lang::Unknown;
    LocalBindKind kind      = LocalBindKind::Type;   // Type = Rule 2 var→type; FnDecl/FnAssign = L3 var→function
    std::uint32_t spanStart = 0;   // kind==VarDecl only: the declaring BLOCK's byte span (shadow scope);
    std::uint32_t spanEnd   = 0;   //   {0,0} on every other kind — see model.h Binding
    std::string   var;             // the declared variable identifier (`x`)
    std::string   typeName;        // kind==Type: the written type's final segment (`Foo`);
                                   // kind==FnDecl/FnAssign: the bound function name (or an L3 sentinel)
};

// B6.3 raw client-side HTTP-route USE (pre-attribution). startByte sits at the call-expression's own
// start so the enclosing-def byte-span scan (same DefSweep as RawRef/RawBind) assigns fromSymbol. The
// server-side RouteDef needs no such raw/final split (its handler is resolved by NAME, see graph.h), so
// it rides model.h's own RouteDef struct straight through the cache — same posture as BindingAlias.
struct RawRouteUse
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // call-expression start (for enclosing-def attribution)
    std::uint32_t line      = 0;   // 1-based
    HttpMethod    method    = HttpMethod::Unknown;
    std::string   path;
};

// ---- incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY
//      changed files. A parserVer bump invalidates the whole cache on any extraction change.
//      Node ids are NOT cached — they're reassigned each run by the existing deterministic sort,
//      so the cache stores fileId-free facts and re-stamps fileId on load (R3 id-positionality). --
constexpr std::uint32_t kCacheMagic   = 0x4b505443;   // "CTPK"
// 2: whole-blob FNV checksum trailer (corrupt-cache detection).
// 3 (T5): the file-path KEY stored per record switched from the verbatim absolute/as-typed ingest
//   path (`<root-arg>/<rel>`, root-spelling-dependent) to a ROOT-RELATIVE key via relForHash — the
//   same lexical root-prefix strip S2 uses for the baseline sidecars. This makes the cache PORTABLE
//   (committable): a cache built at one root spelling/absolute path is re-absolutized against the
//   CURRENT invocation's root on load, so `repo.ripwirecache` built in CI or by a teammate at a
//   different checkout path still warm-hits. Old (v2) caches store the pre-T5 key shape; bumping
//   this field makes loadCache's version guard reject them outright (magic/version/parserVer must
//   all match) rather than silently re-absolutizing a key that was never root-relative to begin
//   with — a v2 cache simply misses on every lookup that survives the guard, which is exactly the
//   self-healing full-reparse path already used for any other corrupt/stale cache.
constexpr std::uint32_t kCacheVersion = 14;           // 14 (card A3 follow-up): each FILE record gains ctimeNs,
                                                      //    a THIRD stat-gate discriminator written right after
                                                      //    mtimeNs. (size, mtime) alone let a byte-length-
                                                      //    preserving edit with a restored mtime be trusted and
                                                      //    served STALE — reproduced on argv in docs/EVALS.md and
                                                      //    gated by statgatecheck (b2) / freshnesscheck arms 6-7.
                                                      //    st_ctime moves on any write AND on the utimes() that
                                                      //    performs the restore, and POSIX gives an unprivileged
                                                      //    process no way to set it back; ::stat already returns
                                                      //    it, so the fix costs no syscall and no file read. A
                                                      //    FORMAT change → reject v13 blobs (self-healing full
                                                      //    reparse writes the field on the next run).
                                                      // 13 (§L1 parse health): each FILE record gains the
                                                      //    four FileHealth u32s (errNodes, errBytes, fileBytes,
                                                      //    wsBytes) right after the stat-gate pair. The auto-cache
                                                      //    is the DEFAULT path, so a health measurement that did
                                                      //    not round-trip it would evaporate on the second run and
                                                      //    report "nothing degraded" on a corpus it had never
                                                      //    re-read — the exact zero-means-none-exists defect the
                                                      //    lane exists to kill. A v12 blob has no such bytes, so
                                                      //    the version guard rejects it (self-healing full reparse
                                                      //    repopulates health).
                                                      // 12 (B6.3): FILE records gain two new record arrays —
                                                      //    RouteDef (server-side route registrations) and
                                                      //    RawRouteUse (client-side HTTP calls). A v11 (or older)
                                                      //    blob has neither, so the version guard rejects it
                                                      //    outright (self-healing full reparse repopulates routes).
                                                      // 11 (B2 graph precision): RawDef gains arityExact, RawRef gains
                                                      //    argCount+argCountKnown (call-site arity for B2.2) — a v10
                                                      //    (or older) blob lacks those bytes, so the version guard
                                                      //    rejects it (self-healing full reparse rebuilds with arity).
                                                      // 10 (B0 r2, H3): the rich def records' postings shrink —
                                                      //    each FILE record gains a sorted per-file subtoken
                                                      //    DICTIONARY (u64 hashes) and each def row stores narrow
                                                      //    dict INDICES + narrowest-exact-width tfs instead of raw
                                                      //    u64 hash + u32 tf pairs (the v9 shape grew the rich
                                                      //    blob +38-56% and dragged index/warm p95). Lossless by
                                                      //    construction (widths from maxima, VERIFY'd) — a FORMAT
                                                      //    change → reject v9 blobs (v9 never shipped; local v9
                                                      //    blobs self-heal via the same full-reparse path).
                                                      // 9 (B0.2 postings): each RICH-family def record gains the
                                                      //    persisted doc/body subtoken statistics (dlWeighted +
                                                      //    sorted (hash,tf) pair arrays; lexindex.h) — a FORMAT
                                                      //    change → reject v8 blobs (self-healing full reparse
                                                      //    rebuilds them with stats). Lean records are unchanged
                                                      //    in shape but share the header version, so lean v8
                                                      //    blobs self-heal identically (one version, one guard).
                                                      // 8 (A1 team-index): header gains a kArtifactArch tag byte
                                                      //    (endian + pointer width) after parserVer — a native-endian
                                                      //    blob is only same-arch-consumable, so a foreign-arch blob
                                                      //    must self-heal to a cold parse. A HEADER change → reject
                                                      //    v7 blobs (they lack the byte → the guard mismatches).
                                                      // 7 (A4-R5): each file record gains a BindingAlias (FFI)
                                                      //    stream after binds — a FORMAT change → reject v6 blobs.
                                                      // 6 (A4-P7): header gains a u64 blob-write timestamp; each
                                                      //    file record gains (sizeBytes,mtimeNs) for the warm-run
                                                      //    stat-gate + racy rule — a FORMAT change → reject v5 blobs.
                                                      // 5: non-C import targets now store the CLEAN specifier
                                                      //    (Py `pkg.mod`, TS `./x`, Rust `crate::a::b`/`mod:x`) —
                                                      //    a target FORMAT change → old caches must be rejected.
                                                      // 4: Include gained a `bool isAngle` (quote/angle) field
constexpr std::uint32_t kParserVer    = 77;           // bump on any grammar/.scm/extraction change
                                                      // 77 = 2026-09-03 (Phase 5, docs/EVALS.md): two Python
                                                      //    ingest FACTS — (a) a `super()` call receiver classifies
                                                      //    RecvKind::SuperObj (appended) instead of None, so
                                                      //    `super().m()` stops reading as a BARE call; (b) every
                                                      //    import statement records the NAMES it binds as file-
                                                      //    scope LocalBindKind::Import RawBinds (appended kind),
                                                      //    `np`→`numpy`, the fuel of the external-name veto.
                                                      //    Record shapes unchanged, kCacheVersion stays; Python
                                                      //    ref and bind FACTS changed → parserVer moves.
                                                      // 75 = 2026-09-02 (member-variable round, card A3): a new
                                                      //    SymKind::Field — C/C++ @definition.field (non-static
                                                      //    field_declaration) and Python (`self.x = …` / annotated
                                                      //    class attribute, the latter re-kinded from Var) — plus
                                                      //    the value-use visitor now captures the FIELD half of a
                                                      //    non-call member access (`a.f`/`p->f`/`o.f`) as a
                                                      //    Read/Write ref carrying its receiver shape (recv/
                                                      //    recvVar/fieldName, fields the record already had).
                                                      //    Record shape unchanged, kCacheVersion stays; the def
                                                      //    and ref FACTS changed for every C-family and Python
                                                      //    file → parserVer moves.
                                                      // 74 = 2026-08-30 (objc-sniff lane): looksObjC masks
                                                      //    comments and string/char literals before testing for
                                                      //    @interface/@protocol/@implementation — a C++ .h whose
                                                      //    doc comments MENTION those tokens (ingest_model.h's own
                                                      //    collapseObjCDeclDefs contract) was rerouted wholesale to
                                                      //    the objc grammar and its C++ symbols (struct DefSweep +
                                                      //    DefSweep::find, anon namespace) shredded at extraction.
                                                      //    Language ROUTING changed for such headers → cached facts
                                                      //    extracted under the wrong grammar must be rejected.
                                                      // 73 = 2026-08-25 (candhead-ugrep lane): C++ out-of-line
                                                      //    NESTED CLASS/STRUCT definitions (`class Outer::Inner :
                                                      //    Base { … };`) — queries/cpp/tags.scm gains a
                                                      //    qualified_identifier name: pattern for class_specifier/
                                                      //    struct_specifier, mirroring the out-of-line METHOD
                                                      //    pattern already there. Previously dropped at extraction
                                                      //    with no symbol minted at all (N11/N12).
                                                      // 72 = 2026-08-24 (fnbody-require lane): CommonJS `require("./x")` /
                                                      //    dynamic `import("./x")` captured INSIDE a function body — kJsImportContainers
                                                      //    grows past the 71 top-level-only set (statement_block, return_statement,
                                                      //    the six function-body node kinds, control-flow clauses, and the
                                                      //    object/pair/arguments/call_expression/parenthesized_expression chain
                                                      //    needed to reach a `get X() { return require(…); }` getter sitting
                                                      //    inside an object literal passed as a call argument — webpack's
                                                      //    lib/index.js lazy-getter barrel, read off a real parse). Same three
                                                      //    guards as top-level (bare require/import callee, one arg, string
                                                      //    literal) — SAME jsModuleLoadTarget, called from a deeper set of
                                                      //    containers. Include gains `bool isLazy` (a FORMAT change → reject v71
                                                      //    blobs): true when the call sits inside a function-body container,
                                                      //    disclosed on --impact's import tier as `lazy=` (graph.h::impactImportTier,
                                                      //    graphlegend.h::kImpactImportTierLegend) — a lazy require is a real
                                                      //    dependency (the importer tier must still name the file) but a WEAKER
                                                      //    one: it only fires if and when the function runs. See
                                                      //    test/impactimportcheck.sh's lazy fixture arm and
                                                      //    test/nestedimportfix/scope_control.ts.
                                                      // 70 = 2026-08-22 test-macro blocks (LB-E, r10 harvest): a known
                                                      //    doctest/Catch2 block-forming test macro (kTestBlockMacroNames)
                                                      //    invoked as `TEST_CASE( "title" ) { … }` — which tree-sitter-cpp
                                                      //    parses as an expression_statement with a MISSING ";" plus a
                                                      //    SIBLING compound_statement, so pre-70 it minted NO symbol and
                                                      //    every call inside the body attributed to NOTHING (measured:
                                                      //    five pageRankDouble sites invisible to --callers on this
                                                      //    repo's own test/verify_pagerank.cpp) — now extracts as a
                                                      //    t="fn" symbol named by its title literal, spanning through
                                                      //    the block, testScope=1. queries/cpp/tags.scm gains the
                                                      //    sibling pattern (@definition.testmacroblock). The extracted
                                                      //    SET grows on any C++ tree using those harnesses, so a v69
                                                      //    blob misses rows and must be rejected, not served. See
                                                      //    test/testmacrocheck.sh.
                                                      // 69 (2026-08-21 wave-2 merge): TWO INDEPENDENT extraction changes
                                                      //    both landed on 68 in separate branches. Per the note at 65 below,
                                                      //    a collision is resolved by RE-BUMPING to the next free number, never
                                                      //    by keeping one side's value: no released binary ever wrote a 68 blob,
                                                      //    and a v67 blob is missing BOTH sets of rows, so one reject covers both.
                                                      //    (a) PHP + Lua language port (phpcheck.sh / luacheck.sh):
                                                      //    TWO new grammars (tree-sitter-php v0.24.2's `php/`
                                                      //    sub-grammar, tree-sitter-grammars/tree-sitter-lua
                                                      //    v0.5.0) and TWO new .scm files, so the extracted SET
                                                      //    changes on any tree holding a .php/.phtml/.lua file
                                                      //    that previously fell out as unsupported-ext. ONE bump
                                                      //    for both is deliberate: they land in the same commit,
                                                      //    so no released version ever keyed a cache on one
                                                      //    without the other. Three shared-path edits ride along
                                                      //    and each is LANG-GATED so every existing corpus stays
                                                      //    byte-identical: isDecisionType/cc_isNestingControl take
                                                      //    a Lang and exclude Lua's `do … end` (a bare scope
                                                      //    block, not a loop — counting it would be a WRONG
                                                      //    number, not a floor) while admitting Lua
                                                      //    repeat/elseif and PHP `match` arms; the &&/||
                                                      //    accumulator learns the word forms `and`/`or`/`xor`
                                                      //    behind a Php||Lua gate; captureBases learns PHP's
                                                      //    base_clause/class_interface_clause and captureIncludes
                                                      //    its namespace_use_declaration. Known, disclosed cost:
                                                      //    one cold re-parse everywhere.
                                                      //    (b) receiver-guard misfires (chainguardcheck.sh):
                                                      //    receiverOf classified EVERY chained receiver as
                                                      //    RecvKind::None, so five guard sites keyed on
                                                      //    `recv == None` misread `this->m_pool.run()` as a
                                                      //    BARE name: Rule 1's bareCish arm wrong-narrowed it
                                                      //    to the caller's OWN class, and shadow suppression
                                                      //    deleted it under a same-named local. RecvKind gains
                                                      //    FieldOfThis / FieldOfVar (u8, 5 of 256 used) and the
                                                      //    INTERMEDIATE field name rides RawRef::fieldName,
                                                      //    which is free on a call ref (isCompose owns it
                                                      //    otherwise). The wire FORMAT is unchanged —
                                                      //    writeRef/readRef already carry recv and fieldName —
                                                      //    but the extracted VALUES change and DO move edges= /
                                                      //    ambiguous= (recovered + split-widened calls). NO
                                                      //    resolve rule consumes the new kinds yet. A v67 blob
                                                      //    holds None where this binary expects a chain and
                                                      //    must be rejected rather than served. quality.h
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      //    Registered + measured: docs/EVALS.md §4.
                                                      // 67 (2026-08-20 RefRole::Type use-sites, typerefcheck.sh):
                                                      //    usesVisitNode's accept set was the single test
                                                      //    `strcmp( t, "identifier" ) != 0 → return`, so a
                                                      //    `type_identifier` node — a bare TYPE mention in a
                                                      //    signature, a declaration or a template argument —
                                                      //    was captured by NOTHING. It now emits a RawRef with
                                                      //    the new RefRole::Type (model.h), which joins
                                                      //    Read/Write/Import/Extends on the NEVER-in-the-CSR
                                                      //    list, so the default ranked map, PageRank, edges=
                                                      //    and ambiguous= are unchanged BY CONSTRUCTION — the
                                                      //    value-uses pass is also RICH-family only, so the
                                                      //    lean blob that backs the default map holds no such
                                                      //    ref at all. What changes is the extracted SET of
                                                      //    references, which the RICH per-file cache record
                                                      //    persists (writeRef/readRef already carry `role`, so
                                                      //    the wire FORMAT is unchanged — a v66 rich blob would
                                                      //    simply be missing every type row and must be
                                                      //    rejected rather than served). quality.h
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      //    Registered + measured: docs/EVALS.md §4.
                                                      // 66 (2026-08-19 subtoken acronym shredding, subtokencheck.sh):
                                                      //    the shared subtoken state machine (lexindex.h
                                                      //    forEachLexSubtoken/forEachLexSubtokenHashed) stopped
                                                      //    cutting a token at EVERY interior uppercase byte, which
                                                      //    had reduced an all-caps run to 1-byte fragments that the
                                                      //    ≥2-byte rule then dropped — an acronym was indexed as
                                                      //    nothing at all. A run is now one token, split only at the
                                                      //    last upper before a lowercase ("HTTPServer" → http|server).
                                                      //    lexSubtokenHash also lowercases EVERY byte now, not just
                                                      //    the first. Both feed the PERSISTED rich-cache record —
                                                      //    RawDefLex's dlWeighted/tokenHashes/tokenTfs and the
                                                      //    per-file 512-bit H3 signature derived from them — so v65
                                                      //    blobs hold token statistics this binary would never
                                                      //    produce and must be rejected. quality.h
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      //    Registered + measured: docs/EVALS.md §4.
                                                      // 65 (2026-08-15 C++ nested out-of-line defs, cppqualcheck.sh §11):
                                                      //    queries/cpp/tags.scm gains a second out-of-line
                                                      //    definition pattern (`qualified_identifier name:
                                                      //    (qualified_identifier)`), so a C++ definition written
                                                      //    with TWO OR MORE qualifier segments
                                                      //    (`void nsD::OuterD::InnerD::deep3(){}`) is indexed at
                                                      //    last — it was dropped at extraction, silently, at every
                                                      //    depth past one. The extracted SET grows on any C++ tree
                                                      //    using that spelling (memgraph: 575 defs), so v64 blobs
                                                      //    must be rejected. quality.h kIngestParserVerMirror
                                                      //    bumped in the SAME commit. NOTE for whoever lands the
                                                      //    unmerged integration/lang-round, which also holds a
                                                      //    kParserVer bump: resolve a collision by RE-BUMPING to
                                                      //    the next free number, never by keeping one side's value.
                                                      // 64 (2026-08-14 in-file test scope, test/testscopecheck.sh):
                                                      //    every def carries a new syntactic `testScope` bit
                                                      //    (Rust `#[cfg(test)] mod` / `#[test] fn`, Python
                                                      //    `class Test*` / module-level `def test_*`, JS/TS
                                                      //    `describe(`/`it(`/`test(` blocks, C# `[Fact]`/`[Test]`/
                                                      //    `[TestMethod]`), written into the cache record — so a
                                                      //    v63 blob has no such field and must be rejected.
                                                      //    quality.h kIngestParserVerMirror bumped in the SAME commit.
                                                      // 63 (2026-08-12 markdown section tier, test/mdsectioncheck.sh):
                                                      //    .md/.markdown now parse with the vendored tree-sitter-markdown
                                                      //    block grammar — headings (ATX + setext) become sections with
                                                      //    REAL SPANS (heading → next same-or-higher heading), parent-
                                                      //    heading scopes, and link/mention edges; html-block phantom
                                                      //    headings vanish; .markdown joins the table. The extracted SET
                                                      //    and the spans both change on any md-bearing tree, so v62
                                                      //    blobs must be rejected.
                                                      // 62 (2026-08-12 module-constant round, test/moduleconstcheck.sh):
                                                      //    C/C++ const-qualified module constants index CASE-BLIND —
                                                      //    a const/constexpr/constinit type_qualifier on an INITIALIZED
                                                      //    module-scope declaration keeps the binding regardless of
                                                      //    name case (declarationCarriesConstQualifier; previously the
                                                      //    r3 q10 SCREAMING-only gate dropped every k-camel constant,
                                                      //    which made this repo's own kParserVer unfindable by its own
                                                      //    --for/--uses — the 2026-08-12 census's 21.4% constant-shaped
                                                      //    lookup family). queries/cpp/tags.scm also gains the
                                                      //    class-static field_declaration capture (static + const
                                                      //    qualifier + in-class initializer, fieldConstantCaptureKept —
                                                      //    NO class-static constant was indexed before, even SCREAMING).
                                                      //    The extracted SET grows on any C/C++-bearing tree (this repo:
                                                      //    src/ +~350 rows), so v61 blobs miss rows -> reject.
                                                      //    Deferred with probe evidence (2026-08-12): enumerators
                                                      //    (corpus blow-up: >=5000 capture-cap hits on a 2 377-file private ObjC++/C++ validation tree),
                                                      //    TS/JS non-SCREAMING top-level consts (r3 q10 pinned policy,
                                                      //    constcheck arm 3), variable templates, `T* const` pointer
                                                      //    constants, out-of-line static-member definitions.
                                                      // 61 (2026-08-11 YAML config-key tier): .yml/.yaml indexed for
                                                      //    the first time — mapping keys at mdepth<=2 (sequences
                                                      //    transparent) become t="sec" symbols via queries/yaml/
                                                      //    tags.scm + the definition.yamlkey gate. A v60 blob on a
                                                      //    YAML-bearing tree is missing every such row -> reject.
                                                      //    Known, disclosed cost: one cold re-parse everywhere.
                                                      // 60 (2026-08-10 language-port round): one shared bump covering
                                                      //    THREE hand-ported language rounds, each stranded on a branch
                                                      //    this tree never had. Listed separately because each changes
                                                      //    the extracted SET on a different corpus.
                                                      //    (a) PYTHON shapes: annotated class attributes, gated
                                                      //        enum-family members, class lambda attrs, one-guard-deep
                                                      //        + tuple-unpack module bindings, and .pyi routing.
                                                      //        RE-MEASURED at v59 on django@c334c1a8ff /
                                                      //        pydantic@8898b8f: every one of those shapes read 0.0%
                                                      //        EXCLUSIVE recall. A v59 blob on a Python-bearing tree
                                                      //        is missing those rows -> reject.
                                                      //    (b) SWIFT shapes (hand port of stranded bb78f97, which
                                                      //        originally landed at kParserVer 41): enum_entry /
                                                      //        typealias_declaration / associatedtype_declaration /
                                                      //        protocol_property_declaration / the builtin-operator-
                                                      //        token alternation in function_declaration's name:
                                                      //        field. RE-MEASURED at v59/v60 on Alamofire@0455bfb +
                                                      //        swift-nio@72973283, the 2026-08-04 corpora pinned to
                                                      //        the same SHAs.
                                                      //    (c) TYPESCRIPT #private: tags.scm gains the #private
                                                      //        method / field-arrow / call-ref coverage JS already
                                                      //        had -- a sibling-completeness gap, not a new shape.
                                                      //    Shared finalSegment() gains the leading-'<' carve-out (a
                                                      //    Swift operator name like `<` or `<+>` is not a generic
                                                      //    type-argument list, which the unconditional strip erased
                                                      //    to ""). That touches the shared C++/TS/JS/Python path, so
                                                      //    it changes the extracted SET only for a name legitimately
                                                      //    starting with '<'; every other language's bare-identifier
                                                      //    path is unaffected (tsshapecheck / jsshapecheck /
                                                      //    pyshapecheck / constcheck / langcheck stay green).
                                                      //    The vendored scanner.c UBSan fix that rode the same source
                                                      //    commit was deliberately NOT ported -- see the header of
                                                      //    test/swiftshapecheck.sh for the reason and its trigger.
                                                      //    (d) CUDA memory-space module bindings (cudacheck 7b
                                                      //        close-out): queries/cpp/tags.scm gained the
                                                      //        UNINITIALIZED qualified-declaration patterns and
                                                      //        ingest gained cudaMemorySpaceQualifierOf
                                                      //        (`__constant__` case-blind, `__device__`/
                                                      //        `__managed__` behind the SCREAMING gate). Keyed on
                                                      //        Lang::Cpp, NOT on constCaptureNeedsScreamingGate --
                                                      //        that gate also covers TS/JS/Ruby/Java/C#/C, whose
                                                      //        constants bind through non-C-family nodes and would
                                                      //        read as uninitialized and be dropped wholesale.
                                                      //        Verified zero removed rows over ~250K symbol rows /
                                                      //        ~2 200 C/C++ files; MONAI's 80 adds are an exact
                                                      //        multiset match to its 80 __constant__ source lines.
                                                      //    ONE bump for all four is deliberate: they land together,
                                                      //    so no released version ever keyed a cache on one without
                                                      //    the others. Record shape unchanged, kCacheVersion stays.
                                                      // 59 (TOML config-key tier): +TOML (.toml) — a NEW
                                                      //    grammar and a new .scm, so the extracted SET
                                                      //    changes on any tree holding a .toml. Table
                                                      //    headers and their keys become t="sec" defs; no
                                                      //    references, so edges are unchanged. Key depth is
                                                      //    HEADER-relative, not root-relative — JSON's
                                                      //    "top-level + 2nd-level" cut ported literally
                                                      //    would capture 38.3% of keys and miss every key
                                                      //    under a 2-dotted table. Known, disclosed cost:
                                                      //    one cold re-parse everywhere.
                                                      // 58 (r9 A5 iteration 6): the L3 DECLARATION arm gets
                                                      //    the matching value-INITIALIZATION noise gate — a
                                                      //    bare-identifier initializer mints a fn-pointer
                                                      //    binding only when the declarator spells one, the
                                                      //    written type is a same-file fn-pointer alias, or
                                                      //    the type is UNKNOWN (`auto`, template, decltype).
                                                      //    A CLASS type used to sail through the primitive-
                                                      //    only gate, so `std::string tag = zzz;` minted a
                                                      //    binding that vetoed shadow suppression for the
                                                      //    local's whole scope.
                                                      // 57 (r9 A5 iteration 5): the L3 assignment arm gets
                                                      //    the value-assignment NOISE GATE — a bare-
                                                      //    identifier `x = y;` mints a fn-pointer binding
                                                      //    only when the file's own declarations do not
                                                      //    prove x a value variable (`std::string line;
                                                      //    line = zzz;` no longer vetoes shadow
                                                      //    suppression, nor tombstones a same-named
                                                      //    file-scope binding corpus-wide).
                                                      // 56: three declarator shapes isNonValueContext
                                                      //    could not see stop leaking their DECLARED name
                                                      //    out as a read of the symbol they shadow — a
                                                      //    DEFAULTED parameter (`int key = 0`, parent
                                                      //    optional_parameter_declaration), a pack
                                                      //    (`Ts... key`) and an attributed declarator
                                                      //    (`int key [[maybe_unused]]`).
                                                      // 55 (r9 A5 iteration 4): an ordinary BLOCK
                                                      //    declaration's shadow span starts at its
                                                      //    DECLARATION POINT (end of the complete
                                                      //    declarator, [basic.scope.pdecl]) instead of the
                                                      //    block's brace, so a genuine call written above
                                                      //    the local survives; whole-scope shapes keep
                                                      //    their spans, and isDeclSiteName gains the
                                                      //    `declaration` arm the narrowed span un-masks.
                                                      //    Span VALUES + reference population change →
                                                      //    old caches must be rejected; mirror bumped in
                                                      //    the SAME commit.
                                                      // 54 (r9 A5 iteration 3): shadow spans stop at the
                                                      //    owning CONTROL STATEMENT — a for/if/while/switch
                                                      //    header declaration scopes to that statement's
                                                      //    span, no longer leaking past the loop; range-for
                                                      //    unified to the whole-statement span; catch
                                                      //    parameters captured (handler-block span). Span
                                                      //    VALUES land in cached bind records → extraction
                                                      //    output changes → old caches must be rejected.
                                                      //    quality.h's mirror bumped in the SAME commit.
                                                      // 53 (r9 A5 fix round): shadow suppression tightened
                                                      //    to BLOCK spans (RawBind gains spanStart/spanEnd —
                                                      //    a bind-record FORMAT change, rejected via this
                                                      //    bump) and the capture now sees reference
                                                      //    declarators, structured bindings, lambda params
                                                      //    and capture-list names. quality.h's mirror
                                                      //    bumped in the SAME commit.
                                                      // 52 (r9 loss bucket 2): local-shadow suppression —
                                                      //    captureBindings gains kind=VarDecl records (every
                                                      //    declared C++/ObjC variable NAME incl. primitives,
                                                      //    definition parameters, range-for vars) — a NEW
                                                      //    bind kind on the per-file record → old caches
                                                      //    lack the rows and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      // 51 (r9 loss bucket 1): C++ `using ns::name;`
                                                      //    re-export sites now mint a role="import" RawRef
                                                      //    (new tags.scm @reference.import pattern +
                                                      //    usingDeclarationIsDirective guard) — a NEW ref
                                                      //    kind on the per-file record → old caches lack
                                                      //    the rows and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      // 48 (macro-edges): function-like #define → t="macro"
                                                      //    symbols (C++ gains the capture; C/Rust re-kind
                                                      //    Function→Macro), replacement-text call scan, and
                                                      //    the role="macro" invocation retag.
                                                      // 47 (L3, 2026-08-08 audit): `locals` now counts
                                                      //    DECLARATORS, not declaration statements —
                                                      //    cc_countLocalDeclarators sums every
                                                      //    `declarator`-fielded child of a countable
                                                      //    `declaration` node instead of the fused DFS
                                                      //    incrementing by one per statement. A
                                                      //    comma-separated local (`int a,b,c;`) moves from
                                                      //    locals=1 to locals=3, and a type-only local
                                                      //    declaration (no declarator at all) moves from 1
                                                      //    to 0 — a VALUE change on the per-file RawDef
                                                      //    record's existing `locals` u32 (no format
                                                      //    change) → old caches carry the undercounted
                                                      //    number and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME
                                                      //    commit (P0.2).
                                                      // 46: integration/quality-fleet merge of TWO independent 45s
                                                      //    — the integrated ppalt+nestcal 45 (below) and ev(G),
                                                      //    which took 45 on feat/nest-profile (entry next; it had
                                                      //    skipped 44 to dodge exactly this trap, but the
                                                      //    integration line had already spent 45). The merged
                                                      //    extraction (ppalt + nestcal clause semantics + ev/evWhy
                                                      //    + Swift guard decision counting) matches neither
                                                      //    lineage, so neither's blobs may be served. Mirror moved
                                                      //    in the same commit; qschemetrip re-pinned.
                                                      // 45 (feat/nest-profile numbering): essential complexity (the essential-complexity design note).
                                                      //    45 and not 44: the nesting-quirk round on a sibling
                                                      //    branch independently took 44 for the else-clause hump
                                                      //    rewrite; two independent 44s would cross-hit caches at
                                                      //    merge (that trap already fired once between two 43s).
                                                      //    RawDef/Symbol gain `ev` (u16 FLOOR) + `evWhy` (8×u8 tag
                                                      //    counters), computed inside the fused cc_walk DFS — a
                                                      //    FORMAT change to the per-file def record (u32 + 8×u8
                                                      //    after deepLoc) → old caches must be rejected. ALSO a
                                                      //    VALUE change: Swift `guard_statement` joins
                                                      //    isDecisionType (it is a decision point every cyclomatic
                                                      //    tool counts; required so ev's counting of the
                                                      //    guard-else exit keeps ev <= cx structural), so Swift
                                                      //    cx moves on guard-bearing defs. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit (P0.2).
                                                      // 43 (feat/nest-profile numbering): deepLoc line accounting fixed in cc_walk's else/elif
                                                      //    clause — the hump PROFILE pass now runs forward
                                                      //    (document order) instead of inside the backwards PUSH
                                                      //    loop, so the `else` token's own line is no longer
                                                      //    clamped away behind its block's high-water end. deep=
                                                      //    VALUES move on else-at-the-bar shapes, so caches
                                                      //    written by 42 hold numbers this build would not
                                                      //    produce and must be rejected.
                                                      // 45: integration/quality-fleet merge of the ppalt line
                                                      //    (43 below) and the nestcal r1 line (44 below) — the
                                                      //    merged extraction (ppalt disclosure + r1 else/elif
                                                      //    clause semantics) matches neither lineage, so the
                                                      //    merge takes a fresh number and both sides' blobs are
                                                      //    rejected. Mirror moved in the same commit.
                                                      // 44: the merge of TWO independent 43s, so neither 43's
                                                      //    caches may be served. One 43 was nestcal r1 (else/elif
                                                      //    clause bodies no longer double-deepen — no per-child
                                                      //    maxNest bump or hump minting; nest/humps/deep/ccx
                                                      //    values shift). The other 43 fixed deepLoc's clamp
                                                      //    order for else-clause regions (cc_noteElseRegions,
                                                      //    forward pass); r1's removal of clause noting subsumes
                                                      //    it — every surviving cc_noteHump site notes one node
                                                      //    pre-descent, so document order holds by construction.
                                                      // 43: ppalt disclosure — RawDef/Symbol gained a `ppAlt` u16
                                                      //    counting the ALTERNATIVE-introducing preprocessor nodes
                                                      //    (preproc_else/preproc_elif/preproc_elifdef) inside the
                                                      //    def, filled by the same fused cc_walk DFS: structural
                                                      //    metrics sum branches that never coexist at compile time
                                                      //    (bullet's btMatrix3x3.h::getRotation, ~2x vs any one
                                                      //    build), and the row now DISCLOSES it instead of anyone
                                                      //    guessing a branch. A FORMAT change (new u32 between
                                                      //    locals and params in the def record) → reject old blobs.
                                                      //    quality.h kIngestParserVerMirror bumped in the SAME
                                                      //    commit (P0.2). (Was 42 on its own branch; renumbered 43
                                                      //    at integration — it collided with the independent 42
                                                      //    below.)
                                                      // 42: nested-closure span attribution — the body-climb in
                                                      //    the tags pass no longer adopts an ancestor whose body
                                                      //    CONTAINS the def (JS/TS named const-closures nested in
                                                      //    a function stole the encloser's whole span, so their
                                                      //    cached startByte/endByte/loc/cx/params are wrong) →
                                                      //    old blobs carry the bad spans and must be rejected.
                                                      // 41: Phase 1 (local-variable-indexing, PLAN.md 2026-08-06
                                                      //    evening): RawDef/Symbol gained a `locals` uint32_t
                                                      //    FLOOR field, populated inside the existing fused cc_walk
                                                      //    DFS (C/C++ only — model.h localsCountedLang). A FORMAT
                                                      //    change to the per-file RawDef cache blob (new u32 between
                                                      //    loc and params) → old caches must be rejected, not
                                                      //    misread as an off-by-one on every later field. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit (P0.2).
                                                      // 40: captureIncludes descends into import CONTAINERS instead of
                                                      //    scanning the file root's direct children. Two families, one
                                                      //    walk: (a) preprocessor conditionals —
                                                      //    `#if`/`#ifdef`/`#ifndef`/`#else`/`#elif`/`#elifdef` — in the
                                                      //    C family and C#; (b) ordinary language constructs — Python's
                                                      //    `if TYPE_CHECKING:` / `try…except ImportError` / any function,
                                                      //    method or class body, Rust's `mod x { … }` / fn / impl / trait
                                                      //    / block bodies, and C#'s block-scoped `namespace Foo { … }`.
                                                      //    None of those were ever visited before, so a v39 blob on any
                                                      //    tree using them carries a SHORT include list → reject.
                                                      // (39: JavaScript gains four definition shapes measured missing
                                                      //    against real repos (webpack@957bf3a, node@427d2e1 lib/) —
                                                      //    field_definition bound to an arrow/function, #private
                                                      //    methods (+ their call references), gated CJS export
                                                      //    assignments, gated prototype assignments. A v38 blob on a
                                                      //    JS-bearing tree is missing those rows → reject.)
                                                      // (38: TypeScript
                                                      //    gains three definition shapes measured missing against a real
                                                      //    repo (openclaw, 24 658 .ts files) — abstract_method_signature,
                                                      //    public_field_definition bound to an arrow, and a declarator
                                                      //    whose value is an as/satisfies cast WRAPPING the arrow. A v37
                                                      //    blob on a TS-bearing tree is missing those rows, so it
                                                      //    describes a different graph and must be rejected; the on-disk
                                                      //    RECORD SHAPE did not change, so only parserVer moves, not
                                                      //    kCacheVersion — the CUDA (37) precedent exactly.
                                                      //    37: +CUDA (.cu/.cuh)
                                                      //    on the vendored tree-sitter-cuda grammar (kLangTable) — the
                                                      //    crawl SET changed (two new extensions) and `<<<>>>` launch
                                                      //    sites now extract as call references, so a v36 blob on a
                                                      //    CUDA-bearing tree describes a different graph and must be
                                                      //    rejected; the on-disk RECORD SHAPE did not change, so only
                                                      //    parserVer moves, not kCacheVersion — the +Metal (30)
                                                      //    precedent exactly; 36: H4 W3 V3-verifier
                                                      //    fixup L-1 — a Rust CONTAINER no longer scopes ITSELF.
                                                      //    rustEnclosingScopeOf started its ancestor walk at the node's
                                                      //    parent, and a `mod util`/`trait Shape` definition node IS that
                                                      //    owner's own `name:` child, so the module published `util::util`
                                                      //    and the trait `Shape::Shape` — a self-scope in the canonical-id
                                                      //    space that ids are keyed on. Per-def `scope` is a CACHED field,
                                                      //    so a v35 blob carries the old self-scoped ids and a warm run
                                                      //    would serve them: extraction change, bump required. (The M-2
                                                      //    file-module guard and the M-3 canonical-multi-match routing that
                                                      //    ship alongside are RESOLUTION-only, in graph.h, and would not
                                                      //    have needed one on their own.); 35: H4 W3 MERGE of two
                                                      //    lane bumps that each shipped an in-flight 34 with a DIFFERENT
                                                      //    extraction set (the never-reuse rule again) — the RUST
                                                      //    qualified-call widening: two new reference patterns
                                                      //    (`scoped_identifier name: (identifier)` — depth-unbounded because
                                                      //    Rust nests scoped paths LEFT — and `generic_function function:
                                                      //    (identifier)` for the bare turbofish), so `Widget::new()` /
                                                      //    `util::deep::deepfn()` / `Self::helper()` / `Vec::<u32>::new()` /
                                                      //    `generic::<u32>()` now extract at all, PLUS both halves of the
                                                      //    canonical tier for Rust: per-REF `qualifier` (the path's last
                                                      //    segment, turbofish-stripped, `Self` resolved to the enclosing
                                                      //    impl type) and per-DEF `scope` (the enclosing impl/trait/mod
                                                      //    owner), PLUS the Rust method-SPAN fix (the @definition.method
                                                      //    capture moved off the `declaration_list` wrapper onto the
                                                      //    `function_item`, so spans/loc/cx/ccx/params and ref attribution
                                                      //    for Rust all change); AND the W2b-fixup operator re-split — a
                                                      //    qualified call to an OPERATOR (`outer::inner::operator>`) now
                                                      //    re-splits on the operator-name tail instead of being handed to
                                                      //    the angle-depth scan, which its trailing `>` poisoned: the
                                                      //    per-ref `qualifier` for every `>`-family operator call changes
                                                      //    from the outermost scope to the immediate one. Blobs from
                                                      //    EITHER in-flight v34 describe a different graph and must be
                                                      //    rejected; 33: H4 W2b — the C++
                                                      //    qualified-call widening. The 2-segment `qualified_identifier
                                                      //    name: (identifier)` reference pattern is REPLACED by the
                                                      //    depth-unbounded `name: (_)` (3+-segment calls now extract at all
                                                      //    depths) and a `template_function` pattern is added (explicit
                                                      //    template-argument calls, cast keywords excluded at capture time),
                                                      //    plus ingest's re-split of the widened capture into
                                                      //    name + immediate qualifier. Both the extracted REFERENCE SET and
                                                      //    per-ref `qualifier` change → every blob written by a v32 binary
                                                      //    describes a different graph and must be rejected; 32: H4 wave-2a MERGE of two
                                                      //    lane bumps that each shipped an in-flight 31 with a DIFFERENT extraction
                                                      //    set (the never-reuse-an-in-flight-number rule, further down this comment log) — C#
                                                      //    conditional-access ("?.") calls (two member_binding_expression patterns,
                                                      //    so `w?.Bump()` / `a?.b?.C()` / `w?.Gen<T>()` now emit references) AND
                                                      //    qualified-`new` call refs for TS/JS (member_expression constructor) and
                                                      //    Java (scoped_type_identifier object_creation_expression), plus the ObjC
                                                      //    field_expression call-ref parity line with C; Go's explicit-generic-
                                                      //    instantiation widening was investigated and REJECTED (comment-only .scm change, extraction unaffected),
                                                      //    so Go is unaffected by this bump; 30: +Metal (.metal) on the
                                                      //    C++ grammar, C-family `#import` include edges, and the phantom-scope
                                                      //    guard in qualifierOf (a MISSING `::` no longer publishes the return type
                                                      //    as a canonical scope) — the crawl SET, the include-edge set, AND the
                                                      //    per-def `scope` field all changed; the on-disk RECORD SHAPE did not, so
                                                      //    only parserVer moves, not kCacheVersion. 29 was an in-flight value that
                                                      //    covered only the first two of those three; it must be rejected, because a
                                                      //    v29 blob carries the pre-guard phantom scopes and a warm run would serve
                                                      //    them (observed: `--uses` reported `Out::f` warm and `f` cold on the same
                                                      //    tree). RULE THIS COST US: a cached FIELD changing is an extraction change
                                                      //    even when no record grows — bump again, do not reuse the round's earlier
                                                      //    number; 28: JSON-lane ceilings —
                                                      //    kMaxJsonConfigBytes crawl skip + kMaxJsonNestDepth hostile-data guard;
                                                      //    the crawl/parse SET changed; 27: +C (.c); 26: +JSON config keys)

// A1 (team-index artifact): architecture/ABI tag for the cache-blob header. The blob is NATIVE-ENDIAN —
// ByteW/ByteR memcpy raw ints (see ByteW below), no portable varint/LE re-encoding — so it is only safely
// consumable on a machine with the same integer byte order AND pointer width that WROTE it. This one byte
// lets loadCache's existing header guard reject a foreign-arch blob exactly like a version mismatch → the
// blob is ignored → full cold reparse → correct output, just not fast. Encodes precisely the two properties
// that make a native-endian blob same-arch-consumable: bit 0 = byte order
// (0 little / 1 big), bits 1.. = sizeof(void*) (pointer width in bytes, the ABI word size the raw-int
// widths are keyed to). "Correctness never depends on the artifact" is preserved without paying for a
// portable encoding on the hot (de)serialize path that fe47139/PERF.md P2 optimized; a future big-endian
// target that actually needs a portable re-encode is a separate gated decision,
// not pre-paid here — the guard already makes such a target CORRECT (self-heal), just not fast.
constexpr std::uint8_t kArtifactArch =
      static_cast<std::uint8_t>( ( __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ ) ? 1u : 0u )   // bit 0: endianness
    | static_cast<std::uint8_t>( sizeof( void* ) << 1 );                                   // bits 1..: pointer width (bytes)

// The lean/rich cache FAMILY split (documented against reality per a reviewer note).
// captureValueUses gets its OWN parserVer so a lean blob and a value-uses ("rich") blob can never cross-hit;
// the caller (main.cpp:587) sets it via `needsValueUses = !usesSym.empty() || metrics || !forTask.empty() ||
// !exemplar.empty()`. So which verbs each committed artifact accelerates, precisely:
//   LEAN  (captureValueUses=false): the DEFAULT map, all nav/read verbs (--callers/--callees/--around/
//         --expand/--impact/--path/--grep/--match), --pr-context, --affected, AND --situ (it is NOT in
//         needsValueUses — the DESIGN's "--situ needs rich" aside is backwards; the lean artifact serves it).
//   RICH  (captureValueUses=true): --for, --exemplar, --metrics (and its --hotspots/quality lenses), and
//         --uses. NB: --for is the flagship orientation verb every CLAUDE.md session opens with, and it is
//         RICH — so a team that commits ONLY the lean artifact gets NO warm hit on --for/--exemplar/--metrics
//         (those cold-parse unless the rich artifact is also committed). "Lean accelerates the common
//         orientation path" therefore overstates: lean speeds the default map + nav/read + --pr-context;
//         --for-led sessions need the rich family too. See the ingest-report to the wiring wave for the
//         measured lean-vs-rich blob sizes and the both-families recommendation.
inline std::uint32_t parserVerFor( bool captureValueUses ) noexcept
{
    return kParserVer + ( captureValueUses ? 1u : 0u );   // lean and full-use caches must never cross-hit
}

// T5: renamed from fnv1a64 to contentHash64 to avoid an ODR clash now that this file also includes
// arch.h (which defines its OWN fnv1a64 for the baseline-hash path, quality.h's canonId hashing, etc.
// — same FNV-1a family, DIFFERENT offset-basis constant; this is ingest's file-content-hash cache
// KEY and must not change bit-for-bit, so it keeps its own constant rather than switching to arch.h's).
inline std::uint64_t contentHash64( std::string_view s ) noexcept
{
    std::uint64_t h = 1469598103934665603ull;
    for( const char c : s )
    {
        h = hashutil::fnv1aAbsorb( h, c );
    }
    return h;
}

// BONUS (S): a whole-blob checksum for the cache trailer. The single-lane contentHash64 above is the file-content
// hash (cache KEY — must never change), but a scalar byte loop over the multi-MB cache blob costs ~1 byte/
// cycle. This uses 8 INDEPENDENT FNV lanes (byte i feeds lane i&7) so the multiplies pipeline, then folds —
// ~5× faster on the big blob while staying a pure, deterministic function of the bytes (a lane permutation of
// FNV-1a). Purpose is integrity detection (fuzzer-found bit-flips inside cached strings), not the cache key.
inline std::uint64_t blobChecksum( std::string_view s ) noexcept
{
    std::uint64_t lane[ 8 ] = { 1469598103934665603ull, 1099511628211ull, 0x100000001b3ull, 0x9e3779b97f4a7c15ull,
                                0xc2b2ae3d27d4eb4full, 0x165667b19e3779f9ull, 0xff51afd7ed558ccdull, 0xc4ceb9fe1a85ec53ull };
    const unsigned char* p = reinterpret_cast<const unsigned char*>( s.data() );
    const std::size_t    n = s.size();
    std::size_t          i = 0;
    for( ; i + 8 <= n; i += 8 )
    { // 8 lanes advance in lockstep — no cross-lane dependency
        for( int k = 0; k < 8; ++k ) { lane[ k ] ^= p[ i + k ]; lane[ k ] = hashutil::fnv1aMultiply( lane[ k ] ); }
    }
    for( int k = 0; i < n; ++i, ++k ) { lane[ k ] ^= p[ i ]; lane[ k ] = hashutil::fnv1aMultiply( lane[ k ] ); }   // tail (< 8 bytes)

    std::uint64_t h = 1469598103934665603ull;                   // fold the 8 lanes into one 64-bit digest
    for( int k = 0; k < 8; ++k ) { h ^= lane[ k ]; h = hashutil::fnv1aMultiply( h ); }
    return h;
}

// sizeBytes/mtimeNs/ctimeNs (A4-P7 + card A3 follow-up): the file's stat at the run that HASHED it — the
// warm-run stat-gate trusts this record (skips read+hash) only when ALL THREE still match AND mtimeNs is
// not racy. ctimeNs is the one an unprivileged writer cannot restore (see ingest_crawl.h statSizeTimes),
// so it is what makes a same-(mtime,size) edit visible for free. -1 ⇒ unknown (the file was unstatable at
// hash time) → the gate always re-hashes, which is the safe direction.
struct FileFacts { std::uint64_t hash = 0; long long sizeBytes = -1; long long mtimeNs = -1; long long ctimeNs = -1; FileHealth health; std::vector<RawDef> defs; std::vector<RawRef> refs; std::vector<Include> incs; std::vector<RawBind> binds; std::vector<BindingAlias> ffis; std::vector<RouteDef> routeDefs; std::vector<RawRouteUse> routeUses; };

// tiny native-endian binary (de)serializer (the cache is host-local, never shipped)
struct ByteW
{
    std::string b;
    void u8 ( std::uint8_t  v ) { b.push_back( char( v ) ); }
    void u32( std::uint32_t v ) { b.append( reinterpret_cast<const char*>( &v ), 4 ); }
    void u64( std::uint64_t v ) { b.append( reinterpret_cast<const char*>( &v ), 8 ); }
    void str( std::string_view s ) { u32( std::uint32_t( s.size() ) ); b.append( s ); }
    void raw( const void* p, std::size_t n )
    {
        if( n )
        {
            b.append( reinterpret_cast<const char*>( p ), n );
        }
    } // B0.2: bulk array append (memcpy-speed (de)serialize)
    // H3 (v10): bulk row extension — one resize + raw-pointer fill instead of a bounds-checked push_back
    // per byte (the postings rows are ~3 B × millions of pairs — this seam is the saveCache hot loop).
    // The narrow ints written through it are explicit little-endian (see writeDef), so the width-packed
    // postings fields read back identically on either endianness the kArtifactArch guard admits.
    char* extend( std::size_t n ) { const std::size_t off = b.size(); b.resize( off + n ); return b.data() + off; }
};
struct ByteR
{
    const char* p; const char* end; bool ok = true;
    std::uint8_t  u8 () { if( p >= end ) { ok = false; return 0; } return std::uint8_t( *p++ ); }
    std::uint32_t u32() { std::uint32_t v = 0; if( p + 4 > end ) { ok = false; return 0; } std::memcpy( &v, p, 4 ); p += 4; return v; }
    std::uint64_t u64() { std::uint64_t v = 0; if( p + 8 > end ) { ok = false; return 0; } std::memcpy( &v, p, 8 ); p += 8; return v; }
    std::string_view view() { const std::uint32_t n = u32(); if( !ok || p + n > end ) { ok = false; return {}; } std::string_view s( p, n ); p += n; return s; }
    std::string      str () { const std::string_view s = view(); return ok ? std::string( s ) : std::string{}; }
    bool rawInto( void* dst, std::size_t n )   // B0.2: bulk array read — overflow-safe bound, memcpy into caller storage
    { if( !ok || std::size_t( end - p ) < n ) { ok = false; return false; } if( n ) { std::memcpy( dst, p, n ); p += n; } return true; }
};

// withLex (B0.2 / v10 H3): the RICH family (captureValueUses=true) persists each def's doc/body subtoken
// stats. v10 encoding: the FILE record carries a sorted per-file subtoken DICTIONARY (see saveCache), and
// each def row stores dict-relative indices at the narrowest width the dict size allows + tfs at the
// narrowest width this def's max tf needs — exact integers either way (widths chosen from maxima, never
// lossy), ~3 B/pair instead of the raw 12 B/pair of v9. The LEAN family never computes them, so its
// record shape is unchanged; the two families can never cross-hit (parserVerFor), so one flag at both
// (de)serialize seams keeps the formats in lock-step.
inline unsigned lexDictIndexWidth( std::size_t dictCount ) noexcept
{
    return dictCount <= 0x100 ? 1u : dictCount <= 0x10000 ? 2u : 4u;   // indices go up to dictCount-1
}
inline void writeDef( ByteW& w, const RawDef& d, bool withLex, std::size_t fileDictCount, const std::uint32_t* rowDictIndex )
{
    w.u32( d.line ); w.u32( d.startByte ); w.u32( d.endByte ); w.u32( d.nameByte ); w.u32( d.bodyByte ); w.u32( d.cx ); w.u32( d.ccx ); w.u32( d.loc ); w.u32( d.locals ); w.u32( d.ppAlt ); w.u32( d.humps ); w.u32( d.deepLoc ); w.u32( d.ev ); w.u32( d.params ); w.u8( d.maxNest ); w.u8( d.arityExact ); w.u8( d.testScope ); w.u8( std::uint8_t( d.kind ) ); w.u8( std::uint8_t( d.lang ) ); w.str( d.name ); w.str( d.scope );
    for( const std::uint8_t tagCount : d.evWhy ) { w.u8( tagCount ); }   // 8×u8, fixed order (model.h kEvWhyTagTable)
    if( withLex )
    {
        VERIFY( d.lex.tokenHashes.size() == d.lex.tokenTfs.size() );
        w.u32( d.lex.dlWeighted );
        w.u32( std::uint32_t( d.lex.tokenHashes.size() ) );
        std::uint32_t maxTf = 0;
        for( const std::uint32_t tf : d.lex.tokenTfs )
        {
            if( tf > maxTf )
            {
                maxTf = tf;
            }
        }
        const unsigned tfWidth  = maxTf <= 0xFFu ? 1u : maxTf <= 0xFFFFu ? 2u : 4u;   // exact-preserving by construction
        const unsigned idxWidth = lexDictIndexWidth( fileDictCount );
        w.u8( std::uint8_t( tfWidth ) );
        // rowDictIndex: this def's precomputed dict indices (saveCache assigns them during the k-way
        // dict merge — no per-hash search here), ascending because the row is sorted. One bulk extend +
        // specialized fill loops per width — no per-byte push_back on this multi-million-pair seam.
        const std::size_t count = d.lex.tokenTfs.size();
        char*             p     = w.extend( count * ( idxWidth + tfWidth ) );
        if( idxWidth == 1 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                *p++ = char( rowDictIndex[k] );
            }
        }
        else if( idxWidth == 2 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = rowDictIndex[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p += 2;
            }
        }
        else
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = rowDictIndex[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p[2] = char( v >> 16 );
                p[3] = char( v >> 24 );
                p += 4;
            }
        }
        const std::uint32_t* tfs = d.lex.tokenTfs.data();
        if( tfWidth == 1 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                *p++ = char( tfs[k] );
            }
        }
        else if( tfWidth == 2 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = tfs[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p += 2;
            }
        }
        else
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = tfs[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p[2] = char( v >> 16 );
                p[3] = char( v >> 24 );
                p += 4;
            }
        }
    }
}
inline void   writeRef( ByteW& w, const RawRef& r ) { w.u32( r.startByte ); w.u8( std::uint8_t( r.lang ) ); w.str( r.name ); w.u8( r.isInherit ? 1 : 0 ); w.u8( r.isDocLink ? 1 : 0 ); w.str( r.qualifier ); w.u8( std::uint8_t( r.recv ) ); w.str( r.recvVar ); w.u8( r.isCompose ? 1 : 0 ); w.str( r.fieldName ); w.str( r.composeRel ); w.u8( std::uint8_t( r.role ) ); w.u32( r.line ); w.u32( r.argCount ); w.u8( r.argCountKnown ? 1 : 0 ); }

// loadCache's countFits() bounds a corrupt on-disk record COUNT against remaining bytes /
// minRecordBytes BEFORE reserve() — the guard that keeps a hostile blob's 0xFFFFFFFF count from reaching
// an allocator. The minima below are named + pinned here (not hand-recounted inline at the call site) so
// they sit next to the writer functions whose field list they must match. A LEAN def record is 14 u32 +
// 13 u8 + 2 empty str(len u32) fields = 14*4 + 13*1 + 2*4 = 77 bytes (Phase 1, local-variable-indexing,
// PLAN.md 2026-08-06 evening: `locals` u32 joined the run — 9 -> 10; the ppalt disclosure added `ppAlt`,
// written as a u32 — 10 -> 11; the nesting profile then added `humps` and `deepLoc`, written as u32 each —
// 11 -> 13; essential complexity then added `ev` as a u32 in the run plus the 8×u8 evWhy tag counters
// after the strings — 13 -> 14 u32 and 4 -> 12 u8, so 56 + 12 + 8 = 76; L8's in-file `testScope` then
// added one u8 in the run — 12 -> 13 u8, so 56 + 13 + 8 = 77); the RICH (withLex) extra is
// dlWeighted u32 + tokenCount u32 + tfWidth u8 = 9 bytes. A ref record is 3 u32 + 7 u8 + 5 empty
// str(len u32) fields = 3*4 + 7*1 + 5*4 = 39 bytes. verifyCacheRecordMinimaTripwire() below derives these
// same numbers from the REAL writer functions at runtime so the next field added to writeDef/writeRef
// can't silently stale them.
inline constexpr std::size_t kMinDefRecordBytesLean      = 77;   // 14×u32 + 13×u8 + 2×str(len u32, empty)
inline constexpr std::size_t kMinDefRecordBytesRichExtra =  9;   // v10 rich withLex extra: dlWeighted u32 + tokenCount u32 + tfWidth u8
inline constexpr std::size_t kMinRefRecordBytes          = 39;   // 3×u32 + 7×u8 + 5×str(len u32, empty)

inline std::size_t minDefRecordBytes( bool captureValueUses ) noexcept
{
    return kMinDefRecordBytesLean + ( captureValueUses ? kMinDefRecordBytesRichExtra : 0 );
}

// runtime tripwire: serialize a DEFAULT-CONSTRUCTED (all-empty) RawDef/RawRef through the real
// writer functions and VERIFY the byte count matches the hand-pinned constants above. This is the runtime
// equivalent of the house `static_assert( sizeof(X) == N )` layout tripwire — ByteW's size is only known at
// runtime (strings, not a POD struct), so it can't be a compile-time static_assert. VERIFY is a no-op
// optimizer hint in release (never costs a shipped run anything); in any debug/ASan build or CI it fires the
// moment a field is added to writeDef/writeRef without updating the matching constant above.
inline void verifyCacheRecordMinimaTripwire() noexcept
{
    ByteW probe;
    writeDef( probe, RawDef{}, false, 0, nullptr );
    VERIFY( probe.b.size() == kMinDefRecordBytesLean );
    probe.b.clear();
    writeDef( probe, RawDef{}, true, 0, nullptr );
    VERIFY( probe.b.size() == kMinDefRecordBytesLean + kMinDefRecordBytesRichExtra );
    probe.b.clear();
    writeRef( probe, RawRef{} );
    VERIFY( probe.b.size() == kMinRefRecordBytes );
}

inline RawDef readDef( ByteR& r, bool withLex, const std::vector<std::uint64_t>& fileDict )
{
    RawDef d; d.line = r.u32(); d.startByte = r.u32(); d.endByte = r.u32(); d.nameByte = r.u32(); d.bodyByte = r.u32(); d.cx = r.u32(); d.ccx = r.u32(); d.loc = r.u32(); d.locals = r.u32(); d.ppAlt = std::uint16_t( r.u32() ); d.humps = std::uint16_t( r.u32() ); d.deepLoc = std::uint16_t( r.u32() ); d.ev = std::uint16_t( r.u32() ); d.params = std::uint16_t( r.u32() ); d.maxNest = r.u8(); d.arityExact = r.u8(); d.testScope = r.u8(); d.kind = SymKind( r.u8() ); d.lang = Lang( r.u8() ); d.name = r.str(); d.scope = r.str();
    for( std::uint8_t& tagCount : d.evWhy ) { tagCount = r.u8(); }   // mirrors writeDef's fixed 8×u8 order
    if( withLex && r.ok )
    {
        d.lex.dlWeighted = r.u32();
        const std::uint32_t tokenCount = r.u32();
        const std::uint8_t  tfWidth    = r.u8();
        // a corrupt on-disk count/width must never reach resize() (the throw would escape ingest()'s
        // never-throw contract) — every honest count is bounded by remaining bytes / min pair bytes
        if( !r.ok || ( tfWidth != 1 && tfWidth != 2 && tfWidth != 4 ) ) { r.ok = false; return d; }
        const unsigned    idxWidth  = lexDictIndexWidth( fileDict.size() );
        const std::size_t needBytes = std::size_t( tokenCount ) * ( idxWidth + tfWidth );
        if( std::size_t( r.end - r.p ) < needBytes ) { r.ok = false; return d; }
        d.lex.tokenHashes.resize( tokenCount );
        d.lex.tokenTfs.resize( tokenCount );
        // decode indices → hashes through the file dict; the dict is strictly ascending (validated at
        // load) and honest rows store strictly-ascending indices, so the decoded row is sorted — the
        // invariant the query-time binary search relies on. Violations ⇒ corrupt ⇒ self-healing reparse.
        // The whole row was bounds-checked ONCE above, so these are tight raw-pointer loops (this is the
        // warm-path deserialize hot spot — ~1M pairs on a jax-class rich blob).
        const unsigned char* q         = reinterpret_cast<const unsigned char*>( r.p );
        const std::uint64_t* dict      = fileDict.data();
        const std::uint32_t  dictCount = std::uint32_t( fileDict.size() );
        std::uint64_t*       hashOut   = d.lex.tokenHashes.data();
        std::uint32_t        prevIndex = 0;
        bool                 rowOk     = true;
        const auto decodeIndexRun = [ & ]( auto readOne )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                const std::uint32_t dictIndex = readOne();
                if( dictIndex >= dictCount || ( k > 0 && dictIndex <= prevIndex ) ) { rowOk = false; return; }
                hashOut[k] = dict[ dictIndex ];
                prevIndex  = dictIndex;
            }
        };
        if( idxWidth == 1 )
        {
            decodeIndexRun( [ & ]() noexcept
                            { return std::uint32_t( *q++ ); } );
        }
        else if( idxWidth == 2 )
        {
            decodeIndexRun( [ & ]() noexcept
                            { const std::uint32_t v = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8; q += 2; return v; } );
        }
        else
        {
            decodeIndexRun( [ & ]() noexcept
                            { const std::uint32_t v = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8 | std::uint32_t( q[2] ) << 16 | std::uint32_t( q[3] ) << 24; q += 4; return v; } );
        }
        if( !rowOk ) { r.ok = false; return d; }
        std::uint32_t* tfOut = d.lex.tokenTfs.data();
        if( tfWidth == 1 )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = *q++;
            }
        }
        else if( tfWidth == 2 )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8;
                q += 2;
            }
        }
        else
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8 | std::uint32_t( q[2] ) << 16 | std::uint32_t( q[3] ) << 24;
                q += 4;
            }
        }
        r.p += needBytes;
    }
    return d;
}
inline RawRef readRef ( ByteR& r ) { RawRef x; x.startByte = r.u32(); x.lang = Lang( r.u8() ); x.name = r.str(); x.isInherit = r.u8() != 0; x.isDocLink = r.u8() != 0; x.qualifier = r.str(); x.recv = RecvKind( r.u8() ); x.recvVar = r.str(); x.isCompose = r.u8() != 0; x.fieldName = r.str(); x.composeRel = r.str(); x.role = RefRole( r.u8() ); x.line = r.u32(); x.argCount = std::uint16_t( r.u32() ); x.argCountKnown = r.u8() != 0; return x; }
inline void   writeBind( ByteW& w, const RawBind& b ) { w.u32( b.startByte ); w.u8( std::uint8_t( b.lang ) ); w.u8( std::uint8_t( b.kind ) ); w.u32( b.spanStart ); w.u32( b.spanEnd ); w.str( b.var ); w.str( b.typeName ); }
inline RawBind readBind( ByteR& r ) { RawBind b; b.startByte = r.u32(); b.lang = Lang( r.u8() ); b.kind = LocalBindKind( r.u8() ); b.spanStart = r.u32(); b.spanEnd = r.u32(); b.var = r.str(); b.typeName = r.str(); return b; }
inline void   writeFfi( ByteW& w, const BindingAlias& a ) { w.u8( std::uint8_t( a.kind ) ); w.u8( a.lowConf ? 1 : 0 ); w.str( a.aliasName ); w.str( a.targetName ); w.str( a.targetScope ); }
inline BindingAlias readFfi( ByteR& r ) { BindingAlias a; a.kind = BindKind( r.u8() ); a.lowConf = r.u8() != 0; a.aliasName = r.str(); a.targetName = r.str(); a.targetScope = r.str(); return a; }
// B6.3: RouteDef needs no startByte (its handler is resolved by NAME in buildGraph); RawRouteUse mirrors
// RawBind (startByte for the enclosing-def byte-span attribution done in the ingest() model-build below).
inline void   writeRouteDef( ByteW& w, const RouteDef& d ) { w.u32( d.line ); w.u8( std::uint8_t( d.method ) ); w.str( d.path ); w.str( d.handlerName ); }
inline RouteDef readRouteDef( ByteR& r ) { RouteDef d; d.line = r.u32(); d.method = HttpMethod( r.u8() ); d.path = r.str(); d.handlerName = r.str(); return d; }
inline void   writeRouteUse( ByteW& w, const RawRouteUse& u ) { w.u32( u.startByte ); w.u32( u.line ); w.u8( std::uint8_t( u.method ) ); w.str( u.path ); }
inline RawRouteUse readRouteUse( ByteR& r ) { RawRouteUse u; u.startByte = r.u32(); u.line = r.u32(); u.method = HttpMethod( r.u8() ); u.path = r.str(); return u; }

// T5: re-absolutize a cache-stored ROOT-RELATIVE key against the CURRENT invocation's rootDir, producing
// the exact spelling collectSources() would crawl it as (`<rootDir>/<rel>`, trailing slash on rootDir
// normalized away) — the same spelling result.files[fileId] holds, so cache.find(path) in the caller
// needs no changes. Pure string join; no filesystem I/O (mirrors relForHash's own no-realpath contract).
inline std::string reAbsolutize( std::string_view rel, std::string_view root )
{
    std::string_view rootTrim = root;
    while( rootTrim.size() > 1 && rootTrim.back() == '/' )
    {
        rootTrim.remove_suffix( 1 );
    }
    if( rootTrim.empty() )
    {
        rootTrim = "."; // empty root ⇒ same "." spelling collectSources' fs::path("") would give
    }
    std::string out;
    out.reserve( rootTrim.size() + 1 + rel.size() );
    out.append( rootTrim );
    out.push_back( '/' );
    out.append( rel );
    return out;
}

// load cache → map<path, FileFacts>, keyed by the ABSOLUTE-AS-CRAWLED path under `rootDir` (matching
// result.files' spelling) even though the on-disk record key is root-relative (T5 portability — see
// kCacheVersion=3 above). Empty on missing / corrupt / version-or-parserVer mismatch.
// blobWriteNsOut (supersedes A4-P7): the racy-rule reference a warm run's stat-gate compares
// every cached file's mtime against. STAMPED FROM A FRESH stat() OF THE CACHE FILE ITSELF (this file's own
// `path`, taken right here — necessarily "post-rename", since by the time a later run's loadCache opens it
// the writer's saveCache has long since renamed tmp -> path), NOT from the ns-precision wall-clock the
// header still carries for legacy/diagnostic reasons. Same clock+granularity domain (stat()) as the
// per-file mtimes it is compared against below — on a coarse-mtime filesystem (HFS+, many network mounts)
// the old wall-clock-vs-stat comparison was a tautology (a floored mtime is always < an unfloored LATER
// timestamp), so a same-granule post-hash edit could slip through undetected. No wall-clock read on this
// path. Left at -1 on any miss/corrupt/version-mismatch/unstatable-path (out is empty then too), which
// makes every stat-gate check see a racy entry and re-hash — the safe default.
inline HashMap<std::string, FileFacts> loadCache( const std::string& path, std::string_view rootDir, bool captureValueUses,
                                                  long long& blobWriteNsOut )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: loadCache (read + deserialize)" );
    HashMap<std::string, FileFacts> out;
    blobWriteNsOut = -1;

    // L1: only a REGULAR file may reach readFile below — on Linux a directory opens cleanly and takes its
    // resize() down with it. Any other shape self-heals into a full reparse, exactly like a checksum
    // mismatch (see isReadableCacheBlob); blobWriteNsOut stays -1 ⇒ the caller cold-parses.
    if( !isReadableCacheBlob( path ) )
    {
        return out;
    }

    std::string blob;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: read cache blob" );
        if( !readFile( path, blob ) )
        {
            return out;
        }
    }

    // BONUS (S): whole-blob FNV-1a checksum trailer (last 8 bytes). saveCache appends fnv1a64(payload) so a
    // silent bit-flip INSIDE a cached string (fuzzer-found: the count/version guards trust the record bytes)
    // is caught here → treat as corrupt → self-healing full reparse. A blob too short to hold magic+trailer
    // is corrupt too. Reader `r` is bounded to the PAYLOAD (blob minus the 8-byte trailer).
    constexpr std::size_t kTrailerBytes = 8;
    if( blob.size() < 21 + kTrailerBytes )
    {
        return out; // 3×u32 + u8 arch + u64 blobWriteNs header + trailer minimum
    }
    const std::size_t payloadLen = blob.size() - kTrailerBytes;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: checksum trailer" );
        std::uint64_t stored = 0;
        std::memcpy( &stored, blob.data() + payloadLen, kTrailerBytes );
        if( blobChecksum( std::string_view( blob.data(), payloadLen ) ) != stored )
        {
            DEGRADED_PATH_ALERT( "ingest: cache checksum mismatch — cache treated as corrupt (full reparse)" );
            return out;
        }
    }

    ByteR r{ blob.data(), blob.data() + payloadLen };
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: header" );
        // A1 (team-index): the kArtifactArch byte is part of the header guard — a foreign-arch blob
        // (different endianness or pointer width) mismatches here exactly like a version/parserVer
        // mismatch → out stays empty, blobWriteNsOut stays -1 → the caller cold-parses (self-heal).
        // Left-to-right && short-circuit means the u8() read only happens once magic/version/parserVer
        // have matched, keeping the byte-stream cursor consistent on the accepted path.
        if( r.u32() != kCacheMagic || r.u32() != kCacheVersion || r.u32() != parserVerFor( captureValueUses ) || r.u8() != kArtifactArch )
        {
            return out;
        }
        (void)r.u64();   // legacy wall-clock write stamp — kept in the wire format for diagnostics, no longer
                          // the racy-rule reference (F3/X5: see blobWriteNsOut below); must still be consumed
                          // to keep the byte-stream cursor aligned with the record count that follows.
    }

    // F3/X5: the racy-rule reference is THIS cache file's own on-disk mtime, stat'd fresh right now — the
    // same stat()-domain, same-granularity value every per-file mtime below is compared against. -1 (unstatable,
    // e.g. removed between the readFile above and here) ⇒ every stat-gate check sees a racy entry (safe default).
    blobWriteNsOut = statSizeTimes( path ).mtimeNs;

    // count validation: a corrupt on-disk count (e.g. 0xFFFFFFFF) must never reach reserve() — the throw
    // (length_error/bad_alloc) would escape ingest(), violating its never-throw contract. Every honest
    // count is bounded by remaining bytes / the record's MINIMUM serialized size; past that → corrupt →
    // same self-healing full-reparse path as a truncated blob (r.ok = false → out.clear() below).
    // (B0.2) a RICH def record additionally carries at least dlWeighted + tokenCount (2×u32) — the pair
    // arrays themselves are bounded per record inside readDef.
    const std::size_t kMinDefRecordBytes  = minDefRecordBytes( captureValueUses );   // F8: named + tripwire-pinned above
    constexpr std::size_t kMinIncRecordBytes  =  6;   // 2×u8 (isAngle,isLazy) + 1×str(len u32, empty)
    constexpr std::size_t kMinBindRecordBytes = 13;   // 1×u32 + 1×u8 + 2×str(len u32, empty)
    constexpr std::size_t kMinFfiRecordBytes  = 14;   // 2×u8 (kind,lowConf) + 3×str(len u32, empty)
    constexpr std::size_t kMinRouteDefRecordBytes = 13;   // B6.3: 1×u32 (line) + 1×u8 (method) + 2×str(len u32, empty)
    constexpr std::size_t kMinRouteUseRecordBytes = 13;   // B6.3: 2×u32 (startByte,line) + 1×u8 (method) + 1×str(len u32, empty)
    const std::size_t kMinFileRecordBytes = 76 + ( captureValueUses ? 4 : 0 );   // path str + hash + sizeBytes + mtimeNs + ctimeNs + FileHealth + six record counts, all empty (v6: +2×u64; v10 rich: + dict count u32; v12/B6.3: +2×u32 route counts; v13/§L1: +4×u32 health; v14: +1×u64 ctimeNs)
    const auto countFits = [ &r ]( std::uint32_t recordCount, std::size_t minRecordBytes ) noexcept
    {
        if( recordCount <= std::size_t( r.end - r.p ) / minRecordBytes )
        {
            return true;
        }
        DEGRADED_PATH_ALERT( "ingest: cache record count exceeds remaining bytes — cache treated as corrupt" );
        r.ok = false;
        return false;
    };

    std::uint32_t nf = 0;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: file count + reserve" );
        nf = r.u32();
        if( !countFits( nf, kMinFileRecordBytes ) )
        {
            return out;
        }
        out.reserve( nf );
    }
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: deserialize file records" );
        std::vector<std::uint64_t> fileDict;   // H3 (v10): per-file subtoken dictionary (rich family only)
        for( std::uint32_t i = 0; i < nf && r.ok; ++i )
        {
            // T5: the on-disk key is ROOT-RELATIVE (relForHash'd at save time); re-absolutize against the
            // CURRENT rootDir so the map key matches result.files' spelling for this invocation exactly —
            // this is what makes a cache built under one root/checkout path warm-hit under another.
            std::string key = reAbsolutize( r.view(), rootDir );
            FileFacts   ff;
            ff.hash      = r.u64();
            ff.sizeBytes = (long long)r.u64();   // A4-P7 stat-gate discriminator
            ff.mtimeNs   = (long long)r.u64();   // A4-P7 stat-gate discriminator + racy-rule input
            ff.ctimeNs   = (long long)r.u64();   // v14 stat-gate discriminator: the one a restore cannot forge
            ff.health.errNodes  = r.u32();       // §L1 parse health (v13) — fileBytes==0 keeps its
            ff.health.errBytes  = r.u32();       //   NOT-MEASURED meaning across the round trip
            ff.health.fileBytes = r.u32();
            ff.health.wsBytes   = r.u32();
            if( captureValueUses )
            {
                // H3 (v10): the file's subtoken dictionary — def rows below index into it. Must be
                // strictly ascending (readDef's sorted-row invariant hangs on it); anything else is
                // corrupt → the same self-healing full-reparse path as a truncated blob.
                const std::uint32_t dictCount = r.u32();
                if( !countFits( dictCount, sizeof( std::uint64_t ) ) )
                {
                    break;
                }
                fileDict.resize( dictCount );
                if( !r.rawInto( fileDict.data(), std::size_t( dictCount ) * sizeof( std::uint64_t ) ) )
                {
                    break;
                }
                for( std::size_t k = 1; k < fileDict.size(); ++k )
                {
                    if( fileDict[k] <= fileDict[ k - 1 ] )
                    {
                        DEGRADED_PATH_ALERT( "ingest: cache file dictionary not strictly ascending — cache treated as corrupt" );
                        r.ok = false;
                        break;
                    }
                }
                if( !r.ok )
                {
                    break;
                }
            }
            const std::uint32_t nd = r.u32();
            if( !countFits( nd, kMinDefRecordBytes ) )
            {
                break;
            }
            ff.defs.reserve( nd );
            for( std::uint32_t j = 0; j < nd && r.ok; ++j )
            {
                ff.defs.push_back( readDef( r, captureValueUses, fileDict ) );
            }
            const std::uint32_t nr = r.u32();
            if( !countFits( nr, kMinRefRecordBytes ) )
            {
                break;
            }
            ff.refs.reserve( nr );
            for( std::uint32_t j = 0; j < nr && r.ok; ++j )
            {
                ff.refs.push_back( readRef( r ) );
            }
            const std::uint32_t ni = r.u32();
            if( !countFits( ni, kMinIncRecordBytes ) )
            {
                break;
            }
            ff.incs.reserve( ni );
            for( std::uint32_t j = 0; j < ni && r.ok; ++j )
            {
                const bool isAngle = r.u8() != 0;
                const bool isLazy  = r.u8() != 0;   // kParserVer 72: TS/JS function-body require/import marker
                ff.incs.push_back( Include { 0, isAngle, isLazy, r.str() } );
            }
            const std::uint32_t nb = r.u32();
            if( !countFits( nb, kMinBindRecordBytes ) )
            {
                break;
            }
            ff.binds.reserve( nb );
            for( std::uint32_t j = 0; j < nb && r.ok; ++j )
            {
                ff.binds.push_back( readBind( r ) );
            }
            const std::uint32_t na = r.u32();
            if( !countFits( na, kMinFfiRecordBytes ) )
            {
                break;
            }
            ff.ffis.reserve( na );
            for( std::uint32_t j = 0; j < na && r.ok; ++j )
            {
                ff.ffis.push_back( readFfi( r ) );
            }
            const std::uint32_t nrd = r.u32();
            if( !countFits( nrd, kMinRouteDefRecordBytes ) )
            {
                break;
            }
            ff.routeDefs.reserve( nrd );
            for( std::uint32_t j = 0; j < nrd && r.ok; ++j )
            {
                ff.routeDefs.push_back( readRouteDef( r ) ); // B6.3
            }
            const std::uint32_t nru = r.u32();
            if( !countFits( nru, kMinRouteUseRecordBytes ) )
            {
                break;
            }
            ff.routeUses.reserve( nru );
            for( std::uint32_t j = 0; j < nru && r.ok; ++j )
            {
                ff.routeUses.push_back( readRouteUse( r ) ); // B6.3
            }
            if( r.ok )
            {
                out.emplace( std::move( key ), std::move( ff ) );
            }
        }
    }
    if( !r.ok )
    {
        out.clear(); // truncated/corrupt → ignore (full reparse; self-healing)
    }
    return out;
}

// write the cache atomically (path.tmp → rename); groups the merged raw facts back by file.
// T5: `rootDir` is the CURRENT invocation's ingest root — every file key is stored root-relative
// (relForHash) rather than verbatim, so the cache blob is committable/portable (see kCacheVersion=3).
inline void saveCache( const std::string& path, std::string_view rootDir, const std::vector<std::string>& files,
                       const std::vector<std::uint64_t>& fileHash,
                       const std::vector<long long>& fileSize, const std::vector<long long>& fileMtime,
                       const std::vector<long long>& fileCtime,     // v14: the third stat-gate discriminator, per fileId
                       const std::vector<FileHealth>& fileHealth,   // §L1 (v13): parse health, per fileId
                       const std::vector<RawDef>& defs, const std::vector<RawRef>& refs, const std::vector<Include>& incs,
                       const std::vector<RawBind>& binds, const std::vector<BindingAlias>& ffis,
                       const std::vector<RouteDef>& routeDefs, const std::vector<RawRouteUse>& routeUses,   // B6.3
                       bool captureValueUses )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: saveCache (serialize + write)" );

    // L1 (write half): never publish over a non-regular file, and decide it BEFORE the serialize so a
    // directory at `path` costs no wasted pass and temp write before rename(tmp,dir) fails EISDIR.
    if( shapeOfPath( path ) == PathShape::Other )
    {
        DEGRADED_PATH_ALERT( "ingest: cache path is not a regular file (directory/device/fifo) — cache not written" );
        return;
    }

    const std::size_t F = files.size();
    // The cache-write side's per-file record indexes. Split by MEASURED shape, not by symmetry:
    //   dIdx  — one entry per DEFINITION; same distribution as model.h's SymbolsByFile (mean 8.4/18.2 per
    //           file, p90 18/37), so it takes that index's measured N=8 knee.
    //   iIdx/aIdx/rdIdx/ruIdx — includes, FFI aliases and the two route tables. N=2 is FREE (rw::svector's
    //           inline array shares storage with the heap pointer, so <uint32,1> and <uint32,2> are both
    //           16 B — a THIRD smaller than the std::vector header it replaces) and covers 85.4%/59.1%,
    //           99.7%/100%, 99.9%/100% and 99.9%/100% of files across the two census corpora.
    //   rIdx/bIdx — deliberately LEFT as std::vector. Means of 155/248 and 28/59 references and bindings per
    //           file with 17%/40% of files empty and no early knee: an N that covered them would have to be
    //           in the hundreds. They are CSR candidates, a separate wave, not small-vector material.
    std::vector<rw::SmallVec<std::uint32_t, 8>> dIdx( F );
    std::vector<std::vector<std::uint32_t>>     rIdx( F ), bIdx( F );
    std::vector<rw::SmallVec<std::uint32_t, 2>> iIdx( F ), aIdx( F ), rdIdx( F ), ruIdx( F );
    for( std::uint32_t i = 0; i < defs.size(); ++i )
    {
        if( defs[i].fileId < F )
        {
            dIdx[defs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < refs.size(); ++i )
    {
        if( refs[i].fileId < F )
        {
            rIdx[refs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < incs.size(); ++i )
    {
        if( incs[i].fileId < F )
        {
            iIdx[incs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < binds.size(); ++i )
    {
        if( binds[i].fileId < F )
        {
            bIdx[binds[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < ffis.size(); ++i )
    {
        if( ffis[i].fileId < F )
        {
            aIdx[ffis[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < routeDefs.size(); ++i )
    {
        if( routeDefs[i].fileId < F )
        {
            rdIdx[routeDefs[i].fileId].push_back( i ); // B6.3
        }
    }
    for( std::uint32_t i = 0; i < routeUses.size(); ++i )
    {
        if( routeUses[i].fileId < F )
        {
            ruIdx[routeUses[i].fileId].push_back( i ); // B6.3
        }
    }

    // This header field is no longer the racy-rule reference — loadCache now derives that from
    // a fresh stat() of the cache file itself (same clock+granularity domain as the per-file mtimes it's
    // compared against; see loadCache's blobWriteNsOut comment for why the wall-clock-vs-stat comparison
    // this used to feed was a tautology on coarse-mtime filesystems). Kept written, at the same wire offset,
    // purely as a diagnostic "when was this blob generated" stamp — changing/removing it would bump
    // kCacheVersion for no behavioral gain.
    const long long blobWriteNs = wallClockNs();

    ByteW w;
    // A1 (team-index): kArtifactArch byte sits in the header right after parserVer so loadCache's guard
    // rejects a foreign-arch (endian/pointer-width) blob before trusting any raw-int record bytes.
    w.u32( kCacheMagic );
    w.u32( kCacheVersion );
    w.u32( parserVerFor( captureValueUses ) );
    w.u8( kArtifactArch );
    w.u64( (std::uint64_t)blobWriteNs );
    w.u32( std::uint32_t( F ) );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: serialize records" );
        std::vector<std::uint64_t> fileDict;                                   // per-file subtoken dictionary, reused across files
        std::vector<LexPair>       mergeA, mergeB;                             // ping-pong buffers of the balanced run-merge, reused
        std::vector<std::size_t>   runOffsets, nextRunOffsets;                 // sorted-run bounds inside the ping-pong buffer
        std::vector<std::uint32_t> pairDictIndex;                              // pair slot → dict index, in def-row order
        for( std::uint32_t f = 0; f < F; ++f )
        {
            w.str( relForHash( files[f], rootDir ) );
            w.u64( f < fileHash.size() ? fileHash[f] : 0 );
            w.u64( f < fileSize.size() ? (std::uint64_t)fileSize[f] : (std::uint64_t)-1 ); // A4-P7 stat-gate: size at hash time (-1 ⇒ unknown → gate re-hashes)
            w.u64( f < fileMtime.size() ? (std::uint64_t)fileMtime[f] : (std::uint64_t)-1 ); // A4-P7 stat-gate: mtimeNs at hash time (-1 ⇒ unknown)
            w.u64( f < fileCtime.size() ? (std::uint64_t)fileCtime[f] : (std::uint64_t)-1 ); // v14 stat-gate: ctimeNs at hash time (-1 ⇒ unknown → gate re-hashes)
            {
                // §L1 (v13): parse health, at a FIXED wire offset right after the stat-gate pair. An
                // out-of-range f writes the default (fileBytes 0), which the reader already means as
                // NOT MEASURED — no sentinel of its own, and no way to mistake it for "clean".
                const FileHealth fh = f < fileHealth.size() ? fileHealth[f] : FileHealth{};
                w.u32( fh.errNodes );  w.u32( fh.errBytes );  w.u32( fh.fileBytes );  w.u32( fh.wsBytes );
            }
            if( captureValueUses )
            {
                // H3 (v10): the sorted union of this file's def rows — subtokens repeat heavily across a
                // file's defs (nested spans re-tokenize the same text), so hoisting each distinct hash into
                // ONE per-file dictionary and storing narrow indices per row shrinks the rich blob's
                // postings from 12 B/pair to ~dictShare×8 + idxWidth + tfWidth bytes. Every row is ALREADY
                // sorted (lexindex.h buildDefLexStats), so the dict is a BALANCED PAIRWISE MERGE over the
                // rows (P·log2(rows) sequential std::merge steps — measured cheaper than both a flat
                // O(P log P) sort and a per-element k-way heap), and the final merged (hash, slot) order
                // assigns every row position's dict index in one walk. Deterministic: equal hashes all land
                // on the same dict entry regardless of slot order. This is the --index-out / prime hot path.
                fileDict.clear();
                mergeA.clear();
                runOffsets.clear();
                runOffsets.push_back( 0 );
                std::uint32_t slotCount = 0;
                for( const std::uint32_t i : dIdx[f] )
                {
                    const std::vector<std::uint64_t>& row = defs[i].lex.tokenHashes;
                    for( const std::uint64_t hash : row )
                    {
                        mergeA.push_back( LexPair{ hash, slotCount++ } );   // braced, not emplace_back( a, b ): aggregate emplace needs P0960, absent in Clang < 20 (CI's Xcode 15.4)
                    }
                    if( !row.empty() )
                    {
                        runOffsets.push_back( mergeA.size() );
                    }
                }
                std::vector<LexPair>* src = &mergeA;
                std::vector<LexPair>* dst = &mergeB;
                while( runOffsets.size() > 2 ) // > 1 run left → one merge pass
                {
                    dst->resize( src->size() ); // exact pass size — merges write via raw pointers,
                    nextRunOffsets.clear(); //   no per-element back_inserter capacity branch
                    nextRunOffsets.push_back( 0 );
                    LexPair* writeCursor = dst->data();
                    for( std::size_t runIndex = 0; runIndex + 1 < runOffsets.size(); runIndex += 2 )
                    {
                        const std::size_t lo = runOffsets[runIndex];
                        const std::size_t mid = runOffsets[runIndex + 1];
                        if( runIndex + 2 < runOffsets.size() ) // a full pair of runs → merge them
                        {
                            const std::size_t hi = runOffsets[runIndex + 2];
                            writeCursor = std::merge( src->data() + lo, src->data() + mid, src->data() + mid, src->data() + hi, writeCursor );
                        }
                        else // odd tail run: carry over
                        {
                            std::memcpy( writeCursor, src->data() + lo, ( mid - lo ) * sizeof( LexPair ) );
                            writeCursor += mid - lo;
                        }
                        nextRunOffsets.push_back( std::size_t( writeCursor - dst->data() ) );
                    }
                    runOffsets.swap( nextRunOffsets );
                    std::swap( src, dst );
                }
                pairDictIndex.resize( slotCount );
                for( const auto& [hash, slot] : *src )
                {
                    if( fileDict.empty() || fileDict.back() != hash )
                    {
                        fileDict.push_back( hash );
                    }
                    pairDictIndex[slot] = std::uint32_t( fileDict.size() - 1 );
                }
                w.u32( std::uint32_t( fileDict.size() ) );
                w.raw( fileDict.data(), fileDict.size() * sizeof( std::uint64_t ) );
            }
            w.u32( std::uint32_t( dIdx[f].size() ) );
            {
                std::size_t rowOffset = 0; // running slot offset into pairDictIndex
                for( std::uint32_t i : dIdx[f] )
                {
                    writeDef( w, defs[i], captureValueUses, fileDict.size(), pairDictIndex.data() + rowOffset );
                    if( captureValueUses )
                    {
                        rowOffset += defs[i].lex.tokenHashes.size();
                    }
                }
            }
            w.u32( std::uint32_t( rIdx[f].size() ) );
            for( std::uint32_t i : rIdx[f] )
            {
                writeRef( w, refs[i] );
            }
            w.u32( std::uint32_t( iIdx[f].size() ) );
            for( std::uint32_t i : iIdx[f] )
            {
                w.u8( incs[i].isAngle ? 1 : 0 );
                w.u8( incs[i].isLazy  ? 1 : 0 );
                w.str( incs[i].target );
            }
            w.u32( std::uint32_t( bIdx[f].size() ) );
            for( std::uint32_t i : bIdx[f] )
            {
                writeBind( w, binds[i] );
            }
            w.u32( std::uint32_t( aIdx[f].size() ) );
            for( std::uint32_t i : aIdx[f] )
            {
                writeFfi( w, ffis[i] );
            }
            w.u32( std::uint32_t( rdIdx[f].size() ) );
            for( std::uint32_t i : rdIdx[f] )
            {
                writeRouteDef( w, routeDefs[i] ); // B6.3
            }
            w.u32( std::uint32_t( ruIdx[f].size() ) );
            for( std::uint32_t i : ruIdx[f] )
            {
                writeRouteUse( w, routeUses[i] ); // B6.3
            }
        }
    }   // symmetric bare scope: serialize-records profiling span

    // BONUS (S): append the whole-payload checksum so loadCache can catch a silent bit-flip inside a cached
    // string (the length/version guards trust the bytes; a flip there survives them). 8-byte trailer, verified
    // at load. blobChecksum is the fast 8-lane FNV variant — cheap even on a multi-MB blob.
    std::uint64_t sum = 0;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: checksum" );
        sum = blobChecksum( std::string_view( w.b.data(), w.b.size() ) );
    }
    w.u64( sum );
    PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: write + rename" );

    // unique per-process temp so two concurrent runs (this repo runs ~20 parallel sessions) don't
    // interleave writes into ONE shared "path.tmp" and rename a torn file. rename(2) is atomic; the
    // per-pid temp makes each writer's bytes whole → last-writer-wins, never a corrupt cache.
    //
    // A3-F9: fwrite/fclose were never checked, so an ENOSPC (or any short write) produced a truncated
    // temp file that still got rename()'d over the previous GOOD cache — silently destroying it (the
    // checksum trailer self-heals on next load via a full reparse, so this was perf-only, but a good
    // cache should never be clobbered without a peep). Mirrors mcpedit::atomicWrite's discipline
    // (src/mcp.h): check the write byte-count AND fclose's return, and on any failure unlink the temp
    // and leave the prior on-disk cache (if any) untouched.
    const std::string tmp = path + "." + std::to_string( getpid() ) + ".tmp";
    std::FILE* fp = std::fopen( tmp.c_str(), "wb" );
    if( !fp )
    {
        DEGRADED_PATH_ALERT( "ingest: saveCache could not open temp file for write — cache left unchanged" );
        return;
    }
    const std::size_t wrote = std::fwrite( w.b.data(), 1, w.b.size(), fp );
    const bool wErr = wrote != w.b.size() || std::fclose( fp ) != 0;
    if( wErr )
    {
        std::remove( tmp.c_str() );   // never rename a short/torn write over a good cache
        DEGRADED_PATH_ALERT( "ingest: saveCache write failed (short write or fclose error) — old cache preserved" );
        return;
    }
    if( std::rename( tmp.c_str(), path.c_str() ) != 0 )
    {
        std::remove( tmp.c_str() );   // clean up on failure
        DEGRADED_PATH_ALERT( "ingest: saveCache rename(tmp -> cache) failed — old cache preserved" );
        return;
    }

    // A5 (cache-dir hygiene): --doctor measured ~11,914 ripwire-* blobs / 2.4 GB accumulating in the cache-ladder
    // dir because only the qsnap/qheadsnap families ever evicted — this main parse-cache family (this very
    // `path`) never did. Best-effort, silent, at most once per process (see sweepStaleCacheBlobsOnce for the
    // policy + the concurrency-safety argument). `path` is the blob we just rename()'d into place, so it is
    // always the retained "keepPath" even if it happens to be the oldest survivor by mtime granularity.
    quality::sweepStaleCacheBlobsOnce( quality::cacheDirLadder(), path );
}
}   // namespace — ingest_cache.h section of ingest.cpp

}   // namespace rw
