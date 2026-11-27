// bench/statfloor.c — the parallel-lstat FLOOR for a path list. Standalone: NOT wired into CMake,
// NOT repo code, never shipped. It exists so a published claim about `warmsnap: replay the crawl`
// can be checked, because that claim is a comparison and a comparison needs both numbers.
//
// WHY. The replay's job is one lstat per watched path. Its cost therefore has a floor that no
// amount of code can go below: the syscalls themselves. Without that floor measured on the SAME
// trees, "the replay got slower on a bigger repo" cannot be told apart from "lstat got slower on a
// bigger repo", and the first reads as a defect while the second is the operating system.
//
// MEASURE IT ON A QUIET MACHINE. Taken under load this program overstates the effect badly: on a
// loaded box it reported llvm-project at 1.56 us/path against kubernetes' 0.43 (3.6x), and inside a
// quiet window the same two trees are 0.57 against 0.40 (1.4x). The contention landed on the larger
// tree, which is exactly how a contention artifact impersonates super-linear growth. Medians of 3.
//
//   clang -O2 -o statfloor bench/statfloor.c
//   find <repo> | ./statfloor 8        # 8 worker threads; `1` for the single-threaded floor
//
// Reads newline-separated paths on stdin, lstats them all, prints paths / wall ms / us per path.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <pthread.h>
#include <time.h>

static char **paths;
static size_t npaths;
static size_t cursor;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static long long hits;

static void *worker(void *arg) {
    (void)arg;
    long long local = 0;
    for (;;) {
        pthread_mutex_lock(&lock);
        size_t lo = cursor;
        size_t hi = lo + 256 < npaths ? lo + 256 : npaths;
        cursor = hi;
        pthread_mutex_unlock(&lock);
        if (lo >= npaths) break;
        for (size_t i = lo; i < hi; ++i) {
            struct stat st;
            if (lstat(paths[i], &st) == 0) local += (long long)st.st_size ? 1 : 1;
        }
    }
    pthread_mutex_lock(&lock);
    hits += local;
    pthread_mutex_unlock(&lock);
    return NULL;
}

int main(int argc, char **argv) {
    int nthreads = argc > 1 ? atoi(argv[1]) : 8;
    size_t cap = 1 << 16;
    paths = malloc(cap * sizeof(char *));
    char *line = NULL;
    size_t linecap = 0;
    ssize_t n;
    while ((n = getline(&line, &linecap, stdin)) > 0) {
        if (line[n - 1] == '\n') line[n - 1] = 0;
        if (npaths == cap) { cap *= 2; paths = realloc(paths, cap * sizeof(char *)); }
        paths[npaths++] = strdup(line);
    }
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    pthread_t *th = malloc((size_t)nthreads * sizeof(pthread_t));
    for (int i = 0; i < nthreads; ++i) pthread_create(&th[i], NULL, worker, NULL);
    for (int i = 0; i < nthreads; ++i) pthread_join(th[i], NULL);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double ms = (double)(t1.tv_sec - t0.tv_sec) * 1e3 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
    printf("paths=%zu threads=%d hits=%lld wall_ms=%.1f us_per_path=%.2f\n",
           npaths, nthreads, hits, ms, npaths ? ms * 1000.0 / (double)npaths : 0.0);
    return 0;
}
