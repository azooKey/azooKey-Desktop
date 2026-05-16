import Combine
import Core
import Foundation
import SwiftUI

/// Wrapper of `State` for SwiftUI. By using this wrapper, you can update config and immediately
/// get the view update. The wrapper also subscribes to `UserDefaults.didChangeNotification`,
/// so a config update made from another window — or via a direct `wrappedValue.value` mutation —
/// re-renders any view that holds a `ConfigState` for that item.
@propertyWrapper
struct ConfigState<Item: ConfigItem>: DynamicProperty {
    @StateObject private var store: ConfigStateStore<Item>

    private let item: Item

    init(wrappedValue: Item) {
        self.item = wrappedValue
        self._store = StateObject(wrappedValue: ConfigStateStore(item: wrappedValue))
    }

    var wrappedValue: Item {
        self.item
    }

    var projectedValue: Binding<Item.Value> {
        Binding(
            get: { self.store.value },
            set: { self.store.set($0) }
        )
    }
}

/// Backing store for `ConfigState`. Observes `UserDefaults.didChangeNotification` so
/// out-of-band writes (other windows, direct `Item.value` mutation) still notify SwiftUI.
///
/// `@MainActor`-isolated because it owns SwiftUI-facing `@Published` state. Observer
/// callbacks are scheduled on `.main` already; we still hop through a `Task { @MainActor }`
/// for type-level isolation since `MainActor.assumeIsolated` requires macOS 14+.
@MainActor
private final class ConfigStateStore<Item: ConfigItem>: ObservableObject {
    @Published private(set) var value: Item.Value

    private let item: Item
    private var observer: NSObjectProtocol?

    init(item: Item) {
        self.item = item
        self.value = item.value

        // `didChangeNotification` does not carry the changed key, so we reload regardless
        // and rely on SwiftUI / @Published to coalesce updates per run loop tick.
        self.observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func set(_ newValue: Item.Value) {
        self.value = newValue
        self.item.value = newValue
    }

    private func reload() {
        self.value = self.item.value
    }
}
