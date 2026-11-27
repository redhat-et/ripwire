# The record parser

A record is a header line, a body and a `#` footer. `parseHeader` reads the first line, `parseBody` reads tokens up to the
footer mark, and `parseFooter` reads the footer token.
