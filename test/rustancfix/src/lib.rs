// rustancfix — fixture for the Rust qualified-call ANCESTOR-CLOSURE memo (perf round 2026-09-09).
// Names are deliberately unique across test/ so no other gate's --for/--grep pins them here.
//
// `impl <Trait> for <Type>` records Type -> Trait in the CHA-lite NAME graph (graph.h's chaUp), so a chain
// of impls is a TRANSITIVE base closure that a one-hop test cannot answer:
//
//     Alphaz -> Zonktop -> Zonkmid -> Zonkbase      (three hops)
//     Betaz  -> Zonkbase                            (one hop)
//     Gammaz -> Otherbase                           (never reaches Zonkbase)
//
// This is a NAME-graph fixture, not idiomatic Rust: the chain is spelled with impls because impls are what
// the graph records. tags.scm reads syntax, so it extracts exactly the same way a real supertrait chain of
// blanket impls would.

pub trait Zonkbase  { fn zonkrun( &self ) -> u32; }
pub trait Zonkmid   { fn zonkrun( &self ) -> u32; }
pub trait Zonktop   { fn zonkrun( &self ) -> u32; }
pub trait Otherbase { fn zonkrun( &self ) -> u32; }

pub struct Alphaz;
pub struct Betaz;
pub struct Gammaz;

impl Zonkbase for Zonkmid  { fn zonklink( &self ) -> u32 { 0 } }
impl Zonkmid  for Zonktop  { fn zonklink( &self ) -> u32 { 0 } }

impl Zonktop   for Alphaz { fn zonkrun( &self ) -> u32 { 1 } }
impl Zonkbase  for Betaz  { fn zonkrun( &self ) -> u32 { 2 } }
impl Otherbase for Gammaz { fn zonkrun( &self ) -> u32 { 3 } }

// (1) the FIRST ask — the guard walks each candidate's base closure looking for Zonkbase.
pub fn zonk_first() -> u32 { Zonkbase::zonkrun() }

// (2) a DIFFERENT qualifier in between, so the next ask is served after the memo has grown.
pub fn zonk_between() -> u32 { Otherbase::zonkrun() }

// (3) the memo HIT — Zonkbase again. It must be Zonkbase's own answer, never Otherbase's.
pub fn zonk_again() -> u32 { Zonkbase::zonkrun() }
