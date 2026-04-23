import SwiftUI

struct DevKitView: View {
    @State private var expanded: Section? = nil
    @Environment(\.popoverController) private var popoverController

    private enum Section: String, Identifiable {
        case simulator, push, deepLink, recorder, color
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            XcodeToolsView()
            SoftDivider()

            VStack(spacing: Spacing.sm) {
                ExpandableSection(
                    title: "iOS Simulator",
                    symbol: "iphone",
                    isExpanded: expanded == .simulator,
                    onToggle: { toggle(.simulator) }
                ) {
                    IOSSimulatorView()
                }
                ExpandableSection(
                    title: "Push Notification Tester",
                    subtitle: "Sends APNs payload to a booted iOS Simulator",
                    symbol: "bell.badge",
                    isExpanded: expanded == .push,
                    onToggle: { toggle(.push) }
                ) {
                    PushNotificationView()
                }
                ExpandableSection(
                    title: "Deep Link Launcher",
                    subtitle: "Opens a URL in a booted iOS Simulator (custom scheme or universal link)",
                    symbol: "arrow.up.right.square",
                    isExpanded: expanded == .deepLink,
                    onToggle: { toggle(.deepLink) }
                ) {
                    DeepLinkLauncherView()
                }
                ExpandableSection(
                    title: "Simulator Recorder",
                    subtitle: "Records the booted iOS Simulator screen to Desktop",
                    symbol: "record.circle",
                    isExpanded: expanded == .recorder,
                    onToggle: { toggle(.recorder) }
                ) {
                    SimulatorRecorderView()
                }
                LaunchSection(
                    title: "JSON Formatter",
                    subtitle: "Opens a dedicated viewer window with tree + raw side by side",
                    symbol: "curlybraces"
                ) {
                    popoverController?.openJSONViewer()
                }
                LaunchSection(
                    title: "JSON to Struct",
                    subtitle: "Generate Codable structs from a JSON sample",
                    symbol: "swift"
                ) {
                    popoverController?.openJSONToSwift()
                }
                ExpandableSection(
                    title: "Color Picker",
                    symbol: "eyedropper",
                    isExpanded: expanded == .color,
                    onToggle: { toggle(.color) }
                ) {
                    ColorPickerView()
                }
            }
        }
    }

    private func toggle(_ s: Section) {
        withAnimation(Motion.default) {
            expanded = (expanded == s) ? nil : s
        }
    }
}
