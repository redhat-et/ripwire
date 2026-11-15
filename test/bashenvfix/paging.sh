#!/usr/bin/env bash
# paging.sh — three reads, then two writes, of one name: the read AND write site lists page under --limit.
echo "$PAGE_MANY"
echo "${PAGE_MANY:-a}"
echo "${PAGE_MANY:?}"
PAGE_MANY=one
PAGE_MANY=two
