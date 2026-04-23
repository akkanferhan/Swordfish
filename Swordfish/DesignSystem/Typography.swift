import SwiftUI

enum Typography {
    static let body         = Font.system(size: 12.5, weight: .regular, design: .default)
    static let bodyMedium   = Font.system(size: 12.5, weight: .medium,  design: .default)
    static let rowLabel     = Font.system(size: 12.5, weight: .regular, design: .default)
    static let title        = Font.system(size: 13,   weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 10.5, weight: .semibold, design: .default)
    static let subtitle     = Font.system(size: 10.5, weight: .regular,  design: .monospaced)
    static let mono         = Font.system(size: 11.5, weight: .regular,  design: .monospaced)
    static let monoSmall    = Font.system(size: 10.5, weight: .regular,  design: .monospaced)
    static let code         = Font.system(size: 11.5, weight: .regular,  design: .monospaced)
    static let statNumber   = Font.system(size: 20,   weight: .semibold, design: .monospaced)
    static let kbd          = Font.system(size: 10.5, weight: .medium,   design: .monospaced)
}

extension View {
    func sectionTitleStyle() -> some View {
        self
            .font(Typography.sectionTitle)
            .tracking(1.2)
            .foregroundStyle(Theme.TextColor.tertiary)
            .textCase(.uppercase)
    }
}
