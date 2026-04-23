import SwiftUI

struct XcodeToolsView: View {
    @State private var derivedSize: String = "—"
    @State private var isPurging = false
    @State private var isCleaning = false
    @State private var toast: String? = nil

    private let derivedPath = "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: "Xcode Tools", badge: "DerivedData · \(derivedSize)")

            HStack(spacing: Spacing.sm) {
                ToolButton(
                    symbol: "trash",
                    title: "Delete DerivedData",
                    subtitle: "Wipe all Xcode builds",
                    busy: isPurging,
                    tint: Theme.Semantic.danger,
                    action: deleteDerivedData
                )
                ToolButton(
                    symbol: "hammer",
                    title: "Clean Build",
                    subtitle: "Xcode active project",
                    busy: isCleaning,
                    tint: Color.accentColor,
                    action: cleanBuild
                )
            }

            if let toast {
                Text(toast)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await refreshSize() }
    }

    // MARK: - Actions

    private func deleteDerivedData() {
        guard !isPurging else { return }
        isPurging = true
        toast = nil
        let path = derivedPath
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for item in contents {
                    try? fm.removeItem(at: item)
                }
            }
            await MainActor.run {
                isPurging = false
                toast = "DerivedData cleared"
                Task { await refreshSize() }
            }
        }
    }

    private func cleanBuild() {
        guard !isCleaning else { return }
        isCleaning = true
        toast = nil
        let script = """
        tell application "System Events"
            if exists (process "Xcode") then
                tell application "Xcode"
                    if (count of workspace documents) > 0 then
                        clean active workspace document
                        return "clean sent"
                    else
                        return "no workspace open"
                    end if
                end tell
            else
                return "Xcode not running"
            end if
        end tell
        """
        Task.detached(priority: .userInitiated) {
            let result = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
            let output = (result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "done"
            await MainActor.run {
                isCleaning = false
                toast = output
            }
        }
    }

    private func refreshSize() async {
        let path = derivedPath
        let size = await Task.detached(priority: .background) { () -> String in
            let result = try? ProcessRunner.run("/usr/bin/du", arguments: ["-sh", path])
            let stdout = result?.stdout ?? ""
            let size = stdout.split(separator: "\t").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? "—"
            return size.isEmpty ? "—" : size
        }.value
        self.derivedSize = size
    }
}

private struct ToolButton: View {
    let symbol: String
    let title: String
    let subtitle: String
    let busy: Bool
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.22 : 0.14))
                    Image(systemName: busy ? "arrow.clockwise" : symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .opacity(busy ? 0.6 : 1.0)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(busy ? "Working…" : title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Theme.TextColor.primary)
                    Text(subtitle)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.smMd)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(hovering ? Theme.Surface.surface2 : Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: hovering)
    }
}
