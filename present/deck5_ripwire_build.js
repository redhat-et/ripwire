// deck5_ripwire_build.js — the ripwire public showcase deck.
// Every number is pinned by an instrument in the ripwire repo (docs/EVALS.md is the source of
// truth; §8's refused claims are absent by construction). Every --flag named exists in
// `ripwire --help` — enforced by test/deckcheck.sh, which scans THIS FILE as its `present` family;
// the slide count and the flag count are derived from this file and the binary by
// test/deckclaimcheck.sh. Design: dark, two-tone on the name's own halves — cyan = ripgrep/speed,
// amber = tripwire/honesty.
// Speaker notes: every slide added for 0.6.0 carries its sources in its notes — the PR body, commit,
// doc or web page each figure was read from, quoted. A claim about a change that has not merged yet
// says "pending merge: #N" in those notes and lives in a commit of its own, so it can be kept or dropped
// when that PR lands; once it lands the note says "merged: #N (<merge commit>)" instead, and the figure
// is re-checked against the merged tree. No note on this deck is pending as of main 40a1895b.
const pptxgen = require("pptxgenjs");

const p = new pptxgen();
p.layout = "LAYOUT_WIDE"; // 13.33 x 7.5

// palette
const BG    = "0D1117";
const CARD  = "161D28";
const CARD2 = "1B2432";
const TEXT  = "E6EDF3";
const MUTED = "8B95A5";
const CYAN  = "56D6E8";
const AMBER = "F2B84B";
const GREEN = "4AC26B";
const RED   = "E5534B";
const MONO  = "Courier New";
const SANS  = "Arial";

const W = 13.33, H = 7.5, MX = 0.62;

// ── --quality-delta examples: DATA, not layout ──────────────────────────────────────────────────────────
// The "What --quality-delta catches" slide renders these entries, copied from docs/QUALITY_DELTA_CATALOG.md
// (catalog commit 553dbadb, whose rows were re-derived with a build of main 766913d0). Nothing is invented: a card
// quotes its row's own attributes, and the entry's notes carry the whole row, the commits and the command that
// reproduces it. An empty array renders the slide as a marked placeholder.
//   { kind:    "…",    // the kind exactly as --quality-delta prints it
//     finding: "…",    // quoted from the row: the symbol(s) and the attributes that carry the finding
//     before:  "…",    // the snippet before the change; "\n" separates lines
//     after:   "…",    // the snippet after the change
//     why:     "…",    // one sentence: why the finding matters
//     notes:   ["…"] } // optional speaker-note lines: catalog section, commits, verbatim row, how to reproduce
// At most 6 entries. The note above qdExamples says how much code a pane holds; this slide shows 4, the most that
// leaves each pane 10 lines of 39 columns. The four vary in kind and in outcome: a copy of a helper three callers
// used, folded back; a nested scan, flattened; dead helpers, deleted, beside the one the kind missed; a near-copy
// extracted, whose residue the detector still gates.
const QD_EXAMPLES = [
  { kind: "new-clone-of-reused-helper",
    finding: 'registeredMacroNames | vendoredPathPrefixes',
    before: [
      "std::vector<std::string> out;",
      "for( std::string_view p :",
      "     kBuiltinVendoredPrefixes )",
      "{ … }",
      "for( std::string& extra :",
      "     readRegisterMacrosConfig( root )",
      "         .vendoredPaths )",
      "{ … }",
      "std::sort( out.begin(), out.end() );",
      "out.erase( std::unique( … ), … );",
    ].join("\n"),
    after: [
      "inline std::vector<std::string>",
      "mergeBuiltinsWithConfig( … builtins,",
      "    … fromConfig )",
      "// … reserve, append both lists,",
      "//   sort, unique",
      "// vendoredPathPrefixes( root ):",
      "return mergeBuiltinsWithConfig(",
      "    kBuiltinVendoredPrefixes,",
      "    readRegisterMacrosConfig( root )",
      "        .vendoredPaths );",
    ].join("\n"),
    why: "A helper with three callers, copied while building the feature that measures copies.",
    notes: [
      `Catalog §1, "new-clone-of-reused-helper: a helper written out longhand beside the one it copies" (catalog commit 553dbadb). Commits: base 05f4b892 → before c7e93089 → after cca0bf8d, in the per-kind dials round (PR #127).`,
      `Row, verbatim (05f4b892..c7e93089): <r kind="new-clone-of-reused-helper" sym="src/quality.h::quality::registeredMacroNames | src/quality.h::quality::vendoredPathPrefixes" was="0" now="3" p="src/quality.h:433" gating="1" next="--expand=src/quality.h:vendoredPathPrefixes"/>. The same report gates two duplication rows (tokens="114") and a verbosity row on readRegisterMacrosConfig (was="58" now="69" bar="60").`,
      `Why it is more than a duplication row: now="3" is the fan-in of the helper the copy duplicated, so three call sites already relied on that shape. Both readers now call mergeBuiltinsWithConfig, and the third member (editplan::callersUnionSize) lost its duplication row with it. The commit ran this on the round that built the dials.`,
      `Reproduce: base=05f4b892 before=c7e93089 after=cca0bf8d; git worktree add --detach ../qd-before $before; ./build/ripwire ../qd-before --quality-delta=$base..$before --scope=src/quality.h --legend=compact → the four rows, gating="4", exit 2; with $base..$after → gating="0", exit 0. Re-run 2026-09-11 with a built_from=766913d02 build: both match the catalog.`,
    ] },
  { kind: "nesting",
    finding: 'runChangeViews was="6" now="8" · complexity was="141" now="178"',
    before: [
      "for( … o < ws.size(); ++o )",
      "{",
      "    if( o == r ) { continue; }",
      "    for( char c : perRootChanged[o] )",
      "    {",
      "        if( c )",
      "        {",
      "            if( !elsewhere.empty() ) …",
      "            elsewhere += ws[o].label;",
      "            break;",
    ].join("\n"),
    after: [
      "const std::string elsewhere =",
      "    situRootsHoldingMatches(",
      "        ws, perRootChanged, r );",
      "// … in situRootsHoldingMatches:",
      "if( o != self && std::any_of(",
      "    perRootChanged[o].begin(),",
      "    perRootChanged[o].end(),",
      "    []( char c ) { return c != 0; } ) )",
      "{",
      "    // … labels += ws[o].label;",
    ].join("\n"),
    why: "The inner loop asked one question; it is now std::any_of, in a named function.",
    notes: [
      `Catalog §6, "nesting: an inline scan inside a per-root loop" (catalog commit 553dbadb). Commits: base e3b52d39 → before 4c526577 → after a8e994d1.`,
      `Rows, verbatim (e3b52d39..4c526577): <r kind="nesting" sym="runChangeViews" was="6" now="8" bar="4" p="src/verbs_change.h:245" gating="1" next="--expand=src/verbs_change.h:runChangeViews"/> and <r kind="complexity" sym="runChangeViews" was="141" now="178" bar="15" p="src/verbs_change.h:245" gating="1" next="--expand=src/verbs_change.h:runChangeViews"/>. A third row gates resolveSinceScope's second git-pipe reader (was="6" now="23" bar="15").`,
      `The inner for/if/break asked whether this root has any change, so it is std::any_of, and the scan is a named function that takes two more levels out of the dispatcher. resolveSinceScope now reads both git answers through popenTrimmed, the pipe reader the tree already had; the commit records a first attempt, a private copy of that reader, which the report flagged as a new-clone-of-reused-helper. The dispatcher keeps a minor row (was="141" now="146"): chronic debt this change neither created nor gated on.`,
      `Reproduce: base=e3b52d39 before=4c526577 after=a8e994d1; git worktree add --detach ../qd-before $before; ./build/ripwire ../qd-before --quality-delta=$base..$before --scope=src/verbs_change.h,src/gitmine.h --legend=compact → the three rows, gating="3", exit 2; with $base..$after → minor rows only, gating="0", exit 0. Re-run 2026-09-11 with a built_from=766913d02 build: both match the catalog.`,
    ] },
  { kind: "dead-code",
    finding: 'mentionFilesCut · namesUnkeptPackageIndex',
    before: [
      "inline bool namesFileNotKept( … )",
      "{ … return !unkept.empty(); }",
      "inline bool mentionFilesCut( … )",
      "{",
      "    // …",
      "    return std::any_of( …, [ & ]( … )",
      "    {",
      "        return namesFileNotKept( … );",
      "    } );",
      "}",
    ].join("\n"),
    after: [
      "// all three definitions: deleted",
      "",
      "// the live verdict comes from a line",
      "// that was already there, unchanged:",
      "const std::uint32_t mentionFilesTotal =",
      "    mentionFilesNamedTotal(",
      "        ing, raw, mentionedFiles );",
    ].join("\n"),
    why: "Deleted, not acked. namesFileNotKept had no row: its only caller was dead too.",
    notes: [
      `Catalog §7, "dead-code: helpers a rewrite left with no caller" (catalog commit 553dbadb). Commits: base edbb978d → before 1ec420f1 → after 06414b52.`,
      `Rows, verbatim (edbb978d..1ec420f1): <r kind="dead-code" sym="src/mention.h::mention_detail::mentionFilesCut" p="src/mention.h:467" gating="1" next="--expand=src/mention.h:mentionFilesCut"/> and <r kind="dead-code" sym="src/mention.h::mention_detail::namesUnkeptPackageIndex" p="src/mention.h:397" gating="1" next="--expand=src/mention.h:namesUnkeptPackageIndex"/>.`,
      `The mention cap's verdict changed to total > kept.size(), computed from mentionFilesNamedTotal, and the predicates that used to answer it lost their callers. The commit's own words are "Deleted, not acked." Dead predicates beside a live verdict leave the next reader unsure which answer is authoritative. The kind could see them only because PR #127 replaced its blanket "headers are exported" exclusion with the rule that names what a language invokes (09d4f5fc).`,
      `The limit, disclosed: namesFileNotKept was deleted too, but no row named it, because its only caller was itself dead. Catalog improvement path IP-8, "Dead code is one hop deep".`,
      `Reproduce: base=edbb978d before=1ec420f1 after=06414b52; git worktree add --detach ../qd-before $before; ./build/ripwire ../qd-before --quality-delta=$base..$before --scope=src/mention.h --legend=compact → both rows, gating="2", exit 2; with $base..$after → new-symbol rows only, gating="0", exit 0. Re-run 2026-09-11 with a built_from=766913d02 build: both match the catalog.`,
    ] },
  { kind: "duplication",
    finding: 'withHeaderAttrAfter | withHeaderField  tokens="122"',
    before: [
      "const std::size_t pos =",
      "    line.find( afterField );",
      "// …",
      "std::size_t at =",
      "    pos + afterField.size();",
      "while( at < line.size()",
      "       && line[ at ] >= '0'",
      "       && line[ at ] <= '9' )",
      "{ ++at; }",
      "line.insert( at, attr );",
    ].join("\n"),
    after: [
      "std::pair<std::size_t, std::size_t>",
      "headerFieldDigits( … line, … field )",
      "// … find it, walk its digit run",
      "// withHeaderAttrAfter( … ):",
      "const auto [ start, end ] =",
      "    headerFieldDigits(",
      "        line, afterField );",
      "if( start != std::string::npos )",
      "{",
      "    line.insert( end, attr );",
    ].join("\n"),
    why: "The locator is shared now, yet a 63-token residue still gates: a false positive.",
    notes: [
      `Catalog §3, "duplication, Type-3: two header writers that each located the same digit run" (catalog commit 553dbadb). Commits: base e3b52d39 → before cf24501d → after 6ef4cb0f.`,
      `Row, verbatim (e3b52d39..cf24501d): <r kind="duplication" members="src/recall.h::rw::withHeaderAttrAfter | src/recall.h::rw::withHeaderField" tokens="122" p="src/recall.h:1058" gating="1"/>. withHeaderField spelled the same locator, then replace() instead of insert().`,
      `The locator is now headerFieldDigits, defined once beside the two writers, and each writer states only its own difference: insert or replace. The detector does not agree this is finished. Against the same base the after-tree still gates on the pair: <r kind="duplication" members="src/recall.h::rw::withHeaderAttrAfter | src/recall.h::rw::withHeaderField" tokens="63" p="src/recall.h:1069" gating="1"/>. The catalog classes that residue as a false positive, improvement path IP-4, "An extraction's residue still gates": what the two writers still share is the call to their common helper.`,
      `Reproduce: base=e3b52d39 before=cf24501d after=6ef4cb0f; git worktree add --detach ../qd-before $before; ./build/ripwire ../qd-before --quality-delta=$base..$before --scope=src/recall.h --legend=compact → tokens="122", gating="1", exit 2; with $base..$after → tokens="63", gating="1", exit 2. Re-run 2026-09-11 with a built_from=766913d02 build: both match the catalog.`,
    ] },
];

