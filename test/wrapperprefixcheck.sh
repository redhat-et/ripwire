#!/usr/bin/env bash
# wrapperprefixcheck.sh — an emitted body starts where its DECLARATION starts, wrapper prefix included.
#
#   test/wrapperprefixcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/wrapperprefixcheck.sh
#   test/wrapperprefixcheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE GAP (measured on 21d4b66b7 and on 0.6.10-dev.74, 103 language x form rows, 45 of them lost their first line or
# its leading keyword). Several grammars wrap a declaration in an OUTER node, or hang its attributes in front of it as
# SIBLINGS, and the tags query captures the inner node. A symbol's span starts at that inner node, and every body a verb
# emitted started there too:
#     export function f() {}          ->  function f() {}            the `export` is gone
#     @cache \n def f(): ...          ->  def f(): ...               a different function
#     template<typename T> T f(T a)   ->  T f(T a)                   does not compile
#     #[inline] \n fn f() {}          ->  fn f() {}
# A graded answer that delivered a TypeScript body in full lost the body rung over the one missing word.
#
# THE CONTRACT. A body element (<b> under --expand, the --for body fold, --pack-task) starts at the declaration's first
# byte: the outermost wrapper node around the definition (TS/JS export_statement and ambient `declare`, Python
# decorated_definition, C++/CUDA template_declaration and single-declaration `extern "C"`, Lua `local x = function`,
# Ruby `private def` / a one-argument receiverless call around a def), then the run of attribute siblings in front of it
# (Rust #[..], TS/JS method decorators, Dart and GDScript annotations). The SYMBOL does not move: l= is still the line
# of its name, and every analysis that reads [sigStartByte, endByte) reads what it read before. The edit verbs splice
# the span --expand prints, so they move with it: --replace-symbol-body replaces the wrapper too, and
# --insert-before-symbol lands above a decorator, not between it and its function.
#
# ARMS. Each row of the manifest below is (arm | file | symbol | form | the declaration's first source line).
#   (W)  wrapper rows — NEW arms, proof: RED on the unfixed binary (the body's first line is the inner node's). The
#        served body starts with the manifest line, is a byte-exact contiguous slice of the file, and still ends where it did.
#   (C)  control rows — forms the base already emitted whole (Java/Kotlin/C#/Swift/PHP annotations and modifiers, Rust
#        `pub`, Go, ObjC, Bash, Clojure, plain definitions in every language). Pinned in BOTH directions: the first line is
#        the manifest's, so the fix adds nothing to a declaration that has no wrapper. Elixir's @doc/@spec are separate
#        module attributes, not a wrapper: `def` stays the first line (an absence, pinned).
#   (N)  MUTATION negative control: the same comparison, fed a manifest line with its first byte dropped, must MISS on
#        every row. Proves the comparator can go red; it is what the (C) rows' green rests on.
#   (X)  no over-reach: the last method of a Python class does not grow into its class; a Rust doc comment above an
#        attribute run is not swept in; a plain function after an attributed one keeps its own first line.
#   (L)  the symbol did not move: l= on the wrapper rows is the NAME's line (py_stacked_deco l=11, rs_stacked_attr_fn l=16,
#        cppTemplateFn l=2, tsDecoratedMethod l=52).
#   (F)  the --for body fold and --pack-task serve the same first line as --expand (py_stacked_deco, rs_stacked_attr_fn).
#   (E)  the edit verbs splice the span --expand prints: replacing a body with the bytes --expand served leaves the file
#        byte-identical (a consistency invariant: holds on the unfixed binary too, and breaks if only one side moves);
#        --insert-before-symbol on a decorated Python def lands ABOVE `@first_deco` (NEW: red on the unfixed binary).
#   (D)  deterministic (two runs byte-identical) and well formed (xmllint, when installed).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
export RIPWIRE_TINY_SHAPE=0   # THETA6-FLIP (tiny shape on by default since #742): (F) reads a served body's first line; the tiny answer serves no bodies
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "wrapperprefixcheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
DIR="${KEEP_DIR:-$( mktemp -d )}"; [ -n "${KEEP_DIR:-}" ] || trap 'rm -rf "$DIR"' EXIT; mkdir -p "$DIR"
FX="$DIR/fx"; mkdir -p "$FX"
echo "wrapperprefixcheck: BIN=$BIN"

