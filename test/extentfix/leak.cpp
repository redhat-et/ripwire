// test/extentcheck.sh fixture — the scope-leak shape. Every struct in the run below ends with a macro
// invocation and NO semicolon, as the last member of its body. tree-sitter-cpp recovers that as a
// field declaration missing its `;`, dissolves the earlier structs into an ERROR region, and lets the
// LAST struct's body swallow everything up to the namespace's closing brace. Without the extent check
// the free functions after the run come out as `method` rows filed under IndiaError:: — a scope the
// source never gave them. test/extentfix/control/leak.cpp is this file with the semicolons added.
// The macro is LOWERCASE on purpose: the member-macro re-parse (src/macroreparse.h, test/macroreparsecheck.sh) repairs
// the ALL-CAPS spelling of this run and deliberately leaves a lowercase invocation alone — so this is the shape that
// still derails, and the extent detector keeps a live producer.
#include <exception>

#define declare_name(T) static const char* Name() { return #T; }

struct Ledger
{
    int larger( int a, int b )
    {
        if( a > b )
        {
            return a;
        }
        return b;
    }
};

int fileScopeHelper( int v )
{
    if( v > 10 )
    {
        return v - 10;
    }
    return v;
}

namespace {

struct AlphaError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(AlphaError)
};

struct BravoError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(BravoError)
};

struct CharlieError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(CharlieError)
};

struct DeltaError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(DeltaError)
};

struct EchoError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(EchoError)
};

struct FoxtrotError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(FoxtrotError)
};

struct GolfError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(GolfError)
};

struct HotelError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(HotelError)
};

struct IndiaError : public lib::BaseError {
  using lib::BaseError::BaseError;
  declare_name(IndiaError)
};

void accumulateOrders(int &total, int count) {
  if (count > 0) {
    total += count;
  }
}

int clampQuantity(int quantity, int ceiling) {
  if (quantity < 0) {
    return 0;
  }
  if (quantity > ceiling) {
    return ceiling;
  }
  return quantity;
}

bool hasLabel(const char *label) {
  if (!label) return false;
  return label[0] != '\0';
}

void drainQueue(int &pending) {
  while (pending > 0) {
    accumulateOrders(pending, -1);
  }
}

}  // namespace
