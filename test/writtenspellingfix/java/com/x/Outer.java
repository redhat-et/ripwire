package com.x;
class Outer {
  static class Inner { void m() { H.javaInnerHelper(); } }
}
class Loose { void m() { H.javaLooseHelper(); } }
