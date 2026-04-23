import SwiftUI
import AppKit

struct JSONToSwiftView: View {
    @AppStorage("swordfish.j2s.input") private var input: String = ""
    @AppStorage("swordfish.j2s.rootName") private var rootName: String = "Root"
    @AppStorage("swordfish.j2s.codable") private var codable: Bool = true
    @AppStorage("swordfish.j2s.camelCase") private var camelCase: Bool = true

    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                inputPane.frame(minWidth: 280)
                outputPane.frame(minWidth: 320)
            }
            Divider()
            statusBar
        }
        .background(Theme.Surface.popover)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.sm) {
            PillButton(title: "Paste", symbol: "doc.on.clipboard") { paste() }
            PillButton(title: "Clear", symbol: "xmark.circle") { input = "" }

            Divider().frame(height: 16)

            HStack(spacing: 6) {
                Text("Name")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
                TextField("Root", text: $rootName)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                    .foregroundStyle(Theme.TextColor.primary)
                    .frame(width: 140)
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

            Divider().frame(height: 16)

            Toggle(isOn: $codable) {
                Text("Codable").font(Typography.monoSmall)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Toggle(isOn: $camelCase) {
                Text("camelCase").font(Typography.monoSmall)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Spacer()
            Button(action: copyOutput) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text("Copy Swift")
                        .font(Typography.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(generationResult.output.isEmpty ? Color.accentColor.opacity(0.35) : Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(generationResult.output.isEmpty || generationResult.error != nil)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Panes

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader("JSON")
            TextEditor(text: $input)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.primary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .background(Theme.Surface.codeBg)
        }
    }

    @ViewBuilder
    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader("SWIFT")
            if let error = generationResult.error {
                errorView(error)
            } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyView
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(generationResult.output)
                        .font(Typography.code)
                        .foregroundStyle(Theme.TextColor.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(Spacing.md)
                }
                .background(Theme.Surface.codeBg)
            }
        }
    }

    private func paneHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Typography.monoSmall)
                .tracking(1.2)
                .foregroundStyle(Theme.TextColor.tertiary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(Theme.Surface.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Border.subtle).frame(height: 1)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "swift")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.TextColor.quaternary)
            Text("Paste JSON on the left to generate Swift types")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
            Button {
                input = Self.sampleJSON
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Load sample").font(Typography.bodyMedium)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.codeBg)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.smMd) {
            Label {
                Text("Can't generate")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(Typography.bodyMedium)
            .foregroundStyle(Theme.Semantic.danger)
            Text(message)
                .font(Typography.code)
                .foregroundStyle(Theme.TextColor.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.md)
        .background(Theme.Surface.codeBg)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: Spacing.md) {
            if generationResult.error != nil {
                Badge(label: "Invalid JSON", tint: Theme.Semantic.danger)
            } else if generationResult.output.isEmpty {
                Badge(label: "Empty", tint: Theme.TextColor.tertiary)
            } else {
                Badge(label: "Ready", tint: Theme.Semantic.ok)
                Text("\(structCount) \(structCount == 1 ? "struct" : "structs")")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.TextColor.tertiary)
            }
            Spacer()
            if let toast {
                Text(toast)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Theme.Semantic.ok)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    private var structCount: Int {
        generationResult.output
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("struct ") }
            .count
    }

    // MARK: - Generation (recomputed on any input change)

    private struct Result {
        let output: String
        let error: String?
    }

    private var generationResult: Result {
        let opts = JSONToSwift.Options(
            rootName: rootName.isEmpty ? "Root" : rootName,
            codable: codable,
            snakeToCamel: camelCase
        )
        do {
            let out = try JSONToSwift.generate(from: input, options: opts)
            return Result(output: out, error: nil)
        } catch {
            return Result(output: "", error: error.localizedDescription)
        }
    }

    // MARK: - Actions

    private func paste() {
        guard let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty else {
            showToast("Clipboard is empty")
            return
        }
        input = raw
        showToast("Pasted")
    }

    private func copyOutput() {
        let text = generationResult.output
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Copied Swift")
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            toast = nil
        }
    }

    // MARK: - Sample data

    private static let sampleJSON = """
    {
      "id": 42,
      "full_name": "Ada Lovelace",
      "is_active": true,
      "score": 9.75,
      "emails": ["ada@example.com", "ada@computing.org"],
      "address": {
        "street": "1 Babbage Way",
        "postal_code": "LN1 2AB"
      },
      "projects": [
        {"id": 1, "name": "Analytical Engine", "completed": false},
        {"id": 2, "name": "Bernoulli Notes", "completed": true}
      ],
      "metadata": null
    }
    """
}
