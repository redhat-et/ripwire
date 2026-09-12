// test/macroreparsecheck.sh fixture — the member-macro leak PLUS an unrelated syntax error the re-parse cannot fix
// (the stray operator in ferryFare). Blanking the invocations still removes most of the error bytes, so the re-parse
// is adopted — and the adopted tree STILL holds an error, which the --skipped row must keep saying (degraded-parse,
// err= above zero) beside the per-file blank count.
#define NAME_OF(T) static const char* kindName() { return #T; }

namespace {

struct UplandFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(UplandFault)
};

struct ValleyFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(ValleyFault)
};

struct WillowFault : public core::Fault {
  using core::Fault::Fault;
  NAME_OF(WillowFault)
};

int portCount(int docks, int closed) {
  if (closed > docks) {
    return 0;
  }
  return docks - closed;
}

int ferryFare(int base) {
  return base * ;
}

}  // namespace
