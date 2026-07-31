//
//  wiringFlags.h — the --flags fixture's COMPILE gates (#ifndef / #define, the build-dark-then-flip idiom).
//

#ifndef flagsfix_wiringFlags_h
#define flagsfix_wiringFlags_h

// DARK: default 0, guards a real region below.
#ifndef FIXTURE_DARK_FEATURE
#define FIXTURE_DARK_FEATURE 0
#endif

// LIT: default 1 — declared the same way, so the gate table must not assume "gate ⇒ dark".
#ifndef FIXTURE_LIT_FEATURE
#define FIXTURE_LIT_FEATURE 1     // shipped ON — this trailing comment must NOT land in the default
#endif

// Declared but never tested anywhere: a dead name, not a gate. Must be absent from the report.
#ifndef FIXTURE_UNREAD_FEATURE
#define FIXTURE_UNREAD_FEATURE 0
#endif

#endif
