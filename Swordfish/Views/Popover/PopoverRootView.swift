import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(onRefresh: { env.displayController.refresh() })
            TabBar(selected: Binding(
                get: { env.selectedTab },
                set: { env.selectedTab = $0 }
            ))
            Divider().opacity(0.0)

            ScrollView {
                Group {
                    switch env.selectedTab {
                    case .systemHub:    SystemHubView()
                    case .devKit:       placeholder("Dev Kit")
                    case .productivity: placeholder("Clipboard")
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.smMd)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            PopoverFooter()
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.popover, style: .continuous))
    }

    private func placeholder(_ title: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Theme.TextColor.primary)
            Text("Content lands in its own feature branch.")
                .font(Typography.monoSmall)
                .foregroundStyle(Theme.TextColor.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }
}
