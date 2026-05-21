import Foundation
import os

enum Log {
    static let subsystem = "app.panbar.PanBar"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let net = Logger(subsystem: subsystem, category: "net")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let quote = Logger(subsystem: subsystem, category: "quote")
    static let fx = Logger(subsystem: subsystem, category: "fx")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
