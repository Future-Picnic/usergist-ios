import Foundation

/// Convenience wrapper for serial/concurrent DispatchQueue creation with
/// consistent labeling.
enum UserGistQueue {
    static let labelPrefix = "studio.usergist.feedback"

    static func serial(_ name: String, qos: DispatchQoS = .utility) -> DispatchQueue {
        DispatchQueue(label: "\(labelPrefix).\(name)", qos: qos)
    }
}
