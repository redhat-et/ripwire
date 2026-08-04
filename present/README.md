# present/ — the showcase deck

`ripwire-showcase.pptx` (and its PDF render) is the tool in 18 slides: what it is, the verb
surface, the measured numbers, and the honesty contract — for anyone who wants the pitch before
the README.

The deck follows the repository's claims discipline: every number on it is pinned by an instrument
in this repo (`docs/EVALS.md` is the source of truth), every named `--flag` exists in
`ripwire --help`, and the historical figures carry their caveats on the slide that shows them.

## Rebuild

The deck is generated, not hand-edited — `deck5_ripwire_build.js` is the source of truth:

```bash
cd present
npm install          # pptxgenjs, pinned by package-lock.json
node deck5_ripwire_build.js   # writes ripwire-showcase.pptx next to itself
```

Regenerate the PDF from the fresh pptx with LibreOffice
(`soffice --headless --convert-to pdf ripwire-showcase.pptx`) or PowerPoint's own export.

When a published number changes (a new head-to-head round, a re-baselined eval), change it in the
generator and rebuild — never patch the .pptx by hand, or the next rebuild silently reverts it.

Paths under a `present/` component are part of the ranking lenses' fixture tier (deliberately
de-prioritized), so these files never crowd real source out of `--for` results.
