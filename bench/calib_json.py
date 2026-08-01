#!/usr/bin/env python3
# calib_json.py — measures the JSON row of kTokenCalib (src/serialize.h) the same way the rest of the
# table was calibrated: real o200k_base tiktoken over a real corpus, bytesPerToken = UTF-8 bytes / tokens
# (see  "Method" + commit aece7e5 "MAPE vs o200k"). Deterministic: fixed corpus
# directory arg, sorted file list, no sampling/shuffling.
#
# Reproduce:
#   python3 bench/calib_json.py <corpus_dir>
# e.g.
#   python3 bench/calib_json.py /path/to/some/scratch/dir/locbench/repos
import sys, glob, os
import tiktoken

ENC = tiktoken.get_encoding("o200k_base")

def main():
    corpus_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    paths = sorted(
        glob.glob(os.path.join(corpus_dir, "**", "package.json"), recursive=True)
        + glob.glob(os.path.join(corpus_dir, "**", "tsconfig.json"), recursive=True)
    )
    total_bytes = 0
    total_tokens = 0
    n = 0
    for p in paths:
        try:
            with open(p, "rb") as f:
                data = f.read()
        except OSError:
            continue
        text = data.decode("utf-8", errors="ignore")
        toks = ENC.encode(text, disallowed_special=())
        total_bytes += len(data)
        total_tokens += len(toks)
        n += 1
    if total_tokens == 0:
        print("no JSON files found / zero tokens — check corpus_dir")
        sys.exit(1)
    rate = total_bytes / total_tokens
    print(f"files (n)     = {n}")
    print(f"total bytes   = {total_bytes}")
    print(f"total tokens  = {total_tokens}  (o200k_base)")
    print(f"bytesPerToken = {rate:.4f}")
    print(f"rounded (2sf) = {rate:.2f}")

if __name__ == "__main__":
    main()
