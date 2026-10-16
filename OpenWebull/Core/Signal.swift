import Foundation

/// A main-actor broadcast channel. Observers are held weakly through their owner,
/// so a view controller's subscriptions disappear with it.
@MainActor
final class Signal<Value> {
    private struct Observer {
        weak var owner: AnyObject?
        let handler: (Value) -> Void
    }

    private var observers: [Observer] = []

    func observe(_ owner: AnyObject, handler: @escaping (Value) -> Void) {
        observers.append(Observer(owner: owner, handler: handler))
    }

    func send(_ value: Value) {
        observers.removeAll { $0.owner == nil }
        for observer in observers {
            observer.handler(value)
        }
    }
}

extension Signal where Value == Void {
    func send() {
        send(())
    }
}
