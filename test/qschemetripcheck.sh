#!/usr/bin/env bash
# qschemetripcheck.sh — the F2/X4 SCHEME-BUMP TRIPWIRE. B10.1a (ffcc618) changed the SEMANTICS of a
# cached quality Snapshot's dead set (added `isTestScriptPath` to `isDeadCandidate`) WITHOUT bumping
# `kQSnapCacheScheme` — the exact determinism hole that constant's own comment exists to prevent (a pre-fix
# blob served to a post-fix binary answers with the OLD, narrower dead-set semantics). This gate is a
# deliberately noisy CHANGE-DETECTOR, not a correctness check: it hashes the concatenated source text of the
# small manifest of "what a cached Snapshot means" functions listed in the comment block right above
# `kQSnapCacheScheme` in src/quality.h, and compares against a pinned hash committed beside it
# (test/qschemetrip.hash). The manifest is read straight out of that comment (one place, no drift between the
# doc and this gate) — see quality.h's "TRIPWIRE (test/qschemetripcheck.sh)" paragraph to grow/shrink it.
#
# A mismatch means the concatenated text of isDeadCandidate / isFixturePath / isTestScriptPath /
# serializeSnapshot / deserializeSnapshot / computeSnapshot changed since the hash was last pinned. Answer,
# in the SAME diff that touched one of those functions:
#   - did the SEMANTICS of what a cached Snapshot represents change (what counts as dead, what a clone
#     group's identity is, the on-disk blob shape)? → bump kQSnapCacheScheme in src/quality.h, THEN re-pin.
#   - refactor-only (rename/reflow/comment edit, no behavior change)? → just re-pin.
# Re-pin:  UPDATE_GOLDEN=1 test/qschemetripcheck.sh
#
#
# r27 P0.2 — THE EXTRACTION SIDE. Until now this gate hashed six quality.h functions and NEVER looked at
# ingest.cpp, and that blind spot is exactly why the qsnap cache shipped un-keyed on the parser version:
# 28c7d32 bumped `kParserVer` 28 -> 30 (correcting 80 wrong canonical ids) and nothing here noticed, because
# nothing here was watching the file where a cached Snapshot's MEANING actually comes from. A Snapshot's whole
# contents are a function of tree-sitter extraction, so ingest.cpp's `kCacheVersion`/`kParserVer` declarations
# are now part of the hashed manifest: bumping either trips this gate, whose answer is "update quality.h's
# kIngest*Mirror constants in the SAME diff, then re-pin". `test/qextractionkeycheck.sh` asserts the resulting
# equality; this gate is what makes you look.
#
# This is a pure source-text check — it does not build or run the ripwire binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="$ROOT/src/quality.h"
ING="$ROOT/src/ingest_cache.h"   # extraction-identity constants moved here (2026-08-29 ingest.cpp section split); the hashed CONCAT label keeps its historical spelling so the pin holds
PIN="$ROOT/test/qschemetrip.hash"
# RE-PIN LOG (the pin is a bare hash, so its justification has to live here).
# 2026-09-11, RUBY ARGUMENT + RESCUE CONSTANTS (feat/ruby-argument-rescue-constants, PR #139): RE-PIN ONLY, kQSnapCacheScheme STAYS 10.
#   Both extraction-identity lines moved: kParserVer 92 -> 93 (a constant argument of a call/super/yield and a rescue
#   class are symbolic Include records; an older blob lacks them, so the parser version is what rejects it) and
#   kCacheVersion 20 -> 21 (Include gains `bool isValueUse`, a fourth u8 in the record — the origin bit the call
#   narrow skips; a FORMAT change). kIngestParserVerMirror 93 and kIngestCacheVersionMirror 21 in the same diff,
#   test/qextractionkeycheck.sh green. RE-DERIVED ON THE MERGE with main 40a1895b (the branch's pre-merge pin
#   hashed 89 over 18). The twelve manifest functions are byte-identical; no snapshot field changed shape.
# 2026-09-11, YAML UNSIGNED CHAR (fix/yaml-scanner-unsigned-char-2026-09-11, PR #140; test/vendorpatchcheck.sh arm K):
#   kParserVer 91 -> 92 and kIngestParserVerMirror -> 92, kCacheVersion STAYS 20 and kQSnapCacheScheme STAYS 10.
#   EXTRACTION identity, and the only kind this repo cannot see from its own CI: vendor patch
#   yaml/003-scan-status-enum gives tree-sitter-yaml's scan status a real enum type instead of returning SCN_FAIL
#   (-1) through plain `char`. Where `char` is UNSIGNED — aarch64 Linux, which is where the linux-arm64 release
#   asset is built — that -1 came back as 255 and no `case SCN_FAIL:` matched it, so a malformed %-escape in a tag
#   parsed as a clean tagged scalar there and as ERROR everywhere else. The patch makes the unsigned-`char` build
#   agree with the signed one, which is byte-identical HERE and a changed parse THERE; kArtifactArch cannot tell an
#   aarch64 blob from an x86-64 one, so only this version can reject a blob the pre-patch unsigned-`char` binary
#   wrote. No Snapshot-side function changed and record SHAPES are untouched. RE-DERIVED ON THE MERGE with main
#   1ad9184a, not carried: the lane's pre-merge tree hashed 88 over kCacheVersion 18 and main's pin hashes 91 over
#   20, so neither side hashed the merged 92/20 declaration lines.
# 2026-09-11, KOTLIN (test/kotlincheck.sh, PR #126): kParserVer 90 -> 91 and kIngestParserVerMirror -> 91, as the
#   contributor's head 1e21943a carries them. Main stands at 90 since #135, so 91 is also the land-time
#   value. A 24th grammar joins kLangTable (.kt), so the crawl admits files it previously refused and only the
#   header version can reject a v90 blob. The port also widens ingest_sidecap.h's positional body fallback and adds
#   Kotlin's scope walker, countParams and complexity arms; its vendor patch kotlin/002 changes a real parse; and the
#   maintainer round refuses a .kt file whose string templates nest past kMaxKotlinStringNestDepth before the parse.
#   All of that is extraction identity for .kt only. Record SHAPES are unchanged (a refused file's record is written
#   UNKNOWN with the existing encoding), so this lane leaves kCacheVersion at #135's 20. No Snapshot-side function changed and
#   kQSnapCacheScheme stays 10. RE-PINNED ON THE MERGED TREE, carried from neither side: main's #132 pin predates
#   this lane's constants, and the PR's pin predates #132's readRegisterMacrosConfig move. RE-DERIVED AGAIN on the
#   merge with main 1187b7f3 (#135): the lane's pin (957701449b76...) hashed 91 over kCacheVersion 18 and #135's
#   (d8dcd5c0b3f9...) hashed 90 over 20, so neither hashed the merged 91/20 declaration lines.
# 2026-09-11, EXTENT HONESTY + MEMBER-MACRO RE-PARSE (fix/cpp-macro-member-reparse-2026-09-11; test/extentcheck.sh,
#   test/macroreparsecheck.sh): kParserVer 88 -> 89 -> 90 and kCacheVersion 18 -> 19 -> 20, with
#   kIngestParserVerMirror / kIngestCacheVersionMirror moved in the same commits. Both are EXTRACTION identity:
#   89 gives every def record the RawDef::recovered u8; 90 extracts a C-family file whose first parse holds error
#   bytes from a re-parse with its semicolon-less member macro invocations blanked, and the FILE record grows
#   FileHealth::macroBlanked. Only the hashed ingest_cache.h declaration lines moved; quality.h's one hunk is the
#   mirror block, outside every manifest function. kQSnapCacheScheme STAYS 10: the mirrors already key each qsnap
#   blob on the extraction behind it, and what a cached Snapshot MEANS is untouched. RE-DERIVED ON THE MERGE with
#   main 096e3544, not carried: the lane's pin (e1e921ca, over 5afadeca) lacked #132's readRegisterMacrosConfig
#   read below, and #132's pin (e005aacc) lacked these version lines, so neither side hashed the merged manifest.
# 2026-09-11, OUT-PARAM RETURNS (lane/outparam-returns-2026-09-11, PR #132): RE-PIN ONLY, kQSnapCacheScheme STAYS 10.
#   One manifest function's SOURCE moved, and only its read. Because readWholeFile returns
#   std::optional<std::string> now, readRegisterMacrosConfig went from
#     if( !docparse::detail::readWholeFile( configPath( root ), text ) || text.empty() )
#   to
#     const std::string text = docparse::detail::readWholeFile( configPath( root ) ).value_or( std::string() );
#     if( text.empty() )
#   Absent, unreadable and empty still all return the inert config. The other eleven manifest functions, and
#   the ingest_cache.h / gitmine.h identity lines, are byte-identical, checked function by function with this
#   gate's own extract_fn. End to end, as the entries below settle it: --quality-baseline written by the
#   pre-change binary (5afadeca) and by this one, on the same corpus, is BYTE-IDENTICAL, 2,454 B on
#   test/fixture and 969,627 B on the real src/ tree. Refactor-only arm: re-pin, do not bump the scheme.
# 2026-09-10, DART (test/dartcheck.sh): kParserVer 87 -> 88 and kIngestParserVerMirror -> 88. A 23rd
#   grammar joins kLangTable, so the CRAWL ADMITS FILES IT PREVIOUSLY REFUSED: a v87 blob's file list has
#   no record for the `.dart` it never saw, the file is ABSENT rather than stale, and only the header
#   version can reject the blob — the same class as the plain-text prose tier below. The commit also
#   extends the definition SPAN for Dart only (dartFollowingBody, adopted in ingest_sidecap.h) and adds
#   formal_parameter_list to cc_isParamList; both are extraction identity, which is exactly what parserVer
#   covers, and every other language is byte-identical (verified against the pre-change binary on src/ and
#   on a 1 406-file multi-language corpus). Record SHAPES are unchanged, so kCacheVersion stays 18. No
#   Snapshot-side function changed and kQSnapCacheScheme stays 8: what a cached Snapshot MEANS is
#   untouched — the corpus it is computed over is what grew. RE-ANSWERED TWICE on the landing rebase: the
#   branch was written against 81 -> 82, and 87 (below) was taken by the markdown-saturation lane while
#   this PR was open — the kParserVer DECLARATION auto-merged clean at that same wrong 87 and only the
#   comment conflicted, which is why the number is re-derived from main rather than carried.
# 2026-09-10, MARKDOWN COUNTER SATURATION (test/vendorpatchcheck.sh arm I,
#   third_party/patches/markdown/002-counter-saturate): kParserVer 86 -> 87 and
#   kIngestParserVerMirror -> 87. A uint8_t counter in four vendored external scanners overflowed past 255 —
#   a hard abort under G1's -fno-sanitize-recover=all (rc=134), found on rails/guides/source/
#   getting_started.md, a pipe-table row padded to 301 columns; 64 tabs also suffice, since advance()
#   charges a tab at tab stop 4. Only ONE of the two remedies in that lane moves extraction. markdown's
#   indentation counters AND its fence `level` SATURATE, because both are read by ordering tests against a
#   FIXED threshold (`>= 4` indented chunk, `< 4` thematic break, `< list_item_indentation` max 17; `>= 3`
#   before a fence may open) and 255 answers each exactly as any larger true value would. Wrapping inverted
#   those predicates inside a narrow window: measured N=255 correct, N=256/257 WRONG at exit 0, N=300 correct
#   again by luck — at 256 an indented code block parsed as a heading and a fence never opened, leaking its
#   body out as live markdown, both minting phantom symbols. The rust/lua/csharp siblings take an explicit
#   CAST instead: those counters close a token by matching the opening count, saturation is not more correct
#   there, and measurement found no extraction difference at any width (255/256/257/300), so the cast half
#   contributes NOTHING to this bump. Measured both ways rather than assumed: map output is byte-identical
#   over 3 538 real files, and a constructed 256-column ATX line changes from n="BuriedHeading" emitted to
#   absent. Record shapes unchanged, kCacheVersion stays 18. No Snapshot-side function changed and
#   kQSnapCacheScheme stays 8: what a cached Snapshot MEANS is untouched.
#   RE-DERIVED OVER main's OWN RE-PIN, not carried over: this lane landed on top of the printf-family
#   -> std::print conversion, which had itself re-pinned this hash for a source-text move in
#   bodyHashesBySym. Both sides of that conflict were stale — main's value predates kParserVer 87 and
#   this lane's predates the conversion — so the correct hash exists only on the MERGED tree and was
#   regenerated there with UPDATE_GOLDEN=1. Taking either side would have pinned a hash no tree has.
# 2026-09-09, REBASED onto main c38d3eea (parser 85, text-docs tier): the entry below is RE-ANSWERED
#   against THAT tree rather than carried over — --quality-baseline written by main's own binary and by
#   this lane's, on the same corpus, is BYTE-IDENTICAL at 930,546 B. So the conversion is still the
#   refactor-only arm on the new base and kQSnapCacheScheme still stays 8.
# 2026-09-09, PRINTF-FAMILY -> std::print (lane/stdprint-conversion): RE-PIN ONLY, kQSnapCacheScheme STAYS 8.
#   One manifest function's SOURCE moved: bodyHashesBySym's hex fold went
#     std::snprintf( b, sizeof( b ), "%016llx", ... )  ->  rw::formatTo( b, sizeof( b ), "{:016x}", ... )
#   That string is concatenated into `joined` and fed to fnv1a64, so it IS the body hash a snapshot stores,
#   and a byte moving there would silently repartition clone groups and the dead set. It does not move:
#   %016llx and {:016x} were proven byte-identical over 0, 1, 255, 4886718345 and UINT64_MAX before the
#   conversion, and the END-TO-END check is what settles it — --quality-baseline written by the
#   pre-conversion binary and by this one, on the same corpus, is BYTE-IDENTICAL: 2,388 B on test/fixture
#   and 924,402 B on the real src/ tree. Nothing a Snapshot means has changed, so this is the
#   refactor-only arm of this gate's own instructions: re-pin, do not bump the scheme.
#   RE-PINNED AGAIN in the same lane (the whitespace pass): the converter had left a double space before
#   the closing paren, and collapsing it touched bodyHashesBySym's line a second time. Same answer, re-run
#   rather than assumed — the --quality-baseline blobs are byte-identical again (924,394 B on src/), so it
#   is still the refactor-only arm and the scheme still stays 8. Lesson for the next conversion: re-pin a
#   source-text tripwire ONCE, at the end of the lane, after formatting has settled.
#   (Note for the next reader: the manifest is TWELVE functions, not the six the family is often described
#   by — topLevelCalleeNameHashes, bodyHashesBySym, readRegisterMacrosConfig, registeredMacroNames,
#   startsWithRegisteredMacro and registeredMacroSymbolIds are in it too, and bodyHashesBySym is the one a
#   formatting change can reach.)
# 2026-09-09, PLAIN-TEXT PROSE TIER (test/textdocscheck.sh): kParserVer 84 -> 85 and
#   kIngestParserVerMirror -> 85. `.rst`/`.adoc`/`.org`/`.mdx` join kLangTable on Lang::Markdown and the
#   markdown BLOCK grammar, so the CRAWL ADMITS FILES IT PREVIOUSLY REFUSED. That is the one class of
#   extraction change a per-file stat gate cannot self-heal — a v84 blob's file list has no record for the
#   `.rst` it never saw, so the file is ABSENT rather than stale and only the header version can reject the
#   blob. Record shapes are unchanged (a markdown file's records already existed), so kCacheVersion stays
#   18. No Snapshot-side function changed and kQSnapCacheScheme stays 8: what a cached Snapshot MEANS is
#   untouched — the corpus it is computed over is what grew.
# 2026-09-07, ES DEFAULT IMPORTS (test/lib/jsdefaultimport.sh): kParserVer and its quality mirror
#   move 81 -> 82 for default import/export facts. Record layouts and Snapshot-side functions are
#   unchanged: kCacheVersion stays 16 and kQSnapCacheScheme stays 8.
# 2026-09-07, FOUR-LANGUAGE IMPORTS (test/bashsourcecheck.sh, test/luarequirecheck.sh,
#   test/rubyrequirecheck.sh, test/eliximportcheck.sh, test/deplangscheck.sh): kParserVer 80 -> 81 and
#   kIngestParserVerMirror -> 81. Bash `source`/`.`, Lua `require`, Ruby `require`/`require_relative`/
#   `load` and Elixir `alias`/`import`/`require`/`use` become Include records — four languages that
#   emitted NO Include record on ANY tree now emit one per directive, so a v80 blob on a tree holding any
#   of them carries an EMPTY include list where a real one exists and must be rejected. Include's RECORD
#   SHAPE is unchanged (same four fields), so kCacheVersion stays 16 — the 38/39 precedent, where the
#   extracted SET grew and only parserVer moved. No Snapshot-side function changed, kQSnapCacheScheme
#   stays 8. The same commit flips lintrules.h::dependencyCapable for those four languages, which moves
#   dep_files=/ccd/acd/nccd and --arch's propagation_cost on any corpus holding them; that is disclosed in
#   the output itself as <health dep_langs=> rather than only here.
# 2026-09-09, RUBY RECEIVER DEDUPE + DEEP CHAIN (test/rubyrecvcheck.sh): kParserVer 85 -> 86 and
#   kIngestParserVerMirror -> 86. A receiver's lazy bit is now the AND over its occurrences (a method-body site
#   above a class-body site used to leave the directive lazy, and the structure lost the load-time edge), and
#   the constant-chain check is a loop (a 5000-segment chain overflowed a worker stack). Record shape and
#   kCacheVersion (18) unchanged — cached Ruby files re-parse; no serialize/deserialize/computeSnapshot change.
#   RE-BUMPED from 85 on landing: main had already spent 85 on the plain-text prose tier (test/textdocscheck.sh),
#   per the collision rule in ingest_cache.h's kParserVer note.
# 2026-09-08, RUBY CONSTANT RECEIVERS (test/rubyrecvcheck.sh): kParserVer 82 -> 83 and kIngestParserVerMirror
#   -> 83. A constant RECEIVER (`User.find`, `App::Mailer.deliver`) is a symbolic Include, one per (file,
#   innermost open, written name), lazy inside a closure; the Ruby walk descends every node. The record shape
#   and kCacheVersion (17) are unchanged — only the extraction identity moved, so cached Ruby files re-parse.
#   No serialize/deserialize/computeSnapshot function changed.
# 2026-09-07, RUBY SCOPE + SETTERS (PR #47 rebased onto the langs integration branch,
#   test/rubyscopecheck.sh, test/rubysettercheck.sh): kParserVer 79 -> 80 and kIngestParserVerMirror -> 80,
#   landing ON TOP of the Elixir (78) and ES-import (79) bumps above. Two Ruby extraction FACTS moved:
#   (a) every Ruby def now records its enclosing class/module as `scope` (rubyEnclosingScopeOf), so Ruby
#   rows gain id= and same-named methods in different classes stop folding into one overloads= row;
#   (b) queries/ruby/tags.scm accepts the (setter) node, so `def name=` is indexed, and a call captured as
#   the `left:` of an (assignment) is renamed `name=` so a WRITE stops edging the getter. The fork branch
#   carried 79 with the usual "skip the rich family" rationale refuted above; on the merged tree 79 was
#   already taken by the ES-import bump, so the next free number over the tip is 80 — the RE-BUMP rule in
#   ingest_cache.h's kParserVer note, applied for the third time this day. Record shapes unchanged, so
#   kCacheVersion stays 16; no Snapshot-side function changed, kQSnapCacheScheme stays 8.
# 2026-09-07, ELIXIR (test/elixircheck.sh): kParserVer 77 -> 78 and kIngestParserVerMirror -> 78 for the
#   new grammar (.ex/.exs), its definition/call capture filters and its metrics. The fork proposed 83,
#   reasoning that 78 must be skipped as "77's rich value"; it must not be. parserVerFor() derives the rich
#   family as kParserVer+1, but the two families live in SEPARATE cache FILES (main.cpp A4-P4 suffixes the
#   blob name with the class), so a lean-78 blob can never be served to a rich-77 reader. The project's own
#   history is the proof: 74 -> 75 -> 76 -> 77 are four consecutive +1 bumps, each logged below. Rebasing a
#   fork's parser version onto main means RE-BUMPING to the next free number over main's (the rule in
#   ingest_cache.h's kParserVer note), which is 78 — never keeping the fork's development value.
#   Extraction identity invalidates snapshots; no Snapshot-side semantics changed, scheme stays 8.
# 2026-09-07, ES NAMED IMPORTS (PR #45 + its review fixes, test/lib/jsimportalias.sh, test/lib/jsimportfacts.sh):
#   kParserVer 78 -> 79 and kCacheVersion 15 -> 16, landing ON TOP of the Elixir bump above. The change adds
#   three JS/TS ingest FACTS — a named ES import records local name + module + exported name
#   (LocalBindKind::JsImport, RawBind gains `importedName`, so the cache RECORD FORMAT moved and
#   kCacheVersion had to move with it), a direct exported declaration records JsExport, and a declaration
#   shadowing an import records JsShadow — and widens JsExport to the CLAUSE forms `export { f }` /
#   `export { f as g }` (JsExport's `importedName` carries the local name the exported spelling binds);
#   re-export and default clauses are deliberately still not recorded. The fork branch carried 79 -> 80 with
#   the same "skip the rich family" rationale refuted above; on the merged tree the next free number over
#   Elixir's 78 is 79, so that is what landed. quality.h's kIngestCacheVersionMirror / kIngestParserVerMirror
#   were bumped to 16 / 79 in the same diff (qextractionkeycheck), no Snapshot-side function changed,
#   kQSnapCacheScheme stays 8.
# 2026-09-03, PHASE 5 — the external-name veto + the receiver MRO walk (test/externalvetocheck.sh, test/mrowalkcheck.sh,
#   docs/EVALS.md "Phase 5"): kParserVer 76 -> 77 — three Python ingest FACTS moved: a `super()` call receiver
#   classifies the new RecvKind::SuperObj (appended) instead of None; every import statement records the NAMES it
#   binds as file-scope LocalBindKind::Import RawBinds (appended kind, ingest_relations.h::capturePythonImportBinds);
#   and a member access whose receiver is too rich to classify stamps FieldOfVar with an empty recvVar on CALL refs
#   (was None — read as a bare call by every bare-name guard). quality.h's kIngestParserVerMirror was bumped to 77
#   in the same diff (qextractionkeycheck), no Snapshot-side function changed, kQSnapCacheScheme stays 8.
# 2026-09-03, PHASE 4b — Rule 2c, the class-name receiver route (test/clsrecvcheck.sh, docs/EVALS.md "Phase 4b"):
#   kParserVer 75 -> 76 — a Python function DEFINITION's parameter NAMES are now recorded as EMPTY-SPAN VarDecl
#   bindings (ingest_binds.h::capturePythonParamShadowDecls), the shadow-veto evidence Rules 2b/2c share; every
#   Python file's binding FACTS change, so the ingest.cpp-side extraction-identity line moved. quality.h's
#   kIngestParserVerMirror was bumped to 76 in the same diff (qextractionkeycheck), no Snapshot-side function
#   changed, kQSnapCacheScheme stays 8.
# 2026-09-02, THE MEMBER-VARIABLE ROUND (card A3, test/fieldusescheck.sh): kParserVer 74 -> 75 — a new
#   SymKind::Field (C/C++ non-static field_declaration, Python self.x / annotated class attribute) plus the
#   value-use visitor's member-access capture change every C-family and Python file's def and ref FACTS. The
#   ingest.cpp-side extraction-identity line moved, quality.h's kIngestParserVerMirror was bumped to 75 in the
#   same diff (qextractionkeycheck), no Snapshot-side function changed, kQSnapCacheScheme stays 8.
# 2026-08-25, THE SCOPE-LESS QUALITY-KEY FOLD (test/qualitykeycheck.sh, scopeless-fold lane): the KEY
#   SPACE of every per-symbol map in a Snapshot moved. ccx/loc/nest/params/defs/mask/dead/api were keyed
#   by `fnv1a64( baselineCanonId(...) )`, which inherits resolve.h::canonicalId's bare-name degrade and
#   therefore folded every scope-less symbol across files into ONE identity (measured on this repo:
#   6,418 scope-less rows collapsing to 3,845 identities, and a ccx 1->18 regression reported as
#   nothing). They key on pathQualifiedKey now, via the new quality.h::qualityKey. This IS a
#   Snapshot-SEMANTICS change of the purest kind — a v6 blob's keys are computed from a different byte
#   string, so serving one to this binary makes every symbol read as absent from the baseline and the
#   whole tree report as new debt — so kQSnapCacheScheme DID move, 6 -> 7, in the same diff, and the
#   .ripwire_quality_baseline header moved v3 -> v4 with a READ-SIDE REFUSAL of anything older.
#   computeSnapshot's text changed (one line, the key derivation); errorMaskCountsBySym moved above
#   pathQualifiedKey's new position so it can call it. No extraction change: kParserVer and the
#   quality.h mirrors deliberately did NOT move.
# 2026-08-25, NESTED QUALIFIED CLASS/STRUCT EXTRACTION (test/nestedqualcheck.sh, candhead-ugrep lane,
#   N11/N12): kParserVer 72 -> 73 and the quality.h mirror with it, in the same diff. queries/cpp/
#   tags.scm gains a class_specifier/struct_specifier `name: (qualified_identifier)` pattern — the
#   class-level twin of the out-of-line METHOD pattern already there — so an out-of-line, qualified
#   nested class definition (`class Outer::Inner : Base { ... };`) now mints its own symbol instead of
#   being silently dropped at extraction. The extracted SET grows on any C++ tree using the Pimpl
#   idiom, so v72 blobs must be rejected. An EXTRACTION change, not a Snapshot-SEMANTICS change (none
#   of isDeadCandidate/isFixturePath/isTestScriptPath/serializeSnapshot/deserializeSnapshot/
#   computeSnapshot's logic moved), so kQSnapCacheScheme deliberately did NOT move.
# 2026-08-12, MARKDOWN SECTION TIER (test/mdsectioncheck.sh): kParserVer 62 -> 63 and the quality.h
#   mirror with it, in the same diff. .md/.markdown now parse with the vendored tree-sitter-markdown
#   block grammar: headings (ATX + setext) become sections with REAL SPANS (heading -> next same-or-
#   higher heading), parent-heading scopes, and link/mention edges; html-block phantom headings vanish
#   and .markdown joins the extension table. The extracted SET and every section's span/bodyByte
#   change on any md-bearing tree, so v62 blobs must be rejected. An EXTRACTION change, not a
#   Snapshot-SEMANTICS change, so kQSnapCacheScheme deliberately did NOT move.
# 2026-08-12, MODULE-CONSTANT ROUND (test/moduleconstcheck.sh): kParserVer 61 -> 62 and the quality.h
#   mirror with it, in the same diff. C/C++ const-qualified module constants (and class-static
#   constants via the new field_declaration capture) now index CASE-BLIND — the const/constexpr/
#   constinit keyword is the evidence, closing the gap where the repo's own `constexpr std::uint32_t
#   kParserVer` was invisible to `--for`/`--uses` (the 2026-08-12 census's 21.4% constant-shaped
#   lookup family). The extracted SET grows on any C/C++ tree, so v61 blobs must be rejected. An
#   EXTRACTION change, not a Snapshot-SEMANTICS change, so kQSnapCacheScheme deliberately did NOT move.
# 2026-08-11, W1-S2 CROSS-FILE CHURN FIX: kQSnapCacheScheme 5 -> 6 (and kQBodyCacheScheme 2 -> 3, the
#   sidecar body-record tag body -> bodyq). bodyHashBySym's KEYS changed meaning — pathQualifiedKey
#   (path\0scope\0name) replaces hash(canonicalId), whose bare-name degrade folded every scope-less
#   same-named symbol ACROSS FILES into one churn-join identity (a new rows() in one file flagged
#   short-horizon-churn against the rows() in an untouched file; gate: qualitysignalcheck.sh §1d).
#   A Snapshot-SEMANTICS change (what the serialized body map's keys MEAN), so the scheme moved; and
#   bodyHashesBySym joined the hashed manifest so the next keying change trips this gate by itself.
# 2026-08-11, W1-S2 dead-code top-level fix: `isDeadCandidate` gained the top-level-invocation exemption
#   (new manifest member `topLevelCalleeNameHashes` — a symbol invoked from a FILE-SCOPE call site, e.g. a
#   bash top-level statement, is alive; buildGraph drops those refs from the CSR so zero in-edges alone was
#   false evidence). A Snapshot-SEMANTICS change (the dead set narrows) → kQSnapCacheScheme 5 -> 6 in the
#   same diff. NOT an extraction change (the refs were always captured), so kParserVer/mirrors unmoved.
# 2026-08-10/11, LANGUAGE-PORT ROUND (three stranded branches hand-ported onto main): kParserVer
#   59 -> 60 and the quality.h mirror with it. ONE shared bump covers all of it, because the four
#   extraction changes land in the same wave and no released version ever keyed a cache on a subset:
#     - PYTHON shapes (54d4507): annotated class attributes, gated enum-family members, class lambda
#       attrs, one-guard-deep + tuple-unpack module bindings, and .pyi routing.
#     - SWIFT shapes (bb78f97): enum_entry/typealias_declaration/associatedtype_declaration/
#       protocol_property_declaration + the builtin-operator-token alternation.
#     - TYPESCRIPT #private: the method/field-arrow/call-ref coverage JS already had.
#     - CUDA memory-space module bindings (5ca4a7e, cudacheck 7b close-out): the uninitialized
#       qualified-declaration patterns + cudaMemorySpaceQualifierOf.
#   Shared finalSegment() also gains the leading-'<' carve-out (a Swift operator-function name is not
#   a generic type-argument list). All EXTRACTION changes (new definition SHAPES + a shared-path fix),
#   not a Snapshot-SEMANTICS change, so kQSnapCacheScheme deliberately did NOT move.
# 2026-08-08, L3 audit (locals= per-declarator counting): kParserVer 46 -> 47 and the quality.h mirror with
#   it, because cc_countLocalDeclarators (ingest.cpp) now sums every `declarator`-fielded child of a
#   countable `declaration` node instead of the fused DFS incrementing by one per statement — a
#   comma-separated local (`int a,b,c;`) moves from locals=1 to locals=3. A VALUE change on the existing
#   `locals` u32 field (no def-record FORMAT change), so a v46 blob's locals= is provably wrong and must
#   not be re-served. An EXTRACTION change, not a Snapshot-SEMANTICS change, so kQSnapCacheScheme
#   deliberately did NOT move.
# 2026-08-07, integration/quality-fleet, third renumbering: kParserVer 45/45 -> 46. The integration line
#   had taken 45 (entry below); ev(G) independently took 45 on feat/nest-profile (its entry below — it
#   skipped 44 to dodge this exact trap, but the integration line had already spent 45). The merged
#   extraction (ppalt + nestcal clause semantics + ev/evWhy + Swift guard decision counting) matches
#   neither, fresh number, mirror moved. kQSnapCacheScheme unmoved (extraction-side only).
# 2026-08-07, integration/quality-fleet again: kParserVer 43/44 -> 45. The integration line had taken 43
#   (ppalt renumbering, entry below); nestcal r1's own lineage had reached 44 (entry below). The merged
#   extraction (ppalt + nestcal else-clause semantics) matches neither, so the merge takes a fresh number,
#   same convention as nestcal's own same-day merge. Mirror moved with it; kQSnapCacheScheme unmoved.
# 2026-08-07, integration/quality-fleet renumbering: kParserVer 42/42 -> 43 and the quality.h mirror with
#   it. Two branches independently claimed 42 (nested-closure span attribution; ppalt disclosure); the
#   integration resolves the collision to max+1 = 43 so blobs written by EITHER 42-binary are rejected —
#   the two 42s describe different def-record formats, so re-serving either under one number would be
#   wrong. EXTRACTION-side renumbering only; kQSnapCacheScheme deliberately did NOT move.
# 2026-08-07, ppalt disclosure: kParserVer 41 -> 42 and the quality.h mirror with it, because RawDef/Symbol
#   gained a `ppAlt` u16 (preproc alternative branches counted in the fused cc_walk DFS) and the def cache
#   record a u32 between locals and params — a v41 blob's records misalign, so it must not be re-served.
#   This is an EXTRACTION change, not a Snapshot-SEMANTICS change: what a cached Snapshot MEANS (dead set,
#   clone-group identity, blob shape) is untouched, so kQSnapCacheScheme deliberately did NOT move — the
#   same split as the 2026-07-31 entry below.
# 2026-08-07, nestcal r1 (bench/nestcal/r1-2026-08-07): kParserVer 42 -> 43 (cc_walk's clause branch no
#   longer double-deepens else/elif bodies; nest/humps/deep/ccx in a v42 blob are provably wrong), then
#   43 -> 44 at the same-day MERGE with the parallel deep=-clamp fix, which had independently taken 43 —
#   two DIFFERENT 43-extractions existed, so neither's caches may be served and the merge takes a fresh
#   number. Mirror moved both times. EXTRACTION changes only: what a cached Snapshot MEANS is untouched,
#   so kQSnapCacheScheme deliberately did NOT move.
# 2026-08-07, essential complexity: kParserVer 43 -> 45 (44 was taken by the sibling nesting-quirk round;
#   see ingest.cpp's own note) and the quality.h mirror with it — RawDef/Symbol gained ev/evWhy (a def-record
#   FORMAT change) and Swift guard_statement joined isDecisionType (a Swift cx VALUE change). An EXTRACTION
#   change, not a Snapshot-SEMANTICS change, so kQSnapCacheScheme deliberately did NOT move.
# 2026-07-31, H4 W2b FIXUP: kParserVer 33 -> 34 and the
#   quality.h mirror with it, because a qualified call to a `>`-family OPERATOR now re-splits on the operator
#   tail — the per-ref qualifier changes, so a v33 blob's edges are provably wrong and must not be re-served.
#   This is an EXTRACTION change, not a Snapshot-SEMANTICS change: what a cached Snapshot MEANS (dead set,
#   clone-group identity, blob shape) is untouched, so kQSnapCacheScheme deliberately did NOT move.
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$SRC" ] || { echo "no $SRC — run from the repo"; exit 2; }
[ -f "$ING" ] || { echo "no $ING — run from the repo"; exit 2; }

