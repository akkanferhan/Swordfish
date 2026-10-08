import SwiftUI
import AppKit

/// Lists DerivedData projects, DeviceSupport versions, archives and caches
/// with their sizes, and deletes the ones the user ticks. Deleting is a
/// two-step confirm inline — an NSAlert would steal focus from the popover.
struct DiskCleanupView: View {
    @StateObject private var service = DevCleanupService()
    @State private var selection: Set<String> = []
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if service.items.isEmpty {
                Text(service.isScanning ? "Scanning developer folders…" : "Nothing to clean up")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(CleanupItem.Group.allCases) { group in
                            let rows = service.items.filter { $0.group == group }
                            if !rows.isEmpty { groupSection(group, rows: rows) }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            if let msg = service.lastMessage {
                ToolboxStatusLine(status: .ok(msg, nil))
            }
            if let err = service.lastError {
                ToolboxStatusLine(status: .error(err))
            }
            footer
        }
        .task { service.scan() }
        .onChange(of: service.items) { items in
            selection = selection.intersection(Set(items.map(\.id)))
            confirming = false
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(service.isScanning
                 ? String(localized: "Scanning…")
                 : String(localized: "Total \(DevCleanupService.format(service.totalBytes))"))
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            Spacer()
            PillButton(title: "Delete Unavailable Sims", symbol: "iphone.slash") {
                service.deleteUnavailableSimulators()
            }
            .help("xcrun simctl delete unavailable")
            ToolboxIconButton(symbol: "arrow.clockwise", help: "Rescan") {
                service.lastMessage = nil
                service.lastError = nil
                service.scan()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            if !selection.isEmpty {
                PillButton(title: "Deselect", symbol: "xmark.circle") {
                    selection = []
                    confirming = false
                }
            }
            Spacer()
            if confirming {
                PillButton(title: "Cancel", symbol: "arrow.uturn.backward") { confirming = false }
                DangerActionButton(
                    title: "Delete \(DevCleanupService.format(selectedBytes))?",
                    symbol: "trash.fill",
                    enabled: !service.isDeleting
                ) {
                    confirming = false
                    service.delete(selection)
                    selection = []
                }
            } else {
                AccentActionButton(
                    title: service.isDeleting ? "Deleting…" : "Delete Selected",
                    symbol: "trash",
                    enabled: !selection.isEmpty && !service.isDeleting
                ) {
                    confirming = true
                }
            }
        }
    }

    private var selectedBytes: Int64 {
        service.items.filter { selection.contains($0.id) }.compactMap(\.bytes).reduce(0, +)
    }

    // MARK: - Rows

    private func groupSection(_ group: CleanupItem.Group, rows: [CleanupItem]) -> some View {
        let groupBytes = rows.compactMap(\.bytes).reduce(0, +)
        let ids = Set(rows.map(\.id))
        let allSelected = ids.isSubset(of: selection)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    if allSelected { selection.subtract(ids) } else { selection.formUnion(ids) }
                    confirming = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(allSelected ? Color.accentColor : Theme.TextColor.tertiary)
                        Text(group.title)
                            .sectionTitleStyle()
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(DevCleanupService.format(groupBytes))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            .padding(.top, Spacing.xs)
            ForEach(rows) { item in
                CleanupRow(item: item, isSelected: selection.contains(item.id)) {
                    if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                    confirming = false
                }
            }
        }
    }
}

private struct CleanupRow: View {
    let item: CleanupItem
    let isSelected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : Theme.TextColor.tertiary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Theme.TextColor.primary)
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                ToolboxIconButton(symbol: "folder", help: "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            Text(item.bytes.map(DevCleanupService.format) ?? "—")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(hovering || isSelected ? Theme.Surface.surface2 : Theme.Surface.surface1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }
}

/// Red variant of `AccentActionButton` for the final "really delete" step.
struct DangerActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(Typography.bodyMedium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Theme.Semantic.danger.opacity(enabled ? 1 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