function bg(s){ s.background = { color: BG }; }
function kicker(s, txt, color){ s.addText(txt, { x: MX, y: 0.42, w: 9, h: 0.32, fontFace: MONO, fontSize: 13, color, margin: 0 }); }
function title(s, txt, opts={}){ s.addText(txt, { x: MX, y: 0.72, w: W-2*MX, h: 0.9, fontFace: SANS, fontSize: opts.size||34, bold: true, color: TEXT, margin: 0 }); }
function foot(s, txt){ s.addText(txt, { x: MX, y: 7.02, w: W-2*MX, h: 0.3, fontFace: MONO, fontSize: 10.5, color: MUTED, margin: 0 }); }
function chip(s, txt, x, y, w, color, opts={}){
  s.addShape("roundRect", { x, y, w, h: opts.h||0.42, fill: { color: opts.fill||CARD2 }, rectRadius: 0.06, line: { color: opts.line||"2A3547", width: 0.75 } });
  s.addText(txt, { x: x+0.06, y, w: w-0.12, h: opts.h||0.42, fontFace: MONO, fontSize: opts.size||12.5, color: color||CYAN, valign: "middle", margin: 0.04 });
}
function card(s, x, y, w, h, fill){ s.addShape("roundRect", { x, y, w, h, fill: { color: fill||CARD }, rectRadius: 0.09, line: { color: "232D3D", width: 0.75 } }); }
function stat(s, big, label, x, y, w, color, opts={}){
  s.addText(big,   { x, y,        w, h: opts.bh||0.95, fontFace: SANS, fontSize: opts.bsize||44, bold: true, color, align: "center", margin: 0 });
  s.addText(label, { x, y: y+(opts.bh||0.95)-0.06, w, h: 0.75, fontFace: SANS, fontSize: opts.lsize||12.5, color: opts.lcolor||MUTED, align: "center", margin: 0 });
}
// a compact N-column row band: used by the table-shaped slides (r4, the ten moments, the ledger).
// opts.w NARROWS the band. It defaults to the full text column, which is what every full-width table
// wants — but a slide with cards beside its table needs the band to stop short of them, or the last
// column renders underneath the card and is clipped. That is one parameter, not a second copy of
// this function.
function row(s, y, h, cols, opts={}){
  const w = opts.w || (W - 2*MX);
  card(s, MX, y, w, h, opts.fill);
  let x = MX + 0.18;
  for (const c of cols){
    s.addText(c.t, { x, y: y+0.03, w: c.w, h: h-0.06, fontFace: c.mono ? MONO : SANS, fontSize: c.size||11.5,
                     bold: !!c.bold, italic: !!c.italic, color: c.color||TEXT, valign: "middle", align: c.align||"left", margin: 0 });
    x += c.w + (c.gap === undefined ? 0.12 : c.gap);
  }
}
// Speaker notes, one line per sourced fact. The notes are where a figure's quote and origin live.
function notes(s, lines){ s.addNotes(lines.join("\n")); }
// A card of [big, label, color] rows under a mono heading: the 0.6.0 overview's four quadrants. Row height
// is shared out of the card, so a quadrant with two rows and one with three keep the same outer frame.
function listCard(s, x, y, w, h, head, headColor, items, opts={}){
  card(s, x, y, w, h, opts.fill);
  s.addText(head, { x: x+0.2, y: y+0.12, w: w-0.4, h: 0.36, fontFace: MONO, fontSize: 14, bold: true, color: headColor, margin: 0 });
  const bigW = opts.bigW || 1.85, top = y + 0.56, rowH = (h - 0.56 - 0.1) / items.length;
  items.forEach(([big, label, c], i) => {
    const ry = top + i * rowH;
    s.addText(big,   { x: x+0.2, y: ry, w: bigW, h: rowH, fontFace: MONO, fontSize: opts.bigSize || 13, bold: true, color: c || TEXT, valign: "middle", margin: 0 });
    s.addText(label, { x: x+0.3+bigW, y: ry, w: w-0.5-bigW, h: rowH, fontFace: SANS, fontSize: opts.lsize || 9.5, color: MUTED, valign: "middle", margin: 0 });
  });
}
// Three story cards in a row: what went confidently wrong, the number, and what catches it now. Each story is
// { tag, headline, what, stat, statLabel, now, gate }. Sized for about 320 characters of `what` and 250 of
// `now` at this width; the honesty slides pass exactly three. The CALLER adds the slide: test/deckclaimcheck.sh
// derives the slide count from the literal addSlide calls in this file, so a helper that added its own slide
// would be counted once however many times it ran.
function storyCards(s, { kick, head, stories, footText }){
  kicker(s, kick, AMBER);
  title(s, head, { size: 32 });
  const GAP = 0.14, cw = (W - 2*MX - 2*GAP) / 3, y = 1.72, h = 5.14;
  stories.forEach((st, i) => {
    const x = MX + i * (cw + GAP), tw = cw - 0.4;
    card(s, x, y, cw, h);
    s.addText(st.tag,       { x: x+0.2, y: y+0.14, w: tw, h: 0.26, fontFace: MONO, fontSize: 10, color: AMBER, margin: 0 });
    s.addText(st.headline,  { x: x+0.2, y: y+0.42, w: tw, h: 0.62, fontFace: SANS, fontSize: 16, bold: true, color: TEXT, valign: "top", margin: 0 });
    s.addText(st.what,      { x: x+0.2, y: y+1.06, w: tw, h: 1.42, fontFace: SANS, fontSize: 10, color: MUTED, valign: "top", margin: 0 });
    s.addText(st.stat,      { x: x+0.2, y: y+2.52, w: tw, h: 0.46, fontFace: MONO, fontSize: 20, bold: true, color: st.statColor || GREEN, valign: "middle", margin: 0 });
    s.addText(st.statLabel, { x: x+0.2, y: y+2.98, w: tw, h: 0.44, fontFace: SANS, fontSize: 9, color: MUTED, valign: "top", margin: 0 });
    s.addText("what catches it now", { x: x+0.2, y: y+3.48, w: tw, h: 0.22, fontFace: MONO, fontSize: 9, color: CYAN, margin: 0 });
    s.addText(st.now,       { x: x+0.2, y: y+3.72, w: tw, h: 1.06, fontFace: SANS, fontSize: 10, color: TEXT, valign: "top", margin: 0 });
    s.addText(st.gate,      { x: x+0.2, y: y+4.8,  w: tw, h: 0.26, fontFace: MONO, fontSize: 8.5, color: MUTED, valign: "middle", margin: 0 });
  });
  if (footText){ foot(s, footText); }
  return s;
}
// "What --quality-delta catches": 1–3 entries lay out as one column of wide cards, 4–6 as two columns; each
// card is a kind + finding header, a before/after pair of mono panes, and a one-line why. With no entries the
// slide is a marked PLACEHOLDER showing three empty frames of that layout — it never renders an invented row.
// Like storyCards, it draws on a slide its caller added. An entry's optional `notes` (an array of strings) is
// printed under that entry in the speaker notes: the catalog section, the commits, the verbatim row, the command.
// Pane capacity (Courier New advances 0.6 em; text boxes keep their default inset): with 4 entries, measured on the
// render, a pane holds 10 lines of 39 columns at 8 pt, and a 40-column line wraps. By the same arithmetic 2 entries hold
// about 10 lines of 69 columns at 9.5 pt, and 3, 5 or 6 entries about 3 lines.
function qdExamples(s, entries){
  if (entries.length > 6){ throw new Error(`QD_EXAMPLES has ${entries.length} entries; the slide is laid out for at most 6`); }
  entries.forEach((e, i) => {
    for (const k of ["kind", "finding", "before", "after", "why"]){
      if (typeof e[k] !== "string" || e[k] === ""){ throw new Error(`QD_EXAMPLES[${i}].${k} is missing or empty`); }
    }
    if (e.notes !== undefined && !(Array.isArray(e.notes) && e.notes.every((l) => typeof l === "string" && l !== ""))){
      throw new Error(`QD_EXAMPLES[${i}].notes must be an array of non-empty strings`);
    }
  });
  const placeholder = entries.length === 0;
  kicker(s, placeholder ? "// examples from docs/QUALITY_DELTA_CATALOG.md — each one reproduced, none invented"
                        : "// real findings from ripwire's own history — each one re-derived by a command", CYAN);
  title(s, "What --quality-delta catches", { size: 32 });
  const shown = placeholder
    ? [0, 1, 2].map(() => ({ kind: "‹kind›", finding: "‹the finding, as the tool prints it›", before: "‹before›", after: "‹after›", why: "‹why it matters, in one sentence›" }))
    : entries;
  const AW = W - 2*MX, AH = 5.08, GAP = 0.14, top = 1.74, PAD = 0.14, PGAP = 0.1;
  const cols = shown.length <= 3 ? 1 : 2, rows = Math.ceil(shown.length / cols);
  const cw = (AW - (cols-1)*GAP) / cols, ch = (AH - (rows-1)*GAP) / rows, codeSize = cols === 1 ? 9.5 : 8;
  shown.forEach((e, i) => {
    const x = MX + (i % cols) * (cw + GAP), y = top + Math.floor(i / cols) * (ch + GAP);
    const edge = placeholder ? { color: "3A4353", width: 1, dashType: "dash" } : { color: "232D3D", width: 0.75 };
    s.addShape("roundRect", { x, y, w: cw, h: ch, fill: { color: CARD }, rectRadius: 0.09, line: edge });
    // The kind box is as wide as its own text, and the finding starts where it ends: the longest kind,
    // new-clone-of-reused-helper, is 2.38 in at 11 pt and wrapped out of the fixed 2.2 in box this replaced.
    const kindW = Math.max(0.9, e.kind.length * 11 * 0.6 / 72 + 0.12);
    s.addText(e.kind,    { x: x+PAD, y: y+0.06, w: kindW, h: 0.3, fontFace: MONO, fontSize: 11, bold: true, color: placeholder ? MUTED : AMBER, valign: "middle", margin: 0 });
    s.addText(e.finding, { x: x+PAD+kindW+PGAP, y: y+0.06, w: cw-2*PAD-kindW-PGAP, h: 0.3, fontFace: SANS, fontSize: 10, color: placeholder ? MUTED : TEXT, valign: "middle", margin: 0 });
    const paneY = y + 0.42, paneH = ch - 0.42 - 0.38, paneW = (cw - 2*PAD - PGAP) / 2;
    [["before", e.before], ["after", e.after]].forEach(([label, code], j) => {
      const px = x + PAD + j * (paneW + PGAP);
      s.addShape("rect", { x: px, y: paneY, w: paneW, h: paneH, fill: { color: BG }, line: { color: "232D3D", width: 0.5 } });
      s.addText(label, { x: px+0.06, y: paneY+0.03, w: paneW-0.12, h: 0.17, fontFace: MONO, fontSize: 7.5, color: MUTED, margin: 0 });
      s.addText(code,  { x: px+0.06, y: paneY+0.21, w: paneW-0.12, h: paneH-0.24, fontFace: MONO, fontSize: codeSize, color: placeholder ? MUTED : TEXT, valign: "top", margin: 0 });
    });
    s.addText(e.why, { x: x+PAD, y: y+ch-0.35, w: cw-2*PAD, h: 0.3, fontFace: SANS, fontSize: 9.5, italic: true, color: MUTED, valign: "middle", margin: 0 });
  });
  if (placeholder){
    chip(s, "PLACEHOLDER", W-MX-2.0, 0.38, 2.0, AMBER, { h: 0.36, size: 12, line: AMBER });
    foot(s, "placeholder: the examples arrive as data (QD_EXAMPLES, top of the generator) once docs/QUALITY_DELTA_CATALOG.md lands");
    notes(s, [
      "PLACEHOLDER — no example is shown on purpose.",
      "The examples come from docs/QUALITY_DELTA_CATALOG.md, which a separate lane is writing with real, reproduced findings. Still not in the tree as of main 40a1895b (checked 2026-09-11): the catalog lives on commit 553dbadb only.",
      "To fill: add 3 to 6 { kind, finding, before, after, why } entries to QD_EXAMPLES at the top of present/deck5_ripwire_build.js, copied from the catalog, then rebuild. The notes list each entry against the catalog.",
    ]);
  } else {
    foot(s, "each pair is copied from docs/QUALITY_DELTA_CATALOG.md, where the command that reproduces it is recorded");
    notes(s, [
      "SOURCES: docs/QUALITY_DELTA_CATALOG.md — one entry per card, left to right, then top to bottom.",
      "The snippets are the catalog's excerpts, trimmed to fit a card: … marks elided code, long lines wrap, and a comment line stands for code the catalog says was elided or deleted.",
    ].concat(entries.flatMap((e, i) => [`${i+1}. ${e.kind}: ${e.finding}`].concat((e.notes || []).map((l) => `   ${l}`)))));
  }
  return s;
}

/* ── S1 · title ─────────────────────────────────────────────────────────── */
{
  // The cover echoes the README hero (docs/assets/banner.svg): a terminal card, the two-tone name, and the
  // wave (present/assets/paddle-out.png: docs/assets/paddle-out.svg rendered at 4x on the card colour with Arial,
  // so it blends into the card in every viewer — a PNG because pptxgenjs writes an SVG's bytes into the PNG
  // fallback slot, which older viewers cannot draw). Below
  // it the two halves, weighted on purpose: speed is the hook, honesty is the half that earns the trust.
  const s = p.addSlide(); bg(s);
  const cw = W - 2*MX;
  s.addShape("roundRect", { x: MX, y: 0.55, w: cw, h: 3.75, fill: { color: CARD }, rectRadius: 0.12, line: { color: "232D3D", width: 0.75 } });
  for (const dx of [0.28, 0.52, 0.76]){
    s.addShape("ellipse", { x: MX+dx, y: 0.74, w: 0.14, h: 0.14, fill: { color: "2A3547" }, line: { color: "2A3547", width: 0 } });
  }
  // Left column: the name, the one-line claim, and the wave under it. Right column: what it is, in one sentence.
  s.addText([{ text: "rip", options: { color: CYAN } }, { text: "wire", options: { color: AMBER } }],
    { x: MX+0.4, y: 0.95, w: 6.0, h: 1.3, fontFace: MONO, fontSize: 72, bold: true, margin: 0 });
  s.addText("The ripgrep of AI context.", { x: MX+0.42, y: 2.25, w: 6.0, h: 0.55, fontFace: SANS, fontSize: 26, bold: true, color: TEXT, margin: 0 });
  // altText is not decoration here: pptxgenjs writes the image's own path into <p:cNvPr descr="…">, and this file
  // builds that path from __dirname, so the default ships whatever directory the deck was generated in inside the
  // pptx — a home path that test/ripwirepubliccheck.sh arm 2b reads out of ppt/slides/*.xml and fails on.
  s.addImage({ path: require("path").join(__dirname, "assets", "paddle-out.png"), altText: "paddle-out wave",
               x: MX+0.36, y: 2.98, w: 4.6, h: 0.94 });
  s.addText("A zero-runtime-dependency C++23 CLI that maps any codebase into a ranked, deterministic call graph for coding agents — and puts a tripwire on every claim it emits.",
    { x: MX+6.7, y: 1.2, w: 5.0, h: 2.6, fontFace: SANS, fontSize: 18, color: MUTED, valign: "middle", margin: 0 });

  const ripW = 4.3, gapH = 0.3, wireX = MX + ripW + gapH, wireW = cw - ripW - gapH;
  card(s, MX, 4.6, ripW, 1.95);
  s.addText([{ text: "rip", options: { color: CYAN, bold: true } }, { text: " — the speed half", options: { color: TEXT, bold: true } }],
    { x: MX+0.25, y: 4.8, w: ripW-0.5, h: 0.4, fontFace: SANS, fontSize: 15, margin: 0 });
  s.addText("Structural answers in tens of milliseconds, from a call graph it built itself.",
    { x: MX+0.25, y: 5.3, w: ripW-0.5, h: 0.95, fontFace: SANS, fontSize: 12.5, color: MUTED, valign: "top", margin: 0 });
  s.addShape("roundRect", { x: wireX, y: 4.6, w: wireW, h: 1.95, fill: { color: "1F1B13" }, rectRadius: 0.09, line: { color: AMBER, width: 1.5 } });
  s.addText([{ text: "wire", options: { color: AMBER, bold: true } }, { text: " — the other half: honesty", options: { color: TEXT, bold: true } }],
    { x: wireX+0.3, y: 4.76, w: wireW-0.6, h: 0.5, fontFace: SANS, fontSize: 20, margin: 0 });
  s.addText("Unprovable totals ship labelled as floors. A zero means none found — never none exists.",
    { x: wireX+0.3, y: 5.3, w: wireW-0.6, h: 0.62, fontFace: SANS, fontSize: 15, color: TEXT, valign: "top", margin: 0 });
  s.addText("Every truncation is disclosed, and every guess says how many it chose from.",
    { x: wireX+0.3, y: 5.98, w: wireW-0.6, h: 0.42, fontFace: SANS, fontSize: 12.5, color: MUTED, valign: "top", margin: 0 });
  foot(s, "Apache-2.0  ·  single binary  ·  hermetic build (proven with the network off)  ·  24 vendored tree-sitter grammars");
  notes(s, [
    "SOURCES (cover)",
    "- \"24 vendored tree-sitter grammars\" — merged: #126 (merge commit 1ad9184a, 2026-09-11), which vendors the Kotlin grammar (PR #126 body: \"vendored fwcd/tree-sitter-kotlin grammar\"). Before #126 the count was 23. On main 40a1895b: README.md, \"24 vendored grammars\", and third_party/deps/ holds a kotlin/ directory.",
    "- The 23 it builds on: commit 680a0a3d,\"It is 23: 22 upstream projects under third_party/deps/, with tree-sitter-typescript supplying both typescript and tsx\"; PR #106's title, \"Dart: a 23rd grammar …\"; README.md, \"23 vendored grammars\".",
    "- The wave under \"The ripgrep of AI context.\": present/assets/paddle-out.png, rendered from docs/assets/paddle-out.svg (commit 680a0a3d; PR #133 moved the wave from the README hero to this deck).",
  ]);
}

