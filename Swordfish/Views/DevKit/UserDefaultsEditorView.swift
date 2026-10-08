import SwiftUI
import AppKit

@MainActor
final class UserDefaultsEditorModel: ObservableObject {
    @Published private(set) var udid = ""
    @Published private(set) var app: InstalledApp?
    @Published private(set) var entries: [DefaultsEntry] = []
    @Published private(set) var isLoading = false
    @Published var status: ToolboxStatus?
    @Published var search = ""
    /// The running app keeps its own in-memory copy and may write it back,
    /// so by default it's terminated before a write and relaunched after.
    @Published var restartApp = true

    var filtered: [DefaultsEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.key.localizedCaseInsensitiveContains(q) || $0.display.localizedCaseInsensitiveContains(q) }
    }

    func open(udid: String, app: InstalledApp) {
        self.udid = udid
        self.app = app
        search = ""
        status = nil
        reload()
    }

    func reload() {
        guard let app, !isLoading else { return }
        isLoading = true
        let udid = self.udid
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try SimulatorDefaults.read(udid: udid, bundleID: app.bundleID) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isLoading = false
                switch outcome {
                case .success(let list): self.entries = list
                case .failure(let error): self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    func save(key: String, type: DefaultsEntry.ValueType, value: String) {
        mutate(String(localized: "Saved \(key)")) { udid, bundleID in
            try SimulatorDefaults.write(udid: udid, bundleID: bundleID, key: key, type: type, value: value)
        }
    }

    func delete(key: String) {
        mutate(String(localized: "Deleted \(key)")) { udid, bundleID in
            try SimulatorDefaults.delete(udid: udid, bundleID: bundleID, key: key)
        }
    }

    private func mutate(_ message: String, _ work: @escaping (String, String) throws -> Void) {
        guard let app else { return }
        let udid = self.udid
        let restart = restartApp
        status = nil
        Task.detached(priority: .userInitiated) {
            let outcome: ToolboxStatus
            do {
                if restart { _ = try? SimulatorToolbox.terminate(udid: udid, bundleID: app.bundleID) }
                try work(udid, app.bundleID)
                if restart { _ = try? SimulatorToolbox.launch(udid: udid, bundleID: app.bundleID) }
                outcome = .ok(message, nil)
            } catch {
                outcome = .error(error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                self?.status = outcome
                self?.reload()
            }
        }
    }
}

struct UserDefaultsEditorView: View {
    @ObservedObject var model: UserDefaultsEditorModel
    @State private var selectedKey: String?
    @State private var editKey = ""
    @State private var editType: DefaultsEntry.ValueType = .string
    @State private var editValue = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                list.frame(minWidth: 320)
                editor.frame(minWidth: 300)
            }
            Divider()
            footer
        }
        .background(Theme.Surface.popover)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.app?.name ?? "—")
                    .font(Typography.title)
                    .foregroundStyle(Theme.TextColor.primary)
                Text(model.app?.bundleID ?? "")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            TextField("Filter keys", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .font(Typography.mono)
                .frame(width: 200)
            PillButton(title: "New Key", symbol: "plus") { startNew() }
            ToolboxIconButton(symbol: "arrow.clockwise", help: "Reload") { model.reload() }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.filtered) { entry in
                    HStack(spacing: Spacing.sm) {
                        Text(entry.key)
                            .font(Typography.mono)
                            .foregroundStyle(Theme.TextColor.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(entry.display.replacingOccurrences(of: "\n", with: " "))
                            .font(Typography.monoSmall)
                            .foregroundStyle(Theme.TextColor.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .trailing)
                        Badge(label: entry.type.label, tint: entry.type.isEditable ? Color.accentColor : Theme.TextColor.tertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(selectedKey == entry.key ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { select(entry) }
                }
            }
            .padding(Spacing.sm)
        }
        .overlay {
            if model.filtered.isEmpty {
                Text(model.isLoading ? "Loading…" : "No UserDefaults keys")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        let existing = model.entries.first { $0.key == selectedKey }
        let editable = existing?.type.isEditable ?? true
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(existing == nil ? "New key" : "Edit key")
                .sectionTitleStyle()
            TextField("Key", text: $editKey)
                .textFieldStyle(.roundedBorder)
                .font(Typography.mono)
                .disabled(existing != nil)
            Picker("Type", selection: $editType) {
                ForEach(DefaultsEntry.ValueType.allCases.filter { $0.isEditable || $0 == editType }) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.menu)
            .disabled(!editable)
            if editType == .boolean {
                Picker("", selection: $editValue) {
                    Text("true").tag("true")
                    Text("false").tag("false")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            } else {
                CodeEditor(text: $editValue,
                           placeholder: editType == .date ? "2026-01-31T12:00:00Z" : "Value",
                           minHeight: 120)
                    .disabled(!editable)
            }
            if !editable {
                Text("Arrays, dictionaries and data are shown read-only — edit them in code or with `defaults import`.")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if existing != nil {
                    if confirmingDelete {
                        PillButton(title: "Cancel", symbol: "xmark") { confirmingDelete = false }
                        DangerActionButton(title: "Delete key", symbol: "trash.fill") {
                            model.delete(key: editKey)
                            confirmingDelete = false
                            startNew()
                        }
                    } else {
                        PillButton(title: "Delete", symbol: "trash") { confirmingDelete = true }
                    }
                }
                Spacer()
                AccentActionButton(title: "Save", symbol: "checkmark",
                                   enabled: editable && !editKey.trimmingCharacters(in: .whitespaces).isEmpty) {
                    model.save(key: editKey.trimmingCharacters(in: .whitespaces), type: editType, value: editValue)
                    selectedKey = editKey
                }
            }
            Spacer()
        }
        .padding(Spacing.md)
        .onChange(of: editType) { type in
            if type == .boolean && !["true", "false"].contains(editValue) { editValue = "true" }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            Toggle("Restart the app around each change", isOn: $model.restartApp)
                .toggleStyle(.checkbox)
                .font(Typography.monoSmall)
            Spacer()
            if let status = model.status {
                ToolboxStatusLine(status: status)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    private func select(_ entry: DefaultsEntry) {
        selectedKey = entry.key
        editKey = entry.key
        editType = entry.type
        editValue = entry.display
        confirmingDelete = false
    }

    private func startNew() {
        selectedKey = nil
        editKey = ""
        editType = .string
        editValue = ""
        confirmingDelete = false
    }
}

@MainActor
final class UserDefaultsEditorWindowController: NSObject {
    private var window: NSWindow?
    private let model = UserDefaultsEditorModel()

    func show(udid: String, app: InstalledApp) {
        model.open(udid: udid, app: app)
        if let window {
            window.title = String(localized: "UserDefaults — \(app.name)")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: UserDefaultsEditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "UserDefaults — \(app.name)")
        window.setContentSize(NSSize(width: 820, height: 520))
        window.contentMinSize = NSSize(width: 660, height: 360)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