# ── fixture: one file per language, every wrapper form beside a plain control ─────────────────────────
cat > "$FX/a_ts.ts" <<'WXEOF'
export function tsExportFn(a: number): number {
  return a + 1;
}

export default function tsExportDefaultFn(a: number): number {
  return a + 2;
}

export async function tsExportAsyncFn(a: number): Promise<number> {
  return a + 3;
}

export class TsExportClass {
  run(): number {
    return 4;
  }
}

export abstract class TsExportAbstractClass {
  abstract run(): number;
}

export interface TsExportIface {
  run(): number;
}

export type TsExportAlias = { a: number; b: string };

export enum TsExportEnum {
  A,
  B,
}

export const tsExportArrow = (a: number): number => {
  return a + 5;
};

export const tsExportConst = {
  a: 1,
  b: 2,
};

declare function tsDeclareFn(a: number): number;

function tsPlainFn(a: number): number {
  return a + 6;
}

@Component({ selector: 'x' })
export class TsDecoratedClass {
  @Input()
  tsDecoratedMethod(): number {
    return 7;
  }
}

export namespace TsExportNs {
  export function tsNsInnerFn(): number {
    return 8;
  }
}
WXEOF
cat > "$FX/b_tsx.tsx" <<'WXEOF'
export function TsxExportFn(props: { a: number }) {
  return <div>{props.a}</div>;
}

export default function TsxExportDefaultFn() {
  return <span>x</span>;
}

export const TsxExportArrow = (props: { a: number }) => {
  return <b>{props.a}</b>;
};
WXEOF
cat > "$FX/c_js.js" <<'WXEOF'
export function jsExportFn(a) {
  return a + 1;
}

export default function jsExportDefaultFn(a) {
  return a + 2;
}

export async function jsExportAsyncFn(a) {
  return a + 3;
}

export class JsExportClass {
  run() {
    return 4;
  }
}

export const jsExportArrow = (a) => {
  return a + 5;
};

function jsPlainFn(a) {
  return a + 6;
}
WXEOF
cat > "$FX/d_py.py" <<'WXEOF'
import functools


@functools.cache
def py_single_deco(a):
    return a + 1


@first_deco
@second_deco(arg=1)
def py_stacked_deco(a):
    return a + 2


@dataclass
class PyDecoClass:
    a: int = 0

    @property
    def py_deco_method(self):
        return self.a

    @staticmethod
    def py_static_method(a):
        return a + 3


def py_plain(a):
    return a + 4


async def py_async_plain(a):
    return a + 5
WXEOF
cat > "$FX/e_cpp.cpp" <<'WXEOF'
template<typename T>
T cppTemplateFn( T a )
{
    return a + 1;
}

template<typename T>
class CppTemplateClass
{
public:
    T cppInlineMember( T a )
    {
        return a + 2;
    }

    template<typename U>
    U cppMemberTemplate( U a )
    {
        return a + 3;
    }

    T cppOutOfLine( T a );
};

template<typename T>
T CppTemplateClass<T>::cppOutOfLine( T a )
{
    return a + 4;
}

template<typename T>
template<typename U>
U CppNested<T>::cppNestedTemplate( U a )
{
    return a + 5;
}

template<>
int cppTemplateFn<int>( int a )
{
    return a + 6;
}

template<typename T>
struct CppTemplateStruct
{
    T v;
};

template<typename T>
using CppTemplateAlias = CppTemplateStruct<T>;

[[nodiscard]] static inline int cppAttrFn( int a )
{
    return a + 7;
}

extern "C" int cppExternC( int a )
{
    return a + 8;
}

int cppPlain( int a )
{
    return a + 9;
}
WXEOF
cat > "$FX/f_java.java" <<'WXEOF'
package p;

public class JavaClass {
    @Override
    public String javaAnnotated() {
        return "a";
    }

    @Deprecated
    @SuppressWarnings("x")
    private static int javaStacked(int a) {
        return a + 1;
    }

    int javaPlain(int a) {
        return a + 2;
    }
}

@FunctionalInterface
interface JavaAnnotatedIface {
    int run(int a);
}
WXEOF
cat > "$FX/g_rs.rs" <<'WXEOF'
pub fn rs_pub_fn(a: i32) -> i32 {
    a + 1
}

