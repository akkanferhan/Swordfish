import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject var clipboard: ClipboardService

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: "Clipboard History", badge: "\(clipboard.items.count) items")
            Picker("", selection: $clipboard.filter) {
                ForEach(ClipboardService.Filter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if clipboard.filtered.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(clipboard.filtered.enumerated()), id: \.element.id) { idx, item in
                        ClipboardRow(index: idx, item: item)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(Theme.TextColor.quaternary)
            Text("Nothing copied yet")
                .font(Typography.body)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

private struct ClipboardRow: View {
    let index: Int
    let item: ClipboardItem
    @EnvironmentObject var clipboard: ClipboardService
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(String(format: "%02d", index + 1))
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.content)
                    .font(Typography.code)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Spacing.sm) {
                    Badge(label: label(for: item.kind), tint: tint(for: item.kind))
                    Text(relativeTime(item.capturedAt))
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                    Text("\(item.content.count) chars")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            Spacer(minLength: 0)

            if hovering || item.pinned {
                HStack(spacing: 4) {
                    Button { clipboard.togglePin(item) } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(item.pinned ? Color.accentColor : Theme.TextColor.tertiary)
                    }
                    .buttonStyle(.plain)
                    Button { clipboard.remove(item) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { clipboard.copyToPasteboard(item) }
    }

    private func label(for kind: ClipboardItem.Kind) -> String {
        switch kind {
        case .text: return "text"
        case .link: return "link"
        case .code: return "code"
        }
    }

    private func tint(for kind: ClipboardItem.Kind) -> Color {
        switch kind {
        case .text: return Theme.TextColor.tertiary
        case .link: return Color.accentColor
        case .code: return Theme.Semantic.ok
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
