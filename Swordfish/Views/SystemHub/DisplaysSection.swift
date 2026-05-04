import SwiftUI

struct DisplaysSection: View {
    @EnvironmentObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(
                title: "Displays",
                badge: "DDC · \(controller.displays.count) connected"
            )
            VStack(spacing: Spacing.sm) {
                ForEach(controller.displays) { display in
                    DisplayRow(display: display) { value in
                        controller.setBrightness(value, for: display.id)
                    }
                }
            }
        }
    }
}

private struct DisplayRow: View {
    let display: DisplayDevice
    let onBrightnessChange: (Double) -> Void

    @State private var value: Double
    @State private var suppressWrite = false

    init(display: DisplayDevice, onBrightnessChange: @escaping (Double) -> Void) {
        self.display = display
        self.onBrightnessChange = onBrightnessChange
        self._value = State(initialValue: display.brightness)
    }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Spacing.smMd) {
                HStack(spacing: Spacing.md) {
                    MiniMonitorGlyph()
                        .frame(width: 36, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Theme.TextColor.primary)
                            .lineLimit(1)
                        Text("\(Int(display.resolution.width)) × \(Int(display.resolution.height))")
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.tertiary)
                    }
                    Spacer()
                }
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sun.max")
                        .foregroundStyle(Theme.TextColor.tertiary)
                        .font(.system(size: 11))
                    Slider(value: $value, in: 0...1)
                    Text("\(Int(value * 100))%")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .onChange(of: value) { newValue in
            if suppressWrite {
                suppressWrite = false
                return
            }
            onBrightnessChange(newValue)
        }
        .onChange(of: display.brightness) { newValue in
            // Outside source updated brightness (refresh, hotkey) — sync the
            // slider without re-triggering a DDC write.
            guard abs(newValue - value) > 0.005 else { return }
            suppressWrite = true
            value = newValue
        }
    }
}

private struct MiniMonitorGlyph: View {
    var body: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.Border.default, lineWidth: 1)
                .frame(height: 16)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.Border.default)
                .frame(width: 10, height: 2)
        }
    }
}
