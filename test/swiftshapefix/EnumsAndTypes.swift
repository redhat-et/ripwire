import Foundation

// Enum cases in every spelling a real repo uses: raw value, bare, comma list, indirect,
// associated values with labels. Alamofire's AFError alone carries 200+ of these.
enum PaintColor: String {
    case crimson = "CRIMSON"
    case teal
    case ochre, umber
    indirect case blend(PaintColor, PaintColor)
    case sized(width: Double, count: Int)
    var css_hex: String { rawValue }
}

enum Cargo {
    case pallet(weight: Double)
    case empty_slot
}

// switch decoy — a `case` ARM is not an enum case; its pattern bindings are locals and must
// never mint symbols.
func routeCargo(_ c: Cargo) -> Int {
    switch c {
    case .pallet(let grabbed_val): return Int(grabbed_val)
    case .empty_slot: return 0
    }
}

typealias FrameHandler = (Int) -> Void
typealias PairOf<T> = (T, T)

// custom operator: the DECLARATION line is a pinned non-goal (mints no def); the operator
// FUNCTION is callable surface and must extract.
infix operator <+>: AdditionPrecedence
func <+> (a: Int, b: Int) -> Int { a + b }

let GLOBAL_SPOOL = 9
let (tuple_left, tuple_right) = (1, 2)

#if os(Linux)
func linux_only_probe() -> Int { 1 }
let LINUX_SPOOL = 2
#else
func not_linux_probe() -> Int { 3 }
#endif

#if DEBUG
enum DebugKnob {
    case verbose_knob
}
#endif
