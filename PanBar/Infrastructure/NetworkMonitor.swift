import Foundation
import Network
import Combine

/// 监听网络状态变化,通过 onChange 通知 QuoteRefresher 暂停 / 恢复。
@MainActor
final class NetworkMonitor {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private(set) var isOffline: Bool = false
    var onChange: ((Bool) -> Void)?

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "app.panbar.network-monitor")
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                guard let self = self else { return }
                if self.isOffline != offline {
                    self.isOffline = offline
                    self.onChange?(offline)
                    Log.app.info("network status changed offline=\(offline, privacy: .public)")
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
