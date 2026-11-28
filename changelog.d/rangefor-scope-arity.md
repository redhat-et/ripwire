### Fixed — `portablebuildcheck` arm #7 no longer blames an unrelated range-for for a local variable's name

Arm #7 holds a portability rule: no range-for in `src/` may read through a temporary that only C++23 P2718 keeps alive, because GCC 13/14 do not implement P2718 and the same source segfaults there. It is a text pass, and it resolves a range-for's callee **by name** across the whole tree: a finding unless every declaration of that name returns a reference or a pointer.

Two unrelated lanes hit the same false positive on the same day, both reported at `src/backhops.h:841` — `for( const std::uint32_t put : m_back.queue().putsIn( u ) )`, a line neither lane touches. That code is safe: `queue()` returns `const QueueHops&`, a reference to a live member, so there is no temporary, and `putsIn()` returns a `std::vector` by value, which the range-for's own `auto&&` lifetime-extends in every standard. What flipped it was the name `queue` acquiring a second, by-value meaning somewhere else in the tree:

- **#822** added a local `std::vector<std::uint32_t> queue( nodeCount + 1, 0u )` in `src/pagerank.cpp`. A local declared with parenthesised initialisation reads, to a text pass, exactly like a declaration of a function `queue` returning a vector by value. Bisected one file at a time onto main's `src/`: that file alone flips the arm, and renaming those 7 tokens clears it with `backhops.h` untouched.
- **#837** added `ClassLevelWalk::queue( NodeId )` in `src/resolve.h` — a genuine by-value declaration at class scope, on a class the range-for never names. Its head commit `b5f2cdafb` renamed the member to `queueNext` to escape the arm.

Two fixes, each necessary, neither sufficient:

1. **Scope.** A `RET NAME( … )` inside a **function body** is a local variable, not a declaration a call site could resolve to, and is no longer collected. The container/function-body distinction mirrors the one `test/lib/capdisclose.py` has drawn for cap sites since 2026-11-12.
2. **Arity.** A C++ call cannot resolve to a declaration taking more required parameters than it passes arguments, so the zero-argument `m_back.queue()` cannot mean `bool queue( NodeId )`. Only declarations whose `(required, most)` parameter range admits the call's argument count are considered; `...` makes `most` unbounded, a defaulted parameter lowers `required`, and top-level commas only, so `std::map<int, int> m` is one parameter.

Recall is unchanged: the planted control still finds exactly its four shapes (method, member path + method, subscript, undeclared callee), and an undeclared callee is still a finding, because unknown is not safe.

Gate: the near-miss control gains all three shapes, and each is held by a different half — **(a)** #822's local, **(b)** #837's class-scope by-value declaration, and **(c)** a local whose initialiser passes as many arguments as the call site does, so arity cannot separate it and only scope can. Measured: with both filters the control is clean; with the scope filter removed it reds on (c); with the arity filter removed it reds on (b). (a) alone would not have proved the scope filter, because its local passes two arguments where the call passes none — the first version of this control had exactly that hole.

Cross-checked against both lanes' real trees: main's `src/` plus #822's `pagerank.cpp` passes, and #837 **before** its rename (`b5f2cdafb^`) passes — so that rename would not have been needed.