pub(crate) fn rs_pub_crate_fn(a: i32) -> i32 {
    a + 2
}

#[inline]
fn rs_attr_fn(a: i32) -> i32 {
    a + 3
}

#[inline]
#[must_use]
pub fn rs_stacked_attr_fn(a: i32) -> i32 {
    a + 4
}

#[derive(Debug, Clone)]
pub struct RsAttrStruct {
    a: i32,
}

/// doc comment
#[derive(Debug)]
pub enum RsAttrEnum {
    A,
    B,
}

pub async unsafe fn rs_async_unsafe_fn(a: i32) -> i32 {
    a + 5
}

fn rs_plain(a: i32) -> i32 {
    a + 6
}
WXEOF
cat > "$FX/h_cs.cs" <<'WXEOF'
namespace N
{
    [Serializable]
    public class CsAttrClass
    {
        [Obsolete("x")]
        public static int CsAttrMethod(int a)
        {
            return a + 1;
        }

        [Obsolete]
        [Conditional("D")]
        internal int CsStackedAttr(int a)
        {
            return a + 2;
        }

        public async Task<int> CsModifiers(int a)
        {
            return a + 3;
        }
    }
}
WXEOF
cat > "$FX/i_swift.swift" <<'WXEOF'
@available(iOS 13, *)
public func swiftAttrFn(a: Int) -> Int {
    return a + 1
}

@objc
public class SwiftAttrClass {
    @discardableResult
    public func swiftAttrMethod(a: Int) -> Int {
        return a + 2
    }

    private static func swiftModifiers(a: Int) -> Int {
        return a + 3
    }
}

public func swiftPublicFn(a: Int) -> Int {
    return a + 4
}
WXEOF
cat > "$FX/j_go.go" <<'WXEOF'
package p

// GoDocFn doc
func GoFn(a int) int {
	return a + 1
}

type GoStruct struct {
	A int
}

func (g *GoStruct) GoMethod(a int) int {
	return a + 2
}

type GoIface interface {
	Run(a int) int
}
WXEOF
cat > "$FX/k_rb.rb" <<'WXEOF'
class RbClass
  private def rb_private_inline(a)
    a + 1
  end

  def self.rb_class_method(a)
    a + 2
  end

  memoize def rb_macro_wrapped(a)
    a + 3
  end

  def rb_plain(a)
    a + 4
  end
end
WXEOF
cat > "$FX/l_objc.m" <<'WXEOF'
#import <Foundation/Foundation.h>

@interface ObjcClass : NSObject
- (int)objcMethod:(int)a;
@end

@implementation ObjcClass
- (int)objcMethod:(int)a
{
    return a + 1;
}

+ (int)objcClassMethod:(int)a
{
    return a + 2;
}
@end

__attribute__((always_inline)) static int objcAttrFn(int a)
{
    return a + 3;
}
WXEOF
cat > "$FX/m_sh.sh" <<'WXEOF'
#!/bin/bash
function sh_keyword_fn {
  echo 1
}

sh_plain_fn() {
  echo 2
}
WXEOF
cat > "$FX/n_cu.cu" <<'WXEOF'
template<typename T>
__global__ void cuTemplateKernel( T* a )
{
    a[0] = 1;
}

__global__ void cuKernel( float* a )
{
    a[0] = 2;
}

__device__ __forceinline__ float cuDeviceFn( float a )
{
    return a + 3;
}
WXEOF
cat > "$FX/o_c.c" <<'WXEOF'
static inline int cStaticInline( int a )
{
    return a + 1;
}

__attribute__((noinline)) int cAttrFn( int a )
{
    return a + 2;
}
WXEOF
cat > "$FX/p_php.php" <<'WXEOF'
<?php
namespace N;

#[Route('/x')]
function phpAttrFn(int $a): int
{
    return $a + 1;
}

final class PhpClass
{
    #[Deprecated]
    public static function phpAttrMethod(int $a): int
    {
        return $a + 2;
    }

    private function phpModifiers(int $a): int
    {
        return $a + 3;
    }
}
WXEOF
cat > "$FX/q_kt.kt" <<'WXEOF'
package p

@Deprecated("x")
fun ktAnnotatedFn(a: Int): Int {
    return a + 1
}

@Serializable
data class KtAnnotatedClass(val a: Int) {
    @JvmStatic
    private fun ktAnnotatedMethod(a: Int): Int {
        return a + 2
    }
}

