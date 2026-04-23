import SwiftUI
import AppKit

enum Theme {
    enum Surface {
        static let popover   = adaptive(light: rgba(246, 246, 248, 0.78), dark: rgba(32, 32, 34, 0.78))
        static let surface1  = adaptive(light: rgba(0, 0, 0, 0.04),        dark: rgba(255, 255, 255, 0.04))
        static let surface2  = adaptive(light: rgba(0, 0, 0, 0.06),        dark: rgba(255, 255, 255, 0.07))
        static let surface3  = adaptive(light: rgba(0, 0, 0, 0.09),        dark: rgba(255, 255, 255, 0.10))
        static let codeBg    = adaptive(light: rgba(0, 0, 0, 0.04),        dark: rgba(0, 0, 0, 0.25))
    }

    enum Border {
        static let subtle    = adaptive(light: rgba(0, 0, 0, 0.06), dark: rgba(255, 255, 255, 0.06))
        static let `default` = adaptive(light: rgba(0, 0, 0, 0.10), dark: rgba(255, 255, 255, 0.10))
    }

    enum TextColor {
        static let primary    = adaptive(light: Color(hex: 0x1d1d1f), dark: Color(hex: 0xf2f2f4))
        static let secondary  = adaptive(light: Color(hex: 0x494951), dark: Color(hex: 0xb8b8bd))
        static let tertiary   = adaptive(light: Color(hex: 0x6f6f77), dark: Color(hex: 0x8a8a92))
        static let quaternary = adaptive(light: Color(hex: 0x9a9aa1), dark: Color(hex: 0x60606a))
    }

    enum Semantic {
        static let accent = Color.accentColor
        static let ok     = Color(hex: 0x30D158)
        static let warn   = Color(hex: 0xFFD60A)
        static let danger = Color(hex: 0xFF453A)
    }

    enum Syntax {
        static let key    = adaptive(light: Color(hex: 0xc71585), dark: Color(hex: 0xff9ac1))
        static let string = adaptive(light: Color(hex: 0x0b8043), dark: Color(hex: 0xa4e4a0))
        static let number = adaptive(light: Color(hex: 0xb86c13), dark: Color(hex: 0xf7c682))
        static let bool   = adaptive(light: Color(hex: 0x0066cc), dark: Color(hex: 0x9ecbff))
        static let null   = adaptive(light: Color(hex: 0x7850c8), dark: Color(hex: 0xc4a8ff))
        static let punct  = adaptive(light: Color(hex: 0x6f6f77), dark: Color(hex: 0x8a8a92))
    }
}

private func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
    Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
}

private func adaptive(light: Color, dark: Color) -> Color {
    let ns = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(isDark ? dark : light)
    }
    return Color(nsColor: ns)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF)  / 255
        let b = Double(hex & 0xFF)         / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