/* ── S2 · the problem ───────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the problem", CYAN);
  title(s, "Your agent reads the whole library to answer one question");
  s.addText([
    { text: "Blind grep, then whole-file reads. Most of what enters the context window is never used — it is paid for anyway, on every step of every task.\n\n", options: {} },
    { text: "And bigger context is not better context: irrelevant text actively degrades the answer. The job is selection — a small, ranked, structural map beats a pile of open files.", options: {} },
  ], { x: MX, y: 1.95, w: 6.1, h: 3.2, fontFace: SANS, fontSize: 16.5, color: TEXT, margin: 0 });

  card(s, 7.25, 1.95, 5.35, 2.15);
  stat(s, "0.108 s", "median answer, warm index — round 4, all arms one machine one day, N = 60", 7.35, 2.2, 5.15, CYAN, {});
  card(s, 7.25, 4.3, 5.35, 2.15);
  stat(s, "−39.4%", "token ceiling vs the un-routed baseline — LocBench cost ledger, N = 243", 7.35, 4.55, 5.15, GREEN, {});
  s.addText("Speed caveat travels with the number: ripwire answers from a warm, pre-built index, and round 4 measured its index cost too — 0.31 s, tabulated beside the competitors' rather than omitted. Measured 2026-08-08, before 0.6.0's performance work; not re-measured since.",
    { x: MX, y: 5.5, w: 6.1, h: 1.2, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
  foot(s, "bench/headtohead/r4-2026-08-06/ · bench/locbench/ — every figure on this deck names its instrument");
}

/* ── S3 · what it is ────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// one binary, the whole pipeline", CYAN);
  notes(s, [
    "SOURCES (grammar count and language row)",
    "- \"24 vendored grammars\" and Kotlin in the language row — merged: #126 (merge commit 1ad9184a, 2026-09-11); PR body, \"Adds Kotlin (.kt) language support: vendored fwcd/tree-sitter-kotlin grammar\". Before #126: 23 (commit 680a0a3d) and no Kotlin. README.md on main 40a1895b says \"24 vendored grammars\".",
  ]);
  title(s, "Crawl → parse → resolve → rank → emit. Deterministic, end to end.");
  const stages = [
    ["crawl",   "the tree, no VCS needed"],
    ["parse",   "tree-sitter, 24 vendored grammars"],
    ["resolve", "references → call graph"],
    ["rank",    "Personalized PageRank"],
    ["emit",    "minified XML, one line"],
  ];
  const bw = 2.25, gap = 0.22; let x = MX;
  for (const [name, sub] of stages){
    card(s, x, 2.2, bw, 1.5, CARD2);
    s.addText(name, { x: x+0.12, y: 2.38, w: bw-0.24, h: 0.45, fontFace: MONO, fontSize: 17, bold: true, color: CYAN, margin: 0 });
    s.addText(sub,  { x: x+0.12, y: 2.86, w: bw-0.24, h: 0.75, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
    if (name !== "emit") s.addText("→", { x: x+bw-0.04, y: 2.62, w: 0.32, h: 0.5, fontFace: SANS, fontSize: 20, color: MUTED, margin: 0 });
    x += bw + gap;
  }
  const props = [
    ["byte-identical", "two runs, same bytes — a gate on every push, not a tendency; warm equals cold"],
    ["zero runtime deps", "CMake + a C++23 compiler; builds with the network off — vendored everything"],
    ["the languages", "Rust · C++ · ObjC/C++ · C · Metal · CUDA · Python · Go · Swift · TypeScript · JavaScript · Java · Kotlin · Ruby · PHP · Lua · Elixir · Dart · Bash · C# · JSON · TOML · YAML · Markdown — 24 vendored grammars; markdown headings are real symbols"],
    ["agent-native", "an MCP server and 179 long flags behind one `--help` that is always the authority"],
  ];
  // Row height carries the LONGEST body (the language line, which wraps to three at this width),
  // not the shortest — a fixed 0.68 clipped its last line off the bottom of the card.
  let y = 3.98;
  for (const [h2, b] of props){
    card(s, MX, y, 12.09, 0.78);
    s.addText(h2, { x: MX+0.2, y: y+0.05, w: 2.9, h: 0.68, fontFace: MONO, fontSize: 13.5, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+3.2, y: y+0.05, w: 8.7, h: 0.68, fontFace: SANS, fontSize: 12, color: TEXT, valign: "middle", margin: 0 });
    y += 0.86;
  }
}

/* ── S4 · seven families ────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// every feature, one screen", CYAN);
  title(s, "Seven families of questions it answers");
  const fams = [
    ["understand cold",  "What is this repo, and what matters in it?",          "--for  --tree  --lego  --exemplar  --recall  --pack-task  --token-budget"],
    ["navigate",         "Who calls this? Safe to change or delete? Which tests?", "--callers  --callees  --uses  --impact  --path  --connect  --affected  --situ  --test-gate  --from-trace  --pattern  --safe-delete"],
    ["detail ladder",    "Show me more — but only where it pays.",              "--detail  --pack-signatures  --outline  --expand  --compress"],
    ["quality & risk",   "Where is the risk, and did I just add some?",         "--quality-panel  --quality-delta  --dmm  --readability  --ensemble  --context-ratio  --nonlocal-state  --field-affinity  --hotspots  --lint  --clones"],
    ["self-diagnosis",   "Is my setup actually working?",                       "--doctor  --skipped"],
    ["security",         "Is this agent skill file safe to install?",           "--scan-skill  --scan-skills"],
    ["knobs & modes",    "Shape, format, cache, budget.",                       "--json  --format  --mcp"],
  ];
  let y = 1.85;
  for (const [fam, q, flags] of fams){
    card(s, MX, y, 12.09, 0.66, CARD);
    s.addText(fam,   { x: MX+0.18, y: y+0.04, w: 2.35, h: 0.58, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(q,     { x: MX+2.65, y: y+0.04, w: 3.55, h: 0.58, fontFace: SANS, fontSize: 11,  italic: true, color: MUTED, valign: "middle", margin: 0 });
    s.addText(flags, { x: MX+6.3,  y: y+0.04, w: 5.65, h: 0.58, fontFace: MONO, fontSize: 9, color: CYAN, valign: "middle", margin: 0 });
    y += 0.74;
  }
  foot(s, "--help is generated from the binary's own flag table — 179 long flags; docs/COMMANDS.md carries an entry for every one of them, 161 with a recorded invocation and its output");
}

/* ── S5 · the moments ───────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// reach for it at the moment, not the manual", CYAN);
  title(s, "The reflexes: which verb fires when");
  const moments = [
    ["Landing cold on a task",        "--for=\"<task>\"  ·  --pack-task", "ranked, budgeted context in one call"],
    ["Stack trace in hand",           "--from-trace",                     "frames mapped to symbols, innermost body included"],
    ["“Is it safe to change X?”", "--impact  ·  --uses",         "the whole blast radius, not just 1-hop callers"],
    ["Just edited a symbol",          "--edit-check",                     "did the contract change, who breaks — ~ms, warm"],
    ["About to write a helper",       "--exemplar  ·  --grep",            "imitate the house pattern; catch the duplicate early"],
    ["Landing several branches",      "--merge-scout",                    "pairwise conflict sites + a landing order"],
    ["Before you call it done",       "--quality-delta  ·  --test-gate",  "only what you made worse; exactly which tests to run"],
    ["Handing the area on",           "--handoff  ·  --note-add",         "the verified-vs-heuristic packet the next agent needs"],
  ];
  const cw = 5.95, ch = 1.08; let i = 0;
  for (const [when, flags, what] of moments){
    const x = MX + (i % 2) * (cw + 0.19), y = 1.9 + Math.floor(i / 2) * (ch + 0.16);
    card(s, x, y, cw, ch);
    s.addText(when,  { x: x+0.18, y: y+0.08, w: cw-0.36, h: 0.34, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
    s.addText(flags, { x: x+0.18, y: y+0.42, w: cw-0.36, h: 0.3,  fontFace: MONO, fontSize: 11.5, color: CYAN, margin: 0 });
    s.addText(what,  { x: x+0.18, y: y+0.72, w: cw-0.36, h: 0.32, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });
    i++;
  }
  foot(s, "and --pr-context when you are reviewing someone else's diff — per-file blast radius, tests-to-run, hotspot flags");
}

/* ── S5b · what shipped since the last deck refresh ─────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// new since 2026-08-15 — each figure re-derived on the binary that ships", CYAN);
  title(s, "What 2026-08-15 to 2026-08-23 added", { size: 32 });
  const shipped = [
    ["--pattern", "search by code SHAPE, not by node kinds",
     "foo($X, ...) across 13 grammar objects / 11 languages. On this repo VERIFY($X) finds 116 hits over 896 eligible files, each with its enclosing symbol. A pattern no served grammar resolves REFUSES (exit 1) instead of reporting hits=0.", CYAN],
    ["--safe-delete", "“can I delete this?” in one call",
     "callers + transitive radius + every read/write/import site + how much of that radius a test reaches. risk= names what was FOUND — never a go/no-go verdict.", CYAN],
    ["--impact importers=", "the second, weaker reach",
     "the files that include/require a file defining SYM, with their own cap pair — NEVER summed into reaches=, because files and symbols are different units. IngestResult: reaches=0, importers=70.", CYAN],
    ["compact --for bundles", "bodies were 52.7% of every conceptual byte",
     "the subtoken+body route now ships the ranked map plus one-hop edge context, disclosed as bundle=compact bodies=0. 15-query class B: 184,857 B → 95,256 B, −48.5%, all 11 decisive markers still present. --auto-bodies is a permanent opt-out.", GREEN],
    ["corroborated callers", "shared= on --pack-task rows",
     "a neighbour reached by four of the bundle's anchors sorts above one reached by a single anchor — omitted at 1, which is what every 1-hop row satisfies anyway.", CYAN],
    ["per-rule --lint roll-up", "a capped view stops hiding whole rules",
     "on this repository 16 of the 31 rules that fired contribute ZERO shown rows — 588 findings whose only evidence is their count=. A rule no corpus language registers carries applicable=0, so its zero is inertness, not a measurement.", AMBER],
  ];
  let y = 1.72;
  for (const [flag, what, detail, c] of shipped){
    card(s, MX, y, 12.09, 0.79);
    s.addText(flag,   { x: MX+0.18, y: y+0.05, w: 2.55, h: 0.34, fontFace: MONO, fontSize: 12, bold: true, color: c, margin: 0 });
    s.addText(what,   { x: MX+0.18, y: y+0.40, w: 2.55, h: 0.34, fontFace: SANS, fontSize: 9,  italic: true, color: MUTED, margin: 0 });
    s.addText(detail, { x: MX+2.95, y: y+0.05, w: 9.0,  h: 0.69, fontFace: SANS, fontSize: 10.5, color: TEXT, valign: "middle", margin: 0 });
    y += 0.87;
  }
  card(s, MX, 6.95, 12.09, 0.0, CARD2);
  s.addText([
    { text: "And two languages: PHP and Lua, ", options: { color: TEXT, bold: true } },
    { text: "each shipped with its floor stated rather than implied — PHP's run-time dispatch ($fn(), call_user_func, __call) names its callee at run time and is a declared floor; a Lua corpus reports no inheritance edges, because metatable inheritance has no syntax to read.", options: { color: MUTED } },
  ], { x: MX, y: 6.92, w: 12.09, h: 0.5, fontFace: SANS, fontSize: 10, margin: 0 });
  notes(s, [
    "SOURCES (the two live-repo figures on this slide — both re-derived 2026-09-11 on main 40a1895b, because they move with the tree)",
    "- --pattern: `git archive 40a1895b | tar -x -C DIR; ripwire DIR --pattern='VERIFY($X)' --no-cache` → hits=\"116\" eligible_files=\"896\" skipped_files=\"0\" of_files=\"1961\", grammars= naming 13 objects over 11 languages. It read 101 hits over 625 eligible files when the slide was written on 2026-09-06; the tree has grown since.",
    "- --lint: `ripwire DIR --lint --no-cache` over the same archive → 39 rule rows, 31 with count>0, of which 16 carry shown_rows=\"0\", totalling 588 findings. It read 14 of 31 and 368 findings on 2026-09-06.",
  ]);
}

/* ── S5b · new since 2026-08-23 ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// new since 2026-08-23 — each figure measured, dated, and re-derivable", CYAN);
  title(s, "What 2026-08-23 to 2026-08-30 added", { size: 32 });
  const rows = [
    ["--slice-flow", "cross-statement data-flow slicing\n(ARISE, arXiv:2605.03117)",
     "The paper's own slicer — reaching-definition edges, a seed plus a direction, a bounded BFS that stops at function boundaries — implemented and MEASURED on a registered fix-commit protocol: flow rows lift function-level added-line recall 0.163 → 0.198 at 25% of --expand's whole-body bytes (whose recall is 1.0 by construction). 7 commits / 38 instances, cpp only — a thin corpus, reported as thin.", CYAN],
    ["--slice, first numbers", "the 2026-08-28 registered contract,\nfinally measured",
     "Per-variable line-recall 0.726, hit-all rate 0.632 — a FLOOR under a noisy relevance oracle: every inspected miss was the protocol's word-regex matching identifiers inside comments and string literals, occurrences the slicer correctly refuses to call variable uses. No inspected instance showed a real occurrence the slice dropped.", CYAN],
    ["~1350× on --expand", "the secret-redaction sweep was\nquadratic in LINE length",
     "One selector in a 2.1 MB / 768-line minified yarn bundle NEVER completed — killed at 1,343.9 s of user CPU with an empty output file; 196.7 s is the only clean lower bound — and now answers in 0.46 s warm. The 20 KB single-line fixture: 23.02 s → 0.017 s. A pure memoization, so an output no-op: 120/120 invocations byte-identical; gated on behaviour, the timings a ledger row and never a red-CI threshold.", GREEN],
  ];
  let y = 1.72;
  for (const [flag, what, detail, c] of rows){
    card(s, MX, y, 12.09, 1.52);
    s.addText(flag,   { x: MX+0.18, y: y+0.10, w: 2.55, h: 0.40, fontFace: MONO, fontSize: 13, bold: true, color: c, margin: 0 });
    s.addText(what,   { x: MX+0.18, y: y+0.52, w: 2.55, h: 0.85, fontFace: SANS, fontSize: 9,  italic: true, color: MUTED, margin: 0 });
    s.addText(detail, { x: MX+2.95, y: y+0.10, w: 9.0,  h: 1.32, fontFace: SANS, fontSize: 11, color: TEXT, valign: "middle", margin: 0 });
    y += 1.70;
  }
  foot(s, "sources: docs/EVALS.md §--slice-flow (registered protocol + per-instance ledger) · bench/PROFILE.md 2026-08-30 — no number travels without its caveat");
}

/* ── S5d · new since 2026-08-30 ───────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// new since 2026-08-30 — the window this deck did not cover until now", CYAN);
  title(s, "What 2026-08-30 to 2026-09-06 added", { size: 32 });
  const rows = [
    [".gitignore, honoured\nby default", "named for ripgrep, whose\ndefining default this is",
     "The crawl walked ignored files; in a git work tree it now consults git's own rules and skips what the repository already declared uninteresting. This root, three checkouts under an ignored bench/external/: files= 8,674 \u2192 1,522, cold 2.81 s \u2192 0.52 s, warm 0.63 s \u2192 0.10 s \u2014 and --no-ignore restores the previous walk exactly. Nothing drops silently: ignored_files= is exact, ignored_dirs= says the walk STOPPED there so those contents are UNKNOWN rather than zero, and both are ABSENT when the rules dropped nothing \u2014 so a tree with nothing ignored is byte-identical to what it produced before.", GREEN],
    ["--html --color-by", "the map, rendered \u2014\nno server, no CDN",
     "One self-contained HTML file: a force-directed call graph you click to recentre. --color-by=lang|community|cx|churn|tested sets the INITIAL colour only \u2014 the page embeds all five and keeps a live selector, so switching lens costs no second run. One five-stop blue-to-orange scale rather than the usual green-to-red, so reading it never depends on telling red from green.", CYAN],
    ["--eval-retrieval,\nre-sampled", "the sampler was measuring\nthe corpus, not the ranker",
     "For fourteen months the gold set was the first 150 doc-commented symbols in PATH order \u2014 and bench/ sorts before src/, so adding a docstring to a benchmark harness moved a published number without touching ranking code. One 60-symbol probe, one corpus, only its PATH varied: 0.105 and 0.356 MRR from spelling alone. Now exhaustive \u2014 population=3011 scored=3011 rule=exhaustive \u2014 and EVERY retrieval figure this project publishes was re-derived under it.", AMBER],
    ["--plan-lanes", "which lanes would collide,\nBEFORE a line is written",
     "Where --merge-scout says \"these branches already conflict\", this says \"these lanes WOULD conflict if assigned this way\" \u2014 no ref to resolve, no re-ingest. Each lane now also carries an advisory execution profile (model + reasoning effort) that labels its own evidence basis=\"structural-only\" and versions its policy separately from the schema, so a recommendation cannot quietly claim more than the structure it read.", CYAN],
  ];
  let y = 1.70;
  for (const [flag, what, detail, c] of rows){
    card(s, MX, y, 12.09, 1.17);
    s.addText(flag,   { x: MX+0.18, y: y+0.09, w: 2.55, h: 0.50, fontFace: MONO, fontSize: 12, bold: true, color: c, margin: 0 });
    s.addText(what,   { x: MX+0.18, y: y+0.60, w: 2.55, h: 0.50, fontFace: SANS, fontSize: 9, italic: true, color: MUTED, margin: 0 });
    s.addText(detail, { x: MX+2.95, y: y+0.08, w: 9.0,  h: 1.01, fontFace: SANS, fontSize: 10, color: TEXT, valign: "middle", margin: 0 });
    y += 1.25;
  }
  foot(s, "CHANGELOG.md [Unreleased] carries the ignore-default measurement and its ledger in bench/PROFILE.md \u00b7 the sampler negative is docs/EVALS.md \u00a77, published as a counterexample against our own published numbers");
}

/* ── S5e · 0.6.0 at a glance ────────────────────────────────────────────── */
{
  // Four quadrants, one per theme of the release. The language quadrant is DATA: a change that lands later
  // adds a row to `langs`, and the card shares its height out among the rows.
  const s = p.addSlide(); bg(s);
  kicker(s, "// 0.6.0 — everything since v0.5.0 (tagged 2026-09-07); each figure names its PR", CYAN);
  title(s, "0.6.0: faster where it hurt, clearer where it stops", { size: 32 });
  const CW = (W - 2*MX - 0.14) / 2, CH = 2.43, X2 = MX + CW + 0.14, Y2 = 1.72 + CH + 0.12;
  const langs = [
    ["Dart", "the 23rd grammar, by @calvinchengx: 71,726 symbols from flutter/packages' 3,706 .dart files, none among its 289 degraded parses (#75, #106)", CYAN],
    ["Kotlin", "by @xCatG: calls resolve between Kotlin and Java, both ways; no sanitizer finding across 501 real .kt files, deterministic on ~9,500 more (#126)", CYAN],
    ["any language", "Dart's landing caught six per-language arrays sized off the last enum by hand: an appended language dropped out of --skipped's census silently. Fixed for all.", AMBER],
  ];
  listCard(s, MX, 1.72, CW, CH, "two new languages", CYAN, langs, { bigW: 1.55 });
  listCard(s, X2, 1.72, CW, CH, "Rip'n Fast", CYAN, [
    ["159.7 → 9.2 s", "warm --grep on llvm-project: an inheritance cone rebuilt on every still-ambiguous receiver-typed call is now built once per type (#83)", GREEN],
    ["−19.9% CPU",    "cold parse on llvm-project, 194.1 → 155.6 s: child walks that went quadratic now use a cursor, output byte-identical (#127, #130)", GREEN],
    ["−27.6% CPU",    "warm --pack-task on go, 8.13 → 5.88 s: the tokenizer rebuilt on one header of NEON, AVX2 and scalar string kernels (#127)", GREEN],
  ]);
  listCard(s, MX, Y2, CW, CH, "honest where it counts", AMBER, [
    ["2,107 → 3",    "false callers of memgraph's SafeString::move: a std::move call no longer binds to your own code (#134)", AMBER],
    ["12/12 → 8/12", "commits --quality-delta gated, of 12 landed: true-positive share 2% → 12%, with 0 wrong rows (#127)", AMBER],
    ["13/25 → 0",    "harmful --help-task recommendations on the adversarial prose set; precision 0.797 → 1.000 (#127)", AMBER],
  ]);
  listCard(s, X2, Y2, CW, CH, "fewer tokens, nothing hidden", GREEN, [
    ["46,385 → 4,473",  "tokens for --help: one line per flag now, and every disclosure is still one call away (#92)", CYAN],
    ["6 → 50",          "--handoff symbols per code file (12 per prose file): containment 16% → 54%, purely additive (#127)", CYAN],
    ["pages, not cuts", "--doc-drift, --flags, --flip and --situ disclose their cuts and page; --situ lists every tests-to-run row (#127)", CYAN],
  ]);
  foot(s, "upgrade note: prebuilt x86-64 binaries now need an x86-64-v3 (AVX2-class) CPU, RHEL 10's own floor — the installer checks before it downloads and names what is missing; arm64 uses NEON (#127, #137, #138)");
  notes(s, [
    "SOURCES (0.6.0 at a glance). Window: after the v0.5.0 tag (commit bacfa3b7, 2026-09-07) through main 40a1895b. Merge dates read with gh: #83 2026-09-09, #92 2026-09-10, #106 (merge commit 6f91fed2) 2026-09-10, #127, #134, #136 (d752d953), #137 (f22081b0), #138 (688cc321), #135 (1187b7f3), #126 (1ad9184a), #141 (d8e788b1) and #140 (40a1895b) all 2026-09-11.",
    "- Title words “faster where it hurt”: the draft 0.6.0 release notes' heading. “Rip'n Fast”: README.md's H1, “Rip'n Fast. Fewer Tokens. Better Code.”",
    "A NEW LANGUAGE",
    "- Dart: merge commit 6f91fed2, “merge(dart): a 23rd grammar …” — “On flutter/packages (3,706 .dart files) this indexes 71,726 Dart symbols and none of that corpus's 289 degraded parses is a .dart file.” Lane by @calvinchengx (#75).",
    "- Six arrays: 6f91fed2 — “moves six per-language array extents off the spelled-out last enumerator (std::size_t( Lang::Elixir ) + 1) and onto model.h's kLangCount”; with two tallies reverted, --skipped over two .cpp and two .dart files “prints indexed=4 with a single <lang n=cpp …> row: two indexed files gone from the census, with nothing saying a row is missing.”",
    "- Kotlin — merged: #126, merge commit 1ad9184a (2026-09-11); PR body, PR author xCatG: “vendored fwcd/tree-sitter-kotlin grammar … a JVM interop bridge that resolves Kotlin↔Java calls bidirectionally”; “Zero ASan/UBSan/LSan findings across 501 real .kt files (8 local Android/JVM repos) … and ~9,500 additional .kt files across 5 larger real-world corpora (nowinandroid, compose-samples, architecture-samples, ktor, Signal-Android) — deterministic and well-formed on every one”. The quadrant heading “two new languages” is true as of that merge.",
    "RIP'N FAST",
    "- 159.7 → 9.2 s: PR #83 body, table “--grep | 159.7 s | 9.2 s” (warm, llvm-project); cause “recomputed on every still-ambiguous receiver-typed call”, “Each receiver type's cone is now computed once”.",
    "- −19.9%, 194.1 → 155.6 s: PR #127 body table, llvm-project cold map --no-cache, 194.14 → 155.60 CPU s, −19.9%, n=1, output identical. PR #130 body: “22 walks converted”. “byte-identical”: #127 “Every row cmp-identical between the two binaries.”",
    "- −27.6%, 8.13 → 5.88 s: PR #127 body table, go warm --pack-task, n=5, identical. Lane K: src/infra/strkern.h “(NEON/AVX2/scalar); the query-time tokenizer rewritten as mask algebra”.",
    "HONEST WHERE IT COUNTS",
    "- 2,107 → 3: PR #134 body, “memgraph --callers=SafeString::move | 2,107 | 3”.",
    "- 12/12 → 8/12, 2% → 12%, 0 wrong: PR #127 lane Q, “12 landed commits: 12/12 → 8/12 gating, TRUE 2% → 12%, WRONG → 0”.",
    "- 13/25 → 0, 0.797 → 1.000: PR #127 lane R, “harmful 13/25 → 0, precision 0.797 → 1.000”; the brief names the set “the adversarial prose set”.",
    "FEWER TOKENS, NOTHING HIDDEN",
    "- 46,385 → 4,473: PR #92 body, “46,385 → 4,473 tokens (10.4x)”, “Nothing is deleted”, “every disclosure one call away” (title).",
    "- 6 → 50 / 12, 16% → 54%: PR #127 lane H, “kHandoffSymbolsPerFile 6 → 50 code / 12 prose (containment 16 → 54%, additive)”.",
    "- Paging: PR #127 lane H2, “--doc-drift, --flags/--flip, --situ disclose their cuts and page; answer rows never page”; gate-pin note, “the 25-row cap on tests-to-run was RETIRED … the arm now asserts every row listed”.",
    "FOOTER",
    "- PR #127 body: “x86-64 floor is -march=x86-64-v3 (AVX2, BMI1/2, FMA — RHEL 10's own floor). Prebuilt Linux x86 binaries now require AVX2-class CPUs. NEON on arm64.”",
    "- The footer says “x86-64”, not “x86-64 Linux”, because of #137 (merge commit f22081b0, 2026-09-11): PR body, the macOS x86_64 cross-build “picked its flags from CMAKE_SYSTEM_PROCESSOR … Every x86_64 compile line got -mcpu=apple-m1 and no -march at all”, and now gets “-march=x86-64-v3”. So the floor is the x86-64 binaries', both OSes.",
    "- “the installer checks before it downloads and names what is missing” — #138 (merge commit 688cc321, 2026-09-11): PR body, “Before downloading, on x86_64 … Below v3, it stops before the download, lists the missing features, and points to a source build”; and INSTALL.md on main 40a1895b, “From 0.6.0 the prebuilt x86-64 binaries need an x86-64-v3 CPU (AVX2, BMI2, FMA and the rest of that level), roughly Intel Haswell (2013) or AMD Excavator (2015) and newer; the installer checks before it downloads.”",
  ]);
}

