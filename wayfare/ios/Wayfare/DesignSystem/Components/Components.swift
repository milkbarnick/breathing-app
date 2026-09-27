import SwiftUI

// MARK: - Kind chip

/// A circular chip with the kind symbol on its tint (design system 9, "Kind chip").
struct KindIcon: View {
    let kind: ItemKind
    var symbolOverride: String?
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var symbolSize: CGFloat

    init(kind: ItemKind, size: CGFloat = 32, symbolOverride: String? = nil) {
        self.kind = kind
        self.symbolOverride = symbolOverride
        _size = ScaledMetric(wrappedValue: size)
        _symbolSize = ScaledMetric(wrappedValue: size * 15 / 32)
    }

    var body: some View {
        Image(systemName: symbolOverride ?? kind.filledSymbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(kind.color)
            .frame(width: size, height: size)
            .background(Circle().fill(kind.tint))
            .accessibilityHidden(true)
    }
}

// MARK: - Cover tile

/// One emoji on one color, as a rounded square (design system 7).
struct CoverTile: View {
    let emoji: String
    let colorHex: String
    @ScaledMetric private var size: CGFloat

    init(emoji: String, colorHex: String, size: CGFloat = 44) {
        self.emoji = emoji
        self.colorHex = colorHex
        _size = ScaledMetric(wrappedValue: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size > 64 ? 20 : Radius.card, style: .continuous)
            .fill(CoverColor.color(forHex: colorHex))
            .frame(width: size, height: size)
            .overlay {
                Text(emoji.isEmpty ? "✈️" : emoji)
                    .font(.system(size: size * 0.55))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Pills and badges

enum PillStyle {
    case now, next, today, countdown, viewOnly

    var background: Color {
        switch self {
        case .now, .today: return Palette.accent
        case .next, .countdown: return Palette.accentTint
        case .viewOnly: return Palette.surface2
        }
    }

    var foreground: Color {
        switch self {
        case .now, .today: return Palette.onAccent
        case .next, .countdown: return Palette.accent
        case .viewOnly: return Palette.textSecondary
        }
    }

    var font: Font {
        self == .countdown ? .wfCountdown : .wfPill
    }
}

/// Capsule pill: Now, Next, Today, countdown, View only (design system 5.5).
struct Pill: View {
    let text: String
    let style: PillStyle
    var systemImage: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(style.font)
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.background))
    }
}

/// Time zone badge under a time ("EDT", "Oct 1 · EDT").
struct ZoneBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.wfBadge)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Radius.badge, style: .continuous).fill(Palette.surface2))
            .fixedSize()
    }
}

/// Small sync icon shown after titles with local changes the server hasn't acknowledged.
struct UnsyncedMarker: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel("not yet synced")
    }
}

// MARK: - Avatar

/// Initials in a colored circle (design system 9, "Avatar").
struct AvatarCircle: View {
    let name: String
    let color: Color
    @ScaledMetric private var size: CGFloat

    init(name: String, color: Color, size: CGFloat = 36) {
        self.name = name
        self.color = color
        _size = ScaledMetric(wrappedValue: size)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(Initials.from(name))
                    .font(size > 44 ? .title3.bold() : .subheadline.bold())
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

enum Initials {
    /// "Nick Smith" -> "NS", "sam" -> "S", "" -> "?".
    static func from(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .shadow(color: colorScheme == .dark ? .clear : Color(rgb: 0x1A1D21).opacity(0.06),
                            radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(colorScheme == .dark ? Palette.separator : .clear, lineWidth: 1)
            )
    }
}

extension View {
    /// `surface` card: radius 16 / padding 16 by default, light-mode shadow, dark-mode hairline.
    func wfCard(radius: CGFloat = Radius.card, padding: CGFloat = Spacing.l) -> some View {
        modifier(CardModifier(radius: radius, padding: padding))
    }

    /// Full-width large prominent button in `accent`.
    func wfPrimaryButton() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Palette.accent)
    }
}

// MARK: - Banners

/// "Offline. Changes will sync when you're back online."
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
            Text("Offline. Changes will sync when you're back online.")
        }
        .font(.footnote)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(.horizontal, Spacing.l)
        .background(Palette.surface2)
        .accessibilityElement(children: .combine)
    }
}

/// Inline error/info banner with a symbol.
struct InlineBanner: View {
    let systemImage: String
    let text: String
    var color: Color = Palette.danger

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(Palette.surface2))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Label / value row

struct LabeledValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Spacing.l)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}
