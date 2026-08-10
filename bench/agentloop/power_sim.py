#!/usr/bin/env python3
"""
power_sim.py — Monte Carlo power / MDE simulation for the ripwire agentloop A/B eval
(bench/agentloop/analyze.py's repository-clustered bootstrap on SWE-bench-Lite resolution rate).

STDLIB ONLY. No numpy (confirmed absent from this interpreter). Uses random.betavariate and
random.binomialvariate (both in Python's stdlib `random` module; binomialvariate requires Python
>= 3.12 — this environment reports 3.14.6, so it's available).

WHAT THIS REPRODUCES FROM analyze.py (bench/agentloop/analyze.py, read in full before writing this):
  - pair_by_task_seed (L38-56): pairs records by (instance_id, seed) across the two arms. We generate
    already-paired data directly (no need to re-derive the pairing logic; the object of interest is
    the *bootstrap*, not the join).
  - clustered_bootstrap_lower (L58-76): resamples REPOS with replacement len(repos) times per bootstrap
    draw, pools every paired per-(instance,seed) delta belonging to the sampled repos, takes the mean;
    repeats n_boot times; sorts; returns the alpha-quantile (default alpha=0.025, i.e. the 2.5th
    percentile => nominally a "95% one-sided lower bound", see NOTE-1 below) as the lower confidence
    bound. `resolved_delta` (L78) is bool(ctx.resolved) - bool(base.resolved) per pair, i.e. a paired
    binary outcome in {-1,0,+1}.

MATHEMATICAL SIMPLIFICATION (derived by hand, stated here so it can be checked against the source):
  Every config we simulate has EQUAL cluster size (every repo contributes the same number of
  instance*seed pairs — true of the real design, which caps 4 instances/repo, and true of every
  hypothetical config below). Under equal cluster sizes, clustered_bootstrap_lower's
      vals = [ v for r in sampled_repos for v in by_repo[r] ]; boots.append(mean(vals))
  is algebraically IDENTICAL to: draw G repo names with replacement from the G repo-level MEANS
  m_1..m_G, and average those G (possibly repeated) means. Proof: if every repo contributes exactly n
  values, mean(vals) = (1/(G*n)) * sum_{drawn r} sum(by_repo[r]) = (1/(G*n)) * sum_{drawn r} (n*m_r)
                       = (1/G) * sum_{drawn r} m_r.
  This is exactly what "effective N ~= number of clusters" means in the task brief, made precise: the
  entire bootstrap distribution is a resampling of only G numbers, regardless of how many instances or
  seeds sit inside each repo. We exploit this for speed (no need to materialize per-instance arrays
  inside the bootstrap loop) and for correctness (it is an exact identity, not an approximation).

  A second identity we use: for the repo-level MEAN delta m_g = mean(ctx_ijk - base_ijk) over the n
  instance*seed pairs in repo g, m_g = mean(ctx) - mean(base) regardless of any correlation between a
  specific pair's base and ctx outcome (linearity of the sum). So m_g's distribution needs only two
  independent Binomial draws per repo per trial — Binomial(n, p1_g) for ctx successes and
  Binomial(n, p0_g) for base successes — not n individual paired Bernoulli draws. This does NOT
  reproduce row-level pairing correlation (irrelevant to analyze.py's statistic, which is a repo-level
  MEAN) but is exact for the quantity the bootstrap actually consumes.

NOTE-1 (a mislabeling in analyze.py worth flagging, per task item 1): the docstring at L58-62 calls
  alpha=0.025's 2.5th-percentile cutoff a "95% one-sided lower bound". That is not quite right: the
  2.5th percentile is the lower edge of a *two-sided* 95% CI (equivalently, a *97.5%* one-sided lower
  bound). A true 95% one-sided lower bound uses the 5th percentile (alpha=0.05). The practical
  consequence is that analyze.py's shipped default is MORE conservative than a plain one-sided 5% test:
  it requires slightly stronger evidence to call `lower > 0`, which lowers realized power at any given
  N relative to what "alpha=0.05" nominally promises. We compute the MDE table using alpha=0.05 (the
  value the task asks for), and separately quantify the alpha=0.025-vs-0.05 gap (function
  `alpha_sensitivity_check`) so the reader can see the size of this effect on the number that matters.

REPO-LEVEL RANDOM EFFECTS MODEL (this is the part with no ground truth to calibrate against — the pilot
never scored resolution, see FINDINGS.md item 2). Single ICC parameter rho, applied twice, both
draws sharing the same variance scale (the standard beta-binomial ICC identity Var(p_g) = rho*p*(1-p)):
  1. Baseline-difficulty heterogeneity: p0_g ~ Beta(mean=baseline_rate, ICC=rho)   [rho=0 => p0_g fixed]
  2. Treatment-effect heterogeneity:    delta_g = delta + eps_g,  eps_g ~ Normal(0, sqrt(rho*p*(1-p)))
     p1_g = clip(p0_g + delta_g, 0, 1)
  Component (1) mostly CANCELS in the paired difference delta_g = p1_g - p0_g (that's the point of
  pairing on the same instance/repo in both arms). Component (2) is what actually stops power from
  reaching 100% as instances-per-repo -> infinity with G fixed: it is a true between-repo nuisance
  parameter on the ESTIMAND itself (some repos may benefit from ripwire more than others), and no
  amount of within-repo sampling can shrink Var(delta_g)/G below a floor of rho*p*(1-p)/G. This is the
  most important and most debatable modeling choice in this file — see FINDINGS.md for the sensitivity
  discussion. At rho=0 both components vanish and the model is a fully homogeneous paired design (no
  cluster nuisance at all), where more instances always buys more power regardless of G — also checked
  explicitly (function `homogeneous_sanity_check`).
"""
import random, math, sys, json, time

