// Shape fixture: mixin, extension, enum, typedef — and the CASCADE case, which the
// upstream tags.scm over-captures. A cascade is a chain of member accesses on ONE
// receiver; only the invoked members are calls, and the receiver name is not one.

typedef IntTransform = int Function(int);

enum Mode { fast, slow }

mixin Loggable {
  void log(String message) {
    emit(message);
  }
}

void emit(String message) {}

extension Doubling on int {
  int doubled() => this * 2;
}

class Builder with Loggable {
  final List<int> items = [];

  void add(int x) {
    items.add(x);
  }

  void reset() {}

  void build() {
    // Cascade: `add` and `reset` are invoked; `this` is not a call.
    this
      ..add(1)
      ..add(2)
      ..reset();
  }

  int transform(int x) => x.doubled();
}
