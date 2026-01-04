import Foundation

/// namespace for `Config`
public enum Config {}

public protocol ConfigItem<Value> {
    static var key: String { get }
    associatedtype Value: Codable
    var value: Value { get nonmutating set }
}
