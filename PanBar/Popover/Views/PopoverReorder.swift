import AppKit
import SwiftUI

struct PopoverReorder: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: PopoverDragItem
    let title: String
    let onDrop: (PopoverDragItem, Bool) -> Bool
    @State private var height: CGFloat = 1
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { height = proxy.size.height }
                        .onChange(of: proxy.size.height) { height = $0 }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(targeted ? Color.accentColor : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .draggable(item.value) {
                Label(title, systemImage: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { values, location in
                targeted = false
                guard values.count == 1, let value = values.first,
                      let source = PopoverDragItem(value: value), source.kind == item.kind else { return false }
                return withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    onDrop(source, location.y >= height / 2)
                }
            } isTargeted: { targeted = $0 }
            .help(L("action.dragToReorder"))
    }
}

struct PopoverDropLocation: Equatable {
    let groupID: UUID?
    let beforeID: String?
}

enum PopoverDropTarget: Hashable {
    case row(String, group: UUID?)
    case group(UUID?)
    case empty(UUID?)
    case placeholder
}

@MainActor
final class PopoverItemDrag: ObservableObject {
    struct Active {
        let item: PopoverDragItem
        let id: String
        let groupID: UUID?
        let size: CGSize
        let grabOffset: CGPoint
    }

    let coordinateSpace = UUID()
    @Published private(set) var active: Active?
    @Published private(set) var destination: PopoverDropLocation?
    @Published private(set) var pointer = CGPoint.zero
    @Published private(set) var highlightedID: String?
    var reduceMotion = false
    private(set) var listID: UUID?
    private(set) var viewport = CGRect.zero
    private var rows: [(id: String, groupID: UUID?)] = []
    private var groups: [UUID?] = []
    private(set) var frames: [PopoverDropTarget: CGRect] = [:]
    private var needsScrollUpdate = false
    private weak var scrollView: NSScrollView?
    private var scrollTimer: Timer?
    private var escapeMonitor: Any?
    private var highlightTask: Task<Void, Never>?