ALPHA_PRIMARY = 0.05      # what the task asks the MDE table to target (one-sided 95% lower bound)
ALPHA_SHIPPED = 0.025     # analyze.py's actual default (see NOTE-1)
N_BOOT = 2000              # bootstrap replicates per simulated trial (analyze.py's own default is 10000;
                            # reduced for wall-clock — see FINDINGS.md for the stability check)
TRIALS = 400                # Monte Carlo trials per power estimate (SE of a power estimate ~= 2.5pp)
BISECT_ITERS = 9             # range/2^9 ~= 0.12pp resolution, well under the MC noise floor
TARGET_POWER = 0.80

BASELINE_RATES = (0.20, 0.30, 0.40)
ICC_VALUES = (0.0, 0.05, 0.15, 0.30)

CONFIGS = [
    ("a", "24 inst / 6 clusters / K=1", 6, 4, 1),
    ("b", "24 inst / 6 clusters / K=3", 6, 4, 3),
    ("c", "48 inst / 6 clusters / K=3", 6, 8, 3),
    ("d", "96 inst / 6 clusters / K=3", 6, 16, 3),
    ("e", "96 inst / 12 clusters / K=3 (hypothetical: no disjointness rule)", 12, 8, 3),
]
# each tuple: (label, description, G=num_repos, instances_per_repo, K=seeds_per_instance)


def draw_p0( rng, baseline_rate, icc ):
    if icc <= 1e-9:
        return baseline_rate
    kappa = 1.0 / icc - 1.0
    a = max( baseline_rate * kappa, 1e-6 )
    b = max( ( 1.0 - baseline_rate ) * kappa, 1e-6 )
    return rng.betavariate( a, b )

def repo_effect_sd( baseline_rate, icc ):
    return math.sqrt( icc * baseline_rate * ( 1.0 - baseline_rate ) )

