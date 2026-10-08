import SwiftUI
import AppKit

/// Top processes by CPU / memory, listening TCP ports, and one-click
/// restarts for the dev daemons that most often get stuck.
struct ProcessesSection: View {
    enum Mode: CaseIterable, Identifiable {
        case cpu, memory, ports
        var id: Self { self }
        var label: LocalizedStringKey {
            switch self {
            case .cpu:    return "Top CPU"
            case .memory: return "Top Memory"
            case .ports:  return "Ports"
            }
        }
    }

    @StateObject private var service = ProcessMonitorService()
    @State private var mode: Mode = .cpu

    var body: some View {
        CollapsibleSection(title: "Processes",
                           badge: mode == .ports ? "\(service.ports.count) listening" : nil,
                           id: "processes") {
            Tile {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: 4) {
                        ForEach(Mode.allCases) { m in
                            ModeChip(title: m.label, isSelected: mode == m) { mode = m }
                        }
                        Spacer()
                        Menu {
                            Button("Restart SourceKit (autocomplete / indexing stuck)") {
                                service.restart("SourceKitService", label: "SourceKit")
                            }
                            Button("Restart CoreSimulator (simctl / Simulator hangs)") {
                                service.restart("com.apple.CoreSimulator.CoreSimulatorService", label: "CoreSimulator")
                            }
                            Button("Restart Xcode build service") {
                                service.restart("XCBBuildService", label: "XCBBuildService")
                            }
                        } label: {
                            Label("Fix", systemImage: "bandage")
                                .font(Typography.monoSmall)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Restart a stuck developer daemon")
                    }

                    if mode != .ports, !service.heavyDevTools.isEmpty {
                        devToolsSummary
                    }

                    switch mode {
                    case .cpu:    processList(service.top(by: .cpu))
                    case .memory: processList(service.top(by: .memory))
                    case .ports:  portList
                    }

                    if let status = service.status {
                        ToolboxStatusLine(status: status)
                    }
                }
            }
            .task {
                // Poll only while the section is on screen and expanded.
                while !Task.isCancelled {
                    service.refresh()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    // MARK: - Dev tools summary

    private var devToolsSummary: some View {
        let heavy = service.heavyDevTools
        let total = heavy.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        return HStack(spacing: 6) {
            Image(systemName: "hammer")
                .font(.system(size: 10))
            Text("Dev tools: \(total.humanBytes) across \(heavy.count) process(es)")
                .lineLimit(1)
        }
        .font(Typography.monoSmall)
        .foregroundStyle(Theme.TextColor.tertiary)
    }

    // MARK: - Lists

    private func processList(_ rows: [RunningProcess]) -> some View {
        VStack(spacing: 2) {
            ForEach(rows) { p in
                ProcessRow(process: p) { force in
                    service.kill(pid: p.pid, name: p.name, force: force)
                }
            }
            if rows.isEmpty {
                placeholder("Reading processes…")
            }
        }
    }

    private var portList: some View {
        VStack(spacing: 2) {
            ForEach(service.ports) { port in
                PortRow(port: port) {
                    service.kill(pid: port.pid, name: port.process, force: false)
                }
            }
            if service.ports.isEmpty {
                placeholder("No TCP ports listening for your user")
            }
        }
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.TextColor.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Rows

private struct ProcessRow: View {
    let process: RunningProcess
    let kill: (_ force: Bool) -> Void
    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(process.name)
                .font(Typography.mono)
                .foregroundStyle(process.isDevTool ? Color.accentColor : Theme.TextColor.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\(process.pid)")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)
            Spacer(minLength: 0)
            if confirming {
                Button("Quit") { kill(false); confirming = false }
                    .buttonStyle(.plain)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.accentColor)
                Button("Force") { kill(true); confirming = false }
                    .buttonStyle(.plain)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                Button { confirming = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.TextColor.tertiary)
            } else {
                if hovering && process.isOwn {
                    Button { confirming = true } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .help("Quit process")
                }
                Text(String(format: "%.1f%%", process.cpu))
                    .font(Typography.monoSmall)
                    .foregroundStyle(cpuTint)
                    .frame(width: 52, alignment: .trailing)
                Text(process.memoryBytes.humanBytes)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Color.clear)
        )
        .onHover { hovering = $0; if !$0 { confirming = false } }
    }

    private var cpuTint: Color {
        if process.cpu >= 80 { return Theme.Semantic.danger }
        if process.cpu >= 30 { return Theme.Semantic.warn }
        return Theme.TextColor.secondary
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let kill: () -> Void
    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(verbatim: ":\(port.port)")
                .font(Typography.mono.weight(.semibold))
                .foregroundStyle(Theme.TextColor.primary)
                .frame(width: 62, alignment: .leading)
            Text(port.isLoopbackOnly ? String(localized: "local") : port.address)
                .font(Typography.monoSmall)
                .foregroundStyle(port.isLoopbackOnly ? Theme.TextColor.tertiary : Theme.Semantic.warn)
                .help(port.isLoopbackOnly ? "Only reachable from this Mac" : "Reachable from the network")
            Text(verbatim: "\(port.process) · \(port.pid)")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if confirming {
                Text("Quit \(port.process)?")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.danger)
                ToolboxIconButton(symbol: "xmark", help: "Cancel") { confirming = false }
                ToolboxIconButton(symbol: "checkmark", help: "Confirm") { kill(); confirming = false }
            } else if hovering {
                ToolboxIconButton(symbol: "safari", help: "Open http://localhost in browser") {
                    if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) }
                }
                CopyButton(text: "localhost:\(port.port)")
                    .help("Copy localhost:port")
                ToolboxIconButton(symbol: "xmark.circle", help: "Quit the process holding this port") {
                    confirming = true
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(hovering ? Theme.Surface.surface2 : Color.clear)
        )
        .onHover { hovering = $0; if !$0 { confirming = false } }
    }
}

private struct ModeChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.monoSmall)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Theme.TextColor.secondary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Theme.Surface.surface2)
                )
        }
        .buttonStyle(.plain)
    }
}
