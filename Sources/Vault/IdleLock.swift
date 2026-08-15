import SwiftUI
import AppKit

/// 閒置自動上鎖。
///
/// 跟 Babos 的螢幕保護剛好相反：那邊「app 不在前面就不計時」，因為在背景跳出
/// 螢幕保護只會嚇到人。這裡不在前面**更要**計時——離開電腦去做別的事，
/// 正是最需要鎖上的時候。所以只有 app 內的實際操作會歸零。
@MainActor
@Observable
final class IdleLock {
    /// 秒。0 表示關閉。
    var limit = 30

    @ObservationIgnored private var seconds = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onFire: (() -> Void)?

    func start(_ fire: @escaping () -> Void) {
        onFire = fire

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown]
        ) { [weak self] e in
            MainActor.assumeIsolated { self?.reset() }
            return e
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.limit > 0 else { return }
                self.seconds += 1
                if self.seconds >= self.limit {
                    self.seconds = 0
                    self.onFire?()
                }
            }
        }
    }

    func reset() { seconds = 0 }

    /// 已鎖定時不需要計時，解鎖時重新開始。
    func suspend() { seconds = 0 }
}
