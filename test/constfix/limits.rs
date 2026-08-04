// Connection limits config — Rust const/static items are constants by construction.

pub const RS_MAX_CONNECTIONS: usize = 128;

pub static RS_DEFAULT_TIMEOUT_MS: u64 = 5_000;

pub fn effective_limit() -> usize {
    RS_MAX_CONNECTIONS
}