    var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }

    func attachList(_ id: UUID) {
        guard listID != id else { return }
        clearDrag()
        frames = [:]
        scrollView = nil
        listID = id
    }

    func detachList(_ id: UUID) {
        guard listID == id else { return }
        cancel()
        listID = nil
    }

    func configure(rows: [(id: String, groupID: UUID?)], groups: [UUID?]) {
        self.rows = rows
        self.groups = groups
        if let active {
            guard rows.contains(where: { $0.id == active.id && $0.groupID == active.groupID }),
                  destination.map({ target in
                      groups.contains(target.groupID)
                          && (target.beforeID == nil || rows.contains { $0.id == target.beforeID && $0.groupID == target.groupID })
                  }) ?? true else {
                cancel()
                return
            }
        }
    }

    func setViewport(_ size: CGSize) {
        viewport = CGRect(origin: .zero, size: size)
    }

    func setFrames(_ frames: [PopoverDropTarget: CGRect]) {
        self.frames = frames
        // 让位会改变命中区域，不能因此重新解释静止的鼠标落点。
        if active != nil, needsScrollUpdate {
            needsScrollUpdate = false
            updateDestination()
        }
    }

    func setScrollView(_ view: NSScrollView) { scrollView = view }

    func begin(at point: CGPoint, kind: PopoverDragItem.Kind) {
        guard active == nil, kind != .holdingGroup && kind != .watchGroup, viewport.contains(point),
              let (target, frame) = hit(at: point), case .row(let id, let groupID) = target,
              rows.contains(where: { $0.id == id && $0.groupID == groupID }) else { return }
        let item = PopoverDragItem(kind: kind, id: id)
        highlightTask?.cancel()
        highlightedID = nil
        pointer = point
        active = Active(item: item, id: id, groupID: groupID, size: frame.size,
                        grabOffset: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
        destination = PopoverDropLocation(groupID: groupID, beforeID: id)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            DispatchQueue.main.async { self?.cancel() }
            return nil
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollAtEdge() }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func update(_ point: CGPoint) {
        guard active != nil else { return }
        guard viewport.contains(point) else { cancel(); return }
        guard point != pointer else { return }
        pointer = point
        updateDestination()
    }

    func finish(at point: CGPoint, commit: (PopoverDragItem, PopoverDropLocation) -> Bool) {
        update(point)
        let source = active
        let target = destination
        // 松手时实物行直接接替占位，否则下一次按下可能命中高度仍为零的行。
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            clearDrag()
            if let source, let target, commit(source.item, target) {
                highlightedID = source.id
                highlightTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard !Task.isCancelled, let self else { return }
                    withAnimation(self.animation) { self.highlightedID = nil }
                }
            }
        }
    }

    func cancel() {
        withAnimation(animation) { clearDrag() }
    }

    private func clearDrag() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        escapeMonitor = nil
        needsScrollUpdate = false
        active = nil
        destination = nil
    }

    func showsPlaceholder(in groupID: UUID?, before id: String?) -> Bool {
        active != nil && destination == PopoverDropLocation(groupID: groupID, beforeID: id)
    }

    func targetsGroup(_ groupID: UUID?) -> Bool {
        active != nil && destination?.groupID == groupID && destination != nil
    }

    private func hit(at point: CGPoint) -> (PopoverDropTarget, CGRect)? {
        var divider: (PopoverDropTarget, CGRect)?
        var region: (PopoverDropTarget, CGRect)?
        for (target, frame) in frames where frame.height > 0 && target != .placeholder {
            if frame.contains(point) {
                if case .row = target { return (target, frame) }
                region = (target, frame)
            } else if case .row = target, point.y >= frame.maxY, frame.offsetBy(dx: 0, dy: 1).contains(point) {
                // 组末单独绘制的分隔线也算上一行；真正的组头优先。
                divider = (target, frame)
            }
        }
        return region ?? divider
    }

    private func updateDestination() {
        guard let active else { return }
        if let placeholder = frames[.placeholder], placeholder.contains(pointer), destination != nil { return }

        let next = hit(at: pointer).flatMap { target, frame -> PopoverDropLocation? in
            switch target {
            case .row(let id, let group):
                if id == active.id || pointer.y < frame.midY {
                    return PopoverDropLocation(groupID: group, beforeID: id)
                }
                let nextRow = rows.drop { $0.id != id }.dropFirst().first { $0.groupID == group && $0.id != active.id }
                return PopoverDropLocation(groupID: group, beforeID: nextRow?.id)
            case .group(let group):
                // 展开组的标题下沿和首行上半部都是组首插入区；标题其余位置仍可追加。
                if let first = rows.first(where: { $0.groupID == group && $0.id != active.id }),
                   let firstFrame = frames[.row(first.id, group: group)], firstFrame.height > 0,
                   pointer.y >= firstFrame.minY - 4, pointer.y < firstFrame.minY {
                    return PopoverDropLocation(groupID: group, beforeID: first.id)
                }
                return PopoverDropLocation(groupID: group, beforeID: nil)
            case .empty(let group):
                return PopoverDropLocation(groupID: group, beforeID: nil)
            case .placeholder:
                return destination
            }
        }
        if next != destination {
            withAnimation(animation) { destination = next }
        }
    }

    static func scrollStep(at point: CGPoint, in viewport: CGRect) -> CGFloat {
        guard viewport.contains(point) else { return 0 }
        let edge: CGFloat = min(28, viewport.height / 3)
        guard edge > 0 else { return 0 }
        if point.y < viewport.minY + edge { return -12 * (1 - (point.y - viewport.minY) / edge) }
        if point.y > viewport.maxY - edge { return 12 * (1 - (viewport.maxY - point.y) / edge) }
        return 0
    }

    private func scrollAtEdge() {
        guard active != nil, let scrollView, let document = scrollView.documentView else { return }
        let step = Self.scrollStep(at: pointer, in: viewport)
        guard step != 0 else { return }
        let clip = scrollView.contentView
        var bounds = clip.bounds
        bounds.origin.y += document.isFlipped ? step : -step
        let origin = clip.constrainBoundsRect(bounds).origin
        guard origin != clip.bounds.origin else { return }
        needsScrollUpdate = true
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    deinit {
        scrollTimer?.invalidate()
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        highlightTask?.cancel()
    }
}

private struct PopoverDropFrames: PreferenceKey {
    static var defaultValue: [PopoverDropTarget: CGRect] = [:]
    static func reduce(value: inout [PopoverDropTarget: CGRect], nextValue: () -> [PopoverDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct PopoverDropRegion: ViewModifier {
    @EnvironmentObject private var drag: PopoverItemDrag
    let target: PopoverDropTarget

    func body(content: Content) -> some View {
        content
            .opacity(hidesEmptyContent ? 0 : 1)
            .background {
                if case .group(let groupID) = target, drag.targetsGroup(groupID) {
                    Color.accentColor.opacity(0.08)
                }
            }
            .overlay {
                if case .empty(let groupID) = target {
                    PopoverDropPlaceholder(groupID: groupID, beforeID: nil)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PopoverDropFrames.self,
                                           value: [target: proxy.frame(in: .named(drag.coordinateSpace))])
                }
            }
    }

    private var hidesEmptyContent: Bool {
        if case .empty(let groupID) = target {
            return drag.showsPlaceholder(in: groupID, before: nil)
        }
        return false
    }
}

struct PopoverDropPlaceholder: View {
    @EnvironmentObject private var drag: PopoverItemDrag
    let groupID: UUID?
    let beforeID: String?

    var body: some View {
        if drag.showsPlaceholder(in: groupID, before: beforeID), let active = drag.active {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.07))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                .padding(.horizontal, 8)
                .frame(height: active.size.height)
                .modifier(PopoverDropRegion(target: .placeholder))
                .allowsHitTesting(false)
        }
    }
}

