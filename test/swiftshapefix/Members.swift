import Foundation

struct Depot {
    var stock_count: Int = 0
    var doubled_stock: Int { stock_count * 2 }
    var stock_gauge: Int {
        get { stock_count }
        set { stock_count = newValue }
    }
    var audited_stock: Int = 0 {
        willSet { }
        didSet { }
    }
    static func == (lhs: Depot, rhs: Depot) -> Bool { lhs.stock_count == rhs.stock_count }
    subscript(idx: Int) -> Int { idx }
    init(seed: Int) { stock_count = seed }
}

extension Depot {
    func ext_audit() -> Int { 1 }
    var ext_ratio: Int { 2 }
    static func ext_make() -> Depot { Depot(seed: 1) }
}

actor RelayHub {
    var relay_count = 0
    func pump_relay() async { relay_count += 1 }
}

final class Manifest {
    static var `default`: Manifest { Manifest() }
    lazy var lazy_manifest: String = { "m" }()
    func close_books() { }
    deinit { }
    class Ledger {
        let ledger_rows = 0
    }
}

func localHost() -> Int {
    let local_shadow = 5
    func inner_probe() -> Int { local_shadow }
    return inner_probe()
}
