// test/macroreparsecheck.sh fixture — the member-macro leak under the CUDA grammar (a .cu file rides
// tree_sitter_cuda as Lang::Cpp). Same shape, same derailment, same repair.
#define NAME_OF(T) static const char* kindName() { return #T; }

namespace {

struct RiverKernel : public gpu::Kernel {
  using gpu::Kernel::Kernel;
  NAME_OF(RiverKernel)
};

struct StreamKernel : public gpu::Kernel {
  using gpu::Kernel::Kernel;
  NAME_OF(StreamKernel)
};

struct TideKernel : public gpu::Kernel {
  using gpu::Kernel::Kernel;
  NAME_OF(TideKernel)
};

int blockCount(int n, int blockSize) {
  if (blockSize <= 0) {
    return 0;
  }
  return (n + blockSize - 1) / blockSize;
}

}  // namespace
