# ripwire-router — reference: legend (read on demand; the recipe is in SKILL.md)

## The legend: compact by default, full when a definition needs its reasoning

Every command these skills spell asks for the compact legend (`--legend=compact`: terse definitions of only the attributes the answer carries). Compact is also the CLI's DEFAULT now, so on a current binary the flag is redundant — it stays so a command reads the same on an older one. Add `--legend=full` when a definition's reasoning is needed — a term you do not recognise, a floor or cap you need explained, or a map a human will read. `--for` spells no flag: its compact legend is its own dialect, and the default.

The other exceptions are not a choice — **the binary refuses `--legend=compact` on any command that does not answer with an XML legend**, and a command it refuses runs not at all. Two families: the **state-changing** commands, which write something rather than answer (`--quality-ack`, `--quality-baseline`, `--arch --baseline`, `--note-add`, `--replace-symbol-body` / `--insert-before-symbol` / `--insert-after-symbol`, `--edit-plan`, `--index-out=`), which refuse either posture, and the **non-XML renderings** (`--mermaid`, `--html`, `--report`, `--sarif`, `--situ`, `--recall=`, `--export`), where `--legend=full` is accepted as a no-op because the full form is the only one they have. Those carry no `--legend=compact`. `--pin-census=` is not among them: it writes its census beside a map, and the map takes a posture like any other. This matters when you compose rather than copy: a flag that turns an XML verb into one of these — `--zoom --mermaid`, `--quality-delta --quality-ack` — takes the whole command with it, so the verb is not what decides, the command is. Nothing here is a rule you have to apply by hand: `ripwire --help-task` spells no posture at all (the binary's default decides), and `test/skilltruthcheck.sh` runs every `--legend=compact` command these skills spell against the binary and fails on a refusal.

### Say which definitions you hold, then stop paying for them: `--legend-have=`

**The flag is a statement that you READ those lines, not a switch.** The legend is a near-FIXED cost per answer — measured 531–4,305 B, median 1,796 — so the SHORTER the answer, the bigger its share: 14 % of a `--for` bundle but **62 % of a `--whereis` answer**. The CLI has no session, so it cannot know what you were sent; you tell it, and you may only tell it what is in your context.

Read the core once — **all of it** (13 definitions, about 1.5 KB):

```bash
ripwire --legend-dict=core
```

Its first line carries `have=<16 hex>`. Pass that value on later calls — `ripwire ROOT --callers=SYM --legend-have=<that value>` — and each answer comes back rows first, root unchanged, ending `<about legend="ref" have="core" …/>`. A definition you hold is left out; **one you do not hold is still in the answer, in a comment after the rows.** You are never expected to open the full dictionary.

About to call one verb three or more times? Read its pack instead (`ripwire --legend-dict=callers`: the core plus that verb's definitions, 0.4–2.3 KB more for the everyday verbs) and pass the `have=` on *its* first line. Several packs: join the values with commas.

**What it costs and when it pays — measured over 453 answers of 12 verbs on five corpora.** The core is 1,512 B and removes 149 B per call: **11 calls to repay** (9 over the 388 that are not `--for`; 9 to 17 by corpus). A pack repays within 3 calls of its verb and removes 0.3–1.7 KB per call. Core plus the verb's pack keeps 86 % of what holding the whole dictionary would save — and the whole dictionary is about 130 KB, about 130 calls to repay, so it is not the handshake to reach for. **On a session of fewer than about 10 ripwire calls, pass nothing**: the default answer already defines only what it carries. `--for` answers are not reduced at all, and stderr says so.

**Read first.** Passing a value whose lines you never read leaves every dropped definition unread, and the answer will be correct while you cannot interpret it. If your context was compacted and the lines are gone, read them again or stop passing the flag. The first line alone is a value with nothing behind it.

Refusals, all deliberate: an empty `--legend-have=` (usually a shell variable that expanded to nothing — ignoring it would serve a full-price answer while you believed it was reduced), and any value this binary does not recognise, even beside a valid one (the message names the command to re-read).