/* ── S5f · 0.6.0: the scale rung ────────────────────────────────────────── */
{
  // Three defects that were measured on llvm-project, then a bar per corpus for the one no standard corpus
  // showed, then — on the right, kept to ONE callout — why that corpus, with every item verified in the notes.
  const s = p.addSlide(); bg(s);
  // The one kicker drawn larger than kicker() draws it: the file count is this slide's claim, so it reads first.
  s.addText([
    { text: "// Rip'n Fast, at scale — llvm-project, " },
    { text: "182,555", options: { bold: true } },
    { text: " files, as the instrument" },
  ], { x: MX, y: 0.34, w: W-2*MX, h: 0.42, fontFace: MONO, fontSize: 18, color: CYAN, margin: 0 });
  title(s, "Three bugs found at llvm-project scale", { size: 32 });
  const LW = 7.55;
  const found = [
    ["O(C²) child walks", CYAN,
     "An indexed ts_node_child( n, i ) loop re-walks the child list on every call, so wide, flat lists (comment runs, C/C++ include guards) go quadratic. #127 moved 24 walks to one cursor helper (18 arms red first at 11–125×); #130 moved 22 more (13–126×).",
     "194.1 → 155.6 s", "cold parse CPU, n = 1\n−19.9% · wall −25%"],
    ["the inheritance cone", CYAN,
     "Rebuilt on every still-ambiguous receiver-typed call: 86,667 cones for 2,984 distinct types, 143 s of a 154 s run. Each type's cone is now built once, and default maps are byte-identical on go and llvm-project.",
     "159.7 → 9.2 s", "warm --grep\ndefault map 248 s → 10 s"],
    ["the cache that evicted itself", AMBER,
     "One llvm root needs 1.76 GB of cache, and the 2 GB oldest-first sweep was evicting that root's own index. The sweep now pins the root you are working in, and two key builders that hashed one root with different seeds share one key.",
     "274 → 26 s", "a repeated --for, CPU"],
  ];
  let y = 1.72;
  for (const [name, c, what, big, lbl] of found){
    card(s, MX, y, LW, 1.18);
    s.addText(name, { x: MX+0.2, y: y+0.08, w: 5.0, h: 0.3, fontFace: MONO, fontSize: 12.5, bold: true, color: c, margin: 0 });
    s.addText(what, { x: MX+0.2, y: y+0.38, w: 5.05, h: 0.76, fontFace: SANS, fontSize: 9.5, color: MUTED, valign: "top", margin: 0 });
    s.addText(big,  { x: MX+5.3, y: y+0.14, w: 2.1, h: 0.5, fontFace: MONO, fontSize: 16, bold: true, color: GREEN, align: "right", valign: "middle", margin: 0 });
    s.addText(lbl,  { x: MX+5.3, y: y+0.64, w: 2.1, h: 0.46, fontFace: SANS, fontSize: 9, color: MUTED, align: "right", valign: "top", margin: 0 });
    y += 1.27;
  }
  s.addText("the same round's cold parse, CPU Δ by corpus (median of 5; llvm-project n = 1)", { x: MX, y: 5.56, w: LW, h: 0.26, fontFace: MONO, fontSize: 9.5, color: MUTED, margin: 0 });
  const bars = [["ripwire", 2.1], ["go", 1.7], ["rocksdb", 6.7], ["llvm-project", 19.9]];
  const BX = MX + 1.55, BMAX = 4.9;
  let by = 5.86;
  for (const [corp, d] of bars){
    const hit = corp === "llvm-project", bw = Math.max(0.04, BMAX * d / 19.9);
    s.addText(corp, { x: MX, y: by, w: 1.45, h: 0.24, fontFace: MONO, fontSize: 10, color: hit ? TEXT : MUTED, align: "right", valign: "middle", margin: 0 });
    s.addShape("rect", { x: BX, y: by+0.04, w: bw, h: 0.16, fill: { color: hit ? GREEN : "3A4353" }, line: { color: hit ? GREEN : "3A4353", width: 0 } });
    s.addText("−" + d.toFixed(1) + "%", { x: BX+bw+0.08, y: by, w: 0.9, h: 0.24, fontFace: MONO, fontSize: 10, bold: hit, color: hit ? GREEN : MUTED, valign: "middle", margin: 0 });
    by += 0.26;
  }

  const CX = 8.35, CWd = W - MX - CX;
  card(s, CX, 1.72, CWd, 5.18, CARD2);
  s.addText("Why llvm-project", { x: CX+0.22, y: 1.84, w: CWd-0.44, h: 0.32, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, margin: 0 });
  s.addText("A scale test that is also the real thing. Built on or with LLVM:", { x: CX+0.22, y: 2.16, w: CWd-0.44, h: 0.3, fontFace: SANS, fontSize: 10, italic: true, color: MUTED, margin: 0 });
  const built = [
    ["Clang (C, C++, Objective-C)", "Chromium's only supported compiler; the Android NDK's; Apple Clang in Xcode; the PS4 toolchain"],
    ["Swift · Rust · Julia · Zig · Kotlin/Native", "each has an LLVM backend for its code generation"],
    ["CUDA", "NVIDIA's NVVM compiler is based on LLVM, and Clang compiles CUDA too"],
    ["Metal", "Apple's shading language: “Metal uses clang and LLVM”"],
    ["MLIR", "part of LLVM; used by TensorFlow, OpenAI Triton and Mojo"],
    ["WebAssembly", "Emscripten, a compiler toolchain to WebAssembly using LLVM"],
    ["ROCm · oneAPI", "AMD ROCm's compilers fork llvm-project; Intel's oneAPI DPC++/C++ uses LLVM"],
  ];
  let ly = 2.5;
  for (const [n, d] of built){
    s.addText([
      { text: n + "\n", options: { color: CYAN, bold: true, fontSize: 10.5, fontFace: MONO } },
      { text: d, options: { color: MUTED, fontSize: 9.5 } },
    ], { x: CX+0.22, y: ly, w: CWd-0.44, h: 0.56, fontFace: SANS, valign: "top", margin: 0 });
    ly += 0.575;
  }
  s.addText("LLVM received the 2012 ACM Software System Award · each item's source is in the notes", { x: CX+0.22, y: 6.56, w: CWd-0.44, h: 0.28, fontFace: SANS, fontSize: 8.5, color: MUTED, margin: 0 });
  foot(s, "all three measured on llvm-project; no standard corpus could see the first · sources: #127, #130, #83 — quotes in the notes");
  notes(s, [
    "SOURCES (the scale rung)",
    "- 182,555 files: PR #127 body, “with llvm-project (182,555 files) as the scale rung”; PR #83 body, “llvm-project (182,555 files)”.",
    "- Kicker “Rip'n Fast”: README.md's H1.",
    "ROW 1, O(C²) CHILD WALKS",
    "- Mechanism: the #127 presentation brief — “indexed ts_node_child(n,i) loops re-walk the child list on every call, which is O(children²)”; “Only wide FLAT child lists trigger it (comments as extras, C/C++ include guards), so no standard corpus could see it.”",
    "- 24 walks, 18 arms at 11–125×: the brief, “24 walks converted to one cursor helper (src/infra/tschildren.h); 18 isolation arms proven red-first at 11–125×”; PR #127 lanes W and W2/W3.",
    "- 22 more at 13–126×: PR #130 body, “22 walks converted, every one proven quadratic on the pre-change binary first … 13x..126x its control under a 16 000-comment flood”; “3 loops stay indexed with the reason written at the loop”; “156 generated fixture × verb pairs and the 21 committed ones are byte-identical”.",
    "- 194.1 → 155.6 s, −19.9%, n = 1: PR #127 body table, llvm-project cold map --no-cache, 194.14 → 155.60. Wall −25%: the brief, “wall −25%”.",
    "ROW 2, THE INHERITANCE CONE",
    "- PR #83 body: “86,667 cones for 2,984 distinct receiver types”; “143 s of 154 s”; table --grep 159.7 s → 9.2 s and default map 248 s → 10 s; “default maps byte-identical pre/post on go and llvm-project”.",
    "ROW 3, THE CACHE THAT EVICTED ITSELF",
    "- The brief: “One llvm root needs 1.76 GB of cache against a 2 GB oldest-first sweep. Once the sweep stopped evicting the working root's own families, a repeated --for went from 274 s to 26 s CPU.” “Two cache-key builders hashed the root with different FNV seeds (one of them truncated), so every root minted two key families. There is one key now.” PR #127 lanes C and C2.",
    "BARS",
    "- PR #127 body table, cold map --no-cache, Δ median: ripwire (own tree) −2.1% (n=5), go −1.7% (n=5), rocksdb −6.7% (n=5), llvm-project −19.9% (n=1). The body: “the cold parse (--no-cache) carries the child-walk and field-id lanes … the O(C²) walks only bite on wide flat child lists, which C/C++ include guards and comment floods produce”. The bars therefore carry both lanes, as that table does.",
    "- Title and footer: all three rows were measured on llvm-project (#127 body and brief; #83 body). Only the child walk is sourced as invisible elsewhere — the brief, “no standard corpus could see it” — so the footer claims that for the first row alone.",
    "WHY LLVM-PROJECT — each item verified on 2026-09-11 against the page named; anything not verified was dropped",
    "- 2012 ACM Software System Award: https://llvm.org/ — “LLVM has been awarded the 2012 ACM Software System Award!”",
    "- Clang (C/C++/Objective-C): https://llvm.org/ lists “Clang (C/C++/Objective-C compiler)” among the sub-projects.",
    "- Chromium: https://chromium.googlesource.com/chromium/src/+/main/docs/clang.md — “Chromium ships a prebuilt clang binary”; “This is the only supported compiler for building Chromium.”",
    "- Android NDK: https://developer.android.com/ndk/guides/other_build_systems — “The Clang compiler in the NDK is useable with only minimal configuration required to define your target environment.” https://developer.android.com/ndk/downloads/revision_history — r18b: “GCC has been removed.”",
    "- Apple: https://developer.apple.com/xcode/cpp/ — “Apple supports C++ with the Apple Clang compiler (included in Xcode)”.",
    "- PS4: https://llvm.org/devmtg/2013-11/slides/Robinson-PS4Toolchain.pdf (Paul T. Robinson, Sony Computer Entertainment, LLVM Dev Meeting 2013) — “Compiler – LLVM with the Clang front end”. Only the PS4 deck was read, so later consoles are not claimed.",
    "- Swift: https://www.swift.org/documentation/swift-compiler/ — “IR generation (implemented in lib/IRGen) lowers SIL to LLVM IR, at which point LLVM can continue to optimize it and generate machine code.”",
    "- Rust: https://rustc-dev-guide.rust-lang.org/overview.html — “Since rustc uses LLVM for code generation, the first step is to convert the MIR to LLVM-IR.”",
    "- Julia: https://docs.julialang.org/en/v1/devdocs/jit/ — “It is primarily built on LLVM's On-Request-Compilation (ORCv2) technology”.",
    "- Zig: https://ziglang.org/download/0.15.1/release-notes.html — “the LLVM backend is still the default” on several targets, and the self-hosted x86 backend “emit[s] slower machine code than the LLVM backend”. Zig also has self-hosted backends, hence “has an LLVM backend”, not “uses only LLVM”.",
    "- Kotlin/Native: https://kotlinlang.org/docs/native-overview.html — “Kotlin/Native includes an LLVM-based backend for the Kotlin compiler”.",
    "- CUDA: https://docs.nvidia.com/cuda/nvvm-ir-spec/ — “The NVVM compiler (which is based on LLVM) generates PTX code from NVVM IR.” https://llvm.org/docs/CompileCudaWithLLVM.html — “This document describes how to compile CUDA code with clang”.",
    "- Metal: the Metal Shading Language Specification, https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf — “Metal uses clang and LLVM so you get a compiler that delivers optimized performance on the GPU.” Read through a search-index extract of Apple's PDF: the file is larger than the fetch limit.",
    "- MLIR: https://mlir.llvm.org/ (source at github.com/llvm/llvm-project/tree/main/mlir). TensorFlow: https://www.tensorflow.org/mlir — MLIR “unifies the infrastructure required to execute high performance machine learning models in TensorFlow and similar ML frameworks”. OpenAI Triton: https://github.com/triton-lang/triton — “Backend rewritten to use MLIR”; “Triton uses LLVM to generate code for GPUs and CPUs.” Mojo: https://mojolang.org/docs/vision — “KGEN is built using MLIR Core”.",
    "- Emscripten: https://emscripten.org/ — “a complete compiler toolchain to WebAssembly, using LLVM”.",
    "- AMD ROCm: https://rocm.docs.amd.com/projects/llvm-project/en/latest/ — “The AMD llvm-project is a fork of llvm/llvm-project.”",
    "- Intel oneAPI DPC++/C++: https://www.intel.com/content/www/us/en/developer/tools/oneapi/dpc-compiler.html — “Uses well-proven LLVM compiler technology”.",
    "- DROPPED as unverified: XLA/OpenXLA as MLIR-based (the openxla.org pages fetched did not say so).",
  ]);
}

