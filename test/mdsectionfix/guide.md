---
zqfrontkey: zqfrontval
tags: [alpha, beta]
---

Preamble prose before any heading, mentioning `zqCodeAnchorFn` inline.

# Orientation Guide

The orientation body carries zqorientbody as its unique marker token.

## Cache Warm Path

The warm path body carries zqcachewarmbody and mentions `codeIdentFn` in a
backtick. It links to [the partner doc](partner.md) and jumps to
[result tables](#result-tables) further down. An archived copy
[lives here][zqref].

```cpp
# zqfencephantom is not a heading
void zqFencedPhantomFn( int keepOut )
{
    return;
}
```

## Closed Heading ##

The closed-heading body carries zqclosedheadingbody.

## Result Tables

The tables body carries zqresulttables and cites [[decoy]] the wiki way.

| metric | value |
|--------|-------|
| rows   | `zqcellmention` |

Deployment Rollout Setext
=========================

The setext h1 body carries zqsetextbody1.

Rollback Plan
-------------

The setext h2 body carries zqsetextbody2.

> # Quoted Phantom
> a blockquoted heading is quoted content, not document structure

<div>
# zqhtmlphantom is not a heading
</div>

~~~
# zqtildephantom is not a heading
~~~

### Deep Appendix

    # zqindentphantom is not a heading

The appendix body carries zqdeepappendix.

#

[zqref]: decoy.md "Archived decoy copy"
