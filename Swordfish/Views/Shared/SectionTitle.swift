import SwiftUI

struct SectionTitle: View {
    // `badge` stays String — call sites feed it dynamic values (counts, states).
    let title: LocalizedStringKey
    var badge: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .sectionTitleStyle()
            if let badge {
                Text(badge)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(Theme.Surface.surface1)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

/// A `SectionTitle` that collapses / expands its content when clicked. The
/// open/closed state is remembered per section across launches.
struct CollapsibleSection<Content: View>: View {
    let title: LocalizedStringKey
    var badge: String?
    @AppStorage private var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    init(title: LocalizedStringKey, badge: String? = nil, id: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.badge = badge
        self._isExpanded = AppStorage(wrappedValue: true, "section.expanded.\(id)")
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(Motion.default) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(hovering ? Theme.TextColor.secondary : Theme.TextColor.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    SectionTitle(title: title, badge: badge)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
    }
}
