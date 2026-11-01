#!/usr/bin/env python3
# TEMP measuring step for lane mem-largealloc (removed in the next commit): interleaved max RSS and wall per mode.
import hashlib, os, subprocess, sys, time
BIN, FX = sys.argv[1], sys.argv[2]
MODES = {"default": {"RW_B": "0"},
         "thr256k": {"RW_B": "0", "MALLOC_MMAP_THRESHOLD_": "262144"},
         "B": {"RW_B": "2048"},
         "B+thr256k": {"RW_B": "2048", "MALLOC_MMAP_THRESHOLD_": "262144"},
         "arena1": {"RW_B": "0", "MALLOC_ARENA_MAX": "1"},
         "thr256k+trim": {"RW_B": "0", "MALLOC_MMAP_THRESHOLD_": "262144", "MALLOC_TRIM_THRESHOLD_": "1048576"}}
names = list(MODES)
for rd in range(3):
    for i in range(len(names)):
        m = names[(i + rd) % len(names)]
        env = dict(os.environ); env.update(MODES[m])
        with open("/tmp/o.txt", "wb") as o:
            t = time.time()
            p = subprocess.Popen([BIN, FX, "--no-cache", "--deps"], cwd=FX, env=env, stdout=o, stderr=subprocess.DEVNULL)
            _, st, ru = os.wait4(p.pid, 0)
            w = time.time() - t
        h = hashlib.md5(open("/tmp/o.txt", "rb").read()).hexdigest()[:8]
        print(f"MEASURE\t{rd}\t{m}\trss_mb={ru.ru_maxrss/1024:.0f}\twall={w:.1f}\tuser={ru.ru_utime:.1f}\tsys={ru.ru_stime:.1f}\trc={st}\tmd5={h}", flush=True)
