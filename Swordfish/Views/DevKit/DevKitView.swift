import SwiftUI

struct DevKitView: View {
    @State private var expanded: Section? = nil
    @Environment(\.popoverController) private var popoverController

    private enum Section: String, Identifiable {
        case simulator, toolbox, push, deepLink, universalLink, recorder
        case devices, appStoreConnect, appleStatus
        case buildTimes, cleanup, releases
        case throttle
        case color
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            XcodeToolsView()
            SoftDivider()

            CollapsibleSection(title: "Simulator", id: "devkit.simulator") {
                VStack(spacing: Spacing.sm) {
                    section(.simulator, "iOS Simulator", symbol: "iphone") {
                        IOSSimulatorView()
                    }
                    section(.toolbox, "Simulator Toolbox",
                            subtitle: "Status bar, permissions, location & routes, media, apps, accessibility",
                            symbol: "wrench.and.screwdriver") {
                        SimulatorToolboxView()
                    }
                    LaunchSection(title: "Simulator Logs",
                                  subtitle: "Live unified log of a booted Simulator, filtered by app or subsystem",
                                  symbol: "text.alignleft") {
                        popoverController?.openSimulatorLogs()
                    }
                    section(.push, "Push Notification Tester",
                            subtitle: "Simulator via simctl, or a real device via APNs",
                            symbol: "bell.badge") {
                        PushNotificationView()
                    }
                    section(.deepLink, "Deep Link Launcher",
                            subtitle: "Opens a URL in a booted iOS Simulator (custom scheme or universal link)",
                            symbol: "arrow.up.right.square") {
                        DeepLinkLauncherView()
                    }
                    section(.universalLink, "Universal Link Validator",
                            subtitle: "Checks apple-app-site-association and which app a URL opens",
                            symbol: "checkmark.seal") {
                        UniversalLinkView()
                    }
                    section(.recorder, "Simulator Recorder",
                            subtitle: "Records the booted Simulator screen to Desktop, exports GIFs",
                            symbol: "record.circle") {
                        SimulatorRecorderView()
                    }
                    LaunchSection(title: "Design Overlay",
                                  subtitle: "Lay a design export over the Simulator to check pixels",
                                  symbol: "square.on.square.dashed") {
                        popoverController?.openDesignOverlay()
                    }
                }
            }

            CollapsibleSection(title: "Devices & Distribution", id: "devkit.distribution") {
                VStack(spacing: Spacing.sm) {
                    section(.devices, "Physical Devices",
                            subtitle: "Install builds, launch apps, deep links, screenshots & crash logs",
                            symbol: "iphone.gen3.radiowaves.left.and.right") {
                        PhysicalDevicesView()
                    }
                    section(.appStoreConnect, "App Store Connect",
                            subtitle: "Recent builds and TestFlight processing status",
                            symbol: "airplane.departure") {
                        AppStoreConnectView()
                    }
                    LaunchSection(title: "Signing & Profiles",
                                  subtitle: "Provisioning profiles, certificates & expiry dates",
                                  symbol: "checkmark.seal") {
                        popoverController?.openSigning()
                    }
                    section(.appleStatus, "Apple Developer Status",
                            subtitle: "APNs, App Store Connect, TestFlight, notary… up or down",
                            symbol: "antenna.radiowaves.left.and.right") {
                        AppleStatusView()
                    }
                }
            }

            CollapsibleSection(title: "Build & Disk", id: "devkit.build") {
                VStack(spacing: Spacing.sm) {
                    section(.buildTimes, "Build Times",
                            subtitle: "Xcode build durations per scheme, with finish notifications",
                            symbol: "stopwatch") {
                        BuildTimesView()
                    }
                    section(.cleanup, "Disk Cleanup",
                            subtitle: "DerivedData, simulator runtimes, DeviceSupport, archives & caches",
                            symbol: "externaldrive.badge.minus") {
                        DiskCleanupView()
                    }
                    section(.releases, "Xcode Releases & Runtimes",
                            subtitle: "Latest Xcode versions, install via xcodes, download simulator runtimes",
                            symbol: "hammer.circle") {
                        XcodeReleasesView()
                    }
                    LaunchSection(title: "Crash Symbolicator",
                                  subtitle: "Symbolicate .ips / .crash reports with your dSYMs",
                                  symbol: "ant") {
                        popoverController?.openCrashSymbolicator()
                    }
                }
            }

            CollapsibleSection(title: "Network", id: "devkit.network") {
                VStack(spacing: Spacing.sm) {
                    section(.throttle, "Network Link Conditioner",
                            subtitle: "Throttle Wi-Fi / Ethernet so Simulators & apps see slower networks",
                            symbol: "speedometer") {
                        NetworkConditionerView()
                    }
                    LaunchSection(title: "Network Lab",
                                  subtitle: "Watch HTTP(S) traffic through a local proxy, or serve mock APIs",
                                  symbol: "network") {
                        popoverController?.openNetworkLab()
                    }
                }
            }

            CollapsibleSection(title: "Tools", id: "devkit.tools") {
                VStack(spacing: Spacing.sm) {
                    LaunchSection(title: "JSON Formatter",
                                  subtitle: "Opens a dedicated viewer window with tree + raw side by side",
                                  symbol: "curlybraces") {
                        popoverController?.openJSONViewer()
                    }
                    LaunchSection(title: "JSON to Struct",
                                  subtitle: "Generate Codable structs from a JSON sample",
                                  symbol: "swift") {
                        popoverController?.openJSONToSwift()
                    }
                    LaunchSection(title: "Dev Utilities",
                                  subtitle: "JWT, timestamps, Base64, URL, cURL, UUID, plist, hashes, SF Symbols, app icons, localization",
                                  symbol: "wrench.adjustable") {
                        popoverController?.openDevUtilities()
                    }
                    section(.color, "Color Picker", symbol: "eyedropper") {
                        ColorPickerView()
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ id: Section,
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        symbol: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ExpandableSection(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            isExpanded: expanded == id,
            onToggle: { toggle(id) },
            content: content
        )
    }

    private func toggle(_ s: Section) {
        withAnimation(Motion.default) {
            expanded = (expanded == s) ? nil : s
        }
    }
}