def simulate_repo_means( rng, G, n_per_repo, baseline_rate, delta, icc ):
    """One simulated trial's G repo-level mean deltas m_g. n_per_repo = instances_per_repo * K."""
    sd_eff = repo_effect_sd( baseline_rate, icc )
    m = []
    for _g in range( G ):
        p0 = draw_p0( rng, baseline_rate, icc )
        eps = rng.gauss( 0.0, sd_eff ) if icc > 1e-9 else 0.0
        p1 = min( 1.0, max( 0.0, p0 + delta + eps ) )
        base_hits = rng.binomialvariate( n_per_repo, p0 )
        ctx_hits  = rng.binomialvariate( n_per_repo, p1 )
        m.append( ( ctx_hits - base_hits ) / n_per_repo )
    return m

def bootstrap_lower( rng, m, n_boot, alpha ):
    """Exactly mirrors analyze.py's clustered_bootstrap_lower under the equal-cluster-size identity
    proven in the module docstring: resample G repo MEANS with replacement, G draws, average; repeat;
    sort; take boots[max(0,int(alpha*n_boot))]."""
    G = len( m )
    boots = [ sum( rng.choices( m, k=G ) ) / G for _ in range( n_boot ) ]
    boots.sort()
    idx = max( 0, int( alpha * len( boots ) ) )
    return boots[ idx ]

def power_at_delta( seed_key, G, n_per_repo, baseline_rate, delta, icc, trials=TRIALS, n_boot=N_BOOT, alpha=ALPHA_PRIMARY ):
    rng = random.Random( seed_key )
    hits = 0
    for _ in range( trials ):
        m = simulate_repo_means( rng, G, n_per_repo, baseline_rate, delta, icc )
        lb = bootstrap_lower( rng, m, n_boot, alpha )
        if lb > 0.0:
            hits += 1
    return hits / trials

def find_mde( G, n_per_repo, baseline_rate, icc, alpha=ALPHA_PRIMARY, target_power=TARGET_POWER,
              lo=0.0, hi=0.60, iters=BISECT_ITERS, tag="" ):
    """Bisection search for the smallest delta (resolution-rate lift, in probability units) at which
    power_at_delta reaches target_power. Assumes power is monotone non-decreasing in delta (true of
    this generative model up to Monte Carlo noise); hi=0.60 is well above any plausible MDE for the
    configs in scope, checked once below (assert_hi_saturates)."""
    key_base = f"mde|{tag}|G{G}|n{n_per_repo}|p{baseline_rate}|icc{icc}|a{alpha}"
    for i in range( iters ):
        mid = ( lo + hi ) / 2.0
        p = power_at_delta( key_base + f"|mid{i}", G, n_per_repo, baseline_rate, mid, icc, alpha=alpha )
        if p < target_power:
            lo = mid
        else:
            hi = mid
    return ( lo + hi ) / 2.0

def assert_hi_saturates( G, n_per_repo, baseline_rate, icc, alpha=ALPHA_PRIMARY, hi=0.60 ):
    p = power_at_delta( f"hicheck|G{G}|n{n_per_repo}|p{baseline_rate}|icc{icc}", G, n_per_repo, baseline_rate, hi, icc, alpha=alpha )
    return p

def find_required_n( G, K, baseline_rate, icc, target_delta, alpha=ALPHA_PRIMARY, target_power=TARGET_POWER,
                      n_grid=(4,8,12,16,24,32,48,64,96,128,192,256,384,512,768,1024,1536,2048,3072,4096,6144,8192) ):
    """Smallest instances_per_repo (from n_grid) such that power_at_delta(target_delta) >= target_power.
    Returns (instances_per_repo, total_instances, achieved_power) or (None, None, power_at_largest_grid_point)
    if even the largest grid point never reaches target_power (i.e. the ICC-imposed floor bites)."""
    last_power = None
    for inst_per_repo in n_grid:
        n_per_repo = inst_per_repo * K
        p = power_at_delta( f"reqn|G{G}|K{K}|p{baseline_rate}|icc{icc}|d{target_delta}|n{inst_per_repo}",
                             G, n_per_repo, baseline_rate, target_delta, icc, alpha=alpha, trials=300 )
        last_power = p
        if p >= target_power:
            return inst_per_repo, inst_per_repo * G, p
    return None, None, last_power

