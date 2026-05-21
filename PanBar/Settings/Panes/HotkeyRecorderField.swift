import SwiftUI
import AppKit

/// SwiftUI 包裹的快捷键录入控件。点击进入"按下任意键"状态,捕获带修饰键的下一次按键。
struct HotkeyRecorderField: View {
    @Binding var binding: HotkeyBinding?
    var onChange: ((HotkeyBinding?) -> Void)? = nil

    var body: some View {
        HotkeyRecorderRepresentable(binding: $binding, onChange: onChange)
            .frame(minWidth: 130, maxWidth: 180, minHeight: 24, maxHeight: 24)
    }
}

private struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var binding: HotkeyBinding?
    var onChange: ((HotkeyBinding?) -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.binding = binding
        view.onCommit = { newBinding in
            DispatchQueue.main.async {
                self.binding = newBinding
                self.onChange?(newBinding)
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        if nsView.binding != binding {
            nsView.binding = binding
            nsView.needsDisplay = true
        }
    }
}

final class HotkeyRecorderNSView: NSView {
    var binding: HotkeyBinding?
    var onCommit: ((HotkeyBinding?) -> Void)?
    private var recording: Bool = false {
        didSet { needsDisplay = true; updateFocus() }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        recording.toggle()
        if recording {
            window?.makeFirstResponder(self)
        } else {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        // Escape:取消录入
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            return
        }
        // Delete:清空当前 binding
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            binding = nil
            onCommit?(nil)
            recording = false
            return
        }
        // 必须带修饰键
        guard let newBinding = HotkeyBinding.from(event: event) else { return }
        binding = newBinding
        onCommit?(newBinding)
        recording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 背景
        let bg = recording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()

        // 文字
        let text: String
        if recording {
            text = L("hotkey.recording", comment: "")
        } else if let b = binding, b.isValid {
            text = b.displayString
        } else {
            text = L("hotkey.unbound", comment: "")
        }
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: recording ? .regular : .semibold),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let str = NSAttributedString(string: text, attributes: attr)
        let size = str.size()
        str.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    private func updateFocus() {
        layer?.borderColor = recording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = recording ? 1.5 : 0.5
    }
}
