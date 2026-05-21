import Foundation
import ServiceManagement

/// 包装 SMAppService 实现 macOS 13+ 的开机启动。
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled {
            if SMAppService.mainApp.status == .enabled { return }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notFound { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
