#!/usr/bin/env bash
# b.sh — Bash ingest fixture for jslangcheck.sh.
# Two functions where sum_of_squares calls square → one intra-file call edge
# sum_of_squares -> square.

square()
{
    echo $(( $1 * $1 ))
}

sum_of_squares()
{
    local a
    a=$( square "$1" )
    local b
    b=$( square "$2" )
    echo $(( a + b ))
}

sum_of_squares 3 4
