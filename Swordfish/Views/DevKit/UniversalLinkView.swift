import SwiftUI

struct UniversalLinkView: View {
    @AppStorage("swordfish.universalLink.input") private var input = ""
    @State private var report: UniversalLinkValidator.Report?
    @State private var isChecking = false
    @State private var showJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                TextField("example.com or https://example.com/products/42", text: $input)
                    .textFieldStyle(.plain)
                    .font(Typography.mono)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Theme.Surface.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .strokeBorder(Theme.Border.subtle, lineWidth: 1)
                            )
                    )
                    .onSubmit(validate)
                AccentActionButton(title: isChecking ? "Checking…" : "Validate",
                                   symbol: "checkmark.seal",
                                   enabled: !isChecking && !input.trimmingCharacters(in: .whitespaces).isEmpty,
                                   action: validate)
            }
            Text("Add a path to see which app opens it, e.g. https://example.com/products/42")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.quaternary)

            if let report {
                results(report)
            }
        }
    }

    @ViewBuilder
    private func results(_ report: UniversalLinkValidator.Report) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(report.checks) { check in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon(check.level))
                        .font(.system(size: 11))
                        .foregroundStyle(tint(check.level))
                    Text(check.message)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Theme.TextColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if let match = report.match {
            matchBanner(match)
        }

        ForEach(report.apps) { app in
            VStack(alignment: .leading, spacing: 3) {
                ForEach(app.appIDs, id: \.self) { id in
                    HStack(spacing: 6) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                        Text(id)
                            .font(Typography.mono)
                            .foregroundStyle(Theme.TextColor.primary)
                            .textSelection(.enabled)
                    }
                }
                ForEach(Array(app.rules.enumerated()), id: \.offset) { _, rule in
                    Text(verbatim: rule)
                        .font(Typography.monoSmall)
                        .foregroundStyle(rule.hasPrefix("NOT") ? Theme.Semantic.warn : Theme.TextColor.tertiary)
                        .padding(.leading, 16)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(Theme.Surface.surface1)
            )
        }

        if !report.webCredentials.isEmpty || !report.appClips.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if !report.webCredentials.isEmpty {
                    Text("Password AutoFill: \(report.webCredentials.joined(separator: ", "))")
                }
                if !report.appClips.isEmpty {
                    Text("App Clips: \(report.appClips.joined(separator: ", "))")
                }
            }
            .font(Typography.monoSmall)
            .foregroundStyle(Theme.TextColor.tertiary)
        }

        if let json = report.rawJSON {
            HStack {
                Button(showJSON ? "Hide file" : "Show file") { showJSON.toggle() }
                    .buttonStyle(.plain)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                CopyButton(text: json)
            }
            if showJSON {
                ScrollView {
                    Text(verbatim: json)
                        .font(Typography.code)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .fill(Theme.Surface.codeBg)
                )
            }
        }
    }

    private func matchBanner(_ match: UniversalLinkValidator.MatchResult) -> some View {
        let (symbol, color, text): (String, Color, String) = {
            switch match {
            case .opens(let ids, let rule):
                return ("arrow.up.forward.app.fill", Theme.Semantic.ok,
                        String(localized: "Opens \(ids.joined(separator: ", ")) — rule \(rule)"))
            case .excluded(let rule):
                return ("nosign", Theme.Semantic.warn, String(localized: "Excluded by \(rule) — opens in Safari"))
            case .noMatch:
                return ("safari", Theme.Semantic.danger, String(localized: "No rule matches — opens in Safari"))
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
                .font(Typography.monoSmall)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private func validate() {
        let target = input
        guard !target.trimmingCharacters(in: .whitespaces).isEmpty, !isChecking else { return }
        isChecking = true
        Task {
            let result = await UniversalLinkValidator.validate(target)
            report = result
            isChecking = false
        }
    }

    private func icon(_ level: UniversalLinkValidator.Check.Level) -> String {
        switch level {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    private func tint(_ level: UniversalLinkValidator.Check.Level) -> Color {
        switch level {
        case .pass: return Theme.Semantic.ok
        case .warn: return Theme.Semantic.warn
        case .fail: return Theme.Semantic.danger
        }
    }
}
