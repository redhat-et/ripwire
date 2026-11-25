### Changed — `--for` page 1 now lists where the question's own words occur, by default (θ11)

Page 1 of a `--for` answer (CLI and the MCP `for` tool) now ends with a short question-sites block inside its root: for each
name, option or rare word the question spells, every `path:line` it occurs on, as a grep would list them, in at most 1,000 B
outside `est_tokens` and any budget. It saves the follow-on grep an agent would otherwise run. The block was added behind
`RIPWIRE_THETA11=1` in #746; it is now on by default, after two sealed held-out runs (NL4, NL5-large) passed.
`RIPWIRE_THETA11=0` turns it off, and the answer is then byte-identical to the one served before the block existed.
`--version` names the posture as `qsites=on` or `qsites=off`. The block no longer prints a newline: like the rest of the page,
it is minified XML with no newline outside CDATA. JSON, columnar and candidate output never carry it. The offline measurement
(no model calls) is in the pull request; the follow-on calls it removes are a grep-coverage proxy, not a live count.