/* ── S5g · 0.6.0: honesty stories ───────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  storyCards(s, {
    kick: "// wire, in practice — three stories from 0.6.0, all merged",
    head: "Confidently wrong, caught, and fixed in the open",
    footText: "every figure is quoted from its PR body or commit in the speaker notes — the tripwire covers our own instruments too",
    stories: [
      { tag: "#134 · the resolver",
        headline: "std::move had 2,107 callers",
        what: "On memgraph, calls written std::move bound to the repository's lone in-repo move, SafeString::move, at full confidence and with no amb= or prov= marker. It became map row #1. In ripwire's own graph, std::min, std::max and std::sort bound fastmath and svector members.",
        stat: "2,107 → 3", statColor: GREEN,
        statLabel: "callers of SafeString::move after the fix: two of its unit tests and one std::ranges::move, a disclosed gap",
        now: "A std::-qualified call keeps only candidates inside namespace std; anything else counts toward external= and gets no edge. On ripwire's own tree, --callers=min went from 131 to 5.",
        gate: "test/stdqualcheck.sh · 35 checks, 19 red before" },
      { tag: "#127 · the string kernels' gate",
        headline: "The probe that lied",
        what: "strkerncheck asked Rosetta 2 whether it could run the x86-64-v3 kernels, using a one-add AVX2 probe. Clang folded that probe to a scalar addb, with zero ymm or VEX opcodes, so it answered ok on every runtime while the v3 slice SIGILLed on the macos-14 runner. The first fix's commit gave the wrong reason; the next one corrected it.",
        stat: "0 ymm opcodes", statColor: AMBER,
        statLabel: "in the probe binary that had answered “ok” (otool)",
        now: "The probe is now built with the floor's own -march and touches every v3 extension. The gate disassembles it and requires ymm, pdep, pext, lzcnt, tzcnt, vfmadd and vcvtph2ps; a folded probe routes to the scalar slice instead of passing.",
        gate: "test/strkerncheck.sh · b4ebf0bb, 150fb6d3" },
      { tag: "#127 · the audit's own tools",
        headline: "The audit's instrument was wrong twice",
        what: "A 14× super-linear reading turned out to be the cache evicting its own working root. And the recorded cap sweep had measured retrieval caps on a population of zero: it discarded exit codes, counted rows that emit nothing, and read back its own 10.4 MB cache blob, which “responded” to 103 of 108 caps.",
        stat: "59/195 → 64/151", statColor: CYAN,
        statLabel: "cap-sensitive rows: the published split, then the split re-derived over the rows that answer",
        now: "Every sweep row now carries a state (ok, rc=N, unparseable, unexpanded, timeout), a run where nothing answered refuses to report, and nothing it writes may land in the corpus. The cache sweep pins the root you are working in.",
        gate: "test/capsweepcheck.sh · 209f97a4 · 5723b2c0" },
    ],
  });
  notes(s, [
    "SOURCES (three stories, all merged to main)",
    "STD::MOVE — PR #134 body (merged 2026-09-11):",
    "- “A C++ call written std::X(...) bound to the repository's lone in-repo definition named X. It bound at full confidence, with no amb= or prov= marker.” “On memgraph, SafeString::move became map row #1 with 2,107 false callers from std::move.” “In ripwire's own graph, std::min/std::max/std::sort bound fastmath and svector members.”",
    "- Table: “memgraph --callers=SafeString::move | 2,107 | 3”; “ripwire --callers=min / max / sort | 131 / 67 / 7 | 5 / 14 / 2”. “The three remaining memgraph callers are two SafeString unit tests and one std::ranges::move; see the first gap below.”",
    "- Fix: “only candidates scoped inside std. Otherwise the call is counted through the existing external path (external=) and gets no edge.”",
    "- Gate: “test/stdqualcheck.sh (35 checks, fresh fixture): pre-fix binary: 19 FAIL / 16 PASS, where the 16 are controls”.",
    "THE PROBE THAT LIED — commits b4ebf0bb and 150fb6d3 (in #127, on main) and test/strkerncheck.sh:",
    "- b4ebf0bb: “Correction of a fact the run-8 commit stated: run 7's probe did NOT execute an AVX2 instruction that Rosetta then survived — clang had folded the one-add probe to a scalar addb despite its volatile (otool: zero ymm/VEX opcodes), so it printed 'ok' on every runtime and never chose the baseline slice.” “the gate disassembles it (otool -tv, or objdump -d) and requires one opcode of each class — ymm, pdep, pext, lzcnt, tzcnt, vfmadd, vcvtph2ps — so a future compiler that folds the probe makes it route to the baseline slice rather than lie”.",
    "- 150fb6d3: “Run 7: the macos-14 runner's Rosetta 2 executed the one-instruction AVX2 probe and then SIGILL'd the v3 slice” (the reason b4ebf0bb corrects); “The probe is now compiled with the floor itself and touches every extension it implies”.",
    "- test/strkerncheck.sh: “clang folded that to a scalar addb despite the volatile (otool: zero ymm/VEX opcodes), so it printed ok on every runtime”.",
    "THE AUDIT'S INSTRUMENT WAS WRONG TWICE — the #127 presentation brief, PR #127's body, commits 209f97a4 and 5723b2c0:",
    "- The brief: “A 14× super-linear reading was a cache-eviction artifact, and the recorded cap sweep had measured retrieval caps on a population of zero.”",
    "- 209f97a4: “run_corpus recorded len(stdout) and discarded returncode”; “The denominator counted 56 rows that emit nothing at all”; “a 10.4 MB cache blob that --batch= then read back, ‘responding’ to 103 of 108 caps”; “Every row now carries a state (ok / rc=N / unparseable / unexpanded / timeout)”; “A run in which NOTHING answered … now refuses to report a split”; “the destination must resolve outside the corpus”.",
    "- PR #127 lane H: “re-derived split 64 of 151 answering rows (was published as 59/195)”.",
    "- 5723b2c0: “fix(cache): the budget sweep pins the root you are working in, and says what it took”.",
  ]);
}

/* ── S5h · 0.6.0: three more honesty stories (#135, #136, #126 — all merged) ───────────── */
{
  // All three have landed: #136 d752d953, #135 1187b7f3, #126 1ad9184a, all 2026-09-11, all ancestors of
  // main 40a1895b. Every figure below is re-checked against the merged tree in the notes.
  const s = p.addSlide(); bg(s);
  storyCards(s, {
    kick: "// wire, in practice — three more: the parser, the resolver, and a new language",
    head: "Three more: a semicolon, a silence, a new language",
    footText: "every figure is quoted from its PR body or commit in the speaker notes",
    stories: [
      { tag: "#135 · the parser",
        headline: "One missing semicolon",
        what: "A member macro with no ';' as a class's last line, like EXC_NAME(Foo) before '};', derails tree-sitter's C, C++ and ObjC error recovery. On memgraph one file had 472 of its 487 definitions misfiled, and a 14-line function ranked #4 in --hotspots, with nothing on the row saying so.",
        stat: "ccx 920 → 2", statColor: GREEN,
        statLabel: "PrintFuncSignature, 14 lines: cx=749 ccx=920 before, cx=3 ccx=2 after the re-parse",
        now: "Misfiled definitions carry extent_suspect=, and --hotspots leaves them out and says so. An error-gated re-parse blanks ALL-CAPS member macros and keeps the result only if it has fewer error bytes. Lowercase and namespace-scope runs still derail: flagged, not fixed.",
        gate: "extentcheck.sh (55) · macroreparsecheck.sh (103)" },
      { tag: "#136 · the resolver",
        headline: "22% of calls, declined in silence",
        what: "--callers answered count=0, as if nothing called. When a call names two or more same-named definitions, none in the caller's file or directory, the resolver declines to guess: the right rule, but the decline was silent. On memgraph, 22% of all call references were declined this way.",
        stat: "65,516 / 295,086", statColor: AMBER,
        statLabel: "memgraph call references declined (22.2%), now shown as declined= and declined_calls=",
        now: "Every call reference ends in exactly one named bucket, and --pin-census prints the balance. It proved itself in the merge: #134's std:: refusals had gone uncounted, 1,495 on ripwire and 4,966 on memgraph. Now they count, and unaccounted=0.",
        gate: "test/declinecheck.sh · 17 languages, 104 checks" },
      { tag: "#126 · Kotlin, by @xCatG",
        headline: "A new language must not change old answers",
        what: "Kotlin brings calls that cross into Java. In #126's review, once retrofit's same-named Kotlin body() methods were indexed, calls to the Java Response.body were declined, and its callers fell from 279 to 5: a Java-only answer, changed by files in another language.",
        stat: "279 → 5 → 279", statColor: GREEN,
        statLabel: "callers of retrofit's Response.java:body: before Kotlin, with the first Kotlin binary, after the fix",
        now: "A call reaches the other JVM language only when its own language has no candidate, so adding .kt files never changes a Java-only edge. The bridge keeps its real job: a call into a name only the other language defines.",
        gate: "test/kotlincheck.sh §14 · the Java-only invariant" },
    ],
  });
  notes(s, [
    "SOURCES (three more stories — all merged). #136 merge commit d752d953, #135 merge commit 1187b7f3, #126 merge commit 1ad9184a, all 2026-09-11 and all ancestors of main 40a1895b.",
    "ONE MISSING SEMICOLON — merged: #135, merge commit 1187b7f3 (PR body):",
    "- “A function-like macro invoked without ; as the last member of a class or struct (EXC_NAME(Foo) right before };) sends tree-sitter-cpp's error recovery off course.” “The same shape derails tree-sitter-c and tree-sitter-objc.”",
    "- “On memgraph, one file had 472 of 487 definitions misfiled”; “A 14-line function (PrintFuncSignature) reported cx=749, ccx=920, and it ranked #4 in --hotspots. Before this PR, nothing on the row said anything was wrong.”",
    "- Measurements table: “PrintFuncSignature | a method, cx=749 ccx=920 loc=5479 | a free function, cx=3 ccx=2 loc=15”.",
    "- “--hotspots excludes flagged functions instead of ranking a number the tool itself calls an artifact”; the re-parse “Blank[s] ALL-CAPS function-like macro invocations that sit alone on a line as class/struct/union members” and “Adopt[s] the new tree only if it holds strictly fewer error bytes”; “Only the ALL-CAPS, class-body shape is repaired. Lowercase and namespace-scope macro runs still derail, and the detector keeps flagging them.”",
    "- Gates: “test/extentcheck.sh (55 checks …)” and “test/macroreparsecheck.sh (103 checks)”, “both red on their pre-change binaries”. Those two counts are the PR body's, taken at merge; on main 40a1895b both gates print ALL PASS but neither prints a total, and extentcheck's unit arm now reads “20 rule cases” where the PR body said 19 — so read 55/103 as the merged PR's count, not a re-derive.",
    "22% DECLINED IN SILENCE — merged: #136, merge commit d752d953 (PR body):",
    "- The rule: “a bare-name call with two or more candidates, none in the caller's file or directory, and no narrowing rescue is declined”; “the decline was silent … --callers=X answered count=0 exactly as if nothing called X”.",
    "- “memgraph: 22% of all call references were being discarded this way.” Table: “memgraph (merged tree) | 295,086 | 65,516 | 22.2%”.",
    "- “Header: declined=N”; “declined_calls=K on the --callers, --callees and --impact roots”.",
    "- “every iteration of the resolve loop now ends in exactly one named disposition”; “--pin-census prints the balance”.",
    "- “#134's std:: guard exits the loop with continue, and on the merged tree its refused calls came out uncounted: 1,495 on ripwire and 4,966 on memgraph … They are now counted as external”; both census lines end “unaccounted=0”.",
    "- “test/declinecheck.sh has a fixture covering 17 languages”; “Now it passes 104 checks.” Also the PR body's count at merge; the gate prints “declinecheck: PASS” on main 40a1895b without a total.",
    "- Re-checked on the merged tree: CHANGELOG.md on main 40a1895b, “On main after the std::-qualified call guard … the same --no-cache map declines 65,516 of memgraph's 295,086 call references (22.2%)”, and “both end unaccounted=0”.",
    "A NEW LANGUAGE MUST NOT CHANGE OLD ANSWERS — merged: #126, merge commit 1ad9184a (Kotlin; PR author xCatG):",
    "- The 279 figures are re-verified on the merged tree. Commit 359adca7 (on main via 1ad9184a), “fix(kotlin): the JVM bridge reaches the other language only when the caller's own has no candidate”: “On square/retrofit (306 .java, 16 .kt), Response.java:body is 279 callers on main 766913d0 and 5 on the PR head merged with main (09d8a6a3): 253 Java (caller, callee) pairs deleted by the test-only Kotlin body() functions (five spelled in two test directories, three with bodies), every gauge unmoved.”",
    "- Same commit, the fix: “graph.h keepOwnJvmLanguageCandidates … a Java or Kotlin reference admits the other JVM language's candidates only when its own language offers none”; “Every name the caller's language defines resolves exactly as it did before the bridge existed”.",
    "- The gate line, from the same commit's §14: “(c) the invariant: a Java-only tree against the same tree plus Kotlin definitions spelling the same names. --callers of six Java definitions, the Java interface's implementors and all 23 Java map rows (edges, prov=, amb=) must be identical, plus a mutation deleting the Kotlin interface so Tagged must bridge.”",
    "- On main 40a1895b: test/kotlincheck.sh, “on square/retrofit the test-only Kotlin body() functions … took Response.java's body from 279 callers to 5”; docs/ARCHITECTURE.md, “square/retrofit: Response.body keeps its 279 callers”.",
    "- PR #126 body: “a JVM interop bridge that resolves Kotlin↔Java calls bidirectionally”.",
    "- The earlier draft's “28 of its 48 arms fail on main” was DROPPED, not restated: nothing on main or in #126's body carries it, and kotlincheck's own header says the pre-Kotlin red is trivial — “every .kt file in this fixture leaves the index as why=\"unsupported-ext\" … That trivial red is not what this gate is for.” The card now names §14's invariant instead.",
  ]);
}

