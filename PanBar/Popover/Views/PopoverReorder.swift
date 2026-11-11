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
