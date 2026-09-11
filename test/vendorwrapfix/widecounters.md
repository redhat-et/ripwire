# narrowCounterWrapMarkdown

Every construct below drives one of this scanner's uint8_t counters past 255. Each is pinned at
EXACTLY 256 — the first unrepresentable width — and not at a round 300, because the two damage
windows are different sizes: the sanitizer aborts at every value >= 256, but the WRONG PARSE only
fires while the wrapped value lands below the threshold the parser tests, i.e. N mod 256 in 0..3.
A 300-wide fixture reproduces the abort and asserts nothing about the parse, so it would stay
green through a full revert of the fix on the plain build. Widths here are gate-pinned as ==256.

## buriedHeadingIsACodeBlockNotAHeading

An ATX heading buried under exactly 256 columns. CommonMark says indented code block. Upstream
wrapped 256 to 0 and emitted a heading symbol for it, at exit 0. Arm I asserts the name is ABSENT.

                                                                                                                                                                                                                                                                # buriedByTwoFiftySixColumns

## sixtyFourTabsReachItSoonerThanSpacesDo

advance() charges a tab at tab stop 4, so 64 tabs is 256 columns — far more reachable in a real
repository than 256 spaces, and a separate arm because it exercises the tab arm of advance().

																																																																# buriedBySixtyFourTabs

## softLineEndingLookaheadSite

A list item followed by a 256-column continuation line. This drives the soft-line-ending
lookahead loop, a SECOND indentation site that the plain leading-indent case above never reaches.

- list item
                                                                                                                                                                                                                                                                # buriedInListContinuation

## fenceDelimiterPastTwoFiftyFive

A fence of exactly 256 tildes. `level` is tested `>= 3` before a fence may open, so wrapping to 0
meant the fence never opened and its contents leaked out as live markdown. Arm I asserts the
heading inside the fence is ABSENT. Tildes, not backticks: parse_fenced_code_block takes the
delimiter as a parameter so both spellings reach the same counter, and a 4+-backtick run in any
doc --recall serves verbatim breaks the five-backtick embedding fence mdembedcheck pins.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# buriedInsideFence
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## indentAccumulatesPastTwoFiftyFive

The list-marker sites: parse_minus, parse_star, parse_plus, parse_ordered_list_marker.

-                                                                                                                                                                                                                                                                minus marker then 256 spaces

*                                                                                                                                                                                                                                                                star marker then 256 spaces

+                                                                                                                                                                                                                                                                plus marker then 256 spaces

1.                                                                                                                                                                                                                                                                ordered marker then 256 spaces

## pipeTableRowPaddedPastTwoFiftyFive

The shape found in the wild (rails/guides/source/getting_started.md line 122):

| File/Folder                    | Purpose                                                                                                                                                                                                                                                                |
| --- | --- |
| a | b |