def homogeneous_sanity_check():
    """At icc=0 the model has zero between-repo nuisance; power should climb toward 1.0 as n grows,
    for ANY G (even G=1), confirming the model correctly reduces to a plain paired-proportions test
    with no cluster penalty when there truly is no clustering."""
    out = []
    for G in ( 1, 6 ):
        for n in ( 8, 64, 512 ):
            p = power_at_delta( f"homog|G{G}|n{n}", G, n, 0.30, 0.10, 0.0, trials=300 )
            out.append( ( G, n, p ) )
    return out

def alpha_sensitivity_check():
    """Quantifies NOTE-1: MDE at analyze.py's shipped alpha=0.025 vs the nominal alpha=0.05 the task
    asked for, at config (b), across the ICC grid, baseline_rate=0.30."""
    rows = []
    for icc in ICC_VALUES:
        mde_05 = find_mde( 6, 4*3, 0.30, icc, alpha=0.05, tag="alphasens05" )
        mde_025 = find_mde( 6, 4*3, 0.30, icc, alpha=0.025, tag="alphasens025" )
        rows.append( ( icc, mde_05, mde_025 ) )
    return rows

def cluster_vs_instance_floor_check():
    """item 5: fixes G=6, baseline=0.30, icc=0.15, and grows n_per_repo from 24 -> 300*3 to show the
    MDE PLATEAUS (instance-only scaling has diminishing, then ~zero, further return once within-repo
    noise is small relative to the icc-imposed between-repo floor); then shows what doubling G to 12 at
    matched per-repo N buys instead."""
    baseline_rate, icc = 0.30, 0.15
    growth = []
    for inst_per_repo in ( 4, 8, 16, 32, 64, 128, 256, 512 ):
        n_per_repo = inst_per_repo * 3
        mde = find_mde( 6, n_per_repo, baseline_rate, icc, tag=f"floor{inst_per_repo}" )
        growth.append( ( inst_per_repo, inst_per_repo * 6, mde ) )
    # matched per-repo-N cluster-count comparison: G=6 vs G=12, same n_per_repo (8 instances * K=3 = 24)
    mde_g6  = find_mde( 6,  8*3, baseline_rate, icc, tag="clustercmp_g6" )
    mde_g12 = find_mde( 12, 8*3, baseline_rate, icc, tag="clustercmp_g12" )
    return growth, mde_g6, mde_g12


