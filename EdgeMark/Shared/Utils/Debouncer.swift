import Foundation

final class Debouncer {
    private var timer: Timer?
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func call(action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
