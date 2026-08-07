==============================================================================
cppbench — real-repo C++ localization eval  n_scored=115  (unindexable=5)
==============================================================================
Acc@k = STRICT (all gold files within top-k of one flat rank), per LocAgent's metric shape.
arm            |  file@1  file@3  file@5 file@10 |  any@10     MRR | wall/inst
------------------------------------------------------------------------------
for            |    5.2%   11.3%   18.3%   28.7% |   41.7%   0.205 |     0.88s
for-no-mention |    5.2%   11.3%   18.3%   28.7% |   41.7%   0.205 |     0.28s
query          |    5.2%   11.3%   18.3%   28.7% |   41.7%   0.205 |     0.29s

mention-anchor ablation: for.file@10 - for-no-mention.file@10 = +0.0pp

wall clock total: 863.5s over 120 mined instances