def main():
    t_start = time.time()
    print( "=" * 100 )
    print( "ripwire agentloop A/B eval: power / MDE simulation" )
    print( f"alpha_primary={ALPHA_PRIMARY} alpha_shipped(analyze.py default)={ALPHA_SHIPPED} "
           f"n_boot={N_BOOT} trials/point={TRIALS} target_power={TARGET_POWER}" )
    print( "=" * 100 )

    # 0. sanity checks first — if these fail, nothing below can be trusted.
    print( "\n[sanity] homogeneous (icc=0) model: power should climb to ~1.0 with more N, any G" )
    for G, n, p in homogeneous_sanity_check():
        print( f"    G={G:<3} n_per_repo={n:<5} power={p:.3f}" )

    print( "\n[sanity] hi=0.60 saturation check (must be power=1.0-ish for bisection's hi bound to be valid)" )
    for ( label, desc, G, inst, K ) in CONFIGS:
        n_per_repo = inst * K
        p_hi = assert_hi_saturates( G, n_per_repo, 0.30, 0.15 )
        print( f"    config {label} ({desc}): power@delta=0.60pp-scale={p_hi:.3f}" )

    # 1. main MDE table: config x icc x baseline_rate
    print( "\n" + "=" * 100 )
    print( "MAIN TABLE: minimum detectable effect (MDE), percentage points, at 80% power, alpha=0.05" )
    print( "=" * 100 )
    results = {}   # (config_label, baseline_rate, icc) -> mde_pp
    for ( label, desc, G, inst, K ) in CONFIGS:
        n_per_repo = inst * K
        total_instances = inst * G
        print( f"\n-- config {label}: {desc}  [G={G} clusters, {inst} instances/repo, K={K} seeds -> "
               f"{total_instances} instances total, {n_per_repo} pairs/repo, {total_instances*K} pairs total]" )
        for baseline_rate in BASELINE_RATES:
            row = []
            for icc in ICC_VALUES:
                mde = find_mde( G, n_per_repo, baseline_rate, icc, tag=f"main_{label}" )
                results[ ( label, baseline_rate, icc ) ] = mde
                row.append( f"icc={icc:<4} -> {100*mde:5.1f}pp" )
            print( f"    baseline={int(100*baseline_rate)}%:  " + "   ".join( row ) )

    # 2. alpha sensitivity (NOTE-1)
    print( "\n" + "=" * 100 )
    print( "ALPHA SENSITIVITY (NOTE-1): config (b), baseline=30%, shipped alpha=0.025 vs nominal alpha=0.05" )
    print( "=" * 100 )
    for icc, mde05, mde025 in alpha_sensitivity_check():
        gap = 100 * ( mde025 - mde05 )
        print( f"    icc={icc:<4}  MDE@alpha0.05={100*mde05:5.1f}pp   MDE@alpha0.025(shipped)={100*mde025:5.1f}pp   gap={gap:+.1f}pp" )

    # 3. cluster-count vs instance-count floor
    print( "\n" + "=" * 100 )
    print( "CLUSTER-COUNT vs INSTANCE-COUNT (item 5): G=6 fixed, baseline=30%, icc=0.15" )
    print( "=" * 100 )
    growth, mde_g6, mde_g12 = cluster_vs_instance_floor_check()
    print( "    instances/repo -> total instances -> MDE(pp)  [G=6 fixed: watch this plateau]" )
    for inst_per_repo, total, mde in growth:
        print( f"      {inst_per_repo:<5} -> {total:<5} -> {100*mde:5.1f}pp" )
    print( f"    matched per-repo-N (24 pairs/repo) comparison: G=6 -> {100*mde_g6:.1f}pp   "
           f"G=12 -> {100*mde_g12:.1f}pp   (delta attributable to doubling cluster count alone)" )

    # 4. instances required for 5pp and 10pp detection, G=6 K=3, across icc
    print( "\n" + "=" * 100 )
    print( "DECISION QUESTION: instances required to detect a 5pp / 10pp lift (G=6 clusters, K=3, baseline=30%)" )
    print( "=" * 100 )
    for target_pp, target_delta in ( ( 5, 0.05 ), ( 10, 0.10 ) ):
        print( f"  -- target lift = {target_pp}pp --" )
        for icc in ICC_VALUES:
            inst_per_repo, total, achieved = find_required_n( 6, 3, 0.30, icc, target_delta )
            if inst_per_repo is None:
                print( f"      icc={icc:<4}: NOT REACHABLE within grid up to 8192 instances/repo "
                       f"(power only {achieved:.3f} at largest grid point) — icc-imposed floor" )
            else:
                print( f"      icc={icc:<4}: {inst_per_repo} instances/repo -> {total} instances total "
                       f"(achieved power {achieved:.3f})" )

    print( f"\n[done in {time.time()-t_start:.1f}s]" )

    # dump machine-readable results too
    out = {
        "config": { "alpha_primary": ALPHA_PRIMARY, "alpha_shipped": ALPHA_SHIPPED, "n_boot": N_BOOT,
                    "trials_per_point": TRIALS, "target_power": TARGET_POWER,
                    "baseline_rates": BASELINE_RATES, "icc_values": ICC_VALUES },
        "main_table_mde_pp": { f"{label}|baseline={br}|icc={icc}": 100*mde
                                for ( label, br, icc ), mde in results.items() },
    }
    with open( "power_sim_results.json", "w" ) as f:
        json.dump( out, f, indent=2 )

if __name__ == "__main__":
    main()
