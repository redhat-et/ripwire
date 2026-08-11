import Foundation

// A protocol's contract is HALF property requirements — swift-nio's Channel alone declares 30+
// (`var allocator`, `var closeFuture`, `var pipeline`, ...). Before this round none of them
// extracted; the methods did.
protocol TransportLane {
    var lane_id: String { get }
    static var default_capacity: Int { get }
    func open_lane() -> Bool
    associatedtype Freight
    init(tag: String)
    subscript(idx: Int) -> Int { get }
}

// protocol-extension default implementations — extracted before this round, pinned in §5.
extension TransportLane {
    func open_lane() -> Bool { true }
    var lane_banner: String { "lane" }
}