sha256(){
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else echo "no sha256sum/shasum available" >&2; exit 2
    fi
}

# ── manifest: read straight out of the comment block above kQSnapCacheScheme (one place, no drift) ─────────
# lines shaped "//   <fnName>            (quality.h) — ..." between the "TRIPWIRE (...)" marker and the
# constant's own declaration.
MANIFEST="$( awk '
    /TRIPWIRE \(test\/qschemetripcheck\.sh\)/ { intrip=1; next }
    intrip && /^constexpr[ \t]+std::uint32_t[ \t]+kQSnapCacheScheme/ { exit }
    intrip && /^\/\/[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+\(quality\.h\)/ {
        line=$0
        sub( /^\/\/[ \t]+/, "", line )
        n=split( line, a, /[ \t]/ )
        print a[1]
    }
' "$SRC" )"

[ -n "$MANIFEST" ] && ok "manifest read from src/quality.h's tripwire comment ($( printf '%s\n' "$MANIFEST" | grep -c . ) functions)" \
    || { no "manifest extraction found ZERO functions — the comment shape near kQSnapCacheScheme moved; fix the awk pattern or the comment"; }

# ── extract one function's full Allman-style source ( signature line(s) .. matching closing brace ) ────────
# Depth-counting starts only once a line whose TRIMMED content is exactly "{" is seen (the true Allman body
# open) — this deliberately ignores any brace pairs on the signature line itself (e.g. a `= {}` default
# argument), which would otherwise terminate the extraction after one line. A candidate match whose line ends
# in ";" (a forward declaration/prototype, e.g. computeSnapshot's own fwd decl a few hundred lines above its
# definition) is skipped — scanning continues for the real, brace-bodied definition.
extract_fn(){
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        BEGIN { capturing=0; bodyStarted=0; depth=0 }
        !capturing && $0 ~ ( "^inline[ \t].*[^A-Za-z0-9_]" fn "\\(" ) {
            probe=$0; sub( /\/\/.*/, "", probe ); gsub( /[ \t]+$/, "", probe )
            if( probe ~ /;$/ ) next                 # forward declaration/prototype — keep scanning
            capturing=1
        }
        capturing {
            print
            if( !bodyStarted )
            {
                t=$0; gsub( /^[ \t]+|[ \t]+$/, "", t )
                if( t == "{" ) { bodyStarted=1; depth=1 }
            }
            else
            {
                line=$0; o=gsub( /\{/, "{", line )
                line=$0; c=gsub( /\}/, "}", line )
                depth+=o-c
                if( depth<=0 ) { capturing=0; exit }
            }
        }
    ' "$file"
}

CONCAT=""
missing=0
for fn in $MANIFEST; do
    body="$( extract_fn "$SRC" "$fn" )"
    if [ -z "$body" ]; then
        no "manifest function '$fn' not found in src/quality.h (renamed/removed? update the manifest comment)"
        missing=1
        continue
    fi
    CONCAT="$CONCAT### $fn
$body
"
done
[ "$missing" -eq 0 ] && ok "every manifest function's source text extracted"

# ── r27 P0.2: the EXTRACTION-side manifest — ingest.cpp's two cache-identity DECLARATION LINES ─────────────
# Only the `constexpr ... = N;` line itself (comments and the long rationale blocks around them are excluded),
# so the hash moves when a VALUE moves and stays put when someone edits the prose. A trip here means: a cached
# Snapshot's meaning may have changed under you — mirror the new value into src/quality.h's
# kIngestCacheVersionMirror / kIngestParserVerMirror, then re-pin.
# (BSD sed has no BRE alternation — one pass per constant, in a fixed order so the hash is stable.)
extract_decl(){ sed -n "s/^\(constexpr[ \t][^=]*[ \t]$1[ \t]*=[ \t]*[0-9][0-9]*;\).*/\1/p" "$ING" | head -1; }
EXTRACT_DECLS="$( extract_decl kCacheVersion; extract_decl kParserVer )"
EXTRACT_N="$( printf '%s\n' "$EXTRACT_DECLS" | grep -c . )"
if [ "$EXTRACT_N" -eq 2 ]; then
    ok "ingest_cache.h extraction-identity declarations extracted (kCacheVersion + kParserVer)"
else
    no "expected 2 extraction-identity declarations in src/ingest_cache.h, found $EXTRACT_N — the constant shape moved; fix the sed pattern"
fi
CONCAT="$CONCAT### ingest.cpp extraction identity
$EXTRACT_DECLS
"

# ── H4 V1-L6: the CHURN-side identity — gitmine.h's merge-diff mode line ───────────────────────────────────
# The qchurn memo caches the OUTPUT of the git-log walks, and kMergeDiffArgs changes that stream's content
# for every merge commit — exactly the hole this gate exists to close, one file over (the H4 round shipped
# the -c change WITH a kQChurnCacheScheme bump; this arm makes forgetting that bump impossible next time).
# Declaration line only (value-sensitive, prose-insensitive), same policy as the ingest.cpp arm above.
GITM="$ROOT/src/gitmine.h"
MERGE_DECL="$( sed -n 's/^\(inline[ \t]constexpr[ \t][^=]*kMergeDiffArgs[ \t]*=[ \t]*"[^"]*";\).*/\1/p' "$GITM" | head -1 )"
if [ -n "$MERGE_DECL" ]; then
    ok "gitmine.h churn-identity declaration extracted (kMergeDiffArgs)"
else
    no "kMergeDiffArgs declaration not found in src/gitmine.h — the constant shape moved; fix the sed pattern"
fi
CONCAT="$CONCAT### gitmine.h churn identity
$MERGE_DECL
"

CURHASH="$( printf '%s' "$CONCAT" | sha256 )"

if [ ! -f "$PIN" ]; then
    if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
        printf '%s\n' "$CURHASH" > "$PIN"
        ok "pinned initial hash to test/qschemetrip.hash ($CURHASH)"
    else
        no "no pinned hash at test/qschemetrip.hash — create with UPDATE_GOLDEN=1 test/qschemetripcheck.sh"
    fi
else
    PINNED="$( tr -d ' \t\r\n' < "$PIN" )"
    if [ "$CURHASH" = "$PINNED" ]; then
        ok "manifest source hash matches the pinned hash (scheme=kQSnapCacheScheme unchanged meaning)"
    elif [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
        printf '%s\n' "$CURHASH" > "$PIN"
        ok "re-pinned test/qschemetrip.hash to $CURHASH (UPDATE_GOLDEN=1)"
    else
        no "manifest source text changed — pinned=$PINNED current=$CURHASH"
        cat <<'EOF'
        Did the SEMANTICS of what a cached Snapshot represents change (what counts as dead, a clone group's
        identity, the on-disk blob shape)?
          -> bump kQSnapCacheScheme in src/quality.h, THEN re-pin: UPDATE_GOLDEN=1 test/qschemetripcheck.sh
        Did ingest_cache.h's kCacheVersion / kParserVer move (an EXTRACTION change — every cached canonId, metric,
        body hash, clone group and dead-set entry is a function of it)?
          -> mirror the new value into src/quality.h's kIngestCacheVersionMirror / kIngestParserVerMirror in
             the SAME diff (test/qextractionkeycheck.sh asserts the equality), THEN re-pin.
        Refactor-only (rename/reflow/comment edit, no behavior change)?
          -> just re-pin:            UPDATE_GOLDEN=1 test/qschemetripcheck.sh
EOF
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
