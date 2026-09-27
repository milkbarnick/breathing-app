import SwiftUI
import UIKit

/// Type styles from design system section 3. All are Dynamic Type text styles.
extension Font {
    static let wfLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let wfHeroTitle = Font.system(.title2, design: .rounded, weight: .bold)
    static let wfSheetTitle = Font.system(.title2, design: .default, weight: .bold)
    static let wfDetailTitle = Font.system(.title2, design: .default, weight: .bold)
    static let wfRouteCode = Font.system(.largeTitle, design: .monospaced, weight: .bold)
    static let wfConfirmationCode = Font.system(.title2, design: .monospaced, weight: .bold)
    static let wfInviteCode = Font.system(.title, design: .monospaced, weight: .bold)
    static let wfBigTime = Font.system(.title3, design: .default, weight: .semibold).monospacedDigit()
    static let wfRowTitle = Font.system(.body, design: .default, weight: .semibold)
    static let wfRowTime = Font.system(.subheadline, design: .default, weight: .semibold).monospacedDigit()
    static let wfRowEndTime = Font.system(.caption).monospacedDigit()
    static let wfBadge = Font.system(.caption2).monospacedDigit()
    static let wfDayOffset = Font.system(.caption2, design: .default, weight: .bold).monospacedDigit()
    static let wfPill = Font.system(.caption, design: .default, weight: .bold)
    static let wfKindLabel = Font.system(.caption, design: .default, weight: .bold)
    static let wfCountdown = Font.system(.caption, design: .default, weight: .semibold).monospacedDigit()
    static let wfCounter = Font.system(.caption).monospacedDigit()
}

enum Typography {
    /// Rounded bold large titles in navigation bars, on the warm paper background.
    @MainActor
    static func configureNavigationBar() {
        let base = UIFont.preferredFont(forTextStyle: .largeTitle)
        let descriptor = base.fontDescriptor.withDesign(.rounded)?.withSymbolicTraits(.traitBold)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        if let descriptor {
            appearance.largeTitleTextAttributes = [
                .font: UIFont(descriptor: descriptor, size: 0),
                .foregroundColor: Palette.uiTextPrimary,
            ]
        }
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