/* ── S6 · head-to-head, round 4 ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// one harness, one machine, one day — N = 60 paired, zero exclusions", AMBER);
  title(s, "Head-to-head: every competitor, one table");
  s.addChart("bar", [{
    name: "strict file@10",
    labels: ["ripwire --for", "codebase-memory-mcp 0.9.0", "repowise 0.37.0", "graphify 0.9.34",
             "aider repo-map 0.86.2", "codeseek 0.1.31 (idents)", "aider (no-persona control)", "codeseek (raw fallback)"],
    values: [58.3, 40.0, 33.3, 31.7, 20.0, 15.0, 10.0, 0.0],
  }], {
    x: MX, y: 1.72, w: 7.5, h: 4.55, barDir: "bar",
    chartColors: [CYAN, "3A4353", "3A4353", "3A4353", "3A4353", "3A4353", "3A4353", "3A4353"],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: '0.0"%"', dataLabelColor: TEXT, dataLabelFontSize: 10.5, dataLabelFontFace: SANS,
    catAxisLabelColor: TEXT, catAxisLabelFontSize: 10, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 9, valAxisMaxVal: 70, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 40,
  });
  card(s, 8.4, 1.72, 4.2, 1.55);
  stat(s, "1.46×", "the margin over the best competitor — 58.3% against 40.0% strict file@10", 8.5, 1.85, 4.0, CYAN, { bsize: 40, bh: 0.8, lsize: 10.5 });
  card(s, 8.4, 3.4, 4.2, 1.62);
  s.addText([
    { text: "And the index it was measured with\n", options: { color: TEXT, bold: true, fontSize: 12 } },
    { text: "ripwire 0.31 s · codebase-memory-mcp 1.24 s · codeseek 3.37 s · graphify 7.82 s · repowise 34.0 s, whose worst single index was ", options: { color: MUTED, fontSize: 10.5 } },
    { text: "352 s", options: { color: AMBER, bold: true, fontSize: 10.5 } },
    { text: ". Cold, nothing to an answer: 0.213 s.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.55, y: 3.52, w: 3.9, h: 1.44, fontFace: SANS, valign: "top", margin: 0 });
  card(s, 8.4, 5.15, 4.2, 1.55);
  s.addText([
    { text: "What re-running cost us, published: ", options: { color: TEXT, bold: true, fontSize: 10.5 } },
    { text: "aider moved 18.3% → 20.0% on its own tie-break nondeterminism, and we printed the higher number. Paired, ripwire loses 2 instances to codebase-memory-mcp, 2 to repowise, and 1 each to graphify, aider and the aider control.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.55, y: 5.27, w: 3.9, h: 1.38, fontFace: SANS, valign: "top", margin: 0 });
  foot(s, "bench/headtohead/r4-2026-08-06/ — harness, JSONL and recipe committed; replaces the two non-comparable tables r1 and r2 needed · measured 2026-08-08, BEFORE 0.6.0's speedups: timings not re-measured");
  notes(s, [
    "SOURCES (head-to-head, round 4)",
    "- The timing caveat in the footer is the README's own, added by #141 (merge commit d8e788b1, 2026-09-11) beside both round-4 tables. README.md on main 40a1895b: “Measured 2026-08-08, before the performance work that ships in 0.6.0. ripwire has become faster since — llvm-project's cold parse (182,555 files) fell from 194.1 s to 155.6 s of CPU, and --pack-task on a Go repository from 8.13 s to 5.88 s — but these timing columns have not been re-measured.”",
    "- It changes no number in the table: the strict file@10 bars and the 1.46x margin are accuracy, not timing, and were never re-measured either. The index-cost card (0.31 s / 1.24 s / 3.37 s / 7.82 s / 34.0 s) is a timing column, so the caveat covers it too.",
  ]);
}

/* ── S6b · the oracle round ─────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// scored against a third-party oracle, never against each other", AMBER);
  title(s, "Graded by a compiler: zero silent misses");
  card(s, MX, 1.72, 6.05, 2.45);
  s.addText("Both tools were scored against a scip-clang compiler-grade index of this repository — 68 answers, 34 blind-authored queries × --uses and --callers.",
    { x: MX+0.22, y: 1.85, w: 5.6, h: 0.72, fontFace: SANS, fontSize: 12, color: MUTED, margin: 0 });
  stat(s, "0", "true silent misses — pre-fix and post-fix alike. Every imperfect answer either carried a discriminating self-flag (amb=, defs>1, external=\"1\") or was an oracle-scope artifact where ripwire was right and the compiler could not see the file.",
    MX+0.22, 2.55, 5.6, GREEN, { bsize: 54, bh: 0.85, lsize: 10.5 });

  card(s, 7.0, 1.72, 5.6, 2.45, CARD2);
  s.addText("What a compiler-grade index costs", { x: 7.2, y: 1.85, w: 5.2, h: 0.32, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
  const cost = [
    ["warm query", "49.8 ms", "3,760 ms", "~70×"],
    ["cold start",  "208 ms",  "8.7 s",    "~40×"],
    ["index build", "none",    "~8 min",   "—"],
    ["errors",      "0 / 101", "7 / 61",   "—"],
  ];
  let cy = 2.19;
  s.addText([{ text: "ripwire", options: { color: CYAN, bold: true } }, { text: "        Serena 1.6.2.dev0 (clangd 19.1.2)", options: { color: MUTED } }],
    { x: 8.5, y: cy, w: 3.95, h: 0.28, fontFace: SANS, fontSize: 10, margin: 0 });
  cy = 2.5;
  for (const [k, a, b, mult] of cost){
    s.addText(k,    { x: 7.2,  y: cy, w: 1.3,  h: 0.32, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    s.addText(a,    { x: 8.5,  y: cy, w: 1.15, h: 0.32, fontFace: MONO, fontSize: 11.5, bold: true, color: CYAN, valign: "middle", margin: 0 });
    s.addText(b,    { x: 9.75, y: cy, w: 1.35, h: 0.32, fontFace: MONO, fontSize: 11.5, color: TEXT, valign: "middle", margin: 0 });
    s.addText(mult, { x: 11.2, y: cy, w: 1.1,  h: 0.32, fontFace: MONO, fontSize: 11.5, color: AMBER, valign: "middle", margin: 0 });
    cy += 0.38;
  }

  card(s, MX, 4.32, 12.0, 1.35);
  s.addText([
    { text: "Read honestly in both directions. ", options: { color: TEXT, bold: true } },
    { text: "The LSP is more precise — site-level 0.929/0.941 against ripwire's 0.914/0.941 after the fix round, a gap of roughly 1.5 points with recall now equal. ripwire also pays ~7× the bytes per call, because its output carries self-describing legends. What it cannot do is answer a macro query at all — clangd's documentSymbol has no macro entries, which is 3 of its 7 errors — or start in less than eight minutes.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 4.44, w: 11.55, h: 1.15, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });

  card(s, MX, 5.78, 12.0, 1.05, CARD2);
  s.addText([
    { text: "The number that moved the wrong way, published with the rest: ", options: { color: AMBER, bold: true } },
    { text: "over-hedging rose 18.6% → 22.6% across the fix round. Closing loss buckets added self-flags faster than it removed imperfect answers. That direction is deliberate — calibrated to warn too often rather than too rarely — but it is a cost, and it is on the slide.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.89, w: 11.55, h: 0.88, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "bench/headtohead/r9-2026-08-09/RESULTS.md — C++ only, 34 scorable queries, one corpus (this repository)");
}

/* ── S6d · r10, the graph-database context server ───────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// 48 paired questions, zero exclusions, both arms exit 0 on all 48", AMBER);
  title(s, "Against a graph-database context server: 27–7–14", { size: 32 });

  // This slide's table stops at TW so it never runs underneath the cards on its right.
  const TW = 7.85;
  const nrow = (ry, h, cols, fill) => { row(s, ry, h, cols, { w: TW, fill }); };
  const CW = [2.45, 0.45, 0.85, 0.9, 0.55, 1.45];
  const splits = [
    ["symbol lookup",         12, 6, 2, 4, "1.35×", AMBER],
    ["conceptual search",     15, 8, 1, 6, "1.23×", AMBER],
    ["callers / blast radius",12, 7, 2, 3, "0.39×", GREEN],
    ["task orientation",       9, 6, 2, 1, "0.06×", GREEN],
  ];
  nrow(1.66, 0.34, [
    { t: "class",      w: CW[0], color: MUTED, size: 9.5, bold: true },
    { t: "n",          w: CW[1], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "ripwire",    w: CW[2], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "GitNexus",   w: CW[3], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "tie",        w: CW[4], color: MUTED, size: 9.5, bold: true, align: "right" },
    { t: "bytes ÷ it", w: CW[5], color: MUTED, size: 9.5, bold: true, align: "right" },
  ], BG);
  let y = 2.04;
  for (const [name, n, w, l, tie, ratio, rc] of splits){
    nrow(y, 0.42, [
      { t: name,        w: CW[0], color: TEXT,  size: 10.5 },
      { t: String(n),   w: CW[1], color: MUTED, size: 10.5, mono: true, align: "right" },
      { t: String(w),   w: CW[2], color: CYAN,  size: 11, mono: true, bold: true, align: "right" },
      { t: String(l),   w: CW[3], color: TEXT,  size: 11, mono: true, align: "right" },
      { t: String(tie), w: CW[4], color: MUTED, size: 11, mono: true, align: "right" },
      { t: ratio,       w: CW[5], color: rc,    size: 11, mono: true, bold: true, align: "right" },
    ]);
    y += 0.47;
  }
  nrow(y, 0.44, [
    { t: "all 48",  w: CW[0], color: TEXT,  size: 11, bold: true },
    { t: "48",      w: CW[1], color: MUTED, size: 11, mono: true, align: "right" },
    { t: "27",      w: CW[2], color: CYAN,  size: 12.5, mono: true, bold: true, align: "right" },
    { t: "7",       w: CW[3], color: TEXT,  size: 12.5, mono: true, bold: true, align: "right" },
    { t: "14",      w: CW[4], color: MUTED, size: 12.5, mono: true, align: "right" },
    { t: "0.159×",  w: CW[5], color: GREEN, size: 12.5, mono: true, bold: true, align: "right" },
  ], CARD2);

  card(s, 8.65, 1.66, 3.96, 1.72);
  s.addText("The cost of the whole sweep", { x: 8.85, y: 1.76, w: 3.6, h: 0.3, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "309,348 B", options: { color: CYAN, bold: true, fontSize: 13 } },
    { text: " against ", options: { color: MUTED, fontSize: 11 } },
    { text: "1,945,231 B", options: { color: TEXT, fontSize: 11 } },
    { text: ". Warm median 197 ms against 1,082 ms. Index 0.25–0.45 s / 6.6–16.5 MB against 23–52 s / 391–623 MB — written into the repository, not $TMPDIR.", options: { color: MUTED, fontSize: 10.5 } },
  ], { x: 8.85, y: 2.10, w: 3.6, h: 1.2, fontFace: SANS, valign: "top", margin: 0 });

  card(s, 8.65, 3.48, 3.96, 0.88, CARD2);
  s.addText([
    { text: "What it does better: ", options: { color: AMBER, bold: true } },
    { text: "compact one-hop context at 0.7–1.0 KB, a depth-LABELLED blast radius, per-stage timing on every query, and two-command onboarding into eight agents.", options: { color: MUTED } },
  ], { x: 8.85, y: 3.56, w: 3.6, h: 0.72, fontFace: SANS, fontSize: 9.5, valign: "middle", margin: 0 });

  card(s, 8.65, 4.4, 3.96, 2.3, CARD2);
  s.addText("Failure modes, both directions", { x: 8.85, y: 4.52, w: 3.6, h: 0.3, fontFace: SANS, fontSize: 12.5, bold: true, color: TEXT, margin: 0 });
  const fails = [
    ["needed a 2nd call", "0", "8/48"],
    ["empty radius, real callers", "0", "1"],
    ["malformed through a pipe", "0", "7/48"],
  ];
  let fy = 4.88;
  for (const [k, a, b] of fails){
    s.addText(k, { x: 8.85, y: fy, w: 2.2, h: 0.5, fontFace: SANS, fontSize: 9.5, color: MUTED, valign: "middle", margin: 0 });
    s.addText(a, { x: 11.1, y: fy, w: 0.45, h: 0.5, fontFace: MONO, fontSize: 11, bold: true, color: CYAN, valign: "middle", align: "right", margin: 0 });
    s.addText(b, { x: 11.62, y: fy, w: 0.8, h: 0.5, fontFace: MONO, fontSize: 11, color: TEXT, valign: "middle", align: "right", margin: 0 });
    fy += 0.5;
  }
  s.addText("The published numbers use the file-redirected form — the configuration favourable to it.",
    { x: 8.85, y: 6.32, w: 3.6, h: 0.32, fontFace: SANS, fontSize: 8.5, italic: true, color: MUTED, margin: 0 });

  card(s, MX, 4.4, 7.85, 2.3);
  s.addText([
    { text: "Its seven wins are named one by one, and its first-pass numbers do not exist. ", options: { color: AMBER, bold: true } },
    { text: "Four are cost losses on an answer ripwire gets right — a by-name lookup it serves in ~1 KB where ripwire spends 3× to also hand back the body. Three are ranking misses on webpack, and two of those share one unfixed mechanism: a symbol whose NAME matches the query beats the implementation that carries it in its body. Under the improve-first rule the round's FIRST pass was never published — its product was a loss list, and what is on this slide is the state after that list was worked. One of those fixes met its pre-registered band and was reverted anyway for failing a separate standing requirement; ", options: { color: MUTED } },
    { text: "the loss it would have fixed is still counted against us above.", options: { color: TEXT, bold: true } },
  ], { x: MX+0.22, y: 4.52, w: 7.4, h: 2.06, fontFace: SANS, fontSize: 10.5, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md §2 — GitNexus 1.6.9 (npm latest at 2026-08-22) vs ripwire at 7eb638e; django, webpack and this repository, all tree-hash verified clean · ratios are on class TOTALS, the medians form is printed there too because the two disagree");
}

/* ── S6c · the rounds ledger ────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the rule: numbers are held back until the loss list is worked", AMBER);
  title(s, "Every head-to-head round, and the ones that went against us", { size: 28 });   // 32 wrapped onto the first row
  const rounds = [
    ["r1", "2026-07-13/14", "Aider repo-map · codebase-memory-mcp · graphify", "superseded by r4", MUTED],
    ["r2", "2026-08-03",    "repowise · codeseek",                             "superseded by r4", MUTED],
    ["r3", "2026-08-03",    "headroom — a compression layer, so a different instrument", "passed code through byte-identical", TEXT],
    ["r4", "2026-08-06/08", "all five competitors, one harness, one day",       "the table on the previous slide", CYAN],
    ["r6", "2026-08-04/05", "agent-in-the-loop: the Codex CLI pilot",           "localization parity; +80% tokens, classified", TEXT],
    ["r7", "2026-08-08",    "CodeGraph, loss-first — we looked for our losses", "fix REJECTED by its own preregistered band", RED],
    ["r8", "2026-08-08",    "aider again, at equal token budget",               "loss questions traced to one root cause", TEXT],
    ["r9", "2026-08-09",    "Serena / scip-clang oracle",                       "0 silent misses; the fix list it produced", CYAN],
    ["r10","2026-08-22",    "GitNexus 1.6.9 — a graph-database context server", "27-7-14 — its own slide, two back", CYAN],
  ];
  let y = 1.68;
  for (const [r, when, what, outcome, c] of rounds){
    row(s, y, 0.5, [
      { t: r,       w: 0.5,  mono: true, bold: true, color: c, size: 12.5 },
      { t: when,    w: 1.35, mono: true, color: MUTED, size: 10.5 },
      { t: what,    w: 5.3,  color: TEXT, size: 11.5 },
      { t: outcome, w: 4.3,  color: c === MUTED ? MUTED : c, size: 11, italic: c === MUTED },
    ]);
    y += 0.49;
  }
  card(s, MX, 6.32, 12.09, 0.62, CARD2);
  s.addText([
    { text: "r7 in full, because it is the point: ", options: { color: AMBER, bold: true } },
    { text: "the fix was built, gated green, measured — predicted 12/22 against a pre-registered band of 10–14, measured 5/22 — and reverted rather than tuned. Published as a negative in docs/EVALS.md §7.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.41, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "bench/headtohead/ (r1–r4, r9) · bench/r7/ · bench/r8/ — harnesses committed even for rounds that rejected their own fix · r5 left no head-to-head record in this tree, so it is not listed · r10's method and pins are published in docs/EVALS.md §2, its pre-fix numbers nowhere");
}

/* ── S7 · locbench ──────────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// held-out, repo-disjoint, frozen dataset", AMBER);
  title(s, "Routing the ranker: +33 points, measured properly");
  s.addChart("bar", [{
    name: "strict file@10",
    labels: ["pre-routing baseline", "routed --for (shipping)"],
    values: [27.6, 60.9],
  }], {
    x: MX, y: 2.1, w: 6.3, h: 3.9, barDir: "col",
    chartColors: ["3A4353", GREEN],
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0.0", dataLabelColor: TEXT, dataLabelFontSize: 15, dataLabelFontFace: SANS,
    catAxisLabelColor: TEXT, catAxisLabelFontSize: 12.5, catAxisLabelFontFace: SANS,
    valAxisLabelColor: MUTED, valAxisLabelFontSize: 10, valAxisMaxVal: 70, valAxisMinVal: 0,
    valGridLine: { color: "232D3D", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: false, showTitle: false, plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG }, border: { color: BG } },
    barGapWidthPct: 80,
  });
  const rows = [
    ["+33.33pp", "paired delta, 243 held-out instances in 78 repository clusters", GREEN],
    ["+25.00pp", "clustered-bootstrap 95% lower bound — the honest floor", GREEN],
    ["−39.4%", "token ceiling for that gain", CYAN],
    ["+3.4%", "warm latency for that gain", MUTED],
  ];
  let y = 2.1;
  for (const [n, l, c] of rows){
    card(s, 7.3, y, 5.3, 0.86);
    s.addText(n, { x: 7.5, y: y+0.06, w: 1.75, h: 0.74, fontFace: SANS, fontSize: 21, bold: true, color: c, valign: "middle", margin: 0 });
    s.addText(l, { x: 9.3, y: y+0.06, w: 3.2, h: 0.74, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    y += 0.98;
  }
  foot(s, "bench/locbench/ — czlll/Loc-Bench_V1, 560 rows, JSON SHA-256 pinned in dataset.lock; metric code = LocAgent's strict Acc@k");
}

/* ── S7b · speed, on numbers you can reproduce ──────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// compiled, not interpreted — and measured on public corpora", CYAN);
  title(s, "Fast enough to call on reflex");
  const cols = [
    ["0.213 s", "cold — nothing to an answer: parse, rank, reply, no cache (r4)", CYAN],
    ["0.108 s", "warm query, median — against aider's 2.920 s (r4)", CYAN],
    ["0.31 s",  "index build — against repowise's 34.0 s, worst case 352 s (r4)", GREEN],
    ["49.8 ms", "warm query on this repo — against a clangd LSP's 3,760 ms (r9)", GREEN],
  ];
  let sx = MX;
  for (const [n, l, c] of cols){
    card(s, sx, 1.9, 2.93, 1.68);
    stat(s, n, l, sx+0.08, 2.06, 2.77, c, { bsize: 30, bh: 0.62, lsize: 10 });
    sx += 3.05;
  }
  card(s, MX, 3.78, 5.95, 2.42);
  s.addText("Where the second goes", { x: MX+0.22, y: 3.92, w: 5.5, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "Cold profiles are tree-sitter parse plus tag-query capture — not graph math. Resolve and PageRank together are a small fraction of the run, and the ranking was never the bottleneck.\n\n", options: { color: MUTED } },
    { text: "Which is why the wins came from removing work, not micro-optimising it: demand-driven side captures, five whole-AST passes fused into one pre-order walk, a calibrated per-worker parse reserve.", options: { color: MUTED } },
  ], { x: MX+0.22, y: 4.3, w: 5.5, h: 1.8, fontFace: SANS, fontSize: 11.5, margin: 0 });

  card(s, 6.75, 3.78, 5.85, 2.42);
  s.addText("Two opt-in faster builds", { x: 6.97, y: 3.92, w: 5.4, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "LTO is on by default. PGO is a script away and buys 14–25% cold.\n\n", options: { color: MUTED } },
    { text: "Both are opt-in performance, not opt-in correctness: ", options: { color: MUTED } },
    { text: "the output stays byte-identical across build flavours", options: { color: CYAN, bold: true } },
    { text: " — the determinism gate runs on both, and CI builds a plain flavour too, because NDEBUG once compiled a whole class of degrade-path checks out of existence.", options: { color: MUTED } },
  ], { x: 6.97, y: 4.3, w: 5.4, h: 1.8, fontFace: SANS, fontSize: 11.5, margin: 0 });
  foot(s, "every card above comes from a committed harness — bench/headtohead/r4-2026-08-06/ and r9-2026-08-09/ — not from a private corpus");
}

/* ── S7b2 · the pre-release sprint, labelled historical ─────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// how it got there — the pre-release performance sprint", MUTED);
  title(s, "Work removed before work optimized");
  const wins = [
    ["file ingest",    "FILE* whole-file reads; CSV counting became a byte scan — iostream out of the hot path"],
    ["capture gating", "value-use capture runs only for the verbs that actually need it, not on every run"],
    ["AST pass fusion","five whole-AST side-capture passes share ONE pre-order walk instead of five"],
    ["parallel parse", "query compile overlaps parse scheduling; files schedule by size — ids stay deterministic"],
    ["radix + S+tree", "numeric keys for edges and scores; a bounded-scratch hot map whose fixed cap reports its own overflow"],
    ["no std::map",    "unordered_dense, reserve() before ingest — no std::unordered_map on any hot path"],
  ];
  const cw = 3.95, ch = 1.4; let i = 0;
  for (const [h2, b] of wins){
    const x = MX + (i % 3) * (cw + 0.12), y = 1.9 + Math.floor(i / 3) * (ch + 0.16);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.18, y: y+0.12, w: cw-0.36, h: 0.34, fontFace: MONO, fontSize: 12.5, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.18, y: y+0.48, w: cw-0.36, h: 0.95, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "top", margin: 0 });
    i++;
  }
  card(s, MX, 4.92, 12.09, 1.68, CARD2);
  s.addText([
    { text: "Why this slide carries no numbers. ", options: { color: AMBER, bold: true } },
    { text: "The sprint's own headline pair was measured in June 2026 on a large private C++ corpus that is not publicly reproducible, and the deck does not quote figures a reader cannot re-derive — the previous slide's numbers all come from committed harnesses. What survives the omission is the ", options: { color: MUTED } },
    { text: "shape", options: { color: TEXT, bold: true, italic: true } },
    { text: ": the graph math was never the bottleneck, and every win came from doing less work rather than doing the same work faster. Same map contract throughout — byte-identical output before and after each of these changes.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.04, w: 11.6, h: 1.46, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "the mechanisms are in bench/PROFILE.md and the commit history; the private-corpus figures they produced are deliberately not quoted");
}

/* ── S7c · the ten moments ──────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// docs/EVALS.md §5, pinned on this repository 2026-08-08 (the --for row re-pinned 2026-08-22)", CYAN);
  title(s, "Ten everyday moments, and what each one costs", { size: 32 });
  const moments = [
    ["Orient me in this repo",                 "ripwire .",                    "~5.6K",   "~20K–25K",    "3.6×–4.5×"],
    ["Where is X handled?",                    "--for=\"…\"",                  "~2.1K",   "~4.9K–20K",   "2.3×–9.3×"],
    ["What do I already know?",                "--recall=\"…\"",               "~15K",    "~445K",       "29.2×"],
    ["Set me up for this task",                "--pack-task=\"…\"",            "~2.1K",   "~16K–80K",    "7.7×–37.7×"],
    ["Show me this one function",              "--expand=SYM --top-k=0",       "~260–16.5K", "~43K–174K", "2.6×–670×"],
    ["Who calls this function?",               "--callers=SYM",                "~580",    "~40K–52K",    "69.2×–89.1×"],
    ["Is it safe to change this?",             "--impact=SYM + --uses=SYM",    "~1.3K",   "~18K",        "14.4×"],
    ["I have a stack trace",                   "--from-trace=FILE",            "~1.4K",   "~124K–298K",  "86.9×–208.6×"],
    ["I changed these files — tests? radius?", "--situ",                       "~410",    "~3K–132K",    "7.3×–324.2×"],
    ["Review this PR/diff",                    "--pr-context=REF",             "~1.9K",   "~4.8K–51K",   "2.6×–27.5×"],
  ];
  row(s, 1.66, 0.34, [
    { t: "Ask it",       w: 3.25, color: MUTED, size: 10, bold: true },
    { t: "Command",      w: 2.45, color: MUTED, size: 10, bold: true, mono: true },
    { t: "ripwire",      w: 1.45, color: MUTED, size: 10, bold: true, align: "right" },
    { t: "naive read",   w: 1.8,  color: MUTED, size: 10, bold: true, align: "right" },
    { t: "savings",      w: 2.3,  color: MUTED, size: 10, bold: true, align: "right" },
  ], { fill: BG });
  let y = 2.04;
  for (const [ask, cmd, rw, naive, save] of moments){
    row(s, y, 0.42, [
      { t: ask,   w: 3.25, color: TEXT,  size: 10.5 },
      { t: cmd,   w: 2.45, color: CYAN,  size: 9.5, mono: true },
      { t: rw,    w: 1.45, color: CYAN,  size: 10.5, mono: true, bold: true, align: "right" },
      { t: naive, w: 1.8,  color: MUTED, size: 10.5, mono: true, align: "right" },
      { t: save,  w: 2.3,  color: GREEN, size: 10.5, mono: true, bold: true, align: "right" },
    ]);
    y += 0.47;
  }
  s.addText([
    { text: "Figures are ~tokens (≈ bytes/4). Every row is scored same-correct-answer-or-it-doesn't-count — both sides were checked, not assumed — and every ratio is a ", options: { color: MUTED } },
    { text: "range", options: { color: TEXT, bold: true } },
    { text: ": the cheap end and the honest end of what an agent would actually read, never the single most flattering number. Absolute counts belong to the corpus AT THE PIN — .gitignore became a crawl default on 2026-09-03, which moved what a re-run reads; the commands, not the constants, are what reproduces.", options: { color: MUTED } },
  ], { x: MX, y: 6.78, w: 12.09, h: 0.62, fontFace: SANS, fontSize: 10, margin: 0 });
}

/* ── S8 · token economy ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the cost lever", CYAN);
  title(s, "Smaller answers that are also better answers");
  card(s, MX, 1.95, 5.9, 2.5);
  stat(s, "74.7%", "fewer element bytes at top-50 — the --pack-signatures ladder,\nroot-neutralised, re-derived on this repo every run", MX+0.2, 2.25, 5.5, CYAN, { bsize: 52, lsize: 12 });
  card(s, MX, 4.65, 5.9, 1.9);
  s.addText("This figure survived its own audit: three corrections deep, re-derived root-neutrally after the original was shown to depend on how the corpus path was spelled — three spellings of one root read 18.6 points apart before that subtraction. top-50 is the quotable number because the payload is top-50 whatever --top-k says.",
    { x: MX+0.25, y: 4.85, w: 5.4, h: 1.55, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  card(s, 7.25, 1.95, 5.35, 2.5);
  s.addText("Ask for a symbol by NAME and the router uses the name-exact ranker:", { x: 7.5, y: 2.15, w: 4.9, h: 0.6, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "MRR  0.745 → 0.960\n", options: { color: GREEN, bold: true } },
    { text: "recall@1  61.1% → 91.3%\n", options: { color: GREEN, bold: true } },
    { text: "name-shaped queries on src/, all 3,011 doc-commented symbols scored, re-pinned 2026-09-05", options: { color: MUTED } },
  ], { x: 7.5, y: 2.8, w: 4.9, h: 1.5, fontFace: MONO, fontSize: 14, margin: 0 });
  card(s, 7.25, 4.65, 5.35, 1.9);
  s.addText("And the pollution metric — fixture and generated paths contaminating results — is driven to 0.0% on the ranking lane while recall went UP, not down.",
    { x: 7.5, y: 4.85, w: 4.9, h: 1.55, fontFace: SANS, fontSize: 12.5, color: MUTED, margin: 0 });
  foot(s, "docs/EVALS.md §4–§5 — showcasecapturecheck re-derives the byte-reduction triple; `ripwire src --eval-retrieval` re-derives the ranking bars, scoring every doc-commented symbol rather than a sample");
}

/* ── S9 · the tripwire ──────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the half no other tool ships", AMBER);
  title(s, "The tripwire: honesty as an output contract");
  const rules = [
    ["counts_floor=\"1\"", "call edges come from source text — dynamic dispatch adds no edge, so every count that cannot claim completeness is labelled a floor, in the output itself"],
    ["a zero is a measurement", "zero means none found, never none exists — and absent ≠ 0"],
    ["truncation is disclosed", "every cap, page seam and budget cut is named in the header before you read a row"],
    ["refusals teach", "a refused query names the flag, the problem, and a working example — never a bare error"],
  ];
  let y = 1.95;
  for (const [h2, b] of rules){
    card(s, MX, y, 7.6, 1.06);
    s.addText(h2, { x: MX+0.2, y: y+0.09, w: 7.2, h: 0.36, fontFace: MONO, fontSize: 13.5, bold: true, color: AMBER, margin: 0 });
    s.addText(b,  { x: MX+0.2, y: y+0.45, w: 7.2, h: 0.55, fontFace: SANS, fontSize: 11, color: MUTED, margin: 0 });
    y += 1.18;
  }
  card(s, 8.5, 1.95, 4.1, 3.1, CARD2);
  s.addText("$ ripwire . --callers=rankGraphTeleport", { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });
  s.addText([
    { text: "<callers of=\"rankGraphTeleport\"\n  defs=\"1\" count=\"6\" ", options: { color: TEXT } },
    { text: "counts_floor=\"1\"", options: { color: AMBER, bold: true } },
    { text: ">\n<s t=\"fn\" n=\"runEval\" .../>\n<s t=\"fn\" n=\"rankGraph\" .../>\n…\n</callers>", options: { color: TEXT } },
  ], { x: 8.68, y: 2.42, w: 3.8, h: 2.5, fontFace: MONO, fontSize: 10.5, valign: "top", margin: 0 });
  card(s, 8.5, 5.25, 4.1, 1.45);
  s.addText([
    { text: "The map grades itself before it answers. ", options: { color: TEXT, bold: true } },
    { text: "This repository's own src/: files=166 symbols=5778 edges=17150 ambiguous=7441 unresolved=1658 declined=4803.", options: { color: MUTED, fontFace: MONO } },
  ], { x: 8.68, y: 5.36, w: 3.8, h: 1.24, fontFace: SANS, fontSize: 10, margin: 0 });
  foot(s, "docs/EVALS.md §8 lists the numbers this project refuses to publish, each with its reason");
  notes(s, [
    "SOURCES (the tripwire)",
    "- The src/ census is re-derived, not remembered: `ripwire ./src` on main 40a1895b prints files=166 symbols=5778 edges=17150 ambiguous=7441 unresolved=1658 declined=4803 (warm and --no-cache identical). It read files=153 symbols=5122 edges=14182 ambiguous=5982 unresolved=1598 when the slide was written on 2026-09-06.",
    "- declined= is new in 0.6.0 — #136, merge commit d752d953: a call the resolver refused to guess at is now counted instead of vanishing. It belongs on this slide because it is the same contract the other three rules state.",
    "- The --callers example: `ripwire . --callers=rankGraphTeleport` on main 40a1895b still answers defs=\"1\" count=\"6\" counts_floor=\"1\", with runEval and rankGraph as its first two rows.",
  ]);
}

/* ── S9b · how complete is the graph ────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the honesty marks stop being a promise and become a measurement", AMBER);
  title(s, "Four levers accepted, one rejected on purpose");
  const levers = [
    ["macro edges",       "kParserVer 48", "function-like #define invocations land role=\"macro\" edges on disclosed-degraded symbols", GREEN],
    ["fn-pointer bindings","kParserVer 49", "calls through unambiguous local function-pointer bindings now resolve", GREEN],
    ["using-declarations","kParserVer 51", "re-exports emit role=\"import\" references — r9 loss bucket 1", GREEN],
    ["shadow suppression","kParserVer 52", "a local variable shadowing a function name stops stealing its use-sites — r9 loss bucket 2", GREEN],
    ["RTA-lite",          "reverted",      "instantiation-filtered CHA cone: refuted TWICE — the instantiated set crossed namespaces, and narrowed calls LOST their amb= mark", RED],
  ];
  let y = 1.8;
  for (const [n, ver, what, c] of levers){
    row(s, y, 0.66, [
      { t: n,    w: 2.15, color: c, bold: true, size: 12 },
      { t: ver,  w: 1.45, color: MUTED, size: 10.5, mono: true },
      { t: what, w: 8.0,  color: c === RED ? TEXT : MUTED, size: 11 },
    ], { fill: c === RED ? CARD2 : CARD });
    y += 0.74;
  }
  card(s, MX, 5.55, 5.95, 1.15);
  s.addText([
    { text: "The two r9 levers, against the compiler oracle: ", options: { color: TEXT, bold: true } },
    { text: "site precision 0.9046 → 0.9136, recall 0.9285 → 0.9412.", options: { color: GREEN, bold: true } },
  ], { x: MX+0.22, y: 5.68, w: 5.5, h: 0.92, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  card(s, 6.75, 5.55, 5.85, 1.15, CARD2);
  s.addText([
    { text: "The fn-pointer lever raised unresolved= by 1,039. Disclosure, not regression: ", options: { color: AMBER, bold: true } },
    { text: "call sites the resolver now RECOGNIZES but refuses to resolve are counted instead of silently ignored.", options: { color: MUTED } },
  ], { x: 6.97, y: 5.68, w: 5.4, h: 0.92, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "bench/resolverround/RESULTS.md — per-lever attribution; RTA-lite's rejection is written up in docs/EVALS.md §7");
}

/* ── S10 · proven, not promised ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// how it stays true", AMBER);
  title(s, "Proven, not promised");
  const cards = [
    ["606 gate scripts", "the suite runs on every push — plus determinism, cache-transparency and golden contracts; the gate count itself is gated against the runner's own loop"], // gatecount
    ["byte-identical, always", "two runs over the same tree produce the same bytes; warm equals cold. Enforced in CI, twice — Release AND a plain flavour, because NDEBUG once blinded a whole class of checks"],
    ["differential refactoring", "a refactor must prove it changed nothing observable: two binaries, hundreds of argv vectors, stdout + stderr + exit codes byte-identical"],
    ["held-out labels, authored blind", "eval labels were written by reading source before the ranker ever ran on them — so the eval is allowed to say the ranker is wrong. It has."],
    ["sanitizer wall", "ASan + UBSan + integer + float-cast, no-recover; TSan separately; leak suppression is one pinned file"],
    ["its own output is audited", "the showcase capture is regenerated and adversarially re-read as a claims corpus — the methodology ships in docs/METHODOLOGY.md"],
  ];
  const cw = 3.95, ch = 2.2; let i = 0;
  for (const [h2, b] of cards){
    const x = MX + (i % 3) * (cw + 0.12), y = 1.95 + Math.floor(i / 3) * (ch + 0.18);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.18, y: y+0.14, w: cw-0.36, h: 0.62, fontFace: SANS, fontSize: 14.5, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.18, y: y+0.6, w: cw-0.36, h: 1.5, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "top", margin: 0 });
    i++;
  }
}

/* ── S10b · why the claims are worth anything ───────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the reason to believe any number on this deck", AMBER);
  title(s, "Claims you can trust, because we publish what failed", { size: 32 });

  card(s, MX, 1.72, 3.86, 1.72);
  stat(s, "606", "gate scripts named by test/regression.sh — and the COUNT itself is gated against the runner's own loop, so it cannot go stale quietly", // gatecount
    MX+0.15, 1.86, 3.56, CYAN, { bsize: 42, bh: 0.66, lsize: 9.5 });
  card(s, 4.68, 1.72, 3.86, 1.72, CARD2);
  stat(s, "8", "registered NEGATIVES — changes built, gated green, measured against a band written before the code, and reverted rather than tuned",
    4.83, 1.86, 3.56, RED, { bsize: 42, bh: 0.66, lsize: 9.5 });
  card(s, 8.76, 1.72, 3.86, 1.72);
  stat(s, "0", "numbers on this deck without a committed instrument behind them — §8 lists the ones this project refuses to publish at all",
    8.91, 1.86, 3.56, GREEN, { bsize: 42, bh: 0.66, lsize: 9.5 });

  const arms = [
    ["the fresh-clone arm", "our own battery only ever ran inside a configured, long-lived worktree — one value of every AMBIENT input. It clones HEAD into a genuinely unconfigured checkout and re-runs the gates whose past failures were exactly that: a developer's git config, a fixture's inherited branch name, the checkout's own path length.", CYAN],
    ["the merge-conservation gate", "consistency is not conservation. A conflict resolution can drop a gate from the runner's loop while regenerating the pinned count from that SAME damaged list — both sides then agree at a wrong number. On a merge, the loop must equal the UNION of both parents', minus explicit tombstones.", AMBER],
    ["the eight, by name", "r7's prose-strip fix (predicted 12/22, band 10–14, measured 5/22) · RTA-lite, refuted twice · file-level evidence pooling, +0.00pp held-out · un-guarded query stemming · its IDF-guarded retry, VOIDED by its own verifier · query-term density weighting, both displacement guards tripped · --anchor and --cochange-boost, no confirmed lift · a name-coverage floor that MET its pre-registered band and was reverted anyway for a standing requirement.", RED],
  ];
  let y = 3.62;
  for (const [h2, b, c] of arms){
    card(s, MX, y, 12.09, 1.06);
    s.addText(h2, { x: MX+0.2, y: y+0.06, w: 3.0, h: 0.94, fontFace: MONO, fontSize: 12, bold: true, color: c, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+3.4, y: y+0.06, w: 8.5, h: 0.94, fontFace: SANS, fontSize: 10.5, color: MUTED, valign: "middle", margin: 0 });
    y += 1.14;
  }
  s.addText("A gate that cannot go red is a gate that proves nothing — which is why every arm on this deck ships with the mutation that makes it fail.",
    { x: MX, y: 7.0, w: 12.0, h: 0.4, fontFace: SANS, fontSize: 12.5, italic: true, color: AMBER, margin: 0 });
}

/* ── S11 · where it loses ───────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// own the losses — they are in the README too", AMBER);
  title(s, "Where it loses, published with the wins");
  const rows = [
    ["The public C++ number is lower than the private one it replaced",
     "SFML: strict file@10 28.7%, any@10 41.7%, first-hit MRR 0.21. Until 2026-08-07 this bullet compared against a ~89% any@10 private corpus that is no longer reproducible. That comparison is retired; the public number is the baseline going forward."],
    ["--grep costs more than it saves",
     "+19.7% tokens / −11.2% — published next to the flag it indicts, and carrying the same private-corpus caveat as every figure in that source"],
    ["PageRank is the wrong co-change ranker",
     "3.8% recall@5 against 40.3% for plain lexical, and fusing the two made it worse — relatedness is lexical, importance is structural"],
    ["Strict multi-file localization stays hard",
     "single-file gold 73.4% vs multi-file 18.2% (held-out); the same cliff on every corpus — open headroom, said plainly"],
  ];
  let y = 1.86;
  for (const [h2, b] of rows){
    card(s, MX, y, 12.09, 1.1);
    s.addText(h2, { x: MX+0.22, y: y+0.06, w: 4.55, h: 0.98, fontFace: SANS, fontSize: 13, bold: true, color: TEXT, valign: "middle", margin: 0 });
    s.addText(b,  { x: MX+4.95, y: y+0.06, w: 6.9, h: 0.98, fontFace: SANS, fontSize: 11, color: MUTED, valign: "middle", margin: 0 });
    y += 1.2;
  }
  s.addText("A tool that publishes its counterexamples is a tool whose wins you can believe.",
    { x: MX, y: 6.72, w: 12.0, h: 0.4, fontFace: SANS, fontSize: 14, italic: true, color: AMBER, margin: 0 });
}

/* ── S11b · the quality panel ───────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// the single command for \"is this code actually rotten?\"", CYAN);
  title(s, "Six families of evidence, counted — never blended", { size: 32 });
  const fams = [
    ["structural",  "shape: complexity, size, nesting, params, readability rank", "--metrics"],
    ["lexical",     "identifier text: the naming rules", "--lint  --naming-consistency"],
    ["confusion",   "syntax: the atoms-of-confusion rules", "--lint"],
    ["historical",  "git change frequency, measured PER FILE", "--hotspots"],
    ["colocation",  "how much you must READ outside this file", "--context-ratio"],
    ["state",       "this function's OWN BODY touching non-local mutable state", "--nonlocal-state"],
  ];
  let y = 1.8;
  for (const [n, what, flag] of fams){
    row(s, y, 0.6, [
      { t: n,    w: 1.75, color: CYAN, bold: true, mono: true, size: 12 },
      { t: what, w: 6.4,  color: TEXT, size: 11.5 },
      { t: flag, w: 3.5,  color: MUTED, size: 10.5, mono: true },
    ]);
    y += 0.68;
  }
  card(s, MX, 5.9, 5.95, 0.85, CARD2);
  s.addText([
    { text: "Ranked by the COUNT of distinct families that fire", options: { color: TEXT, bold: true } },
    { text: " — never a weighted composite, because a composite lets one loud family impersonate six.", options: { color: MUTED } },
  ], { x: MX+0.22, y: 6.0, w: 5.5, h: 0.65, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  card(s, 6.75, 5.9, 5.85, 0.85);
  s.addText([
    { text: "4 of 6", options: { color: AMBER, bold: true, fontSize: 16 } },
    { text: "  is what the strict preset counts — the verb says so itself, families=\"6\" enabled_n=\"4\". Two families did not clear the stability ladder.", options: { color: MUTED, fontSize: 11 } },
  ], { x: 6.97, y: 6.0, w: 5.4, h: 0.65, fontFace: SANS, valign: "middle", margin: 0 });
  foot(s, "--quality-panel[=strict|default|lenient] — and --quality-delta for the narrower question: what did MY change make worse?");
}

/* ── S11c · what the panel had to pass ──────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// a new lens does not ship because it sounds plausible", AMBER);
  title(s, "The calibration that disqualified a family", { size: 32 });
  card(s, MX, 1.8, 3.86, 2.15);
  stat(s, "+0.168", "the LARGEST cross-family correlation in the whole 6×6 matrix — widening the panel from four families to six did not raise it",
    MX+0.15, 1.98, 3.56, GREEN, { bsize: 40, bh: 0.72, lsize: 10.5 });
  card(s, 4.68, 1.8, 3.86, 2.15);
  stat(s, "27,889", "eligible functions, five independent trees — two reported separately and never pooled, because one of them is this repository",
    4.83, 1.98, 3.56, CYAN, { bsize: 40, bh: 0.72, lsize: 10.5 });
  card(s, 8.76, 1.8, 3.86, 2.15, CARD2);
  stat(s, "4 of 6", "families the strict preset actually counts — TWO were measured and held back from gating",
    8.91, 1.98, 3.56, AMBER, { bsize: 40, bh: 0.72, lsize: 10.5 });

  card(s, MX, 4.15, 12.0, 1.35);
  s.addText([
    { text: "The uncomfortable result, kept. ", options: { color: AMBER, bold: true } },
    { text: "The stability pass ran each family across a ladder of commits to ask whether it is steady enough to gate on. ", options: { color: MUTED } },
    { text: "colocation came out worse than historical on one ladder", options: { color: TEXT, bold: true } },
    { text: ", so neither gates: strict counts four of the six — a lens its own author wanted, measured, and demoted. The ladder was run precisely because that answer was possible; assuming it would pass is how a plausible axis becomes a permanent one.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 4.28, w: 11.55, h: 1.15, fontFace: SANS, fontSize: 12, valign: "middle", margin: 0 });

  card(s, MX, 5.68, 12.0, 1.02, CARD2);
  s.addText([
    { text: "--field-affinity was NOT made a family either", options: { color: TEXT, bold: true } },
    { text: " — an exclusion by unit, not a failed measurement: it ranks struct FIELDS by co-access against declared layout, and the panel's unit is a function. Stated in the calibration rather than left for someone to notice.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 5.79, w: 11.55, h: 0.84, fontFace: SANS, fontSize: 11.5, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md §9.9 — same harness and criteria as the original four families, run BEFORE the two new ones shipped enabled");
}

/* ── S11d · what --quality-delta catches (examples: QD_EXAMPLES, top of this file) ─────────── */
{ const s = p.addSlide(); bg(s); qdExamples(s, QD_EXAMPLES); }

