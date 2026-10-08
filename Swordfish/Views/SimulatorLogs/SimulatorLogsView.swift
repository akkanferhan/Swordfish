import SwiftUI
import AppKit

struct SimulatorLogsView: View {
    @EnvironmentObject var logs: SimulatorLogService
    @StateObject private var simulators = SimulatorService()
    @StateObject private var appsModel = InstalledAppsModel()
    @State private var selectedUDID = ""
    @State private var process = ""
    @State private var subsystem = ""
    @State private var level: SimulatorLogService.MinimumLevel = .default
    @State private var search = ""
    @State private var errorsOnly = false
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            filterBar
            Divider()
            logList
            Divider()
            statusBar
        }
        .background(Theme.Surface.popover)
        .task { simulators.refresh() }
        .onChange(of: simulators.simulators) { sims in
            let booted = sims.filter(\.isBooted)
            if !booted.contains(where: { $0.udid == selectedUDID }) {
                selectedUDID = booted.first?.udid ?? ""
            }
        }
        .onChange(of: selectedUDID) { udid in
            if !udid.isEmpty { appsModel.load(udid: udid) }
        }
    }

    // MARK: - Source (simulator, process, subsystem, level)

    private var sourceBar: some View {
        HStack(spacing: Spacing.sm) {
            let booted = simulators.simulators.filter(\.isBooted)
            if booted.isEmpty {
                Text("No booted simulators")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            } else {
                Picker("", selection: $selectedUDID) {
                    ForEach(booted) { sim in Text(sim.name).tag(sim.udid) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            ToolboxIconButton(symbol: "arrow.clockwise", help: "Refresh simulators") {
                simulators.refresh()
            }

            HStack(spacing: 4) {
                field("Process (e.g. MyApp)", text: $process)
                    .frame(width: 150)
                Menu {
                    ForEach(appsModel.apps.filter { $0.executable != nil }) { app in
                        Button("\(app.name) — \(app.bundleID)") {
                            process = app.executable ?? ""
                        }
                    }
                } label: {
                    Image(systemName: "app.badge")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Pick an installed app")
                .disabled(appsModel.apps.isEmpty)
            }
            field("Subsystem prefix (e.g. com.acme)", text: $subsystem)
                .frame(minWidth: 140)
            Picker("", selection: $level) {
                ForEach(SimulatorLogService.MinimumLevel.allCases) { l in Text(l.label).tag(l) }
            }
            .labelsHidden()
            .frame(width: 90)
            .help("Minimum level")

            if logs.isRunning {
                AccentActionButton(title: "Stop", symbol: "stop.fill") { logs.stop() }
            } else {
                AccentActionButton(title: "Stream", symbol: "play.fill", enabled: !selectedUDID.isEmpty) {
                    logs.start(udid: selectedUDID, process: process, subsystem: subsystem, level: level)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Filter (search, errors, autoscroll, clear, copy)

    private var filterBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(Theme.TextColor.tertiary)
            field("Filter lines", text: $search)
            Toggle("Errors only", isOn: $errorsOnly)
                .toggleStyle(.checkbox)
                .font(Typography.monoSmall)
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(Typography.monoSmall)
            PillButton(title: "Copy", symbol: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(visibleLines.map(\.text).joined(separator: "\n"), forType: .string)
            }
            PillButton(title: "Clear", symbol: "xmark.circle") { logs.clear() }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    private var visibleLines: [LogLine] {
        logs.lines.filter { line in
            if errorsOnly && line.level != .error && line.level != .fault { return false }
            if !search.isEmpty && !line.text.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    // MARK: - Lines

    private var logList: some View {
        let rows = visibleLines
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { line in
                        Text(line.text)
                            .font(Typography.code)
                            .foregroundStyle(color(for: line.level))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 1)
                            .id(line.id)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .background(Theme.Surface.codeBg)
            .overlay {
                if rows.isEmpty {
                    Text(logs.isRunning ? "Waiting for log lines…" : "Pick a booted simulator and press Stream")
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.tertiary)
                }
            }
            .onChange(of: logs.lines.last?.id) { _ in
                guard autoScroll, let last = rows.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .error:   return Theme.Semantic.danger
        case .fault:   return Theme.Syntax.key
        case .debug:   return Theme.TextColor.tertiary
        case .info:    return Theme.TextColor.secondary
        case .default: return Theme.TextColor.primary
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(logs.isRunning ? Theme.Semantic.ok : Theme.TextColor.quaternary)
                .frame(width: 7, height: 7)
            Text(logs.isRunning ? "Streaming" : "Stopped")
            if let err = logs.lastError {
                Text(err).foregroundStyle(Theme.Semantic.danger).lineLimit(1)
            }
            Spacer()
            Text("\(visibleLines.count) / \(logs.lines.count) lines")
        }
        .font(Typography.monoSmall)
        .foregroundStyle(Theme.TextColor.tertiary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 5)
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Typography.mono)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Theme.Surface.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                    )
            )
    }
}
