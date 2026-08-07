# Round 4 — unified, N=60 paired (incomplete instances excluded: 0)

| arm | strict file@10 | any@10 | median wall |
| --- | --- | --- | --- |
| ripwire | 58.3% | 85.0% | 0.130 s |
| repowise | 33.3% | 53.3% | 1.324 s |
| cbm | 40.0% | 63.3% | 0.079 s |
| graphify | 31.7% | 46.7% | 0.732 s |
| aider | 18.3% | 35.0% | 3.344 s |
| aider_noperson | 8.3% | 21.7% | 0.919 s |
| codeseek_idents | 15.0% | 20.0% | 0.042 s |
| codeseek_raw | 0.0% | 0.0% | 0.030 s |

single-file stratum, n=32:
  ripwire          strict@10  90.6%   any@10  90.6%
  repowise         strict@10  50.0%   any@10  50.0%
  cbm              strict@10  62.5%   any@10  62.5%
  graphify         strict@10  50.0%   any@10  50.0%
  aider            strict@10  31.2%   any@10  31.2%
  aider_noperson   strict@10  12.5%   any@10  12.5%
  codeseek_idents  strict@10  25.0%   any@10  25.0%
  codeseek_raw     strict@10   0.0%   any@10   0.0%

multi-file stratum, n=28:
  ripwire          strict@10  21.4%   any@10  78.6%
  repowise         strict@10  14.3%   any@10  57.1%
  cbm              strict@10  14.3%   any@10  64.3%
  graphify         strict@10  10.7%   any@10  42.9%
  aider            strict@10   3.6%   any@10  39.3%
  aider_noperson   strict@10   3.6%   any@10  32.1%
  codeseek_idents  strict@10   3.6%   any@10  14.3%
  codeseek_raw     strict@10   0.0%   any@10   0.0%

paired win/loss vs ripwire (strict@10):
  vs repowise         both=18  ripwire-only=17  repowise-only= 2  neither=23
  vs cbm              both=22  ripwire-only=13  cbm-only= 2  neither=23
  vs graphify         both=18  ripwire-only=17  graphify-only= 1  neither=24
  vs aider            both=10  ripwire-only=25  aider-only= 1  neither=24
  vs aider_noperson   both= 5  ripwire-only=30  aider_noperson-only= 0  neither=25
  vs codeseek_idents  both= 9  ripwire-only=26  codeseek_idents-only= 0  neither=25
  vs codeseek_raw     both= 0  ripwire-only=35  codeseek_raw-only= 0  neither=25

ripwire strict losses (a competitor got ALL gold in top-10 where ripwire did not):
  JoinMarket-Org__joinmarket-clientserver-1180 (gold=2) won by cbm; ripwire worst=10 first=2
  scikit-learn__scikit-learn-29130 (gold=1) won by cbm,aider; ripwire worst=25 first=25
  django__django-18435 (gold=1) won by graphify; ripwire worst=40 first=40
  huggingface__transformers-22498 (gold=3) won by repowise; ripwire worst=45 first=0
  django__django-19043 (gold=3) won by repowise; ripwire worst=13 first=0

ripwire near-misses (all gold found, worst rank just outside 10) — the improvement surface:
  JoinMarket-Org__joinmarket-clientserver-1180 (gold=2) worst=10 first=2
  jazzband__django-two-factor-auth-390 (gold=2) worst=12 first=2
  ultralytics__ultralytics-17810 (gold=1) worst=13 first=13
  django__django-19043 (gold=3) worst=13 first=0
  justin13601__ACES-145 (gold=5) worst=20 first=1
  pandas-dev__pandas-29944 (gold=2) worst=21 first=0
  scikit-learn__scikit-learn-29130 (gold=1) worst=25 first=25
  jupyterhub__oauthenticator-764 (gold=2) worst=26 first=0
