### Changed — the near-clone comparison behind `--quality-delta` and `--clones` runs 64 DP cells per machine word

The Type-3 (gapped) clone pass compares candidate function bodies by the longest common subsequence of their normalized
tokens, and on large repos it was most of a warm `--quality-delta`. That LCS is now computed bit-parallel (Allison-Dix /
Hyyrö: one bit vector over one body, updated once per token of the other, 64 cells per word), and it stops as soon as
a pair can no longer reach the 0.8 similarity the pass keeps. The answer is unchanged: a kept pair gets its exact
length, and only pairs the threshold drops anyway stop early. A warm working-tree `--quality-delta` retires 46 %
(envoy), 82 % (cockroach) and 9 % (vscode) fewer instructions (median of five interleaved pairs, M2; user CPU −42 / −77
/ −6 %), a repeat `A..B` about the same, and a cold working-tree run 18 / 47 / 2 % fewer. `RIPWIRE_LCS_VERIFY=1` re-runs
every comparison with the plain DP and prints the counts (`test/lcsidentitycheck.sh`); on the three repos 289,811 real
pairs compared with no difference.
