### Changed — a paged `--for` page 1 obeys the budget_bytes= it states

Page 1 of a default `--for` answer said `budget_bytes="7500"`, but that number was the ranked payload's target, measured before rows
became lines. Nothing held the page to it, and every DEV answer that stated it served more (median 14.6 KB: a 12,000 B row page plus
the legend, which no page counted).

Now (SIZE-PAGE, src/forpagebudgetswitch.h, src/forpages.h, src/verbs_for.h), on a PAGED answer the root's `budget_bytes=` (where the
answer states one) is a cap on EVERYTHING page 1 serves: root, rows (as lines), legend and the question-sites block. The full legend
reads it so. The cap is the page 1 the answer is served without it, so page 1 keeps every row it served before; rows past it are on
the next page, by the root's next=. Page 1 grows only by the cap's own digits (`7500` -> `14468`: +1 B); an answer served whole is
unchanged.

A cap below today's page 1 was measured and is not the default: 95 % lost 4 items on S1+MF1, 80 % lost 24 over DEV, and a fixed
7,500 B lost 80 on S1 (they cut the rows θ5's refill serves). `RIPWIRE_PAGE_BUDGET=0` turns the cap off (byte-identical to the answer
before it). `1-100` serves that percent and a larger number serves that many bytes; both are measurement arms, and a cap no cut fits
states the first cut's size. `--version` names `pagebudget=on|off`. New gate `test/pagebudgetcheck.sh`.
