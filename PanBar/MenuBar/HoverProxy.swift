import AppKit

/// NSTrackingArea 的 owner 必须响应 mouseEntered(with:) / mouseExited(with:),
/// 而 StatusItemController 不是 NSObject 子类。这个小 helper 充当 owner,
/// 把事件转成闭包回调。
final class HoverProxy: NSObject {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    @objc func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    @objc func mouseExited(with event: NSEvent) {
        onExit?()
    }
}
