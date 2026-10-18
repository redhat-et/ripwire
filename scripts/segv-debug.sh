#!/usr/bin/env bash
# DEBUG BRANCH ONLY (debug/callers-band2-segv): run the MCP/--batch invocations that segfault on the gcc-14
# Release/LTO leg under gdb and print every thread's backtrace. Usage: scripts/segv-debug.sh BIN LABEL
BIN="$( cd "$( dirname "$1" )" && pwd )/$( basename "$1" )"; LABEL="$2"
FIX="$PWD/test/fixture"
W="$( mktemp -d )"
echo "===== [$LABEL] $BIN"
file "$BIN"; "$BIN" --version
mk() {   # mk NAME TOOL SYMBOL
    printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":{\"path\":\"$FIX\",\"symbol\":\"$3\"}}}" > "$W/$1.req"
}
mk fs_perimeter find_symbol perimeter
mk fr_distance find_referencing_symbols distance
printf 'callers: distance\n' > "$W/batch.txt"
for r in fs_perimeter fr_distance; do
    echo "----- [$LABEL] MCP $r (plain run)"
    ( cd "$FIX" || exit 1; "$BIN" --mcp < "$W/$r.req" > "$W/$r.out" 2> "$W/$r.err"; echo "rc=$?" ); head -c 600 "$W/$r.out"; echo; tail -5 "$W/$r.err"
    echo "----- [$LABEL] MCP $r under gdb"
    ( cd "$FIX" || exit 1; gdb -q -batch -ex "set pagination off" -ex "set print frame-arguments scalars" -ex "run --mcp < $W/$r.req > $W/$r.gdbout" \
        -ex "echo \n=== bt ===\n" -ex "bt 60" -ex "echo \n=== info registers ===\n" -ex "info registers" -ex "echo \n=== x/12i \$pc-24 ===\n" -ex "x/16i \$pc-32" \
        -ex "echo \n=== thread apply all bt full ===\n" -ex "thread apply all bt full" --args "$BIN" 2>&1 | head -c 120000 )
done
echo "----- [$LABEL] CLI --batch (plain run)"
( cd "$FIX" || exit 1; "$BIN" . --no-cache --batch="$W/batch.txt" > "$W/batch.out" 2> "$W/batch.err"; echo "rc=$?" ); head -c 400 "$W/batch.out"; echo
echo "----- [$LABEL] CLI --batch under gdb"
( cd "$FIX" || exit 1; gdb -q -batch -ex "set pagination off" -ex "run . --no-cache --batch=$W/batch.txt > /dev/null" -ex "bt 60" -ex "thread apply all bt full" --args "$BIN" 2>&1 | head -c 60000 )
exit 0
