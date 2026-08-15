// verbs.cpp -- a standalone, disconnected-from-the-rest-of-the-corpus, STAR-topology community (verbsEntry
// calls each leaf directly; a chain topology here would split into several 2-member Louvain communities the
// way the early draft of leaf.cpp did -- see its own comment) whose only purpose is exercising the label's
// verb-histogram suffix's frequency ranking AND its tie-break: "parse" occurs three times (dominant,
// first), "render" and "emit" occur once each (tied at frequency 1, broken by first-seen NodeId order --
// renderThing is declared before emitThing, so render sorts before emit) -- and a fourth non-verb-prefixed
// member (helperOmega) that contributes nothing to the histogram, proving an unrecognized first word is
// silently skipped rather than corrupting the tally. Expected label suffix: " [parse,render,emit]" (top-3
// of the 3 distinct recognized verbs -- helperOmega's "helper" is not in verbtable.h's dictionary, and
// verbsEntry's own "verbs" is not either).

int parseOne()    { return 1; }
int parseTwo()    { return 2; }
int parseThree()  { return 3; }
int renderThing() { return 4; }
int emitThing()   { return 5; }
int helperOmega() { return 6; }
int verbsEntry()
{
    // separate statements, not one summed return expression -- see leaf.cpp's leafRun for why (the
    // shape, not the call-graph edges, is what collided with a preexisting test/zoomfix fixture symbol).
    parseOne();
    parseTwo();
    parseThree();
    renderThing();
    emitThing();
    return helperOmega();
}
