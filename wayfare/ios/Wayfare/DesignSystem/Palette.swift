import SwiftUI
import UIKit

extension UIColor {
    /// A solid sRGB color from a 0xRRGGBB value.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A color that switches between light and dark appearance (and, optionally, Increase Contrast).
    static func dynamic(light: UInt32, dark: UInt32,
                        highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            if traits.accessibilityContrast == .high {
                if isDark, let highContrastDark { return UIColor(rgb: highContrastDark) }
                if !isDark, let highContrastLight { return UIColor(rgb: highContrastLight) }
            }
            return UIColor(rgb: isDark ? dark : light)
        }
    }
}

extension Color {
    /// A fixed color from a 0xRRGGBB value.
    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }

    /// A light/dark dynamic color from two 0xRRGGBB values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: .dynamic(light: light, dark: dark))
    }

    /// Parses "#RRGGBB" (or "RRGGBB"). Returns nil when unparsable.
    init?(hex: String) {
        guard let value = HexColor.parse(hex) else { return nil }
        self.init(rgb: value)
    }
}

enum HexColor {
    /// "#0A6B7C" -> 0x0A6B7C. Returns nil for anything that is not 6 hex digits.
    static func parse(_ hex: String) -> UInt32? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(text, radix: 16)
    }
}

/// Color tokens from `company/03-design-system.md` section 2. Hex values are copied verbatim.
enum Palette {
    // MARK: Core
    static let background = Color.dynamic(light: 0xF6F4EF, dark: 0x0F1115)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1D23)
    static let surface2 = Color.dynamic(light: 0xEFECE5, dark: 0x252932)
    static let textPrimary = Color.dynamic(light: 0x1A1D21, dark: 0xF2F0EB)
    static let textSecondary = Color(uiColor: .dynamic(light: 0x5B626C, dark: 0xA2A8B2,
                                                       highContrastLight: 0x454B53, highContrastDark: 0xC4C9D0))
    static let accent = Color.dynamic(light: 0x0A6B7C, dark: 0x4EC3D4)
    static let accentTint = Color.dynamic(light: 0xE2EDEF, dark: 0x233B43)
    static let onAccent = Color.dynamic(light: 0xFFFFFF, dark: 0x0F1115)
    static let separator = Color(uiColor: .dynamic(light: 0xE3DED6, dark: 0x2E333B,
                                                   highContrastLight: 0xC9C3B8, highContrastDark: 0x4A505A))
    static let success = Color.dynamic(light: 0x0D7550, dark: 0x4FCB93)
    static let warning = Color.dynamic(light: 0x8F5A00, dark: 0xEDB24C)
    static let danger = Color.dynamic(light: 0xC0282D, dark: 0xFF6B6B)

    // MARK: Item kinds
    static let kindFlight = Color.dynamic(light: 0x1E5FCC, dark: 0x77A6FF)
    static let kindFlightTint = Color.dynamic(light: 0xE4ECF9, dark: 0x2B364B)
    static let kindLodging = Color.dynamic(light: 0x7045B8, dark: 0xB895F6)
    static let kindLodgingTint = Color.dynamic(light: 0xEEE9F6, dark: 0x363349)
    static let kindActivity = Color.dynamic(light: 0x0D7550, dark: 0x4FCB93)
    static let kindActivityTint = Color.dynamic(light: 0xE2EEEA, dark: 0x243C37)
    static let kindFood = Color.dynamic(light: 0xB8431A, dark: 0xFF8F66)
    static let kindFoodTint = Color.dynamic(light: 0xF6E8E4, dark: 0x43322F)
    static let kindTransport = Color.dynamic(light: 0x935400, dark: 0xEDB24C)
    static let kindTransportTint = Color.dynamic(light: 0xF2EAE0, dark: 0x40382A)
    static let kindNote = Color.dynamic(light: 0x5C6675, dark: 0xA7B1BF)
    static let kindNoteTint = Color.dynamic(light: 0xEBEDEE, dark: 0x33383F)

    /// UIKit versions for navigation bar appearance.
    static let uiBackground = UIColor.dynamic(light: 0xF6F4EF, dark: 0x0F1115)
    static let uiTextPrimary = UIColor.dynamic(light: 0x1A1D21, dark: 0xF2F0EB)
}

/// Trip cover palette (design system 7.1). Identical in light and dark.
struct CoverColor: Identifiable, Hashable, Sendable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) ?? Color(rgb: 0x0A6B7C) }

    static let lagoon = CoverColor(name: "Lagoon", hex: "#0A6B7C")

    static let all: [CoverColor] = [
        lagoon,
        CoverColor(name: "Sky", hex: "#1E5FCC"),
        CoverColor(name: "Indigo", hex: "#4B47C4"),
        CoverColor(name: "Violet", hex: "#7045B8"),
        CoverColor(name: "Bougainvillea", hex: "#A8326E"),
        CoverColor(name: "Chili", hex: "#C0282D"),
        CoverColor(name: "Terracotta", hex: "#B8431A"),
        CoverColor(name: "Saffron", hex: "#8A5A00"),
        CoverColor(name: "Olive", hex: "#2F7A36"),
        CoverColor(name: "Jade", hex: "#0D7550"),
        CoverColor(name: "Slate", hex: "#3C4A5C"),
        CoverColor(name: "Cocoa", hex: "#6B4F3A"),
    ]

    /// Renders any synced hex as-is; unparsable values fall back to Lagoon.
    static func color(forHex hex: String) -> Color {
        Color(hex: hex) ?? lagoon.color
    }

    static func name(forHex hex: String) -> String {
        all.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "Custom color"
    }
}

/// Spacing scale (design system 5.1).
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

/// Corner radii (design system 5.2).
enum Radius {
    static let badge: CGFloat = 6
    static let band: CGFloat = 10
    static let button: CGFloat = 12
    static let action: CGFloat = 14
    static let card: CGFloat = 16
    static let headerCard: CGFloat = 20
    static let appIcon: CGFloat = 22
}