struct PopoverItemReorder: ViewModifier {
    @EnvironmentObject private var drag: PopoverItemDrag
    let id: String
    let groupID: UUID?

    func body(content: Content) -> some View {
        let isSource = drag.active?.id == id
        content
            .contentShape(Rectangle())
            .background(drag.highlightedID == id ? Color.accentColor.opacity(0.12) : .clear)
            .opacity(isSource ? 0 : 1)
            .frame(height: isSource ? 0 : nil)
            .clipped()
            .disabled(drag.active != nil)
            .modifier(PopoverDropRegion(target: .row(id, group: groupID)))
            .help(L("action.dragToReorder"))
    }
}

struct PopoverReorderList<Item: Identifiable & Equatable, Content: View, Preview: View>: View where Item.ID: CustomStringConvertible {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var drag: PopoverItemDrag
    let kind: PopoverDragItem.Kind
    let items: [Item]
    let groupID: KeyPath<Item, UUID?>?
    let groups: [UUID?]
    let onDrop: (PopoverDragItem, PopoverDropLocation) -> Bool
    @ViewBuilder let content: (PopoverItemDrag) -> Content
    @ViewBuilder let preview: (Item) -> Preview
    private struct Order: Equatable {
        let items: [Item]
        let groups: [UUID?]
    }

    @State private var started = false
    @State private var listID = UUID()
    @State private var frames: [PopoverDropTarget: CGRect] = [:]
    @GestureState private var gestureActive = false

    var body: some View {
        let order = Order(items: items, groups: groups)
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    content(drag)
                        .background(PopoverScrollProbe { view in
                            if drag.listID == listID { drag.setScrollView(view) }
                        })
                }
                if let active = drag.active, let item = items.first(where: { $0.id.description == active.id }) {
                    preview(item)
                        .frame(width: active.size.width, height: active.size.height)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                        .position(x: drag.pointer.x - active.grabOffset.x + active.size.width / 2,
                                  y: drag.pointer.y - active.grabOffset.y + active.size.height / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .coordinateSpace(name: drag.coordinateSpace)
            .environmentObject(drag)
            .clipped()
            .contentShape(Rectangle())
            // 手势留在滚动容器上，源行让位或滚出可见区域后仍能继续拖动。
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(drag.coordinateSpace))
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        guard drag.listID == listID else { return }
                        if !started {
                            drag.begin(at: value.startLocation, kind: kind)
                            started = drag.active != nil
                        }
                        drag.update(value.location)
                    }
                    .onEnded { value in
                        guard drag.listID == listID else { return }
                        started = false
                        if drag.active != nil { drag.finish(at: value.location, commit: onDrop) }
                    }
            )
            // 切 tab 的退场视图仍会回报布局，只有当前列表能更新共享拖拽状态。
            .onPreferenceChange(PopoverDropFrames.self) { frames in
                self.frames = frames
                if drag.listID == listID { drag.setFrames(frames) }
            }
            .onAppear {
                drag.attachList(listID)
                configure(order)
                drag.reduceMotion = reduceMotion
                drag.setViewport(proxy.size)
                drag.setFrames(frames)
            }
            .onChange(of: proxy.size) { if drag.listID == listID { drag.setViewport($0) } }
            .onChange(of: order, perform: configure)
            .onChange(of: reduceMotion) { if drag.listID == listID { drag.reduceMotion = $0 } }
            .onChange(of: gestureActive) { active in
                guard drag.listID == listID else { return }
                if !active && started { started = false; drag.cancel() }
            }
            .onDisappear { drag.detachList(listID) }
        }
    }

    private func configure(_ order: Order) {
        guard drag.listID == listID else { return }
        drag.configure(rows: order.items.map { item in
            (id: item.id.description, groupID: groupID.flatMap { item[keyPath: $0] })
        }, groups: order.groups)
    }
}

private struct PopoverScrollProbe: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.onResolve = onResolve
        view.resolve()
    }

    final class Probe: NSView {
        var onResolve: ((NSScrollView) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.resolve() }
        }
        func resolve() {
            if let scroll = enclosingScrollView { onResolve?(scroll) }
        }
    }
}
