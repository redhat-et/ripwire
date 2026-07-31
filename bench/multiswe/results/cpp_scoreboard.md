==============================================================================
multiswe — Multi-SWE-bench cpp localization eval  n_scored=121  (unindexable=1 offline-skip=0)
==============================================================================
Acc@k = STRICT (all gold files within top-k of one flat rank), per LocAgent's metric shape.
arm            |  file@1  file@3  file@5 file@10 |  any@10     MRR | wall/inst
------------------------------------------------------------------------------
for            |    8.3%   36.4%   47.9%   55.4% |   89.3%   0.465 |     0.17s
for-no-mention |    8.3%   35.5%   45.5%   53.7% |   86.8%   0.447 |     0.09s
query          |    8.3%   35.5%   45.5%   53.7% |   86.8%   0.447 |     0.09s

mention-anchor ablation: for.file@10 - for-no-mention.file@10 = +1.7pp

single-file primary stratum n=51:
  for            strict@10  86.3%
  for-no-mention strict@10  82.4%
  query          strict@10  82.4%

multi-file primary stratum n=70:
  for            strict@10  32.9%
  for-no-mention strict@10  32.9%
  query          strict@10  32.9%

wall clock total: 227.0s over 122 selected instances