/* ── S12 · agent wiring ─────────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// built for the agent's seat", CYAN);
  title(s, "One command wires it into your agent", { size: 32 });
  chip(s, "$ ripwire wrap claude", MX, 1.95, 4.35, GREEN, { size: 14, h: 0.55 });
  s.addText("claude · cursor · codex · windsurf · gemini · aider — or --all to detect every one you have installed",
    { x: 5.2, y: 1.95, w: 7.4, h: 0.55, fontFace: SANS, fontSize: 12, color: MUTED, valign: "middle", margin: 0 });
  const cards = [
    ["31 MCP verbs", "16 read verbs mirroring the CLI, 12 flagship reflexes (impact, uses, edit_check, from_trace, connect …), 3 span-addressed edit verbs with a safety contract"],
    ["lazy-body handles", "read verbs return signatures and a stable handle; the agent fetches a body only when it decides it needs one — names by default, bytes on request"],
    ["18 agent skills", "moment-matched workflows (orient, navigate, change-check, quality-bar …) — wrap prints the recipe, skills/install.sh installs them"],
    ["12 orchestrator loops", "copy-paste prompts in prompts/: run the same audit, eval and head-to-head machinery that built this tool, on your own repository"],
  ];
  const cw = 5.95, ch = 1.62; let i = 0;
  for (const [h2, b] of cards){
    const x = MX + (i % 2) * (cw + 0.19), y = 2.78 + Math.floor(i / 2) * (ch + 0.18);
    card(s, x, y, cw, ch);
    s.addText(h2, { x: x+0.2, y: y+0.12, w: cw-0.4, h: 0.4, fontFace: MONO, fontSize: 14, bold: true, color: CYAN, margin: 0 });
    s.addText(b,  { x: x+0.2, y: y+0.55, w: cw-0.4, h: 1.1, fontFace: SANS, fontSize: 11.5, color: MUTED, margin: 0 });
    i++;
  }
  card(s, MX, 6.30, 12.09, 0.62, CARD2);
  s.addText([
    { text: "wrap does not just print JSON: ", options: { color: TEXT, bold: true } },
    { text: "it probes what that agent already has, emits the config in that agent's own shape, and includes a use-when blurb so the agent knows which verb fires at which moment — not just that a server exists.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.39, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "the MCP server exposes the same deterministic engine — one index, shared with the CLI, staleness-checked");
  notes(s, [
    "SOURCES (agent wiring)",
    "- “31 MCP verbs … 16 read verbs … 12 flagship reflexes … 3 span-addressed edit verbs” — README.md on main 40a1895b: “One stdio server, 31 verbs — 16 read, 12 flagship-reflex, 3 span-addressed edit”.",
    "- “18 agent skills” — README.md: “skills/ ships eighteen task-shaped skills”; skills/ holds 18 directories.",
    "- “12 orchestrator loops” — README.md: “prompts/ holds twelve self-contained orchestrator prompts”, and prompts/ holds 12 .md files besides its own README.md. This card said 11 until 2026-09-11; test/readmedriftcheck.sh arm (I1) gates the README against the directory, and the deck now states the same number.",
  ]);
}

/* ── S12ab · the edit loop ──────────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// it does not only read", CYAN);
  title(s, "Span-addressed edits: the map writes back", { size: 32 });

  card(s, MX, 1.68, 6.1, 2.42);
  s.addText("Three verbs, one resolved span", { x: MX+0.2, y: 1.80, w: 5.7, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: CYAN, margin: 0 });
  s.addText([
    { text: "--replace-symbol-body=TARGET\n--insert-before-symbol=TARGET\n--insert-after-symbol=TARGET\n", options: { color: TEXT } },
    { text: "  --edit-payload=FILE|-", options: { color: MUTED } },
  ], { x: MX+0.2, y: 2.18, w: 5.7, h: 1.1, fontFace: MONO, fontSize: 11.5, margin: 0 });
  s.addText("TARGET is a name, an @FILE:LINE seed — paste the location out of a diff hunk or a compiler error and it binds the innermost enclosing definition — or a freshness-pinned handle from --grep --handles. No line numbers to keep in your head, and no whole-file rewrite.",
    { x: MX+0.2, y: 3.24, w: 5.7, h: 0.78, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });

  card(s, 7.0, 1.68, 5.62, 2.42, CARD2);
  s.addText("The refusals are the feature", { x: 7.2, y: 1.80, w: 5.22, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: AMBER, margin: 0 });
  s.addText("Freshness hash, lock, a re-check immediately before the rename, fsync, mode preserved, atomic rename. A target that resolves to more than one definition refuses. An empty payload refuses rather than being read as a deletion. Every refusal leaves the file byte-identical, and every success prints a JSON receipt whose span is the POST-EDIT byte range — where the payload now sits, not where it was aimed.",
    { x: 7.2, y: 2.18, w: 5.22, h: 1.84, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });

  card(s, MX, 4.26, 6.1, 1.92);
  s.addText("Preview the bytes before they exist", { x: MX+0.2, y: 4.38, w: 5.7, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: GREEN, margin: 0 });
  s.addText("--edit-check=SYM --edit-payload=- --dry-run splices the payload over the span IN MEMORY, re-parses that one file, rebuilds the call graph over the re-derived tree, and answers the contract question about bytes nobody has written: did the signature change, and which callers does it break? Preview, then apply — no Read of the file in between.",
    { x: MX+0.2, y: 4.76, w: 5.7, h: 1.3, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });

  card(s, 7.0, 4.26, 5.62, 1.92);
  s.addText("Several edits, one transaction", { x: 7.2, y: 4.38, w: 5.22, h: 0.34, fontFace: SANS, fontSize: 14, bold: true, color: CYAN, margin: 0 });
  s.addText("--edit-plan=FILE is a versioned JSON multi-edit plan and its mode is EXPLICIT: exactly one of --dry-run or --apply, and neither is not a default. Every target, payload and span is preflighted before any write; overlapping edits refuse; payload paths are confined to the plan's own directory, so an absolute path or a '..' escape refuses and names what it resolved to.",
    { x: 7.2, y: 4.76, w: 5.22, h: 1.3, fontFace: SANS, fontSize: 10.5, color: MUTED, margin: 0 });

  card(s, MX, 6.32, 12.09, 0.62, CARD2);
  s.addText([
    { text: "Same engine on both seats: ", options: { color: TEXT, bold: true } },
    { text: "the three MCP edit verbs are these three flags, and the navigation the deck has no room for is the same story — --graph-query, --whereis, --stray-content, --at, --arch, --owners, --export, --help-task all sit in docs/COMMANDS.md with a recorded invocation and its output.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.41, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "every claim on this slide is stated by `ripwire --help` and captured in docs/COMMANDS.md — test/deckcheck.sh proves each flag named here exists in the shipped binary");
}

/* ── S12b · the research inside ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// standing on giants", AMBER);
  title(s, "The research inside — classic and current");
  s.addText([
    { text: "49 repositories + 70 papers folded", options: { color: TEXT, bold: true } },
    { text: "  ·  and a labelled survey of 237 tools that contributed nothing, which says so — every row with the lesson taken and where it lives: docs/LINEAGE.md", options: { color: MUTED } },
  ], { x: MX, y: 1.58, w: 12.0, h: 0.34, fontFace: SANS, fontSize: 13, margin: 0 });
  const classics = [
    ["1976", "Cyclomatic complexity — McCabe", "the metric behind --hotspots"],
    ["1994", "Okapi BM25 — Robertson · Spärck Jones", "the lexical ranker (twice: subtoken+body, whole-name)"],
    ["1998", "Personalized PageRank — Page · Brin", "the headline importance signal"],
    ["2008", "Louvain modularity — Blondel et al.", "the module / community map"],
    ["2009", "Reciprocal Rank Fusion — Cormack et al.", "deterministic signal fusion (--rank-by=rrf)"],
    ["2011", "Readability model — Posnett · Hindle · Devanbu", "the lexical family of the quality panel"],
    ["2019", "Delta Maintainability Model — di Biase et al.", "--dmm: one comparable number per change"],
  ];
  let y = 2.05;
  for (const [yr, t, d] of classics){
    // 7 cards at 0.70 end at 6.87, clear of the footer; at 0.74 the last one ran under it.
    card(s, MX, y, 6.1, 0.62);
    s.addText(yr, { x: MX+0.16, y: y+0.04, w: 0.75, h: 0.54, fontFace: MONO, fontSize: 12, bold: true, color: AMBER, valign: "middle", margin: 0 });
    s.addText([
      { text: t + "\n", options: { color: TEXT, bold: true, fontSize: 11 } },
      { text: d, options: { color: MUTED, fontSize: 9.5 } },
    ], { x: MX+1.0, y: y+0.04, w: 5.0, h: 0.54, fontFace: SANS, valign: "middle", margin: 0 });
    y += 0.70;
  }
  const modern = [
    ["TDAD · arXiv 2603.17973", "a static test-map cut agent-caused regressions 6.08% → 1.82%; prose TDD instructions alone made agents WORSE → the shape of --test-gate"],
    ["What-to-Retrieve · arXiv 2503.20589", "retrieval selection beats retrieval volume for coding agents → the selection-over-dumping thesis"],
    ["LocAgent / Loc-Bench (2025)", "the localization metric (strict Acc@k) and the frozen 560-instance dataset every accuracy number here is scored on"],
    ["scip-clang · Serena / clangd", "the compiler-grade oracle round 9 graded both tools against — an outside referee, not a rival"],
    ["tree-sitter", "the incremental GLR parsing substrate — 24 grammars vendored, one parser per thread"],
  ];
  notes(s, [
    "SOURCES (grammar count only)",
    "- \"24 grammars vendored\" — merged: #126, merge commit 1ad9184a (PR body: \"vendored fwcd/tree-sitter-kotlin grammar\"). Before #126 the count was 23 (commit 680a0a3d); README.md on main 40a1895b says \"24 vendored grammars\".",
  ]);
  y = 2.05;
  for (const [t, d] of modern){
    card(s, 7.0, y, 5.6, 0.9, CARD2);   // 5 cards at 0.97 end at 6.83; at 1.03 the last one ran under the footer
    s.addText(t, { x: 7.2, y: y+0.06, w: 5.2, h: 0.3, fontFace: MONO, fontSize: 11, bold: true, color: CYAN, margin: 0 });
    s.addText(d, { x: 7.2, y: y+0.36, w: 5.2, h: 0.5, fontFace: SANS, fontSize: 9.5, color: MUTED, margin: 0 });
    y += 0.97;
  }
  foot(s, "counts gated in-repo: readmedriftcheck arm E derives them from LINEAGE.md's own tables — the lineage is the design rationale");
}

/* ── S12c · re-derive this deck ─────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// do not take any of it on trust", AMBER);
  title(s, "Every claim, and the command that re-derives it");
  const claims = [
    ["179 long flags · 34 slides",        "bash test/deckclaimcheck.sh"],
    ["every --flag named here exists",    "bash test/deckcheck.sh"],
    ["74.7% fewer element bytes",         "bash test/showcasecapturecheck.sh"],
    ["606 gate scripts",                  "bash test/manifestcheck.sh"], // gatecount
    ["49 repos · 70 papers · 237 surveyed","bash test/readmedriftcheck.sh"],
    ["the ten moments, any row",          "ripwire . --callers=SYM | wc -c"],
    ["the head-to-head table",            "bench/headtohead/r4-2026-08-06/"],
    ["the oracle round",                  "bench/headtohead/r9-2026-08-09/RESULTS.md"],
  ];
  let y = 1.7;
  for (const [claim, cmd] of claims){
    row(s, y, 0.5, [
      { t: claim, w: 5.3,  color: TEXT, size: 12 },
      { t: cmd,   w: 6.2,  color: CYAN, size: 11.5, mono: true },
    ]);
    y += 0.575;
  }
  card(s, MX, 6.32, 12.09, 0.62, CARD2);
  s.addText([
    { text: "The deck is generated, and the generator is gated. ", options: { color: TEXT, bold: true } },
    { text: "present/deck5_ripwire_build.js is scanned for fabricated flags and its slide count is derived from its own addSlide() calls — a deck that drifts from the binary fails the suite.", options: { color: MUTED } },
  ], { x: MX+0.25, y: 6.41, w: 11.6, h: 0.46, fontFace: SANS, fontSize: 11, valign: "middle", margin: 0 });
  foot(s, "docs/EVALS.md is the source of truth; §7 is the counterexamples, §8 the claims this project refuses to make");
}

/* ── S13 · quickstart / close ───────────────────────────────────────────── */
{
  const s = p.addSlide(); bg(s);
  kicker(s, "// sixty seconds to the first ranked map", CYAN);
  title(s, "Quickstart");
  card(s, MX, 1.95, 12.09, 1.55, CARD2);
  s.addText(
"git clone <repo> && cd ripwire\ncmake -S . -B build && cmake --build build -j     # hermetic: works with the network off\n./build/ripwire --help",
    { x: MX+0.25, y: 2.12, w: 11.6, h: 1.25, fontFace: MONO, fontSize: 13.5, color: TEXT, margin: 0 });
  const firsts = [
    ["ripwire .", "the ranked map — start here on any unfamiliar repo"],
    ["ripwire . --for=\"cache invalidation\"", "the task lens: what to touch, ranked"],
    ["ripwire . --callers=someFunction", "who calls it — with the honesty marker attached"],
    ["ripwire . --quality-panel", "is this code actually rotten? six families, one shortlist"],
    ["ripwire . --test-gate", "before you commit: exactly which tests must run"],
    ["ripwire wrap claude", "wire it into your agent, in that agent's own config shape"],
  ];
  let y = 3.72;
  for (const [cmd, what] of firsts){
    chip(s, cmd, MX, y, 5.7, CYAN, { size: 12, h: 0.46 });
    s.addText(what, { x: 6.55, y: y, w: 6.1, h: 0.46, fontFace: SANS, fontSize: 11.5, color: MUTED, valign: "middle", margin: 0 });
    y += 0.54;
  }
  s.addText([
    { text: "ripgrep", options: { color: CYAN, bold: true } },
    { text: " for the speed. ", options: { color: TEXT } },
    { text: "tripwire", options: { color: AMBER, bold: true } },
    { text: " for the honesty. Apache-2.0.", options: { color: TEXT } },
  ], { x: MX, y: 7.0, w: 12.0, h: 0.45, fontFace: SANS, fontSize: 16, margin: 0 });
}

p.writeFile({ fileName: require("path").join(__dirname, "ripwire-showcase.pptx") })
  .then(() => console.log("WROTE ripwire-showcase.pptx"));
