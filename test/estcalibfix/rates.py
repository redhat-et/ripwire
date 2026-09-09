"""estcalibfix — FROZEN. See ledger.cpp's header; edits invalidate test/estcalib.manifest."""

DEFAULT_RATE = 2.5
BODY_RATE = 3.8


def bytes_per_token(language):
    """Return the measured bytes-per-token rate for a language, or the mid-band default."""
    table = {"cpp": 2.46, "python": 2.36, "typescript": 2.59}
    return table.get(language, DEFAULT_RATE)


def estimate_tokens(byte_count, language):
    """Convert emitted bytes to a token estimate at the language's own rate."""
    rate = bytes_per_token(language)
    if rate <= 0:
        raise ValueError("a non-positive rate is a corrupt caller, never a runtime condition")
    return int(byte_count / rate + 0.5)


def estimate_body_tokens(byte_count):
    """Body text tokenizes leaner than signature markup; charge it at its own rate."""
    return int(byte_count / BODY_RATE + 0.5)


def signed_error_pct(estimate, real):
    """Positive means the estimate over-reads the real count."""
    if real == 0:
        return None
    return 100.0 * (estimate - real) / real


def summarize(rows):
    """rows: [(estimate, real)]. Returns (n, worst_over, worst_under) with None for an empty set."""
    if not rows:
        return (0, None, None)
    errs = [signed_error_pct(e, r) for e, r in rows if signed_error_pct(e, r) is not None]
    if not errs:
        return (len(rows), None, None)
    return (len(rows), max(errs), min(errs))