internal suspend fun ktModifiers(a: Int): Int {
    return a + 3
}
WXEOF
cat > "$FX/r_dart.dart" <<'WXEOF'
@pragma('vm:prefer-inline')
int dartAnnotatedFn(int a) {
  return a + 1;
}

@immutable
class DartAnnotatedClass {
  @override
  int dartAnnotatedMethod(int a) {
    return a + 2;
  }

  static int dartStatic(int a) {
    return a + 3;
  }
}
WXEOF
cat > "$FX/s_lua.lua" <<'WXEOF'
local function lua_local_fn(a)
  return a + 1
end

function lua_global_fn(a)
  return a + 2
end

local lua_assigned_fn = function(a)
  return a + 3
end
WXEOF
cat > "$FX/t_ex.ex" <<'WXEOF'
defmodule ExMod do
  @doc "doc"
  @spec ex_spec_fn(integer) :: integer
  def ex_spec_fn(a) do
    a + 1
  end

  defp ex_private_fn(a) do
    a + 2
  end
end
WXEOF
cat > "$FX/u_gd.gd" <<'WXEOF'
class_name GdClass

@export var gd_export_var: int = 3

@rpc("any_peer")
func gd_annotated_fn(a):
	return a + 1

static func gd_static_fn(a):
	return a + 2
WXEOF
cat > "$FX/v_clj.clj" <<'WXEOF'
(ns p)

(defn ^:private clj-private-fn [a]
  (+ a 1))

(defn clj-plain-fn [a]
  (+ a 2))
