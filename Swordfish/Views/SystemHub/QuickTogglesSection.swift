import SwiftUI
import CoreAudio

struct QuickTogglesSection: View {
    @StateObject private var toggles = QuickTogglesService()

    var body: some View {
        CollapsibleSection(title: "Quick Toggles", id: "quickToggles") {
            Tile {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        ToggleTile(
                            title: "Dark Mode",
                            symbol: toggles.darkMode ? "moon.fill" : "sun.max",
                            isOn: toggles.darkMode
                        ) { toggles.setDarkMode(!toggles.darkMode) }
                        ToggleTile(
                            title: "Hidden Files",
                            symbol: toggles.showHiddenFiles ? "eye" : "eye.slash",
                            isOn: toggles.showHiddenFiles
                        ) { toggles.setShowHiddenFiles(!toggles.showHiddenFiles) }
                        .help("Show dotfiles in Finder (relaunches Finder)")
                        ToggleTile(
                            title: toggles.micMuted ? "Mic Muted" : "Mute Mic",
                            symbol: toggles.micMuted ? "mic.slash.fill" : "mic",
                            isOn: toggles.micMuted
                        ) { toggles.setMicMuted(!toggles.micMuted) }
                        .disabled(!toggles.canMuteMic)
                        .help(toggles.canMuteMic ? "Mute / unmute the default microphone"
                                                 : "The current input device can't be muted")
                    }
                    .disabled(toggles.isBusy)

                    audioRow(symbol: "speaker.wave.2", devices: toggles.outputs,
                             selected: toggles.defaultOutput, select: toggles.setOutput)
                    audioRow(symbol: "mic", devices: toggles.inputs,
                             selected: toggles.defaultInput, select: toggles.setInput)

                    if let err = toggles.lastError {
                        Text(err)
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.Semantic.danger)
                            .lineLimit(2)
                    }
                }
            }
        }
        .onAppear { toggles.start() }
    }

    private func audioRow(symbol: String, devices: [AudioDevice], selected: AudioDeviceID?,
                          select: @escaping (AudioDeviceID) -> Void) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.TextColor.tertiary)
                .frame(width: 16)
            Menu {
                ForEach(devices) { device in
                    Button {
                        select(device.id)
                    } label: {
                        if device.id == selected {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Text(devices.first { $0.id == selected }?.name ?? String(localized: "None"))
                    .font(Typography.monoSmall)
            }
            .menuStyle(.borderlessButton)
            .disabled(devices.isEmpty)
            Spacer()
        }
    }
}

private struct ToggleTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 18)
                Text(title)
                    .font(Typography.monoSmall)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.white : Theme.TextColor.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(isOn ? Color.accentColor
                          : (hovering ? Theme.Surface.surface3 : Theme.Surface.surface2))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
