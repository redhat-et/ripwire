#!/usr/bin/env bash
# skillshapecheck.sh — the shipped skills keep the shape Anthropic's Agent Skills guidance asks for (2026-11-26 round).
#
# Two structural rules, each from the progressive-disclosure model (metadata always loaded, SKILL.md body on trigger,
# bundled references on demand):
#   (A) a SKILL.md body stays under 500 lines — the guidance's stated limit before content moves to reference files;
#   (B) a reference file over 100 lines opens with a `Contents:` line (within its first 5 lines), so an agent that reads
#       only the head of it still sees everything the file holds;
# Each rule is also run against a planted copy that breaks it, and must go red there: a structural check that cannot
# fail measures nothing.
#
#   test/skillshapecheck.sh            (no binary needed — a pure file check)
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# body_lines FILE — lines after the closing --- of the frontmatter
body_lines(){ awk 'NR==1 && /^---$/ {f=1; next} f==1 && /^---$/ {f=2; next} f==2 {n++} END {print n+0}' "$1"; }

# check SKILLS_DIR — prints one line per violation, returns the count
check(){
    local d="$1" bad=0 f n
    for f in "$d"/ripwire-*/SKILL.md; do
        n="$( body_lines "$f" )"
        [ "$n" -lt 500 ] || { echo "A ${f#"$d"/}: body is $n lines (limit 500)"; bad=$(( bad + 1 )); }
    done
    for f in "$d"/ripwire-*/*.md; do
        [ "$( basename "$f" )" = SKILL.md ] && continue
        n="$( wc -l <"$f" | tr -d ' ' )"
        [ "$n" -le 100 ] && continue
        head -5 "$f" | grep -q '^Contents: .' || { echo "B ${f#"$d"/}: $n lines, no 'Contents:' line in its first 5"; bad=$(( bad + 1 )); }
    done
    return "$bad"
}

out="$( check "$ROOT/skills" )"; rc=$?
nskill="$( ls "$ROOT"/skills/ripwire-*/SKILL.md | wc -l | tr -d ' ' )"
nlong="$( for f in "$ROOT"/skills/ripwire-*/*.md; do [ "$( basename "$f" )" = SKILL.md ] || [ "$( wc -l <"$f" )" -le 100 ] || echo x; done | wc -l | tr -d ' ' )"
[ "$nskill" -gt 0 ] && [ "$nlong" -gt 0 ] \
    && ok "inspected $nskill SKILL.md files and $nlong reference files over 100 lines" \
    || no "inspected $nskill SKILL.md / $nlong long references — the arm saw nothing"
[ "$rc" -eq 0 ] && ok "every skill meets A (body < 500 lines) and B (long reference opens with Contents:)" \
                || { no "$rc violation(s):"; printf '%s\n' "$out" | sed 's/^/        /'; }

# ── controls: each rule goes red on a copy planted to break it ─────────────────────────────────────────────
for rule in A B; do
    P="$TMP/planted_$rule"; cp -R "$ROOT/skills" "$P"
    case "$rule" in
        A) f="$P/ripwire-handoff/SKILL.md"; for i in $( seq 1 500 ); do echo "padding $i"; done >>"$f" ;;
        B) f="$( for g in "$P"/ripwire-*/*.md; do [ "$( basename "$g" )" = SKILL.md ] || { [ "$( wc -l <"$g" )" -gt 100 ] && echo "$g"; }; done | head -1 )"
           grep -v '^Contents: ' "$f" >"$f.new" && mv "$f.new" "$f" ;;
    esac
    pout="$( check "$P" )"
    printf '%s\n' "$pout" | grep -q "^$rule " \
        && ok "control: rule $rule goes red on a copy planted to break it" \
        || no "control: rule $rule stayed green on a planted violation — the check is vacuous"
done

[ "$fail" -eq 0 ] && echo "skillshapecheck: ALL PASS" || echo "skillshapecheck: FAILURES"
exit "$fail"