WXEOF
cat > "$DIR/manifest.psv" <<'WXEOF'
W|a_ts.ts|tsExportFn|ts export fn|export function tsExportFn(a: number): number {
W|a_ts.ts|tsExportDefaultFn|ts export default fn|export default function tsExportDefaultFn(a: number): number {
W|a_ts.ts|tsExportAsyncFn|ts export async fn|export async function tsExportAsyncFn(a: number): Promise<number> {
W|a_ts.ts|TsExportClass|ts export class|export class TsExportClass {
W|a_ts.ts|TsExportAbstractClass|ts export abstract class|export abstract class TsExportAbstractClass {
W|a_ts.ts|TsExportIface|ts export interface|export interface TsExportIface {
W|a_ts.ts|TsExportAlias|ts export type alias|export type TsExportAlias = { a: number; b: string };
W|a_ts.ts|TsExportEnum|ts export enum|export enum TsExportEnum {
W|a_ts.ts|tsExportArrow|ts export const arrow|export const tsExportArrow = (a: number): number => {
W|a_ts.ts|tsDeclareFn|ts declare fn|declare function tsDeclareFn(a: number): number;
C|a_ts.ts|tsPlainFn|ts plain fn (control)|function tsPlainFn(a: number): number {
W|a_ts.ts|TsDecoratedClass|ts @decorator export class|@Component({ selector: 'x' })
W|a_ts.ts|tsDecoratedMethod|ts @decorator method|@Input()
W|a_ts.ts|tsNsInnerFn|ts export fn in namespace|export function tsNsInnerFn(): number {
W|b_tsx.tsx|TsxExportFn|tsx export fn|export function TsxExportFn(props: { a: number }) {
W|b_tsx.tsx|TsxExportDefaultFn|tsx export default fn|export default function TsxExportDefaultFn() {
W|b_tsx.tsx|TsxExportArrow|tsx export const arrow|export const TsxExportArrow = (props: { a: number }) => {
W|c_js.js|jsExportFn|js export fn|export function jsExportFn(a) {
W|c_js.js|jsExportDefaultFn|js export default fn|export default function jsExportDefaultFn(a) {
W|c_js.js|jsExportAsyncFn|js export async fn|export async function jsExportAsyncFn(a) {
W|c_js.js|JsExportClass|js export class|export class JsExportClass {
W|c_js.js|jsExportArrow|js export const arrow|export const jsExportArrow = (a) => {
C|c_js.js|jsPlainFn|js plain fn (control)|function jsPlainFn(a) {
W|d_py.py|py_single_deco|py single decorator|@functools.cache
W|d_py.py|py_stacked_deco|py stacked decorators|@first_deco
W|d_py.py|PyDecoClass|py decorated class|@dataclass
W|d_py.py|py_deco_method|py decorated method|@property
W|d_py.py|py_static_method|py @staticmethod|@staticmethod
C|d_py.py|py_plain|py plain def (control)|def py_plain(a):
C|d_py.py|py_async_plain|py async def|async def py_async_plain(a):
W|e_cpp.cpp|cppTemplateFn|c++ template fn|template<typename T>
W|e_cpp.cpp|CppTemplateClass|c++ template class|template<typename T>
C|e_cpp.cpp|cppInlineMember|c++ inline member of template class (no own wrapper)|T cppInlineMember( T a )
W|e_cpp.cpp|cppMemberTemplate|c++ member template|template<typename U>
W|e_cpp.cpp|cppOutOfLine|c++ out-of-line template member|template<typename T>
W|e_cpp.cpp|cppNestedTemplate|c++ nested template<> template<>|template<typename T>
W|e_cpp.cpp|CppTemplateStruct|c++ template struct|template<typename T>
W|e_cpp.cpp|CppTemplateAlias|c++ template alias|template<typename T>
C|e_cpp.cpp|cppAttrFn|c++ [[attr]] static inline fn|[[nodiscard]] static inline int cppAttrFn( int a )
W|e_cpp.cpp|cppExternC|c++ extern "C" fn|extern "C" int cppExternC( int a )
C|e_cpp.cpp|cppPlain|c++ plain fn (control)|int cppPlain( int a )
C|f_java.java|javaAnnotated|java @annotation method|@Override
C|f_java.java|javaStacked|java stacked annotations|@Deprecated
C|f_java.java|javaPlain|java plain method (control)|int javaPlain(int a) {
C|f_java.java|JavaAnnotatedIface|java annotated interface|@FunctionalInterface
C|f_java.java|JavaClass|java public class|public class JavaClass {
C|g_rs.rs|rs_pub_fn|rust pub fn|pub fn rs_pub_fn(a: i32) -> i32 {
C|g_rs.rs|rs_pub_crate_fn|rust pub(crate) fn|pub(crate) fn rs_pub_crate_fn(a: i32) -> i32 {
W|g_rs.rs|rs_attr_fn|rust #[attr] fn|#[inline]
W|g_rs.rs|rs_stacked_attr_fn|rust stacked #[attr] pub fn|#[inline]
W|g_rs.rs|RsAttrStruct|rust #[derive] struct|#[derive(Debug, Clone)]
W|g_rs.rs|RsAttrEnum|rust doc + #[derive] enum|#[derive(Debug)]
C|g_rs.rs|rs_async_unsafe_fn|rust pub async unsafe fn|pub async unsafe fn rs_async_unsafe_fn(a: i32) -> i32 {
C|g_rs.rs|rs_plain|rust plain fn (control)|fn rs_plain(a: i32) -> i32 {
C|h_cs.cs|CsAttrClass|c# [attr] class|[Serializable]
C|h_cs.cs|CsAttrMethod|c# [attr] method|[Obsolete("x")]
C|h_cs.cs|CsStackedAttr|c# stacked [attr] method|[Obsolete]
C|h_cs.cs|CsModifiers|c# public async modifiers|public async Task<int> CsModifiers(int a)
C|i_swift.swift|swiftAttrFn|swift @attr fn|@available(iOS 13, *)
C|i_swift.swift|SwiftAttrClass|swift @objc class|@objc
C|i_swift.swift|swiftAttrMethod|swift @attr method|@discardableResult
C|i_swift.swift|swiftModifiers|swift private static|private static func swiftModifiers(a: Int) -> Int {
C|i_swift.swift|swiftPublicFn|swift public fn|public func swiftPublicFn(a: Int) -> Int {
C|j_go.go|GoFn|go func (no wrapper form)|func GoFn(a int) int {
C|j_go.go|GoStruct|go type struct|type GoStruct struct {
C|j_go.go|GoMethod|go method|func (g *GoStruct) GoMethod(a int) int {
C|j_go.go|GoIface|go type interface|type GoIface interface {
W|k_rb.rb|rb_private_inline|ruby private def|private def rb_private_inline(a)
C|k_rb.rb|rb_class_method|ruby def self.|def self.rb_class_method(a)
W|k_rb.rb|rb_macro_wrapped|ruby macro-wrapped def|memoize def rb_macro_wrapped(a)
C|k_rb.rb|rb_plain|ruby plain def (control)|def rb_plain(a)
C|l_objc.m|objcMethod|objc instance method|- (int)objcMethod:(int)a
C|l_objc.m|objcClassMethod|objc class method|+ (int)objcClassMethod:(int)a
C|l_objc.m|objcAttrFn|objc __attribute__ static fn|__attribute__((always_inline)) static int objcAttrFn(int a)
C|m_sh.sh|sh_keyword_fn|bash function keyword|function sh_keyword_fn {
C|m_sh.sh|sh_plain_fn|bash plain fn|sh_plain_fn() {
W|n_cu.cu|cuTemplateKernel|cuda template __global__|template<typename T>
C|n_cu.cu|cuKernel|cuda __global__ kernel|__global__ void cuKernel( float* a )
C|n_cu.cu|cuDeviceFn|cuda __device__ __forceinline__|__device__ __forceinline__ float cuDeviceFn( float a )
C|o_c.c|cStaticInline|c static inline|static inline int cStaticInline( int a )
C|o_c.c|cAttrFn|c __attribute__ fn|__attribute__((noinline)) int cAttrFn( int a )
C|p_php.php|phpAttrFn|php #[Attr] fn|#[Route('/x')]
C|p_php.php|PhpClass|php final class|final class PhpClass
C|p_php.php|phpAttrMethod|php #[Attr] method|#[Deprecated]
C|p_php.php|phpModifiers|php private method|private function phpModifiers(int $a): int
C|q_kt.kt|ktAnnotatedFn|kotlin @Annotation fn|@Deprecated("x")
C|q_kt.kt|KtAnnotatedClass|kotlin @Annotation data class|@Serializable
C|q_kt.kt|ktAnnotatedMethod|kotlin @Annotation method|@JvmStatic
C|q_kt.kt|ktModifiers|kotlin internal suspend|internal suspend fun ktModifiers(a: Int): Int {
W|r_dart.dart|dartAnnotatedFn|dart @annotation fn|@pragma('vm:prefer-inline')
C|r_dart.dart|DartAnnotatedClass|dart @annotation class|@immutable
W|r_dart.dart|dartAnnotatedMethod|dart @override method|@override
C|r_dart.dart|dartStatic|dart static method|static int dartStatic(int a) {
C|s_lua.lua|lua_local_fn|lua local function|local function lua_local_fn(a)
C|s_lua.lua|lua_global_fn|lua function|function lua_global_fn(a)
W|s_lua.lua|lua_assigned_fn|lua local x = function|local lua_assigned_fn = function(a)
C|t_ex.ex|ex_spec_fn|elixir def (@doc/@spec are separate module attributes)|def ex_spec_fn(a) do
C|t_ex.ex|ex_private_fn|elixir defp|defp ex_private_fn(a) do
C|u_gd.gd|gd_export_var|gdscript @export var|@export var gd_export_var: int = 3
W|u_gd.gd|gd_annotated_fn|gdscript @rpc func|@rpc("any_peer")
C|u_gd.gd|gd_static_fn|gdscript static func|static func gd_static_fn(a):
C|v_clj.clj|clj-private-fn|clojure defn ^:private|(defn ^:private clj-private-fn [a]
C|v_clj.clj|clj-plain-fn|clojure defn|(defn clj-plain-fn [a]
WXEOF

# ── (W) (C) (N) (X) (L): one python pass over the manifest, one --expand per row ──────────────────────
python3 - "$BIN" "$FX" "$DIR/manifest.psv" <<'PY' || fail=1
import re, subprocess, sys
bin_, fx, manifest = sys.argv[1:4]
bad = 0
def say(good, msg):
    global bad
    print(("  PASS  " if good else "  FAIL  ") + msg)
    bad += 0 if good else 1
def bodies(sym_file, sym):
    p = subprocess.run([bin_, fx, f"--expand={sym_file}:{sym}", "--top-k=1", "--legend=compact"], capture_output=True, text=True, errors="replace")
    return p.returncode, re.findall(r'<b ([^>]*)><!\[CDATA\[(.*?)\]\]></b>', p.stdout, flags=re.S)
def hit(found, want):   # THE comparison: some served body's first line is the declaration's first line
    return any(text.split("\n", 1)[0].strip() == want.strip() for _, text in found)
counts = {"W": [0, 0], "C": [0, 0]}
mutant_hits = 0
lines_of = {}
for row in open(manifest, encoding="utf-8"):
    arm, f, sym, form, want = row.rstrip("\n").split("|", 4)
    rc, found = bodies(f, sym)
    src = open(f"{fx}/{f}", encoding="utf-8").read()
    good = rc == 0 and hit(found, want)
    whole = good and all(text in src for _, text in found)   # byte-exact contiguous slices of the file
    counts[arm][0] += 1
    counts[arm][1] += 1 if ( good and whole ) else 0
    if not ( good and whole ):
        first = found[0][1].split("\n", 1)[0] if found else "(no body)"
        say(False, f"({arm}) {f}:{sym} [{form}] first line is `{first}`, the declaration starts `{want}`" + ("" if good else "") + ("" if whole or not good else " (body is not a slice of the file)"))
    mutant_hits += 1 if hit(found, want[1:]) else 0          # (N): one byte dropped from the expectation
    for attrs, _ in found:
        m = re.search(r'\bl="(\d+)"', attrs)
        lines_of.setdefault(sym, set()).add(int(m.group(1)) if m else -1)
for arm, label in (("W", "wrapper rows start at the wrapper (NEW arms: red on the unfixed binary)"), ("C", "control rows keep their first line (pinned both ways)")):
    n, g = counts[arm]
    say(n > 0 and g == n, f"({arm}) {g} of {n} {label}")
total = counts["W"][0] + counts["C"][0]
say(mutant_hits == 0 and total > 0, f"(N) mutation control: the comparison misses on {total - mutant_hits} of {total} one-byte-dropped expectations")
# (X) no over-reach
_, found = bodies("d_py.py", "py_static_method")
say(len(found) == 1 and found[0][1].rstrip() == "@staticmethod\n    def py_static_method(a):\n        return a + 3", "(X) the last method of a Python class is its decorator and its own three lines, not its class")
_, found = bodies("g_rs.rs", "RsAttrEnum")
say(len(found) == 1 and "/// doc comment" not in found[0][1] and found[0][1].startswith("#[derive(Debug)]\npub enum RsAttrEnum {"), "(X) a Rust doc comment above the attribute run is not swept into the body")
_, found = bodies("g_rs.rs", "rs_plain")
say(len(found) == 1 and found[0][1].startswith("fn rs_plain("), "(X) a plain Rust fn after attributed ones keeps its own first line")
_, found = bodies("e_cpp.cpp", "cppInlineMember")
say(len(found) == 1 and found[0][1].startswith("T cppInlineMember("), "(X) a plain member of a template class does not take the class's template<>")
# (L) the symbol did not move
for sym, want_line in (("py_stacked_deco", 11), ("rs_stacked_attr_fn", 16), ("cppTemplateFn", 2), ("tsDecoratedMethod", 52)):
    say(lines_of.get(sym) == {want_line}, f"(L) {sym} l={sorted(lines_of.get(sym, []))} is its name's line {want_line}")
sys.exit(1 if bad else 0)
PY

# ── (F) the --for fold and --pack-task serve the same first line ──────────────────────────────────────
first_line(){ python3 -c '
import re, sys
m = re.search(r"<b [^>]*\bn=\"" + re.escape(sys.argv[1]) + r"\"[^>]*><!\[CDATA\[([^\n]*)", sys.stdin.read())
print(m.group(1).split("]]>")[0] if m else "(no body)")' "$1"; }
got="$( "$BIN" "$FX" --for="py_stacked_deco" --legend=compact 2>/dev/null | first_line py_stacked_deco )"
[ "$got" = "@first_deco" ] \
    && ok "(F) --for serves py_stacked_deco from @first_deco" \
    || no "(F) --for body of py_stacked_deco starts \`$got\`, want \`@first_deco\`"
got="$( "$BIN" "$FX" --for="how does rs_stacked_attr_fn add four" --legend=compact 2>/dev/null | first_line rs_stacked_attr_fn )"
[ "$got" = "#[inline]" ] \
    && ok "(F) --for serves rs_stacked_attr_fn from #[inline]" \
    || no "(F) --for body of rs_stacked_attr_fn starts \`$got\`, want \`#[inline]\`"
got="$( "$BIN" "$FX" --pack-task="change py_stacked_deco to add three" 2>/dev/null | first_line py_stacked_deco )"
[ "$got" = "@first_deco" ] \
    && ok "(F) --pack-task serves py_stacked_deco from @first_deco" \
    || no "(F) --pack-task body of py_stacked_deco starts \`$got\`, want \`@first_deco\`"

# ── (E) the edit verbs splice the span --expand prints ────────────────────────────────────────────────
ED="$DIR/ed"; mkdir -p "$ED"
for pair in d_py.py:py_stacked_deco a_ts.ts:tsExportAsyncFn e_cpp.cpp:cppTemplateFn g_rs.rs:rs_stacked_attr_fn f_java.java:javaStacked; do
    f="${pair%%:*}"; sym="${pair##*:}"
    rm -rf "$ED/fx"; mkdir -p "$ED/fx"; cp "$FX/$f" "$ED/fx/$f"
    "$BIN" "$ED/fx" --expand="$f:$sym" --top-k=1 --legend=compact 2>/dev/null | python3 -c '
import re, sys
m = re.search(r"<b [^>]*><!\[CDATA\[(.*?)\]\]></b>", sys.stdin.read(), flags=re.S)
sys.stdout.write(m.group(1) if m else "")' > "$ED/payload"
    if [ ! -s "$ED/payload" ]; then no "(E) $f:$sym served no body to replace with"; continue; fi
    "$BIN" "$ED/fx" --replace-symbol-body="$sym" --edit-payload="$ED/payload" >"$ED/out" 2>"$ED/err"; rc=$?
    if [ "$rc" = 0 ] && cmp -s "$FX/$f" "$ED/fx/$f"; then ok "(E) $f:$sym replaced with its own served body is byte-identical"
    else no "(E) $f:$sym replaced with its own served body changed the file (rc=$rc): $( diff "$FX/$f" "$ED/fx/$f" | head -4 | tr '\n' ' ' ) $( head -c 200 "$ED/err" )"; fi
done
rm -rf "$ED/fx"; mkdir -p "$ED/fx"; cp "$FX/d_py.py" "$ED/fx/d_py.py"
printf 'WX_MARK = 1\n' > "$ED/payload"
"$BIN" "$ED/fx" --insert-before-symbol=py_stacked_deco --edit-payload="$ED/payload" >"$ED/out" 2>"$ED/err"; rc=$?
mark="$( grep -n '^WX_MARK = 1$' "$ED/fx/d_py.py" | head -1 | cut -d: -f1 )"; deco="$( grep -n '^@first_deco$' "$ED/fx/d_py.py" | head -1 | cut -d: -f1 )"; def="$( grep -n '^def py_stacked_deco' "$ED/fx/d_py.py" | head -1 | cut -d: -f1 )"
if [ "$rc" = 0 ] && [ -n "$mark" ] && [ -n "$deco" ] && [ -n "$def" ] && [ "$mark" -lt "$deco" ] && [ "$deco" -lt "$def" ]; then ok "(E) --insert-before-symbol lands above the decorators (line $mark < @first_deco $deco < def $def)"
else no "(E) --insert-before-symbol on a decorated def: payload at line ${mark:-none}, @first_deco at ${deco:-none}, def at ${def:-none} (rc=$rc) — NEW arm, red on the unfixed binary"; fi

# ── (D) deterministic and well formed ─────────────────────────────────────────────────────────────────
"$BIN" "$FX" --expand=d_py.py:py_stacked_deco --top-k=1 > "$DIR/d1.xml" 2>/dev/null; "$BIN" "$FX" --expand=d_py.py:py_stacked_deco --top-k=1 > "$DIR/d2.xml" 2>/dev/null
[ -s "$DIR/d1.xml" ] && cmp -s "$DIR/d1.xml" "$DIR/d2.xml" \
    && ok "(D) two runs byte-identical" \
    || no "(D) two runs differ, or the answer is empty"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$DIR/d1.xml" 2>/dev/null \
        && ok "(D) well formed (xmllint)" \
        || no "(D) xmllint rejects the --expand answer"
else
    echo "  SKIP  (D) xmllint not installed"
fi

[ "$fail" = 0 ] && echo "wrapperprefixcheck: PASS" || echo "wrapperprefixcheck: FAIL"
exit "$fail"
