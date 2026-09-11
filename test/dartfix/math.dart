// Core extraction fixture: top-level functions, a class with methods, a getter/setter
// pair, and the call edges between them. Constructors are exercised separately in the
// gate's constructor block, because they index under the class name by design.

int square(int x) => x * x;

int twice(int x) => square(square(x));

int secret() => 42;

int answer() {
  return secret();
}

int branchy(int x) {
  if (x > 0) {
    return square(x);
  }
  return 0;
}

class Calculator {
  int _total = 0;

  int get total => _total;

  set total(int value) => _total = value;

  int accumulate(int x) {
    _total = _total + square(x);
    return _total;
  }

  int untouched() => 7;
}
