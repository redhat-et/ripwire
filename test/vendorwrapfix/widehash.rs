// A raw string literal opened with exactly 256 hashes — the first count a uint8_t cannot hold.
// rustc caps this at 255, but a file on disk can carry it, and before
// rust/001-delimiter-count-cast the opening_hash_count++ at scanner.c:77 truncated and aborted the
// G1 stack. ABORT-ARM ONLY: unlike the markdown fixture there is no plain-build assertion to make
// here, because measurement found no extraction difference at any width (255/256/257/300 all
// recover the symbols after the raw string) — closing this token matches the opening count, so
// wrapping and saturating are equally unparseable and only the sanitizer can see the defect.
pub fn narrow_counter_wrap_rust() -> &'static str {
    r################################################################################################################################################################################################################################################################"two hundred and fifty six hashes"################################################################################################################################################################################################################################################################
}
