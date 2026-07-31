==============================================================================
cppbench — real-repo C++ localization eval  n_scored=115  (unindexable=5)
==============================================================================
Acc@k = STRICT (all gold files within top-k of one flat rank), per LocAgent's metric shape.
arm            |  file@1  file@3  file@5 file@10 |  any@10     MRR | wall/inst
------------------------------------------------------------------------------
for            |    7.0%   14.8%   20.0%   31.3% |   45.2%   0.219 |     0.78s
for-no-mention |    7.0%   14.8%   20.0%   31.3% |   45.2%   0.219 |     0.23s
query          |    7.0%   14.8%   20.0%   31.3% |   45.2%   0.219 |     0.26s

mention-anchor ablation: for.file@10 - for-no-mention.file@10 = +0.0pp

wall clock total: 718.9s over 120 mined instances
