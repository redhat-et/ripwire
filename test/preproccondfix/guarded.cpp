// Every C-family include SPELLING that sits inside a preprocessor conditional. One arm per grammar node
// kind the extractor has to descend through: preproc_if / preproc_ifdef (both `#ifdef` and `#ifndef`) /
// preproc_else / preproc_elif / preproc_elifdef, plus a nested `#if` inside `#if` and the `#import`
// spelling (which under the C/C++ grammar lands as a generic preproc_call, not a preproc_include).
//
// The include TARGETS are one-per-arm on purpose: a gate can name the arm that regressed from the
// missing `t="..."` alone, without counting.

#include "top.h"   // CONTROL — a plain top-level include, captured before this fix and after it

#if defined( RIPWIRE_COND_A )
#include "cond_if.h"
#else
#include "cond_else.h"
#endif

#ifdef RIPWIRE_COND_B
#include "cond_ifdef.h"
#elif defined( RIPWIRE_COND_C )
#include "cond_elif.h"
#endif

#ifndef RIPWIRE_COND_D
#include "cond_ifndef.h"
#elifdef RIPWIRE_COND_H
#include "cond_elifdef.h"
#endif

#if defined( RIPWIRE_COND_E )
#    if defined( RIPWIRE_COND_F )
#        include "cond_nested.h"
#    endif
#endif

#if defined( RIPWIRE_COND_G )
#import "cond_import.h"   // ObjC/Metal spelling under the C/C++ grammar → preproc_call, inside a guard
#endif

int guardedFn()
{
    return 0;
}
