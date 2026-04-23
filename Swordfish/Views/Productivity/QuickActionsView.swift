import SwiftUI

struct QuickActionsView: View {
    @EnvironmentObject var clipboard: ClipboardService

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: "Quick Actions")
            HStack(spacing: Spacing.sm) {
                ActionChip(symbol: "camera", label: "Screenshot", action: runScreenshot)
                ActionChip(symbol: "lock", label: "Lock Screen", action: lockScreen)
                ActionChip(symbol: "arrow.triangle.2.circlepath", label: "Flush DNS", action: flushDNS)
                ActionChip(symbol: "terminal", label: "Terminal", action: openTerminal)
            }
        }
    }

    private func runScreenshot() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? ProcessRunner.run("/usr/sbin/screencapture", arguments: ["-i", "-c"])
        }
    }

    private func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    private func lockScreen() {
        // macOS 13+: the classic CGSession -suspend binary was removed. Trigger
        // the standard Ctrl+Cmd+Q lock shortcut via System Events. First run
        // prompts for Automation permission; subsequent calls work silently.
        let script = #"tell application "System Events" to keystroke "q" using {control down, command down}"#
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        }
    }

    private func flushDNS() {
        // dscacheutil + killing mDNSResponder both require root. `osascript` +
        // `with administrator privileges` triggers the system GUI auth prompt.
        let script = """
        do shell script "dscacheutil -flushcache && killall -HUP mDNSResponder" with administrator privileges
        """
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        }
    }
}

private struct ActionChip: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.TextColor.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Theme.Surface.surface2)
                    )
                Text(label)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(hovering ? Theme.Surface.surface1 : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
            .scaleEffect(hovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: hovering)
    }
}
