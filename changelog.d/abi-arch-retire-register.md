### Changed — `--arch` names its root and prints root-relative paths; `--abi` and `--arch` drop six derivable attributes and define the rest

**`--arch` answers carry `root=` and every `from=`/`to=`/`path=` is relative to it**, the convention every other verb's root already follows. It used to print each path as the root was typed, so `ripwire "$PWD" --arch=rules.txt` repeated the checkout path in every row: on this repository 45,837 B of a 235,417 B answer (1,389 path attributes), which is now 190,330 B. Under `ripwire .` the saving is the `./` prefix only (192,358 B to 190,299 B). The rows are byte-identical whichever way the root is spelled; a multi-root run has no single root to name and is unchanged. The root's own directory is `path="."`.

**Retired, because each was a second spelling of something beside it.** A script that reads one of these reads the right-hand side instead:

| retired | read instead |
|---|---|
| `<abi head=>` | the first nine characters of `at=` (it still rides where `at=` cannot be stamped) |
| `rows=` on `<abi>` and `<ref>` | the sum of the kind counters `drift= unknown= absent= rename= spelling= stub= head-moved=` (absent at 0) |
| `excluded=` on `<abi>` and `<ref>` | the sum of `rename= spelling= stub= head-moved=` |
| `<struct size_differs=>` | `size_delta=` is not 0 |
| `<arch new_violations=>` | the `<v>` rows without `baselined="1"` (the exit code answers the same question: 2 if any) |
| `<metrics note=>` | nothing: it was 574 B of definitions repeated as data in every answer (764 B beside `zone_unknown=`), and is the legend now |

`capped=` stays on `<abi>` and `<ref>` although it is `dropped` above 0: the bit rides beside every `shown=` in the tool.

**Every attribute the two verbs print is now defined in the answer's own legend.** Before, the default answer defined 6 of the 41 attribute names on the `--abi` fixture below and 1 of the 31 on the `--arch` one; its `--abi` purpose line described a different verb.

Measured, whole default answer, same tree, old binary then new:

| answer | before | after | legend | rows |
|---|---|---|---|---|
| `--abi`, 8-branch fixture | 3,962 B | 5,313 B (+34.1 %) | +1,779 B | −428 B |
| `--abi`, this repository (512 branches) | 23,163 B | 23,901 B (+3.2 %) | +1,770 B | −1,032 B |
| `--arch`, 5-file fixture | 1,465 B | 2,216 B (+51.3 %) | +1,355 B | −604 B |
| `--arch`, this repository, absolute root | 235,417 B | 190,330 B (−19.2 %) | +1,491 B | −46,578 B |

**A small answer is larger than it was.** The definitions cost more than the retirements return until the rows outweigh them; what the bytes buy is that no attribute in either answer has to be guessed. `docs/COMMANDS.md` and the dated showcase capture still show the old `--arch` root until they are next regenerated.
