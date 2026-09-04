#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_quality.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_quality.h — the quality family, moved VERBATIM from main.cpp in the 2026-08-29 split:
// the delta-basis plumbing (noBaselineFatalMessage, loadRefPairDelta, resolveDeltaBasis),
// runQualityDelta, runDmm, the dead-code path filters, runQualityPanel, runQualityViews and
// runEditCheck. Same contract as every verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one
// unnamed namespace, internal linkage unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// The exit-1 "nothing to compare against" wording for --quality-delta, in one place. Three cases, and the
// distinction is what the w1 verifier caught: saying "no <file>" is TRUE only in the third. A stale sidecar DID
// exist — either it was just dropped by the self-heal, or the unlink failed and it is sitting there right now —
// and `sel.isStaleFileOnDisk()` (the seam's DISK fact, never the removeStaleFile intent) picks which. The
// stale halves mirror the MCP twin's errMsg in mcpverbs.h::computeQualityDelta, per-arm verbs aside; keeping
// this out of runQualityDelta keeps three branches out of a body that is already the file's largest.
std::string noBaselineFatalMessage( const std::string& baselineFile, const rw::quality::BaselineSelection& sel )
{
    // §B12.4 (CA4): the non-stale arm named only the missing sidecar and left out the OTHER half of the
    // condition it is reporting — this message is reached only when the git-HEAD fallback was attempted and
    // ALSO came back empty. Its MCP twin (mcpverbs.h::computeQualityDelta, the "and no git HEAD to
    // auto-compare against" errMsg) has always carried both halves for the identical state, so a CLI reader
    // could not tell the fallback had even been tried and would look for a bug in the sidecar. Same two
    // clauses, same order, same verb-name spelling convention as the stale arms below.
    if( !sel.isSidecarStale() )
    {
        return "ripwire: no " + baselineFile + " and no git HEAD to auto-compare against — run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }

    return "ripwire: " + baselineFile + " was STALE (pinned at a different HEAD) and there is no current HEAD tree to fall back to — "
         + ( sel.isStaleFileOnDisk() ? "it is still on disk (could not be removed): delete it, or re-run `ripwire <dir> --quality-baseline` to re-pin it\n"
                                     : "it has been removed: re-run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n" );
}

// ── R-I: --quality-delta=A..B, the WAVE-level form ───────────────────────────────────────────────────────
//
// The state two COMMITTED trees need, with the temp-dir teardown bound to the caller's scope. Both trees stay
// alive together on purpose: computeSnapshot reads A while computeDelta reads B, and both read file bytes
// through their materialized tree, so neither guard may fire early (quality::loadRefTree's header states the
// same contract from the other side).
//
// `sameRef` is the A==B case. It is a legal question with an empty answer, and it is answered by materializing
// ONE tree and comparing it with itself rather than by a special-cased early return: the empty delta then
// falls out of the ordinary machinery instead of being asserted by a branch nobody re-tests.
struct RefPairDelta
{
    rw::quality::TmpTreeGuard baseGuard;             // declared BEFORE the trees so teardown outlives their use
    rw::quality::TmpTreeGuard targetGuard;
    rw::quality::RefTree      baseTree;
    rw::quality::RefTree      targetTree;
    bool                  sameRef = false;
    std::string           attrs;                     // XML:  ` base_ref="…" target_ref="…" churn="unavailable"`
    std::string           jsonAttrs;                 // JSON: the SAME three facts — built beside attrs so the
                                                     // two emitters cannot disclose different things
    std::string           rangeSpan;                 // R1: "<baseSha>..<targetSha>" — the range the rename
                                                     // record is read over, against the REAL repo (both trees
                                                     // here are temp dirs with no history of their own)

    const rw::quality::RefTree& target() const noexcept { return sameRef ? baseTree : targetTree; }
};

// Resolve the spec and materialize both sides. Returns an EXIT CODE on any refusal or environment failure
// (already reported on stderr), or nullopt when `out` is ready to compare. Splitting user error from
// environment failure is the same line --dmm's handler draws: a revision that does not resolve is a typo the
// caller can fix, everything else is the machine.
std::optional<int> loadRefPairDelta( const std::string& root, std::string_view spec, const rw::Config& cfg, RefPairDelta& out )
{
    using namespace rw;

    const quality::RefSpec ref = quality::resolveRefSpec( root, spec );
    switch( ref.status )
    {
        case quality::RefSpecStatus::BadRev:
            // The did-you-mean here cannot be a spelling neighbourhood — git already owns the ref namespace and
            // has no cheap enumeration of it — so the adjacent help names the PROBE and the three causes that
            // actually produce this on an agent's machine, which is more use than a guessed nearest ref.
            std::fprintf( stderr, "ripwire: --quality-delta: '%s' does not resolve to a commit in %s\n"
                                  "  check it with `git -C %s rev-parse --verify %s^{commit}`; the usual causes are a typo, a ref that\n"
                                  "  lives only on a remote you have not fetched, or a shallow clone whose history stops before it\n",
                          ref.badToken.c_str(), root.c_str(), root.c_str(), ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::BadRange:
            std::fprintf( stderr, "ripwire: --quality-delta: '%s' uses the three-dot form; this compares two TREES, so spell it A..B "
                                  "(or --quality-delta=$(git merge-base A B)..B if the merge base is what you meant)\n", ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::NoGit:
        case quality::RefSpecStatus::NoParent:
            // Environment, not a typo — and unlike --dmm (a measurement that reports UNAVAILABLE and exits 0)
            // this verb has nothing to report at all, so it takes the same exit 1 the bare form's
            // "nothing to compare against" path takes.
            std::fprintf( stderr, "ripwire: --quality-delta=%.*s: %s\n", int( spec.size() ), spec.data(), ref.reason.c_str() );
            return 1;
        case quality::RefSpecStatus::Ok:
            break;
    }
    // resolveRefSpec only reports Ok for the working-tree form on an EMPTY spec, which the flag table refuses
    // before it reaches here; the guard is belt-and-braces so a future grammar change cannot silently compare
    // a materialized tree against a working tree whose keys are spelled against a different root.
    if( ref.targetIsWorkingTree || ref.baseSha.empty() || ref.targetSha.empty() )
    {
        std::fprintf( stderr, "ripwire: --quality-delta needs TWO commits (A..B); use the bare --quality-delta for the working tree\n" );
        return 1;
    }

    // DISTINCT tags — see quality::loadRefTree's header. Sharing one would make the target's extraction
    // delete the base tree out from under the clone detector, which reads file bytes off disk.
    out.sameRef = ( ref.baseSha == ref.targetSha );
    if( !quality::loadRefTree( root, ref.baseSha, cfg.excludes, cfg.maxFileBytes, "qdpair-base", out.baseGuard, out.baseTree ) )
    {
        std::fprintf( stderr, "ripwire: --quality-delta: could not materialize or parse the tree at %s\n", ref.baseSha.c_str() );
        return 1;
    }
    if( !out.sameRef && !quality::loadRefTree( root, ref.targetSha, cfg.excludes, cfg.maxFileBytes, "qdpair-target", out.targetGuard, out.targetTree ) )
    {
        std::fprintf( stderr, "ripwire: --quality-delta: could not materialize or parse the tree at %s\n", ref.targetSha.c_str() );
        return 1;
    }

    // Both values are bare 40-char object names straight out of `rev-parse --verify` (resolveRefSpec accepts
    // nothing else), so they carry no XML-significant byte and are spliced rather than escaped — the same
    // reasoning gitstamp::atAttr states for its own hex value.
    out.attrs     = " base_ref=\"" + ref.baseSha + "\" target_ref=\"" + ref.targetSha + "\" churn=\"unavailable\"";
    out.jsonAttrs = ",\"base_ref\":\"" + ref.baseSha + "\",\"target_ref\":\"" + ref.targetSha + "\",\"churn\":\"unavailable\"";
    // R1: the same two resolved shas as a range, for the rename record. Empty when the target IS the working
    // tree — `A..` is not a range git will walk, and the working-tree form's own uncommitted+window query is
    // the right scope there anyway.
    out.rangeSpan = ref.targetSha.empty() ? std::string{} : ( ref.baseSha + ".." + ref.targetSha );
    return std::nullopt;
}

// WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides that.
// Extracted from runQualityDelta when the ref-pair form landed: floor selection was previously a single
// straight-line arm inside that body, and adding a second, differently-shaped floor turned it into the kind
// of branch pile the verb itself measures (runQualityDelta's own complexity crossed the bar on this lane's
// --quality-delta before this extraction). Everything downstream — acks, counters, both emitters, the exit
// code — reads these three fields and does not care which floor produced them.
//
// `deltaRoot` is WHICH SIDE was judged, and every root-relative key and displayed symbol downstream is
// spelled against it rather than against the repo root. In the ref-pair form the judged tree is a
// materialized temp dir: its keys must match the floor tree's key-for-key (S2), and its PID-suffixed path
// must never reach stdout — a temp path in the output would make two runs of the same comparison differ
// byte for byte, which is a determinism bug even when every finding is correct.
struct DeltaBasis
{
    rw::quality::BaselineSelection       baseSel;
    std::vector<rw::quality::Regression> regs;
    std::string                          deltaRoot;   // see above — NOT interchangeable with the repo root
    // R1 IDENTITY — the ack ledger, plus the healing pre-pass that re-files BOTH sidecars into the identity
    // the current tree uses (quality::healIdentity). The ledger is read HERE, before computeDelta, because
    // the healing needs both sidecars at once and has to run before anything reads either: heal the baseline
    // after the delta is computed and the delta has already been taken against the stale identity.
    gtl::btree_map<std::string, rw::quality::AckRecord> acks;
    rw::quality::IdentityHealing                        healing;
    std::size_t                                         registerMacroExcluded = 0;   // P2.2: disclosed dead-code exemption count
};

// Returns an EXIT CODE when there is nothing to compare against (already reported), nullopt when `out` holds
// a usable comparison. `refs` is the CALLER's because it owns the materialized trees' teardown, and those
// trees must outlive every read of `out.regs`.
std::optional<int> resolveDeltaBasis( const MainDispatch& d, const std::string& baselineFile,
                                      RefPairDelta& refs, DeltaBasis& out )
{
    using namespace rw;
    const Config&       cfg  = d.cfg;
    const std::string&  root = d.root;

    // ── the REF-PAIR floor: two COMMITTED trees, neither of them the working tree ─────────────────────────
    if( !cfg.qualityDeltaRange.empty() )
    {
        if( const std::optional<int> refused = loadRefPairDelta( root, cfg.qualityDeltaRange, cfg, refs ) )
        {
            return refused;
        }
        // No sidecar is read, written or DELETED by this form. Deliberate, and disclosed in --help: the
        // sidecar's whole contract is "pinned at the current HEAD", which says nothing about a pair of
        // arbitrary commits — and the bare form's self-heal deleting a user's pinned floor as a side effect
        // of a wave-level measurement would be a side effect nobody asked for.
        out.baseSel.snapshot = quality::computeSnapshot( refs.baseTree.ing, refs.baseTree.g, refs.baseTree.root );
        out.baseSel.marker   = "ref-pair";
        out.deltaRoot        = refs.target().root;
        // R1 IDENTITY. The SPAN is what makes this honest here: both trees are materialized OUT of the repo
        // into temp dirs, so asking them about renames answers "not a git repo" — the renames are recorded in
        // the REAL repo, over exactly the range this comparison is about. `root` (the repo) supplies the
        // record; `refs.rangeSpan` scopes it to the pair. Everything else is identical to the working-tree
        // form, which is the point of having one healIdentity.
        out.acks    = quality::readAckRecords( quality::acksPath( root ) );
        out.healing = quality::healIdentity( out.baseSel.snapshot, out.acks, refs.target().ing, refs.target().g,
                                             out.deltaRoot, root, cfg.qualityAck, refs.rangeSpan );
        out.regs    = quality::computeDelta( refs.target().ing, refs.target().g, out.baseSel.snapshot,
                                             out.deltaRoot, cfg.excludes, cfg.maxFileBytes, &out.registerMacroExcluded );
        return std::nullopt;
    }

    // ── the WORKING-TREE floors, unchanged ───────────────────────────────────────────────────────────────
    // Precedence: (1) an explicit `.ripwire_quality_baseline` sidecar (from --quality-baseline) wins whenever
    // it is pinned at the CURRENT HEAD — the mid-task convergence loop (baseline once, edit, re-check) is
    // unchanged; (2) else — no sidecar, or a STALE one (see R3 below) — if the root is a git repo with a HEAD
    // tree, auto-baseline against HEAD so the "before I push" loop works with no start-of-task ritual (T0.1);
    // (3) else degrade to the exit-1 "run --quality-baseline first" guidance (non-git / unborn /
    // detached-no-tree — unchanged).
    //
    // STALENESS + the self-heal live in ONE place, quality::selectBaseline — R3 owner ruling (2026-07-29): a
    // sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b "reachable ancestor is
    // a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor) is REVOKED: a parallel
    // session's sidecar pinned at a commit that merely happened to be an ancestor of this session's HEAD made
    // THIS arm report 31 phantom regressions while the MCP quality_delta verb — same binary, same repo, same
    // second — correctly reported zero. That divergence was only possible because each arm carried its own
    // copy of the test; there is now exactly one, in quality.h.
    //
    // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is silently
    // UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the same dead pin,
    // and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar removed)") — no stderr
    // spam, which is the B10.1b noise fix that survives the ruling intact. The read-only MCP arm passes false
    // and reports "…ignored" instead. When the unlink FAILS (read-only parent dir) this arm degrades to the
    // read-only story — marker "…ignored", one DEGRADED_PATH_ALERT from the seam — because the pin is still
    // on disk; `isStaleFileOnDisk()` is the fact, and the fatal message words itself from it, not the intent.
    out.deltaRoot = std::string( cfg.rootPath );
    out.baseSel   = quality::selectBaseline( root, baselineFile, /*removeStaleFile=*/true );
    if( !out.baseSel.isSidecarHonored() )
    {
        auto [ headSnap, ok ] = computeHeadSnapshot( root, nullptr, cfg.maxFileBytes, cfg.excludes );
        if( !ok )
        {
            // w1 MED: this used to say "no <file>" in BOTH cases — factually false when the file is a STALE
            // sidecar that was just dropped, and doubly so when the self-heal unlink FAILED and the thing is
            // still sitting on disk. The stale-aware wording (and the MCP twin it mirrors) lives in
            // noBaselineFatalMessage above. Exit code is unchanged (1) in every branch.
            std::fputs( noBaselineFatalMessage( baselineFile, out.baseSel ).c_str(), stderr );
            return 1;
        }
        out.baseSel.snapshot = std::move( headSnap );
        if( !out.baseSel.isSidecarStale() )
        { // the stale/healed case is silent by design — only the true "never baselined" case is informative
            std::fprintf( stderr, "ripwire: no %s — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)\n",
                          baselineFile.c_str() );
        }
    }
    // R1 IDENTITY — heal both sidecars into the current tree's identity BEFORE the delta is taken against
    // them. One root here: the judged tree and the git record are the same directory in this form.
    out.acks    = quality::readAckRecords( quality::acksPath( root ) );
    out.healing = quality::healIdentity( out.baseSel.snapshot, out.acks, d.ing, d.g,
                                         std::string( cfg.rootPath ), root, cfg.qualityAck );
    out.regs = quality::computeDelta( d.ing, d.g, out.baseSel.snapshot, cfg.rootPath, cfg.excludes, cfg.maxFileBytes, &out.registerMacroExcluded );
    return std::nullopt;
}

// P1.2 — expand the reserved `diff` token into one literal path pattern per changed INDEXED file. It lives
// in the verb because reading git is the verb's job and quality::Scope is a pure value; and it runs BEFORE
// refuseUnusableScope, so the expanded set is what the "names nothing indexed" test sees.
//
// THREE refusals, all of the same shape and for the same reason — under a scope, a silent zero reads as
// "you're clean", which is the most dangerous sentence this verb can say.
std::optional<int> expandScopeDiff( rw::quality::Scope& scope, bool refPair, const rw::IngestResult& judged,
                                    const std::string& root, std::string_view deltaRoot, std::size_t& diffFileCount )
{
    if( !rw::quality::scopeUsesDiffToken( scope ) || !rw::quality::scopeSpecIsSpellable( scope.spec ) )
    {
        return std::nullopt;   // not our token, or a spec refuseUnusableScope is about to refuse anyway
    }
    if( refPair )
    {
        // The token names the WORKING TREE's changes, and this form compares two committed trees — the
        // working tree is not part of the comparison at all, so the answer would describe a different tree
        // than the one being judged.
        std::fprintf( stderr, "ripwire: --scope=diff scopes to the WORKING TREE's changes, but --quality-delta=A..B compares two COMMITTED trees —\n"
                              "  spell the scope as paths there (e.g. --scope=src/quality.h), or drop the range to measure the working tree\n" );
        return 1;
    }
    std::vector<char> changed( judged.files.size(), 0 );
    if( !rw::gitChangedFiles( root, judged, changed ) )
    {
        std::fprintf( stderr, "ripwire: --scope=diff needs git to say what changed, and %s is not a readable git repository —\n"
                              "  name the paths instead (e.g. --scope=src/quality.h,src/verbs_quality.h)\n", root.c_str() );
        return 1;
    }
    std::vector<std::string> expanded;
    for( const std::string& p : scope.patterns )
    {
        if( p != rw::quality::kScopeDiffToken )
        {
            expanded.push_back( p );   // the token composes by UNION with any literal patterns beside it
        }
    }
    for( std::size_t fileIndex = 0; fileIndex < changed.size(); ++fileIndex )
    {
        if( changed[ fileIndex ] )
        {
            expanded.emplace_back( rw::relForHash( judged.files[ fileIndex ], deltaRoot ) );
            ++diffFileCount;
        }
    }
    if( diffFileCount == 0 )
    {
        std::fprintf( stderr, "ripwire: --scope=diff expanded to NO changed indexed file — the working tree matches the baseline (or the edits are in files\n"
                              "  this index does not carry), so the scope owns nothing and an exit 0 under it would say nothing about your change\n" );
        return 1;
    }
    std::sort( expanded.begin(), expanded.end() );
    expanded.erase( std::unique( expanded.begin(), expanded.end() ), expanded.end() );
    scope.patterns.swap( expanded );
    return std::nullopt;
}

// P1 — the scope flag's two REFUSALS, in their own symbol. They live in the verb rather than in cli.h for
// the reason --quality-panel=PRESET's refusal does: the vocabulary belongs to quality.h, and cli.h is a leaf
// that includes only ingest.h. Returns an exit code (already reported on stderr) or nullopt when the scope
// is usable. `judged` is the tree the findings were taken from — the working tree, or tree B in the
// ref-pair form — because "names nothing indexed" has to be asked of the corpus that was actually measured.
std::optional<int> refuseUnusableScope( const rw::Config& cfg, const rw::quality::Scope& scope,
                                        const rw::IngestResult& judged, std::string_view deltaRoot )
{
    if( !scope.active() )
    {
        return std::nullopt;
    }
    if( !rw::quality::scopeSpecIsSpellable( cfg.qualityScope ) )
    {
        // The spec is recorded VERBATIM as a whitespace-delimited by= token in the ack ledger and echoed into
        // an XML attribute. A pattern that cannot round-trip through both is refused here rather than mangled
        // at the emitter: matching against something the caller never typed is the one outcome worse than
        // not matching at all.
        std::fprintf( stderr, "ripwire: --scope=%.*s contains whitespace or an XML metacharacter — a scope is recorded verbatim in the ack ledger and in the report,\n"
                              "  so each pattern must be spellable as one token (e.g. --scope=src/quality.h,src/verbs_quality.h)\n",
                      int( cfg.qualityScope.size() ), cfg.qualityScope.data() );
        return 1;
    }
    // A scope that names nothing INDEXED is a typo, not a measurement — and a typo here reads as "you're
    // clean", which is the single most dangerous thing this verb can say. Refuse loudly, the same ruling
    // --dead-code=DIR already carries.
    for( const std::string& indexedPath : judged.files )
    {
        if( scope.matchesPath( rw::relForHash( indexedPath, deltaRoot ) ) )
        {
            return std::nullopt;
        }
    }
    std::fprintf( stderr, "ripwire: --scope=%.*s matches no indexed path — an exit 0 under a scope that owns nothing is a failure, not a clean tree\n"
                          "  (patterns are matched ROOT-RELATIVE, the same spelling p= prints: --scope=src or --scope=src/quality.h, not an absolute path)\n",
                  int( cfg.qualityScope.size() ), cfg.qualityScope.data() );
    return 1;
}

// P1 — the partition itself: move every finding the scope does not cover into `outOfScope`, and return how
// many of the disclosed rows WOULD have gated. Called before the in-scope ratchet so acked= counts this
// scope's suppressions rather than the whole tree's.
//
// F-05 fix (audit 2026-09-02, item 2): this USED to ack-ratchet outOfScope too ("a sibling's ALREADY-ACKED
// row is answered over there, so disclosing it again would be noise") — but kScopeLegend promises the
// out-of-scope element is "not dropped: … every one of them is printed", unconditionally, and an ack
// written by ANYONE (not just the row's own owner — applyAckRatchet does not check by= at all) made a row
// vanish from that element entirely: a sibling's exclusive debt, acked once under its OWN scope for an
// unrelated reason, silently stopped being disclosed to every other scope's report. Confirmed live: acking
// two of an owner's four exclusive findings under --scope=alpha made a LATER --scope=beta run's
// <out-of-scope> show zero of that owner's rows instead of the two still-unacked, non-straddling ones.
// Disclosure is now unconditional — outOfScope keeps every row the scope does not cover, acked or not.
// wouldGate stays ack-aware (an already-acked row would not have gated even inside its owner's own scope),
// computed via findSuppressingAck so nothing is removed from what gets printed.
std::size_t partitionByScope( const rw::quality::Scope& scope, std::vector<rw::quality::Regression>& regs,
                              std::vector<rw::quality::Regression>& outOfScope,
                              const gtl::btree_map<std::string, rw::quality::AckRecord>& acks )
{
    if( !scope.active() )
    {
        return 0;
    }
    std::vector<rw::quality::Regression> mine;
    mine.reserve( regs.size() );
    for( rw::quality::Regression& r : regs )
    {
        ( rw::quality::scopeCovers( scope, r ) ? mine : outOfScope ).push_back( std::move( r ) );
    }
    regs.swap( mine );
    std::size_t wouldGate = 0;
    for( const rw::quality::Regression& r : outOfScope )
    {
        if( r.isNewSymbol || r.isMinor )
        {
            continue;
        }
        if( rw::quality::findSuppressingAck( r, acks ) != nullptr )
        {
            continue;   // acked (by whoever) — would not have gated even in its own scope
        }
        ++wouldGate;
    }
    return wouldGate;
}

// P1 — THE RUBBER-STAMP GUARD, in its own symbol because it is the point of the whole flag. Under a scope an
// out-of-scope finding is not in the ack SELECTION at all: there is no spelling of --quality-ack that writes
// one. That leaves exactly one case worth a hard refusal rather than a silent skip — an --ack-only pattern
// that NAMES a row belonging to someone else. It is the difference between "the flag narrowed what I
// accepted" and "I asked for that row and did not get it", so the whole ack is refused, nothing is written,
// and the rows are named. `selected` is the caller's ack predicate, passed rather than rebuilt so the two
// sites can never disagree about what a pattern selects.
template<typename Selector>
std::optional<int> refuseForeignAckSelection( const rw::Config& cfg, const rw::quality::Scope& scope,
                                              const std::vector<rw::quality::Regression>& outOfScope,
                                              std::string_view deltaRoot, Selector&& selected )
{
    if( !scope.active() || cfg.qualityAckOnly.empty() )
    {
        return std::nullopt;
    }
    std::string named;
    std::size_t namedCount = 0;
    for( const rw::quality::Regression& r : outOfScope )
    {
        if( !selected( r, /*inScope=*/false ) )
        {
            continue;
        }
        ++namedCount;
        if( namedCount <= 8 )   // a listing, not a dump: the count in the sentence above it is the total
        {
            named += "\n    " + r.kind + " " + rw::quality::displaySym( r.sym, deltaRoot );
            if( !r.path.empty() )
            {
                named += " at " + r.path + ":" + std::to_string( r.line );
            }
        }
    }
    if( namedCount == 0 )
    {
        return std::nullopt;
    }
    std::fprintf( stderr, "ripwire: --ack-only=%.*s selects %zu finding(s) OUT OF SCOPE for --scope=%s — refusing, and writing nothing at all:%s%s\n"
                          "  those rows belong to whoever is editing those paths. Acking them here writes their debt into a committed ledger under YOUR\n"
                          "  reason string, which is how a per-finding ratchet becomes a rubber stamp. Narrow the pattern, or widen the scope if they really are yours.\n",
                  int( cfg.qualityAckOnly.size() ), cfg.qualityAckOnly.data(), namedCount, scope.spec.c_str(),
                  named.c_str(), namedCount > 8 ? "\n    …" : "" );
    return 1;
}

// ── quality-delta legend, SECTIONED (density round 2026-09-02, lane B) ────────────────────────────
//
// WHY THIS SHAPE. --quality-delta ranks first in this tool's measured call mix — CLAUDE.md tells every
// agent to run it before calling work done — and its legend was ONE 8,574 B constant (10,512 B with the
// scope half) emitted
// unconditionally against a 572 B payload on a clean run — 93.7% of every "am I done?" checkpoint was
// fixed text the reader had already met. The fix generalizes the rule kScopeLegend below already
// followed alone: A DEFINITION IS EMITTED WHEN THE THING IT DEFINES IS IN THE DOCUMENT. Nothing is
// dropped and no limit is softened — a reader still can never meet an undefined name, because a name
// and its sentence appear together or not at all. What went away is (a) four baseline= markers this
// run did not use, (b) the identity/rekey/duplication paragraphs for attributes this run did not emit,
// and (c) prose that restated --help. --help is the catalog; this is the key to THIS document.
//
// G4, for every constant below: an XML comment may never contain the literal byte pair "--", so flag
// names are written bare ("quality-baseline", "the scope flag"), and no "%" appears anywhere because
// these reach stdout through one-argument writes. NO ATTRIBUTE=VALUE NUMERIC LITERAL may be spelled in
// this prose either: several gates grep the header counters (regressions=, gating=, stale=) and a
// quoted example here would be matched ahead of the real one.

// Always. The verb, the ten kinds, the three axes, the exit predicate, and the two counters that are
// printed even at zero. Every row in the document — finding rows and stale-ack rows alike — carries
// kind=, so it is defined here rather than in either conditional row dictionary.
inline constexpr const char* kQdLegendCore =
    "<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. "
    "Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low "
    "score). TEN KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity "
    "(LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), "
    "error-masking, short-horizon-churn, new-clone-of-reused-helper. THREE independent axes, in this "
    "order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a "
    "symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only "
    "because the code is NEW carries origin=\"new-symbol\"; (3) MATERIALITY — a small numeric delta is "
    "sev=\"minor\", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, the gating= "
    "count; new-symbol rows "
    "never gate, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is "
    "yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is "
    "preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a "
    "FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger "
    "whose target no longer applies. "
    "register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind "
    "because their own definition is a registered self-registering test/benchmark macro call. Never gates, "
    "never counted in regressions=, printed even at zero (zero means none excluded, not that the check did "
    "not run). ";

// The macro FAMILIES, and why a member of one cannot be judged dead — printed only when the run actually
// excluded something, because on a repo with no such macro the roster explains an empty set.
inline constexpr const char* kQdRegisterMacroLegend =
    "The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark "
    "BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a "
    "static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. ";

// F-13 (audit 2026-09-02) — printed only when .ripwire_config itself has something wrong with it, which
// used to be a silent no-op: a typo'd key was skipped with no trace, and a register_macros= name that
// matched nothing in the corpus looked exactly like one that was quietly doing its job. config-warnings=
// is the one root count covering both; the specific keys/names are on stderr (never guessed at in the XML
// — a name a hand-edited config carries is not free text this attribute repeats).
inline constexpr const char* kQdRegisterMacroWarnLegend =
    "config-warnings= is a FLOOR, never gating and printed only when non-zero: it counts two DISCLOSED "
    ".ripwire_config problems, each also written to stderr — an unrecognized key (the only key this file "
    "reads is register_macros) and a register_macros= name that matched no indexed symbol, either a typo or "
    "a macro this corpus does not use. Neither refuses the run; a misconfigured exemption is not a broken "
    "tree, but a silent one used to read as a working one. ";

// One sentence per baseline= marker, and ONLY the marker this run actually used. The five are not
// interchangeable — three of them compare against HEAD, so anything already committed cannot appear —
// and the state a reader is in is the state they need spelled out.
inline constexpr const char* kQdBaseSidecar =
    "baseline=\"sidecar\" is the pinned .ripwire_quality_baseline snapshot, honored because it was pinned "
    "at the CURRENT git HEAD: the one floor YOU chose. ";
inline constexpr const char* kQdBaseHead =
    "baseline=\"git-HEAD\" means no sidecar existed, so the working tree was auto-compared against the "
    "HEAD tree — anything already committed cannot appear. ";
inline constexpr const char* kQdBaseHeadRemoved =
    "baseline=\"git-HEAD (stale sidecar removed)\" means a sidecar existed, was pinned at a DIFFERENT sha, "
    "and this run DELETED it from your working tree before falling back to the HEAD tree (re-pin with "
    "quality-baseline) — so anything already committed cannot appear. ";
inline constexpr const char* kQdBaseHeadIgnored =
    "baseline=\"git-HEAD (stale sidecar ignored)\" is the same staleness verdict, but the file was left on "
    "disk (the read-only MCP arm, or an unlink that failed), and the comparison fell back to the HEAD "
    "tree — so anything already committed cannot appear. ";
inline constexpr const char* kQdBaseRefPair =
    "baseline=\"ref-pair\" means neither a sidecar nor the working tree: the verb was given a RANGE, so it "
    "compared two COMMITTED trees and no sidecar was read, written or deleted. base_ref= and target_ref= "
    "are the two RESOLVED shas, at full length because a wave number gets quoted into handoffs, and they "
    "are the anchor, so at= is omitted. churn= is reported unavailable there, which is the honest statement "
    "that one of the ten kinds, short-horizon-churn, cannot be measured at all in that form: it needs git "
    "history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. Its "
    "silence in such a report is not evidence that nothing churned. ";
// at= is absent in the ref-pair form, so its sentence is too.
inline constexpr const char* kQdAtLegend =
    "at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. ";

// Emitted only when the identity re-filing actually ran, i.e. when the run carries its renames= family.
inline constexpr const char* kQdIdentityLegend =
    "IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would "
    "destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT "
    "tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality "
    "of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many "
    "rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and "
    "acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear "
    "ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than "
    "the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current "
    "symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a "
    "regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through "
    "as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key "
    "on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the "
    "rename record but never content, because the baseline stores no content id at all; and a move git "
    "recorded no rename for still reads as new-symbol. ";

// How the two mechanisms decide, in full — printed only when an ack was actually SUPPRESSED by one of
// them (acked= is non-zero), which is the only state in which a reader has a suppression to audit. The
// determinism properties are the audit: an identity claim nobody can re-derive is not a disclosure.
inline constexpr const char* kQdIdentityMechLegend =
    "The two mechanisms in full, because a suppression is a claim about identity: git's rename record is "
    "read with rename detection and the similarity threshold PINNED in the command, never inherited from "
    "the repo config, over a fixed COMMIT window rather than a wall-clock one, so the answer is the same "
    "everywhere; the content match is equality of a body hash scrubbed of whitespace and of the symbol's "
    "own name, for a move git recorded no rename for. A body that CHANGED is a different finding and is "
    "matched by neither. ";

// Emitted only when the scheme re-keying actually moved or refused a row — i.e. when acks_rekeyed_by_scheme=
// or scheme_ambiguous= is on the root. Both are git-INDEPENDENT, so this is not folded into the paragraph
// above: it survives a run where git could not be read at all.
inline constexpr const char* kQdSchemeLegend =
    "A THIRD re-filing, git-independent: on 2026-08-25 the per-symbol quality key stopped being a "
    "canonical-id hash (which degraded to a BARE NAME for a scope-less symbol, folding every same-named one "
    "in the tree into a single identity) and became the path-qualified key the churn kind has used since "
    "the churn-keying round. Ack rows written under the old rule replay forward into the new one, both "
    "being pure functions of the same path, scope and name — no git, no similarity threshold. "
    "acks_rekeyed_by_scheme= counts the rows that replay moved, and is absent once a ledger has been "
    "written back under the new rule, which is the normal steady state rather than a failure. "
    "scheme_ambiguous= counts rows it REFUSED to move: the old key of a name that folded across N files "
    "maps to N new keys, so which symbol the ack was written for is unknowable from the ledger; those rows "
    "keep their old key and surface under stale= rather than being fanned out to all N or guessed. ";

// The sa ROW dictionary — emitted only when there are sa rows. The stale= axis itself is defined in the
// core paragraph, because the counter is on the root of every report whether or not any row follows it.
inline constexpr const char* kQdStaleLegend =
    "Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no "
    "symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). "
    "Hygiene disclosure only — the ledger file is never auto-edited. ";

// Emitted only when the document actually has finding rows (in scope or disclosed out of scope).
inline constexpr const char* kQdRowLegend =
    "ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for "
    "the numeric kinds; p=\"path:line\" is the locator (root-relative; the first-sorting member for the "
    "clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind "
    "classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/"
    "contract-change tier). Every row the header's gating= counter counts also carries a gating attribute "
    "set to 1 — marked positively, never by the ABSENCE of sev or origin. ";

// Emitted only when a clone-family row (duplication / new-clone-of-reused-helper) is in the document,
// which is what puts members=, tokens= and idiom= on a first screen. A clean tree has none.
inline constexpr const char* kQdCloneLegend =
    "CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its "
    "shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a "
    "RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, "
    "switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no "
    "non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and "
    "stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor "
    "instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing "
    "ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse "
    "tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so "
    "the call can be overruled by reading. ";

// P1 — the SCOPE half of the quality-delta legend, printed ONLY when the report actually contains a
// scope partition or a foreign-ack row. That is a G4 (token density) decision, not a hedge: the
// paragraph defines scope=, the out-of-scope element and foreign-acks=, and on an unscoped run none
// of the three is in the document — charging every quality-delta call ~500 tokens to define
// attributes it did not emit is exactly the padding this legend exists to avoid. A reader can never
// meet one of those names undefined, because the names and this paragraph appear together or not at
// all. It lives out here rather than inline so runQualityDelta measures as the code it is.
// G4 again: no flag name spelled with the double dash anywhere inside an XML comment, so this says
// "the scope flag" throughout.
inline constexpr const char* kScopeLegend =
                        "SCOPE, present only when the scope flag was given, and it NARROWS WHAT THIS REPORT "
                        "CLAIMS: scope= is the pattern list it was given, verbatim. Every counter above "
                        "(regressions=, minor=, acked=, preexisting-worse=, new-symbol=, gating=) is then over "
                        "the IN-SCOPE findings alone, and the exit code follows gating= as always. The rest are "
                        "not dropped: scoped-out= counts the findings filed to somebody else, and every one of "
                        "them is printed inside an out-of-scope element carrying n= (the same count), would-gate= "
                        "and note= (the do-not-ack banner). scoped-out-gating= repeats would-gate= on the root "
                        "because it is the number a reader must not miss: it is how many disclosed rows WOULD "
                        "have fired the exit code, so exit 0 under a scope means \"nothing of YOURS is broken\", "
                        "never \"the tree is clean\". Rows inside that element carry the identical attributes to "
                        "the ones above it and never carry the gating attribute, since they are not what this "
                        "exit code fires on. HOW A FINDING IS FILED: by its p= path, matched root-relative "
                        "against the patterns; a clone kind is in scope when ANY member matches, not just the "
                        "first-sorting one; and a finding with no locator at all is filed OUT of scope, because "
                        "under a scope \"we cannot say where this is\" honestly reads as not provably yours. ";

// foreign-acks= is itself "present only when non-zero", so its paragraph follows the same rule the
// attribute does. Split out of kScopeLegend on 2026-09-02: a scoped run with no foreign ack was paying
// ~590 B to define an attribute, a why= value and a by= token none of which were in its document.
inline constexpr const char* kForeignAcksLegend =
                        "foreign-acks= is a SEPARATE axis, never gating and present only when non-zero: an "
                        "ack row records the scope that wrote it as a by= token, and this counts the acks that "
                        "are suppressing a finding whose path that recorded scope does not cover — a session "
                        "having accepted somebody else's debt. Those rows appear among the sa rows with "
                        "why set to foreign-scope and carry by= (the recorded scope). TWO FLOORS on that number: "
                        "only acks suppressing a finding RIGHT NOW can be checked (one whose finding no longer "
                        "fires has no path to test against), and a row with no by= at all is never counted, "
                        "since absence of provenance is not evidence of foreign provenance. ";

// The section table. One struct rather than seven parameters because every field is a property OF THE
// DOCUMENT being introduced, and a caller that has to remember an argument ORDER is the seam where a
// legend starts describing a run it is not attached to.
struct QualityDeltaLegendParts
{
    std::string_view                              marker;        // baseSel.marker — the ONE spelling table (quality::selectBaseline)
    bool                                          refPair;       // the RANGE form: base_ref=/target_ref= are the anchor, at= is absent
    std::string_view                              identityAttrs; // the exact string spliced into the root open tag
    bool                                          anySaRow;      // sa rows present => key= and the why= taxonomy are on screen
    bool                                          anyAcked;      // acked= is non-zero => there is a suppression to audit
    bool                                          anyRegisterMacro; // register-macro-excluded= is non-zero => the family roster describes a real set
    bool                                          anyRegisterMacroWarning; // F-13: config-warnings= is non-zero
    const std::vector<rw::quality::Regression>&   rows;          // in-scope findings
    const std::vector<rw::quality::Regression>&   disclosedRows; // out-of-scope findings — identical attribute set
    bool                                          scoped;        // a scope partition or a foreign-ack row is in the document
    bool                                          anyForeignAck; // foreign-acks= is on the root, with foreign-scope sa rows under it
};

// A DEFINITION IS EMITTED WHEN THE THING IT DEFINES IS IN THE DOCUMENT. Nothing is dropped and no limit is
// softened: a reader can never meet an undefined name, because a name and its sentence appear together or
// not at all. See the constants above for what each section covers and why it is conditional.
inline void emitQualityDeltaLegend( const QualityDeltaLegendParts& p )
{
    const auto anyCloneRow = [] ( const std::vector<rw::quality::Regression>& v )
    {
        for( const rw::quality::Regression& r : v )
        {
            if( r.kind == "duplication" || r.kind == "new-clone-of-reused-helper" ) { return true; }
        }
        return false;
    };

    std::fputs( kQdLegendCore, stdout );

    // (1) the ONE floor in force. Keyed off the same pointer the element prints, so the sentence cannot
    // drift from the attribute. A marker with no sentence would be a disclosure gap, so the fallthrough is
    // the git-HEAD sentence — what every non-sidecar, non-ref-pair marker degrades to.
    if     ( p.marker == "sidecar"                          ) { std::fputs( kQdBaseSidecar,     stdout ); }
    else if( p.marker == "ref-pair"                         ) { std::fputs( kQdBaseRefPair,     stdout ); }
    else if( p.marker == "git-HEAD (stale sidecar removed)" ) { std::fputs( kQdBaseHeadRemoved, stdout ); }
    else if( p.marker == "git-HEAD (stale sidecar ignored)" ) { std::fputs( kQdBaseHeadIgnored, stdout ); }
    else                                                      { std::fputs( kQdBaseHead,        stdout ); }

    // (2) at= is omitted in the ref-pair form, so its sentence follows the attribute, not the verb.
    if( !p.refPair )
    {
        std::fputs( kQdAtLegend, stdout );
    }
    if( p.anyRegisterMacro )
    {
        std::fputs( kQdRegisterMacroLegend, stdout );
    }
    if( p.anyRegisterMacroWarning )
    {
        std::fputs( kQdRegisterMacroWarnLegend, stdout );
    }

    // (3) the two identity re-filings, each keyed to the attribute family it defines. The second is
    // git-INDEPENDENT, so it is a separate condition rather than a clause of the first.
    if( !p.identityAttrs.empty() )
    {
        std::fputs( kQdIdentityLegend, stdout );
        if( p.anyAcked )
        {
            std::fputs( kQdIdentityMechLegend, stdout );
        }
    }
    if( p.identityAttrs.find( "acks_rekeyed_by_scheme=" ) != std::string_view::npos
        || p.identityAttrs.find( "scheme_ambiguous=" ) != std::string_view::npos )
    {
        std::fputs( kQdSchemeLegend, stdout );
    }

    // (4) key= and the why= taxonomy exist only in a document that has sa rows. stale= itself is a header
    // counter, always printed, and is defined in the core paragraph's axis list.
    if( p.anySaRow )
    {
        std::fputs( kQdStaleLegend, stdout );
    }

    // (5) the row dictionary, and its clone-family half. A clean tree emits neither attribute set, so at the
    // "done" checkpoint an agent actually makes, the reader pays for neither.
    if( !p.rows.empty() || !p.disclosedRows.empty() )
    {
        std::fputs( kQdRowLegend, stdout );
        if( anyCloneRow( p.rows ) || anyCloneRow( p.disclosedRows ) )
        {
            std::fputs( kQdCloneLegend, stdout );
        }
    }

    if( p.scoped )
    {
        std::fputs( kScopeLegend, stdout );
    }
    if( p.anyForeignAck )
    {
        std::fputs( kForeignAcksLegend, stdout );
    }
    std::fputs( "-->", stdout );   // every section constant above ends with its own separating space
}

// F-13 — the one place both --dead-code and --quality-delta turn a RegisterMacroConfigDiagnostics into
// output: the specific keys/names on stderr (never guessed at in the XML — a hand-edited config's tokens
// are not free text an attribute repeats), and the shared `config-warnings="N"` attribute string, present
// only when non-zero (this file's standing convention for every optional root attribute). One function so
// the two verbs cannot report the same misconfiguration two different ways.
inline std::string registerMacroConfigWarningAttr( const rw::quality::RegisterMacroConfigDiagnostics& diag )
{
    if( diag.total() == 0 )
    {
        return std::string();
    }
    const auto joined = [] ( const std::vector<std::string>& v ) -> std::string
    {
        std::string out;
        for( std::size_t i = 0; i < v.size(); ++i )
        {
            if( i ) { out += ", "; }
            out += v[i];
        }
        return out;
    };
    if( !diag.unrecognizedKeys.empty() )
    {
        std::fprintf( stderr, "ripwire: .ripwire_config has an unrecognized key (the only key this file reads is register_macros): %s\n",
                      joined( diag.unrecognizedKeys ).c_str() );
    }
    if( !diag.inertNames.empty() )
    {
        std::fprintf( stderr, "ripwire: .ripwire_config's register_macros= names a macro matching no indexed symbol (typo, or unused): %s\n",
                      joined( diag.inertNames ).c_str() );
    }
    return " config-warnings=\"" + std::to_string( diag.total() ) + "\"";
}

// runQualityViews was NOT a dispatch chain — it held two
// branches, one of which was 298 lines. That one body is now runQualityDelta below; the residual
// runQualityViews keeps only --dead-code. ONE extraction, verbatim: the 298-line body is unsplit, because
// its interior is a sequential pipeline over shared locals, not independent arms.
std::optional<int> runQualityDelta( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;

    // --quality-baseline / --quality-delta (the convergence-loop oracle): snapshot ccx + clone groups + dead
    // candidates to .ripwire_quality_baseline; then report ONLY what a change made WORSE vs it. The "delta not
    // absolute" discipline — a refine loop targets the regression it introduced, not absolute numbers (the
    // defense against metric-gaming). exit 2 if any new debt, like --arch.
    if( cfg.qualityBaseline || cfg.qualityDelta )
    {
        // D1 fix (HIGH): resolve BOTH sidecars against the analyzed ROOT, not the process CWD —
        // see quality::rootQualifiedSidecar's comment for why a bare relative filename is unsafe here
        // (a foreign cwd's sidecar could be silently rewritten, or even deleted by the stale-baseline
        // self-heal below). Computed once; every read/write/remove site in this block uses it.
        const std::string baselineFile = quality::baselinePath( root );
        const std::string acksFile     = quality::acksPath( root );

        if( cfg.qualityBaseline )
        {
            const bool wrote = quality::writeBaseline( quality::computeSnapshot( ing, g, cfg.rootPath ), baselineFile, gitHeadSha( root ) );
            std::fprintf( stderr, wrote ? "ripwire: wrote %s (snapshot of %zu symbols)\n" : "ripwire: could not write %s\n",
                          baselineFile.c_str(), ing.symbols.size() );
            return wrote ? 0 : 1;
        }

        // Precedence for the baseline: (1) an explicit `.ripwire_quality_baseline` sidecar (from
        // --quality-baseline) wins whenever it is pinned at the CURRENT HEAD — the mid-task convergence loop
        // (baseline once, edit, re-check) is unchanged; (2) else — no sidecar, or a STALE one (see R3 below) —
        // if the root is a git repo with a HEAD tree, auto-baseline against HEAD so the "before I push" loop
        // works with no start-of-task ritual (T0.1); (3) else degrade to the exit-1 "run --quality-baseline
        // first" guidance (non-git / unborn / detached-no-tree — unchanged).
        //
        // STALENESS + the self-heal now live in ONE place, quality::selectBaseline — R3 owner ruling
        // (2026-07-29): a sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b
        // "reachable ancestor is a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor)
        // is REVOKED: a parallel session's sidecar pinned at a commit that merely happened to be an ancestor of
        // this session's HEAD made THIS arm report 31 phantom regressions while the MCP quality_delta verb —
        // same binary, same repo, same second — correctly reported zero. That divergence was only possible
        // because each arm carried its own copy of the test; there is now exactly one, in quality.h.
        //
        // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is
        // silently UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the
        // same dead pin, and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar
        // removed)") — no stderr spam, which is the B10.1b noise fix that survives the ruling intact. The
        // read-only MCP arm passes false and reports "…ignored" instead. When the unlink FAILS (read-only
        // parent dir) this arm degrades to the read-only story — marker "…ignored", one DEGRADED_PATH_ALERT
        // from the seam — because the pin is still on disk; `baseSel.isStaleFileOnDisk()` is the fact, and the
        // fatal message below words itself from it rather than from the intent.
        // `refs` is declared HERE because it owns both materialized trees' teardown and they must outlive
        // every read of `regs` (DeltaBasis's header states that rule, and why the emitters below spell every
        // path and symbol against basis.deltaRoot rather than against `root`).
        // F-04 (round-4 audit) — SERIALIZE THE ACK LEDGER'S READ-MODIFY-WRITE, cross-process.
        //
        // --quality-ack reads the whole ledger (inside resolveDeltaBasis just below — the heal has to happen
        // before computeDelta), folds this run's accepted findings into that map, then rewrites the file from
        // it. Nothing serialized that. Three sessions acking DISJOINT rows in one shared checkout — the exact
        // scenario --scope exists for — lost two of the three acks on 8 of 8 measured runs, because whichever
        // process rewrote last overwrote a map the other two had already published into.
        //
        // The lock therefore has to span the READ as well as the write, which is why it is taken HERE and not
        // inside writeAckRecords: a lock held only around the final rewrite still lets two processes read the
        // same stale map first and then take turns clobbering. Engaged ONLY under --quality-ack — a read-only
        // --quality-delta never waits, never creates the lockfile, and is byte-for-byte the run it always was.
        // RAII: released when this function returns, on every path including the refusals below. quality.h's
        // SidecarWriteLock has the lockfile's location (per-user cache dir, never a repo-tree sidecar), the
        // wait budget, and the honest limits.
        std::optional<quality::SidecarWriteLock> ackLock;
        if( cfg.qualityAck )
        {
            ackLock.emplace( acksFile );
        }

        const bool   refPair = !cfg.qualityDeltaRange.empty();
        RefPairDelta refs;
        DeltaBasis   basis;
        if( const std::optional<int> refused = resolveDeltaBasis( d, baselineFile, refs, basis ) )
        {
            return *refused;
        }
        const quality::BaselineSelection& baseSel   = basis.baseSel;
        const std::string&                deltaRoot = basis.deltaRoot;
        std::vector<quality::Regression>&  regs     = basis.regs;

        // ── P1 SCOPE — the OWNERSHIP partition for a working tree with several writers in it ─────────────
        quality::Scope                   scope = quality::parseScope( cfg.qualityScope );
        std::vector<quality::Regression> outOfScope;
        std::size_t                      diffFileCount = 0;   // P1.2: 0 = the reserved diff token was not used
        const IngestResult&              judged        = refPair ? refs.target().ing : ing;
        if( const std::optional<int> refused = expandScopeDiff( scope, refPair, judged, root, deltaRoot, diffFileCount ) )
        {
            return *refused;
        }
        if( const std::optional<int> refused = refuseUnusableScope( cfg, scope, judged, deltaRoot ) )
        {
            return *refused;
        }

        // Signal-to-noise round — the per-finding ACK RATCHET. Suppress findings already accepted (with a
        // reason) in .ripwire_quality_acks, honestly (acked="N"); a finding that WORSENED past its acked
        // magnitude survives the filter and reappears. --quality-ack merges the currently-VISIBLE findings
        // into that file instead of printing the report (accepting what previous acks already hid would be
        // a silent blanket ack — only what the agent can see right now is what it can accept).
        // R1 IDENTITY: the ledger was read and HEALED inside resolveDeltaBasis (it had to be — the baseline
        // half of the same healing has to precede computeDelta), so this arm takes the already-current map
        // rather than re-reading the file and undoing it.
        gtl::btree_map<std::string, quality::AckRecord>& acks = basis.acks;
        quality::countAckRescues( regs, acks, basis.healing.ackRemap,
                                  basis.healing.ackedByRename, basis.healing.ackedByContent );
        // P1.4 PROVENANCE — the foreign-ack sweep reads the PRE-ratchet list on purpose (computeForeignAcks'
        // header states why: the question is about acks that are suppressing something right now).
        const std::vector<quality::StaleAck> foreignAcks = quality::computeForeignAcks( regs, acks );
        // P1 — the partition runs BEFORE the ratchet so acked="N" counts THIS scope's suppressions rather
        // than the whole tree's (partitionByScope owns the rest of the rule).
        const std::size_t scopedOutGating = partitionByScope( scope, regs, outOfScope, acks );
        const std::size_t ackedCount = quality::applyAckRatchet( regs, acks );
        if( cfg.qualityAck )
        {
            // --ack-only=SUBSTR[,SUBSTR]: ack a SUBSET instead of everything on screen. Without it, the only
            // way to accept one deliberate contract change was to accept the whole report — which is how a
            // ratchet quietly becomes a rubber stamp. A finding matches if a substring occurs in its kind or
            // in its canonical id (so "api-surface", "src/quality.h", or one exact id all work).
            // P1: `inScope` is a parameter rather than a capture because this predicate is asked about BOTH
            // halves of the partition — once to choose what to write, once to detect an ack selection that
            // NAMES a row belonging to someone else. It is also what keeps the `gating` pseudo-token honest
            // under a scope: an out-of-scope row does not gate, so `gating` must not select it.
            const auto ackSelected = [ & ]( const quality::Regression& r, bool inScope ) -> bool
            {
                if( cfg.qualityAckOnly.empty() )
                {
                    return true;
                }
                std::string_view rest = cfg.qualityAckOnly;
                while( !rest.empty() )
                {
                    const std::size_t     comma = rest.find( ',' );
                    const std::string_view pat  = rest.substr( 0, comma );
                    // kind, canonical id, or FACET. The facet is what makes this precise enough to be honest:
                    // "api-surface" also covers the never-gating new-symbol rows, so acking by kind would
                    // sweep in 59 findings to accept 8. --ack-only=contract-change accepts exactly the
                    // deliberate ones. The pseudo-token "gating" selects whatever would actually exit 2.
                    const bool gates = !r.isMinor && !r.isNewSymbol && inScope;
                    if( !pat.empty() && ( r.kind.find( pat ) != std::string::npos || r.sym.find( pat ) != std::string::npos || ( !r.facet.empty() && r.facet.find( pat ) != std::string::npos ) || ( pat == "gating" && gates ) ) )
                    {
                        return true;
                    }
                    if( comma == std::string_view::npos )
                    {
                        break;
                    }
                    rest = rest.substr( comma + 1 );
                }
                return false;
            };

            // P1 — THE RUBBER-STAMP GUARD (refuseForeignAckSelection owns the rule and the message).
            if( const std::optional<int> refused = refuseForeignAckSelection( cfg, scope, outOfScope, deltaRoot, ackSelected ) )
            {
                return *refused;
            }

            std::size_t ackWritten = 0, ackSkipped = 0;
            for( const quality::Regression& r : regs )
            {
                if( !ackSelected( r, /*inScope=*/true ) ) { ++ackSkipped;  continue; }
                ++ackWritten;
                // P0.3: the ack IDENTITY is ackKindToken, not the bare kind — a zero-magnitude finding
                // (was==now==0: dead-code, api-surface tier A) acks per ORIGIN, so acking the never-gating
                // new-symbol row can no longer blank-check the gating contract-change row on the same symbol.
                const std::string   ackKind = quality::ackKindToken( r );
                quality::AckRecord& rec     = acks[ quality::ackMapKey( ackKind, r.key ) ];
                // R1 IDENTITY: stamp the finding's SCRUBBED CONTENT ID alongside the key, so this ack can
                // still be found after a move git records no rename for. Absent (0) for the two clone kinds —
                // their key is a member-SET hash with no single body behind it — and the row is then written
                // exactly as it is today. A REFRESH, not a preserve: re-acking a finding re-reads the body, so
                // the stored cid always describes the code as accepted, never as it was two edits ago.
                const auto          cidIt   = basis.healing.cids.cidByKey.find( r.key );
                const std::uint64_t cid     = ( cidIt == basis.healing.cids.cidByKey.end() ) ? 0u : cidIt->second;
                // P1.4 PROVENANCE: `by` follows the SAME rule the reason does one line down — set from this
                // run when this run supplies one, PRESERVED otherwise. A later scope-less re-ack therefore
                // refreshes the magnitude without erasing the record of who accepted the row originally,
                // which is the only reading under which the foreign-ack sweep means anything.
                // REASON CLOBBER FIX (round 2026-08-29): a re-ack that supplies a DIFFERENT reason no longer
                // overwrites the row's existing one outright — composeAckReason folds it in as
                // "<new> | prior: <old>" (capped at one hop; a no-op when the reason is unchanged), so a
                // shared row re-acked by unrelated sessions keeps both justifications instead of the last
                // writer silently erasing the one before it. See quality.h's composeAckReason for the rule.
                rec = quality::AckRecord{ ackKind, r.key, std::max( rec.ackNow, r.now ), cid,
                                          scope.active() ? scope.spec : rec.by,
                                          cfg.qualityAckReason.empty() ? rec.reason
                                                                       : quality::composeAckReason( rec.reason, std::string( cfg.qualityAckReason ) ) };
            }
            if( ackWritten == 0 && !cfg.qualityAckOnly.empty() )
            {
                std::fprintf( stderr, "ripwire: --ack-only=%.*s matched none of the %zu finding(s) — nothing written\n",
                              int( cfg.qualityAckOnly.size() ), cfg.qualityAckOnly.data(), regs.size() );
                return 1;
            }
            const bool wroteAcks = quality::writeAckRecords( acksFile, acks );
            if( wroteAcks && !cfg.qualityAckOnly.empty() )
            {
                std::fprintf( stderr, "ripwire: acknowledged %zu of %zu finding(s) (%zu left UNACKED by --ack-only, %zu already acked) → %s\n",
                              ackWritten, regs.size(), ackSkipped, ackedCount, acksFile.c_str() );
            }
            else if( wroteAcks )
            {
                std::fprintf( stderr, "ripwire: acknowledged %zu finding(s) (%zu already acked) → %s\n",
                              regs.size(), ackedCount, acksFile.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: could not write %s\n", acksFile.c_str() );
            }
            // P1 — the skip is DISCLOSED, never silent: the count of rows this ack deliberately did not
            // touch is the whole reason the caller passed a scope, and a quiet success would leave them
            // believing the ledger now covers the report they were looking at.
            if( wroteAcks && scope.active() && !outOfScope.empty() )
            {
                std::fprintf( stderr, "ripwire: %zu finding(s) OUT OF SCOPE for --scope=%s were left unacked — not yours to accept "
                                      "(they are still in the report, under the out-of-scope element)\n",
                              outOfScope.size(), scope.spec.c_str() );
            }
            return wroteAcks ? 0 : 1;
        }

        // L2 — stale-ack disclosure (rationale: quality.h's computeStaleAcks). Checked against the CURRENT
        // tree, not the baseline above, so it costs one more computeSnapshot; skipped when the ledger is
        // empty. Reported, never gated — the exit code below reads `regs` alone.
        // R-I: "the CURRENT tree" is the JUDGED tree, which in the ref-pair form is tree B — checking the
        // ledger against the working tree there would report acks as stale because of edits that have nothing
        // to do with the comparison being made.
        const std::vector<quality::StaleAck> staleAcks = acks.empty() ? std::vector<quality::StaleAck>{}
                                                         : quality::computeStaleAcks( acks, refPair
                                                             ? quality::computeSnapshot( refs.target().ing, refs.target().g, refs.target().root )
                                                             : quality::computeSnapshot( ing, g, cfg.rootPath ) );

        // P1.4 — the <sa> family now carries THREE whys, and the third is counted SEPARATELY: stale= means
        // "this ack no longer applies", and a foreign ack applies fine — it is the SESSION that was wrong,
        // not the target. Merging the rows into one list keeps the two emitters from growing a second loop
        // each; keeping the COUNTS apart keeps stale= meaning what it has always meant.
        std::vector<quality::StaleAck> saRows = staleAcks;
        saRows.insert( saRows.end(), foreignAcks.begin(), foreignAcks.end() );

        // r26 ORIGIN SPLIT — three counts over the VISIBLE (post-ack) findings, one pass:
        //   minorCount      — the materiality tier (unchanged axis).
        //   newSymbolCount  — findings that exist only because the code is NEW (quality.h's origin axis).
        //   gatingCount     — the EXIT PREDICATE: preexisting-worse AND major. Emitted as gating= so the
        //                     header alone tells you the exit code (it used to be "regressions > minor").
        // preexisting-worse = regressions − new-symbol by construction (the axis is a partition), so the two
        // header counters always sum to regressions= — an invariant the gate asserts.
        std::size_t minorCount = 0, newSymbolCount = 0, gatingCount = 0;
        for( const quality::Regression& r : regs )
        {
            if( r.isMinor )
            {
                ++minorCount;
            }
            if( r.isNewSymbol )
            {
                ++newSymbolCount;
            }
            else if( !r.isMinor )
            {
                ++gatingCount;
            }
        }
        const std::size_t preexistingCount = regs.size() - newSymbolCount;

        // R1 IDENTITY — the disclosure, built ONCE for both emitters (quality::identityDisclosure). An ack
        // that follows a rename is a claim about identity, and a claim is only honest if the reader can see
        // what it rested on; building the XML and JSON halves in one place is what keeps the two surfaces
        // from disclosing different things about the same run.
        const auto [ identityAttrs, identityJson ] = quality::identityDisclosure( basis.healing );

        // P1/P1.4 — the scope disclosure, built once for both emitters (quality::scopeDisclosure).
        const auto [ scopeAttrs, scopeJson ] = quality::scopeDisclosure( scope, outOfScope.size(), scopedOutGating, foreignAcks.size(), diffFileCount );

        // F-13 — the .ripwire_config disclosure, built once for both emitters (see the header comment on
        // registerMacroConfigWarningAttr just above runQualityViews for why the stderr wording lives there).
        const rw::quality::RegisterMacroConfigDiagnostics configDiag = rw::quality::diagnoseRegisterMacroConfig( ing, root );
        const std::string configWarnAttr = registerMacroConfigWarningAttr( configDiag );

        // P2.5 — one stderr line NAMING the gating finding, in --token-budget's style ("ripwire: --token-budget
        // exceeded: est_tokens=… > budget=…"). stdout is the machine artifact and a caller that only checks
        // `$?` gets a number with no subject; this puts the WHICH on the channel a human reads, without
        // touching the XML contract. Names the first gating row in the already-sorted list (deterministic).
        //
        // §A4 (minor): emitted BEFORE the format fork, not after the XML tail — under --json the fork returned
        // first, so exactly the caller most likely to be a script reading `$?` got the bare exit=2 with no
        // subject. The line is about the EXIT CODE, which both formats share, so it belongs to neither.
        if( gatingCount > 0 )
        {
            const quality::Regression* first = nullptr;
            for( const quality::Regression& r : regs )
            {
                if( !r.isNewSymbol && !r.isMinor ) { first = &r; break; }
            }
            if( first )
            {
                const std::string at = first->path.empty() ? std::string{}
                                                           : " at " + first->path + ":" + std::to_string( first->line );
                std::fprintf( stderr, "ripwire: --quality-delta gating: %zu preexisting-worse major finding(s); first: %s %s%s (was=%u now=%u)\n",
                              gatingCount, first->kind.c_str(), first->sym.c_str(), at.c_str(), first->was, first->now );
            }
        }

        // L2: --json — same regressions, keys mirror the XML attr names (kind/sym/members/tokens/was/now/
        // sev/churn/surface). jsonUnsupportedVerb already refused --quality-baseline/--quality-ack, so
        // reaching here with cfg.json means the plain --quality-delta report.
        if( cfg.json )
        {
            const char* baseMarkerJ = baseSel.marker;   // R3: the one spelling table lives in quality::selectBaseline — the XML/JSON twins cannot drift apart
            // The JSON sibling of the XML at= anchor — "at":null (never a fake sha) on a non-git root, and
            // null in the ref-pair form too: the list was not computed "at" any working-tree state, and the
            // two refs below ARE its anchor.
            const std::string atValJ  = refPair ? std::string{} : gitstamp::stampAt( root );
            const std::string atJsonJ = atValJ.empty() ? std::string( "null" ) : ( "\"" + atValJ + "\"" );
            // R-I: the same two shas + the same unmeasurable-kind disclosure the XML root carries, spelled in
            // JSON. Empty for the bare form, so that object stays byte-identical to before.
            // F-13: config-warnings is the JSON sibling of the XML config-warnings= attribute — omitted
            // (never 0) when .ripwire_config carried nothing to disclose, same "absent means never happened,
            // 0 means checked and clean" rule scopeJson/identityJson already follow.
            const std::string configWarnJson = configDiag.total() == 0 ? std::string()
                                              : ",\"config-warnings\":" + std::to_string( configDiag.total() );
            std::printf( "{\"baseline\":\"%s\",\"regressions\":%zu,\"minor\":%zu,\"acked\":%zu,\"stale\":%zu,"
                         "\"preexisting-worse\":%zu,\"new-symbol\":%zu,\"gating\":%zu,\"register-macro-excluded\":%zu,\"at\":%s%s%s%s%s,\"r\":[",
                         jsonStr( baseMarkerJ ).c_str(), regs.size(), minorCount, ackedCount, staleAcks.size(),
                         preexistingCount, newSymbolCount, gatingCount, basis.registerMacroExcluded, atJsonJ.c_str(), refs.jsonAttrs.c_str(),
                         identityJson.c_str(), scopeJson.c_str(), configWarnJson.c_str() );
            // P1: one row emitter, called for both halves of the scope partition — the disclosed rows carry
            // the identical key set, so nothing about a row changes by being someone else's. `gatingAllowed`
            // is the ONE difference: an out-of-scope row is not what the exit code fires on, so claiming
            // gating on it would contradict the exit code in the same document.
            const auto emitJsonRow = [ & ]( const quality::Regression& r, bool gatingAllowed )
            {
                std::printf( "{\"kind\":\"%s\"", jsonStr( r.kind ).c_str() );
                if( r.kind == "duplication" )
                {
                    std::printf( ",\"members\":\"%s\",\"tokens\":%u", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now );
                }
                else
                {
                    std::printf( ",\"sym\":\"%s\"", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str() );
                    if( !( r.kind == "dead-code" ) && !( r.kind == "api-surface" && r.was == r.now ) )
                    {
                        std::printf( ",\"was\":%u,\"now\":%u", r.was, r.now );
                    }
                }
                if( !r.path.empty() )
                {
                    std::printf( ",\"p\":\"%s:%u\"", jsonStr( r.path ).c_str(), r.line ); // P2.5 locator
                }
                if( gatingAllowed && !r.isNewSymbol && !r.isMinor )
                {
                    std::printf( ",\"gating\":true" ); // P2.5 — the exit predicate, stated per row
                }
                if( r.isMinor )
                {
                    std::printf( ",\"sev\":\"minor\"" );
                }
                if( !r.facet.empty() )
                {
                    const char* facetName = quality::facetAttrName( r.kind );   // ONE kind→name table (quality.h)
                    if( facetName )
                    {
                        std::printf( ",\"%s\":\"%s\"", facetName, jsonStr( r.facet ).c_str() );
                    }
                }
                if( r.isNewSymbol )
                {
                    std::printf( ",\"origin\":\"new-symbol\"" ); // absent = preexisting-worse (mirrors the XML)
                }
                std::printf( "}" );
            };
            bool firstR = true;
            for( const quality::Regression& r : regs )
            {
                if( !firstR )
                {
                    std::printf( "," );
                }
                firstR = false;
                emitJsonRow( r, /*gatingAllowed=*/true );
            }
            std::printf( "]," );
            if( scope.active() )
            {
                // The JSON sibling of the XML out-of-scope element: a SEPARATE array, never a flag on a row
                // in "r", so a consumer that reads "r" and checks "gating" cannot accidentally count someone
                // else's debt as this run's. Emitted (possibly empty) whenever a scope was given, so its
                // absence means "no scope", never "no disclosed rows".
                std::printf( "\"oos\":[" );
                bool firstO = true;
                for( const quality::Regression& r : outOfScope )
                {
                    if( !firstO )
                    {
                        std::printf( "," );
                    }
                    firstO = false;
                    emitJsonRow( r, /*gatingAllowed=*/false );
                }
                std::printf( "]," );
            }
            std::fputs( quality::staleAcksJsonArray( saRows ).c_str(), stdout );   // L2 — "sa":[...], same taxonomy as the XML sa= rows below
            std::printf( "}" );
            return gatingCount > 0 ? 2 : 0;
        }

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B7.1 (CA4) — the heading used to open "only what changed for the WORSE vs
        // .ripwire_quality_baseline", which is FALSE in every state but one: three of the five floors this
        // verb can use are not that file, and in one of them the file was judged stale and DELETED from the
        // user's tree during this very run. The floor actually used is named by baseline= on the element
        // below, so the heading points at that attribute instead of asserting a floor.
        //
        // 2026-09-02 (lane B): the marker states are still defined on the first screen — the only place a
        // reader meets them — but ONE state per run, the one in force, rather than all five on every call.
        // emitQualityDeltaLegend above holds the section table and the reasoning; it is passed the same
        // values the root element below prints, so "the legend defines what the header emits" is read off
        // one set of values rather than restated as a second condition that could drift from it.
        emitQualityDeltaLegend( { baseSel.marker, refPair, identityAttrs, !saRows.empty(), ackedCount > 0,
                                  basis.registerMacroExcluded > 0, configDiag.total() > 0, regs, outOfScope,
                                  scope.active() || !foreignAcks.empty(), !foreignAcks.empty() } );
        const char* baseMarker = baseSel.marker;    // R3: ditto — one seam decides staleness AND names it
        // at= anchors this regression list to the commit (+dirty state) it was computed against.
        std::printf( "<quality-delta baseline=\"%s\" regressions=\"%zu\" minor=\"%zu\" acked=\"%zu\" stale=\"%zu\" preexisting-worse=\"%zu\" new-symbol=\"%zu\" gating=\"%zu\" register-macro-excluded=\"%zu\"%s%s%s%s%s>",
                     baseMarker, regs.size(), minorCount, ackedCount, staleAcks.size(), preexistingCount, newSymbolCount, gatingCount, basis.registerMacroExcluded,
                     // R-I: at= is OMITTED for the ref-pair form rather than stamped with the working tree's
                     // sha, which would anchor the list to a commit it was not computed from. base_ref= and
                     // target_ref= are the anchor there, and they carry FULL shas because a wave measurement
                     // gets quoted into handoffs where a 9-char prefix is one collision from unverifiable.
                     refPair ? "" : gitstamp::atAttr( root ).c_str(), refs.attrs.c_str(), identityAttrs.c_str(),
                     scopeAttrs.c_str(), configWarnAttr.c_str() );
        // P1: ONE row emitter for both halves of the scope partition — a disclosed row carries the identical
        // attribute set, because nothing about a finding changes by belonging to someone else. `gatingAllowed`
        // is the one difference: an out-of-scope row is not what the exit code fires on, and a gating
        // attribute on it would contradict the header's own gating counter inside the same document.
        const auto emitRow = [ & ]( const quality::Regression& r, bool gatingAllowed )
        {
            // duplication carries a member LIST (members=) + token count; the per-symbol was/now kinds
            // (complexity/verbosity/nesting/params) carry was/now; api-surface + dead-code are sym-only.
            // sev="minor" marks a below-materiality delta (never gates); absent = major.
            const char* sev = r.isMinor ? " sev=\"minor\"" : "";
            // B10.2 — the optional classification facet: attribute NAME is chosen by kind (churn=
            // short-horizon-churn's self/ambient split; surface= api-surface's new-symbol/contract-change
            // tier; idiom= the duplication kind's recognized clone-body shape); r.facet carries only the
            // VALUE, and quality::facetAttrName is the ONE table that maps kind → attribute name for all
            // three emitters (this one, the --json twin above, and the MCP one).
            std::string facetAttr;
            if( !r.facet.empty() )
            {
                const char* facetName = quality::facetAttrName( r.kind );
                if( facetName )
                {
                    facetAttr = std::string( " " ) + facetName + "=\"" + r.facet + "\"";
                }
            }
            // r26 — the ORIGIN axis, emitted LAST so the existing attribute order is untouched. Present only
            // on new-symbol rows (absent = preexisting-worse), the same "mark the exception" convention sev=
            // uses. api-surface's own surface="new-symbol" facet is the same fact narrowed to that kind; it
            // stays for shape compatibility, and origin= is what the exit gate reads.
            const char* origin = r.isNewSymbol ? " origin=\"new-symbol\"" : "";
            // P2.5 — the two attributes that make a row ACTIONABLE, appended last so every pre-r27 attribute
            // keeps its position:
            //   p="path:line" — sym= is a canonical id whose display tail is often a bare one-letter local
            //     (`sym="cc"`), i.e. ungreppable. Omitted, never faked, when no locator was resolvable.
            //   gating="1"    — marks exactly the rows the header's gating= counts and the exit code fires on.
            //     Until now a gating row was identifiable ONLY by the ABSENCE of sev="minor" (and of
            //     origin="new-symbol") — absence-as-signal is the least machine-friendly encoding available.
            std::string locAttr;
            if( !r.path.empty() )
            {
                locAttr = " p=\"" + ex( r.path ) + ":" + std::to_string( r.line ) + "\"";
            }
            const char* gatingAttr = ( gatingAllowed && !r.isNewSymbol && !r.isMinor ) ? " gating=\"1\"" : "";
            if( r.kind == "duplication" )
            {
                std::printf( "<r kind=\"duplication\" members=\"%s\" tokens=\"%u\"%s%s%s%s%s/>", ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
            else if( r.kind == "dead-code" )
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            // B10.2e: api-surface now carries two shapes — a brand-new/newly-public symbol (was=now=0, no
            // param comparison to show) and a param-count contract-change (was/now = the real counts). Print
            // was/now whenever they differ from each other so the contract-change case's was=/now= is visible
            // while the new-symbol case's meaningless was="0" now="0" is omitted, matching its old sym-only shape.
            }
            else if( r.kind == "api-surface" && r.was == r.now )
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
            else
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\" was=\"%u\" now=\"%u\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.was, r.now, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
        };
        for( const quality::Regression& r : regs )
        {
            emitRow( r, /*gatingAllowed=*/true );
        }
        if( scope.active() )
        {
            // P1 — the DISCLOSURE half. Dropping these rows would make a scoped report a quieter lie than
            // the unscoped one it replaces: the debt is real, it is in the same tree, and it will be in
            // someone's report. So they are printed, in their own element, marked non-gating, with the one
            // sentence a reader needs written where they meet it. Emitted even when EMPTY — an absent
            // element then means "no scope was given", never "nobody else has anything open".
            std::printf( "<out-of-scope n=\"%zu\" would-gate=\"%zu\" note=\"not yours - do not ack: these rows lie outside the scope this run named. "
                         "They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.\">",
                         outOfScope.size(), scopedOutGating );
            for( const quality::Regression& r : outOfScope )
            {
                emitRow( r, /*gatingAllowed=*/false );
            }
            std::printf( "</out-of-scope>" );
        }
        std::fputs( quality::staleAcksXml( saRows ).c_str(), stdout );   // L2 — one <sa> row per stale ack (quality::staleAcksXml)
        std::printf( "</quality-delta>" );
        return gatingCount > 0 ? 2 : 0;   // r26: only a PREEXISTING-worse AND major regression gates (== gating=)
    }
    return std::nullopt;
}

// ── --dmm ────────────────────────────────────────────────────────────────────────────────────────────────
// The Delta Maintainability Model scalar — the TRENDABLE complement to --quality-delta above, and it sits
// here because the two answer the same question at different resolutions ("which kinds got worse" vs "how
// did this change score, on one scale"). dmm.h owns the whole computation and the emission; this handler
// resolves the flag, splits the ONE user-error case (a revision that does not resolve → a refusal that
// names the offending token, exit 1) from every environment case (no git, a root commit, an archive that
// failed → an UNAVAILABLE report, exit 0), and never gates: a maintainability score with a threshold on it
// is a score people write code to.
std::optional<int> runDmm( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.dmm )
    {
        return std::nullopt;
    }

    const dmm::Result r = dmm::computeDmm( d.root, cfg.dmmRange, d.ing, cfg.excludes, cfg.maxFileBytes );
    if( r.status == dmm::Status::BadRev )
    {
        std::fprintf( stderr, "ripwire: --dmm: '%s' does not resolve to a commit in %s\n", r.badToken.c_str(), d.root.c_str() );
        return 1;
    }
    if( r.status == dmm::Status::BadRange )
    {
        std::fprintf( stderr, "ripwire: --dmm: '%s' uses the three-dot form; --dmm compares two TREES, so spell it A..B "
                              "(or --dmm=$(git merge-base A B)..B if the merge base is what you meant)\n", r.badToken.c_str() );
        return 1;
    }
    return dmm::writeDmmReport( r );
}

// §A10.6: strips a REPEATED leading "./" so `./src`, `././src`, and `src` all compare on the same text —
// used to normalize both the user's --dead-code=DIR filter and every indexed path it is matched against.
inline std::string_view deadCodeStripDotSlash( std::string_view p ) noexcept
{
    while( p.size() >= 2 && p[0] == '.' && p[1] == '/' )
    {
        p.remove_prefix( 2 );
    }
    return p;
}

// §A10.6: the --dead-code=DIR path filter, hoisted out of runQualityViews so the branch lives on its own
// symbol instead of inflating that function's complexity. `anchoredAtRoot` (a LEADING ./ on the RAW arg,
// decided by the caller before dirFilter is normalized) restricts the match to path position 0 — the
// repo ROOT — instead of the default component-anywhere match (leading dir, trailing filename, or an
// interior directory, all at '/' boundaries so `sr` never matches `src/`). Allocation-free: called once
// per indexed file and once per candidate symbol.
//
// W3FIX: position 0 is only the repo root when the indexed path is ROOT-RELATIVE, which it is for
// `ripwire .` (paths read "./src/x.h") and is NOT for `ripwire /abs/repo` (paths read "/abs/repo/src/x.h").
// So the anchored arm matched nothing at all under an absolute root spelling, and --dead-code=./src refused
// with "matches no indexed path" on a tree that plainly has one — the same root-spelling class arch.h's
// relForHash header comment describes for baseline hashes. The fix is that same normalization, reused rather
// than re-derived: strip the ingest root LEXICALLY first, then compare. `root` empty ⇒ the leading-./ strip
// alone, i.e. byte-identical to the pre-fix relative-root behavior.
inline bool deadCodeFilterMatchesPath( std::string_view path, std::string_view dirFilter, bool anchoredAtRoot,
                                       std::string_view root = {} ) noexcept
{
    const std::string_view p = anchoredAtRoot ? rw::relForHash( path, root ) : deadCodeStripDotSlash( path );
    if( anchoredAtRoot )
    {
        if( dirFilter.size() > p.size() || p.substr( 0, dirFilter.size() ) != dirFilter )
        {
            return false;
        }
        const std::size_t afterEnd = dirFilter.size();
        return afterEnd == p.size() || p[ afterEnd ] == '/';
    }
    for( std::size_t at = p.find( dirFilter ); at != std::string_view::npos; at = p.find( dirFilter, at + 1 ) )
    {
        const std::size_t afterEnd = at + dirFilter.size();
        const bool leftOnBoundary  = at == 0 || p[ at - 1 ] == '/';
        const bool rightOnBoundary = afterEnd == p.size() || p[ afterEnd ] == '/';
        if( leftOnBoundary && rightOnBoundary )
        {
            return true;
        }
    }
    return false;
}

// --quality-panel[=PRESET]: THE SINGLE COMMAND (qualitypanel.h owns the join, the preset selection AND its
// emission, the way --ensemble owns its own). Its own function rather than a block inside runQualityViews:
// that dispatcher is already the tree's third-most complex symbol, and this verb needs three statements the
// other branches there do not (a preset parse, a refusal, a churn mining pass).
//
// It is dispatched from runQualityViews rather than from runMaintenanceViews beside --ensemble because two of
// its six families need what that dispatcher has and this one does not: the call graph (the state family's
// closure) and the value-use references (both new families) — see needsValueUses below.
//
// THE PRESET REFUSAL LIVES HERE, not in validateModifierGuards, and that is deliberate: the preset vocabulary
// belongs to the verb (qualitypanel.h), and cli.h is a leaf that includes only ingest.h. Pulling the whole
// lens stack into the argument parser to spell three names would be a worse trade than refusing one step
// later. Refusing at all is the point — silently substituting `default` for a preset the caller did not name
// answers a different question under the label they typed.
//
// GIT IS OPTIONAL, exactly as it is for --ensemble: five of the six families need no history, so a failed
// mining pass hands the join a nullptr and the historical family is reported UNAVAILABLE rather than as
// "did not fire". --since is deliberately not plumbed in — the churn window is part of the disclosed
// threshold set and one fixed 12-month window keeps hrank= comparable between runs.
int runQualityPanel( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    qpanel::Preset preset = qpanel::Preset::Default;
    if( !cfg.qualityPanelPreset.empty() && !qpanel::parsePreset( cfg.qualityPanelPreset, preset ) )
    {
        std::fprintf( stderr, "ripwire: --quality-panel: unknown preset '%.*s' (supported: strict|default|lenient; "
                              "bare --quality-panel is default)\n",
                      int( cfg.qualityPanelPreset.size() ), cfg.qualityPanelPreset.data() );
        return 1;
    }

    std::vector<std::uint32_t> churn( ing.files.size(), 0 );
    const rw::SinceScope       noScope;
    const bool                 churnOk = mineChurnPerFile( ing, d.root, d.multiRoot, d.ws, std::string_view(), noScope,
                                                           rw::ensemble::kEnsembleChurnSince, churn );
    return qpanel::writePanelReport( ing, d.g, churnOk ? &churn : nullptr, d.root, preset, cfg.pageLimit, cfg.pageOffset );
}

// The residual of §6.3's extraction: --dead-code, the only branch left in runQualityViews. main() calls it
// immediately after runQualityDelta, i.e. in the position the old two-branch chain evaluated it.
std::optional<int> runQualityViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // across every lens dispatched from this function.
    const bool         qvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  qvRootPrefix = qvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  qvRootEsc;
    const std::string  qvRootAttr   = qvSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], qvRootEsc ) ) + "\"" ) : std::string();

    // --readability: the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, per function, LEAST readable
    // first (readability.h owns the measurement AND its emission, the way --handoff owns its packet). It
    // reads only the symbol table and the files on disk, so it needs neither the graph nor git — and it is
    // a LENS: exit 0 always, no verdict, no threshold.
    if( cfg.readability )
    {
        return writeReadabilityReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --comment-coherence: two published content measures per documented function/method (Steidl c_coeff
    // + Scalabrino CIC) — commentcoherence.h owns the measurement AND its emission, the same shape as
    // --readability. Symbol table + files on disk only; no graph, no git; a LENS: exit 0 always.
    if( cfg.commentCoherence )
    {
        return writeCommentCoherenceReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --nonlocal-state: per function, the non-local MUTABLE state it or its transitive callees reach, reads
    // and writes kept apart (nonlocalstate.h owns the discovery, the closure AND its emission, the way
    // --readability does). It needs the symbol table, the value-use references and the call graph — but no
    // git — and it is a LENS: exit 0 always, no verdict, no threshold, every count a disclosed floor.
    if( cfg.nonlocalState )
    {
        return nonlocal::writeNonLocalStateReport( ing, g, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    if( cfg.qualityPanel )
    {
        return runQualityPanel( d );
    }

    // --naming-calibration: §9.5 — the naming-* lint rules judged against the repo's OWN rename history
    // (renamemine.h owns the mining, the join, the scoring AND the emission, the way --readability does).
    // It walks git and reads the symbol table; it needs no graph. Exit 0 always — a measurement, not a
    // verdict: test/namingcalibrationcheck.sh is where the per-rule floor lives.
    if( cfg.namingCalibration )
    {
        return renamemine::writeNamingCalibrationReport( ing, d.root );
    }

    // --naming-consistency: §9.2 TIER A convention normalization — the corpus's own case-convention vote,
    // read-only, graph-free (namingconsistency.h owns the scan, the decision and the emission). Exit 0
    // always — a lens, not a gate.
    if( cfg.namingConsistency )
    {
        return namingconsistency::writeNamingConsistencyReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --dead-code[=DIR]: HIGH-CONFIDENCE candidates only. Zero callers is incomplete whole-program evidence,
    // so the default reports source-defined free functions with explicit internal (`static`) linkage. External
    // entry points, methods, header definitions and declarations are excluded. There is no broad product mode,
    // so do not overload the directory filter with lower-confidence behavior.
    // Output: deterministic (sorted by file path then line), terse XML consistent with other report verbs.
    if( cfg.deadCode )
    {
        const auto* inRo = g.inEdges.rowOffsets();    // in-edge CSR row offsets: inDeg(i) = inRo[i+1]-inRo[i]
        std::vector<std::string> sourceByFile( ing.files.size() );
        std::vector<char>        sourceLoaded( ing.files.size(), 0 );
        const auto sourceFor = [ & ]( std::uint32_t fileId ) -> const std::string&
        {
            if( sourceLoaded[fileId] )
            {
                return sourceByFile[fileId];
            }
            sourceLoaded[fileId] = 1;
            std::FILE* file = std::fopen( diskPath( ing, fileId ).c_str(), "rb" );
            if( !file )
            {
                return sourceByFile[fileId];
            }
            std::fseek( file, 0, SEEK_END );
            const long byteCount = std::ftell( file );
            std::fseek( file, 0, SEEK_SET );
            if( byteCount > 0 )
            {
                sourceByFile[fileId].resize( std::size_t( byteCount ) );
                const std::size_t bytesRead = std::fread( sourceByFile[fileId].data(), 1, std::size_t( byteCount ), file );
                sourceByFile[fileId].resize( bytesRead );
            }
            std::fclose( file );
            return sourceByFile[fileId];
        };
        // lane/safe-delete: the scan itself now lives in sourceHasStaticToken (near isHeaderPath, above) —
        // --safe-delete's dead_code_candidate= asks the identical question for one already-resolved symbol
        // and needs the same predicate, not a second derivation of it. This lambda keeps only what is
        // --dead-code's own: the per-file sourceFor() cache amortizing the scan across every candidate.
        const auto hasStaticToken = [ & ]( const Symbol& symbol ) -> bool
        {
            return sourceHasStaticToken( sourceFor( symbol.fileId ), symbol.sigStartByte, symbol.sigEndByte );
        };

        // P2.2 (agent-friction round, 2026-08-29): a symbol whose OWN signature text is a registered
        // self-registering macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P,
        // Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds —
        // see quality::kBuiltinRegisterMacros) is EXEMPT here too, not only from --quality-delta's dead
        // kind. hasStaticToken alone does not structurally exclude these: it scans [sigStartByte,
        // sigEndByte), which for a doctest/Catch2 title INCLUDES the title text — a TEST_CASE titled
        // "handles static config" contains the whole-word token "static" and was reported as high-
        // confidence dead-code before this fix (test/registermacrocheck.sh pins the repro). Reuses this
        // block's own sourceFor() cache rather than re-reading files via forEachSymbolBody.
        const std::vector<std::string> registerMacroNames = quality::registeredMacroNames( d.root );
        // F-13 — same disclosure --quality-delta's runQualityDelta prints, built once here too: an
        // unrecognized .ripwire_config key or an inert register_macros= name used to be a silent no-op on
        // this verb as well.
        const quality::RegisterMacroConfigDiagnostics dcConfigDiag  = quality::diagnoseRegisterMacroConfig( ing, d.root );
        const std::string                             dcConfigWarn = registerMacroConfigWarningAttr( dcConfigDiag );
        const auto isRegisteredMacroSymbol = [ & ]( const Symbol& symbol ) -> bool
        {
            const std::string& src = sourceFor( symbol.fileId );
            if( symbol.sigStartByte >= src.size() )
            {
                return false;
            }
            return quality::startsWithRegisteredMacro( std::string_view( src ).substr( symbol.sigStartByte ), registerMacroNames );
        };
        std::size_t registerMacroExcluded = 0;   // P2.2: disclosed count — see the header comment below

        // Optional path filter (--dead-code=DIR). §P0.3: this was a bare SUFFIX test, so it could only ever
        // match a FILENAME — every directory argument produced count="0" with confidence="high", and a typo'd
        // directory was byte-identical to a real one. It now matches a directory PREFIX, a trailing path
        // component, or the whole path, all at directory boundaries so `src` never matches `srcmut/` —
        // UNLESS the filter carries a leading ./, which anchors it at the repo root instead (§A10.6,
        // deadCodeFilterMatchesPath above: `./src` matches only the top-level src/ subtree, never an
        // interior `*/src/*` component that the bare `src` spelling also, correctly, matches).
        //
        // W3FIX: `root` is handed to the anchored arm so "position 0" means the repo root under EVERY root
        // spelling. Without it the anchored match compared the filter against an ABSOLUTE indexed path and
        // could never hit, so `ripwire /abs/repo --dead-code=./src` refused where `ripwire . --dead-code=./src`
        // answered. The unanchored (component-anywhere) arm never read the root and is untouched.
        const std::string_view dirFilterRaw = cfg.deadCodeDir;
        std::string_view       dirFilter = deadCodeStripDotSlash( dirFilterRaw );
        while( !dirFilter.empty() && dirFilter.back() == '/' )
        {
            dirFilter.remove_suffix( 1 ); // `test/` ≡ `test`
        }
        const bool anchoredAtRoot = dirFilterRaw.size() >= 2 && dirFilterRaw[ 0 ] == '.' && dirFilterRaw[ 1 ] == '/';
        const auto filterMatchesPath = [ & ]( std::string_view path ) noexcept -> bool
        {
            return deadCodeFilterMatchesPath( path, dirFilter, anchoredAtRoot, d.root );
        };

        // A filter that names nothing in the indexed tree is a user error, not a measurement: refuse loudly
        // rather than ship `count="0" confidence="high"` about a directory that was never crawled.
        if( !dirFilter.empty() )
        {
            bool filterHitsIndex = false;
            for( const std::string& indexedPath : ing.files )
            {
                if( filterMatchesPath( indexedPath ) ) { filterHitsIndex = true; break; }
            }
            if( !filterHitsIndex )
            {
                std::fprintf( stderr, "ripwire: --dead-code=%.*s matches no indexed path — a zero here would be a failure, not a measurement "
                                      "(pass a directory or file that exists in the tree, e.g. ripwire <dir> --dead-code=src)\n",
                              int( dirFilterRaw.size() ), dirFilterRaw.data() );
                return 1;
            }
        }

        // collect candidates: in-degree == 0, not exported, sorted for determinism
        std::vector<NodeId> candidates;
        candidates.reserve( 64 );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Function )
            {
                continue; // methods and non-callable nodes are out of scope
            }
            if( s.sigEndByte >= s.endByte )
            {
                continue; // declarations have no deletion evidence
            }
            if( isHeaderPath( ing.files[s.fileId] ) )
            {
                continue; // may be instantiated by external TUs
            }
            if( !hasStaticToken( s ) )
            {
                continue; // external linkage may be an entry point/API
            }

            // optional path filter: directory prefix, trailing component, or the whole path
            if( !dirFilter.empty() && !filterMatchesPath( ing.files[s.fileId] ) )
            {
                continue;
            }

            // in-degree == 0 → no call in the indexed tree reaches this symbol
            const std::uint32_t inDeg = inRo[ s.id + 1 ] - inRo[ s.id ];
            if( inDeg != 0 )
            {
                continue;
            }
            if( isRegisteredMacroSymbol( s ) )
            {
                ++registerMacroExcluded;   // P2.2: self-registers via a static initializer — never dead-code
                continue;
            }
            candidates.push_back( s.id );
        }

        // deterministic order: file path asc, then line asc, then name asc (stable across runs)
        std::sort( candidates.begin(), candidates.end(), [ & ]( NodeId a, NodeId b )
        {
            const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
            const std::string& pa = ing.files[ sa.fileId ];  const std::string& pb = ing.files[ sb.fileId ];
            if( pa != pb )
            {
                return pa < pb;
            }
            if( sa.line != sb.line )
            {
                return sa.line < sb.line;
            }
            return sa.name < sb.name;
        } );

        std::printf( "<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. "
                     "A bare-name filter matches by path COMPONENT: filter=\"src\" keeps any path with a src segment at any depth "
                     "(test/x/src/y.cpp included); anchor with ./ (filter=\"./src\") to pin the root-level directory only. "
                     "register-macro-excluded= counts symbols excluded because their OWN definition is a registered "
                     "self-registering test/benchmark macro call (doctest/Catch2 TEST_CASE family, GoogleTest TEST/TEST_F/TEST_P, "
                     "Google Benchmark BENCHMARK family, plus any name a .ripwire_config register_macros= line adds): such a "
                     "symbol registers itself through a static initializer the call graph cannot see, so zero in-edges on it is "
                     "not evidence of anything — never a finding, never gating, absent nothing (0 is printed, not omitted). "
                     "config-warnings= counts two DISCLOSED .ripwire_config problems, each also written to stderr — an "
                     "unrecognized key, and a register_macros= name matching no indexed symbol — never gating, present "
                     "only when non-zero. "
                     "Graph evidence is local to the indexed tree; verify before deleting. %s-->", rw::kGraphCountFloorBriefLegend );
        // §P15/§P16: candidates is already deterministically sorted (path asc, line asc, name asc) and used to
        // print every candidate unconditionally — completeness was the whole contract, matching --uses' shape,
        // so it pages the same way: no historic display cap, discloseCap=false (un-paginated tag byte-identical).
        const PageWindow  dcPw = pageWindow( candidates.size(), cfg.pageLimit, cfg.pageOffset );
        char              dcAb[ kPageDisclosureCap ];
        // V2-7: a FILTERED zero must not be byte-identical to an unfiltered clean tree — with the ./-anchor
        // and component spellings now giving different answers for the same word, the root says which
        // filter produced this count. Absent = no filter, whole tree (never an empty filter="").
        std::string dcFilterAttr;
        if( !cfg.deadCodeDir.empty() )
        {
            std::vector<char> dcFiltEsc;
            dcFilterAttr = " filter=\"" + std::string( escapeXml( cfg.deadCodeDir, dcFiltEsc ) ) + "\"";
        }
        std::printf( "<dead-code count=\"%zu\" confidence=\"high\" evidence=\"internal-linkage+zero-callers\" register-macro-excluded=\"%zu\"%s%s%s%s%s>",
                     candidates.size(), registerMacroExcluded,
                     dcFilterAttr.c_str(),
                     pageDisclosure( dcAb, sizeof( dcAb ), dcPw.end - dcPw.begin, candidates.size(), dcPw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     qvRootAttr.c_str(), dcConfigWarn.c_str(),
                     rw::kGraphCountFloorAttrXml );   // H5: "zero callers" is a claim about the name-based CSR — a floor
        std::vector<char> dcEsc;
        for( std::size_t candidateIndex = dcPw.begin; candidateIndex < dcPw.end; ++candidateIndex )
        {
            const NodeId candidateId = candidates[ candidateIndex ];
            const Symbol& s = ing.symbols[ candidateId ];
            // name and path may contain & < > " — escape both so output is valid XML.
            const auto en = rw::escapeXml( s.name, dcEsc );
            std::printf( "<d n=\"%.*s\" t=\"%s\"", int( en.size() ), en.data(), symTag( s.kind ) );
            const std::string_view rp = qvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], qvRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            const auto ep = rw::escapeXml( rp, dcEsc );
            std::printf( " p=\"%.*s\" l=\"%u\"/>", int( ep.size() ), ep.data(), s.line );
        }
        std::printf( "</dead-code>" );
        return 0;
    }
    return std::nullopt;
}

// --edit-check=SYM (B11/L5): "did MY edit change a contract someone depends on", at edit time, for ONE
// symbol — --quality-delta answers the same question per-DIFF at commit time; this is the fast targeted
// entry point. Resolves SYM exactly like --around/--lego
// (resolveFocus — file:name disambiguates), then compares the WORKING-TREE symbol against the git-HEAD
// baseline (computeHeadSnapshot — the SAME qheadsnap/qsnap cache family --quality-delta's T0.1 auto-baseline
// uses, so a warm run is a cache-blob read, never a fresh git-archive/ingest/clone-detection pass — that is
// what keeps this under the ≤100ms warm budget the gate asserts, unlike --quality-delta's own ~250ms+
// per-call clone recompute over the whole tree). Reuses B10.2's per-canonId MAX-aggregation over the overload
// set (same file+scope+name share one g.canonId) for the was/now params + publicness comparison — NOT a
// single arbitrarily-iterated overload — so a low-param overload can never manufacture a phantom
// contract-change (the exact trap B10 fixed in quality.h; re-implementing it single-overload here would
// reintroduce it). status is exactly one of unchanged / new-symbol / contract-change, and it is the JOIN of
// three facts, not of the was/now pair alone (editcheck.h's editCheckVerdict owns the derivation and its
// reasoning; change= names which fact carried a contract-change):
//   new-symbol       — SYM's canonical id has no baseline record at all (absent from base.locBySym, the same
//                       "existed at baseline in ANY form" test quality.h's api-surface kind uses). Never
//                       escalated: there was no contract to change.
//   contract-change   — SYM existed at baseline AND at least one of THREE was-vs-now facts moved: the params
//                       MAX, publicness, or the definition COUNT (defs_was= vs the root's defs=). The third
//                       exists because the MAX fold is blind to an overload REMOVED below it — both sides keep
//                       the same max while a call site stops binding, and answering "unchanged" there is a
//                       false reassurance from the one verb whose value is the headline word. change= names
//                       which fact carried it; it adds broken-callers as corroboration but never as the sole
//                       cause, because incompatible= describes the CURRENT tree rather than the edit.
//   unchanged         — SYM existed at baseline and none of the three moved (a body-only edit is unchanged by
//                       design: this checks the CONTRACT, not the body — that is --quality-delta's
//                       short-horizon-churn kind's job).
// A non-git root / no HEAD degrades to new-symbol (nothing to compare against) with a DEGRADED_PATH_ALERT —
// never a crash; only an unresolvable SYM refuses loudly (below).
//
// 1-hop callers (reuse the --callers 1-hop in-edge walk, unioned over the whole overload set) are listed with
// any call-site flagged INCOMPATIBLE when its argument count is reliably counted (argCountKnown) AND no
// surviving overload could accept it — every overload with a FIXED arity (arityExact!=0) disagrees, and none
// is a variadic/default-arg/implicit-receiver wildcard that an argument count could never disprove
// (editcheck.h::editCheckImplicitReceiver adds the Python/Ruby half that arityExact cannot express), evaluated
// against the CURRENT (post-edit) overload set.
//
// One-sided IN THE ARITY, not a proof of BINDING — and the emitted legend says so rather than promising
// "provably … never a guess". Call edges are name-based, so a receiver-qualified call to a same-named callee
// this tool does not index is measured against the one definition it does index; an untouched, compiling tree
// therefore carries a nonzero incompatible= on a handful of shared names. See editcheck.h's measurement note
// for the swept numbers and why no cheap sound filter exists.
//
// The contract-comparison core (EditCheckContract / editCheckOverloadSet / editCheckContractVsHead /
// editCheckIncompatibleFlags / editCheckCallers / the whole <edit-check> XML assembler) now lives in
// editcheck.h (L4) as editCheckBundleText() — shared verbatim with the MCP edit_check verb (mcpverbs.h's
// editCheckText()). This handler only resolves the CLI's symbol spec (the shared resolver + the did-you-mean
// refusal message + the §A6a ambiguity refusal) and hands the resolved node to that ONE assembler, this round
// also passing d.notesPtr so a note targeting SYM (or its file) surfaces as a <note> child, the same row
// grammar --for/--expand already use (editCheckBundleText's `ni` parameter defaults to nullptr, so the MCP
// call site is untouched and stays notes-inert for now).
//
// §A6a — an AMBIGUOUS bare name is REFUSED, not silently narrowed. resolveFocus() answers "the lowest-id
// definition with this name", which is the right answer for --around's ego graph and the WRONG one here: this
// verb's whole value is "did I break a contract?", and answered about a definition the agent never edited it
// returns status="unchanged" — reassurance for the wrong symbol. Its siblings can union (--callers reports
// defs="3" and lists the union); a CONTRACT cannot be unioned, so the only honest answers are one definition
// or a refusal that says how to name one. The resolver moves to resolveAllByNameQualified (every match, not
// the lowest id) — byte-identical on any selector that matched exactly one definition site, and it accepts a
// canonical id too, which is the spelling the refusal has to offer when a file alone cannot separate two
// scopes in one file.
std::optional<int> runEditCheck( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;

    if( cfg.editCheckSym.empty() )
    {
        return std::nullopt;
    }

    const std::vector<NodeId> matches = resolveAllByNameQualified( ing, cfg.editCheckSym );
    if( matches.empty() )
    {
        // §B4.2: the shared refusal — see selectorrefuse.h. A `file:name` whose FILE half is the fault used
        // to read as "that symbol does not exist", which sends an agent hunting for a rename that never was.
        std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --edit-check symbol not found: ",
                                                               cfg.editCheckSym, "--edit-check=" ).c_str() );
        return 1;
    }

    const std::vector<EditCheckGroup> groups = editCheckGroups( ing, d.g, matches );
    if( groups.size() > 1 )
    {
        std::fprintf( stderr, "ripwire: --edit-check: %s\n",
                      editCheckAmbiguousMessage( cfg.editCheckSym, groups, "--edit-check=", matches.size() ).c_str() );
        return 1;
    }
    const NodeId focus = groups[0].lowestNode;

    // card A1 — the PRE-APPLY fork. Everything above (resolution, the not-found refusal, the §A6a ambiguity
    // refusal) is shared verbatim, because a preview that resolved its target differently from the post-hoc
    // verb would be answering about a different definition. Below the fork the preview splices the payload
    // over THIS definition's span, re-derives the tree, and calls the SAME assembler; refusals from it are
    // the same shape as this handler's own (stderr, exit 1, nothing on stdout).
    if( editPreviewRequested( cfg ) )
    {
        std::string payload, payloadErr;
        if( !rw::editpreview::readPayload( cfg.editPayload, cfg.maxFileBytes, payload, payloadErr ) )
        {
            std::fprintf( stderr, "ripwire: --edit-check --dry-run: %s\n", payloadErr.c_str() );
            return 1;
        }
        const rw::editpreview::Outcome preview = rw::editpreview::run( ing, d.g, d.root, cfg.maxFileBytes, cfg.excludes,
                                                                        d.valueUses, cfg.editCheckSym, focus, payload, d.notesPtr );
        if( !preview.ok )
        {
            std::fprintf( stderr, "ripwire: --edit-check --dry-run: %s\n", preview.message.c_str() );
            return 1;
        }
        std::fwrite( preview.xml.data(), 1, preview.xml.size(), stdout );
        return 0;
    }

    const std::string xml = editCheckBundleText( ing, d.g, d.root, cfg.maxFileBytes, cfg.excludes, focus, d.notesPtr );
    std::fwrite( xml.data(), 1, xml.size(), stdout );
    return 0;
}

}   // namespace — verbs_quality.h section of main.cpp
