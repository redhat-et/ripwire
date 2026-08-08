# Round 4 — FULL RE-RUN 2026-08-08 (all eight arms, one day, one machine)
#
# Binary: the profile-guided release build (build_pgo — RIPWIRE_PGO=use, LTO, Release) from the
# cachelint+PGO working tree on main@c049627+; competitor tools at the SAME pinned versions as
# 2026-08-06 (repowise-venv recreated per README recipe after macOS python-upgrade venv rot —
# same repowise==0.37.0). Per-instance JSONLs + this file's source: bench-assets/r4/rerun-2026-08-08/.
# Accuracy deltas vs 2026-08-06: ripwire/cbm/graphify/repowise instance-identical; aider +1 instance
# (18.3->20.0 strict — its own tie-break nondeterminism); codeseek idents +1 on all-in-10 stratum.

# Round 4 — unified, N=60 paired (incomplete instances excluded: 0)

| arm | strict file@10 | any@10 | median wall |
| --- | --- | --- | --- |
| ripwire | 58.3% | 85.0% | 0.108 s |
| repowise | 33.3% | 53.3% | 1.159 s |
| cbm | 40.0% | 63.3% | 0.075 s |
| graphify | 31.7% | 46.7% | 0.614 s |
| aider | 20.0% | 35.0% | 2.920 s |
| aider_noperson | 10.0% | 25.0% | 0.818 s |
| codeseek_idents | 15.0% | 20.0% | 0.040 s |
| codeseek_raw | 0.0% | 0.0% | 0.024 s |

single-file stratum, n=32:
  ripwire          strict@10  90.6%   any@10  90.6%
  repowise         strict@10  50.0%   any@10  50.0%
  cbm              strict@10  62.5%   any@10  62.5%
  graphify         strict@10  50.0%   any@10  50.0%
  aider            strict@10  31.2%   any@10  31.2%
  aider_noperson   strict@10  15.6%   any@10  15.6%
  codeseek_idents  strict@10  25.0%   any@10  25.0%
  codeseek_raw     strict@10   0.0%   any@10   0.0%

multi-file stratum, n=28:
  ripwire          strict@10  21.4%   any@10  78.6%
  repowise         strict@10  14.3%   any@10  57.1%
  cbm              strict@10  14.3%   any@10  64.3%
  graphify         strict@10  10.7%   any@10  42.9%
  aider            strict@10   7.1%   any@10  39.3%
  aider_noperson   strict@10   3.6%   any@10  35.7%
  codeseek_idents  strict@10   3.6%   any@10  14.3%
  codeseek_raw     strict@10   0.0%   any@10   0.0%

paired win/loss vs ripwire (strict@10):
  vs repowise         both=18  ripwire-only=17  repowise-only= 2  neither=23
  vs cbm              both=22  ripwire-only=13  cbm-only= 2  neither=23
  vs graphify         both=18  ripwire-only=17  graphify-only= 1  neither=24
  vs aider            both=11  ripwire-only=24  aider-only= 1  neither=24
  vs aider_noperson   both= 5  ripwire-only=30  aider_noperson-only= 1  neither=24
  vs codeseek_idents  both= 9  ripwire-only=26  codeseek_idents-only= 0  neither=25
  vs codeseek_raw     both= 0  ripwire-only=35  codeseek_raw-only= 0  neither=25

ripwire strict losses (a competitor got ALL gold in top-10 where ripwire did not):
  ultralytics__ultralytics-17810 (gold=1) won by aider_noperson; ripwire worst=13 first=13
  JoinMarket-Org__joinmarket-clientserver-1180 (gold=2) won by cbm; ripwire worst=10 first=2
  scikit-learn__scikit-learn-29130 (gold=1) won by cbm,aider; ripwire worst=25 first=25
  django__django-18435 (gold=1) won by graphify; ripwire worst=42 first=42
  huggingface__transformers-22498 (gold=3) won by repowise; ripwire worst=45 first=0
  django__django-19043 (gold=3) won by repowise; ripwire worst=14 first=0

ripwire near-misses (all gold found, worst rank just outside 10) — the improvement surface:
  JoinMarket-Org__joinmarket-clientserver-1180 (gold=2) worst=10 first=2
  jazzband__django-two-factor-auth-390 (gold=2) worst=12 first=2
  ultralytics__ultralytics-17810 (gold=1) worst=13 first=13
  django__django-19043 (gold=3) worst=14 first=0
  justin13601__ACES-145 (gold=5) worst=20 first=1
  pandas-dev__pandas-29944 (gold=2) worst=21 first=0
  scikit-learn__scikit-learn-29130 (gold=1) worst=25 first=25
  jupyterhub__oauthenticator-764 (gold=2) worst=26 first=0
