import SwiftUI
import UIKit

/// A short message shown at the top of the screen for 2.5 s (design system 9, "Toast").
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var systemImage: String = "checkmark.circle.fill"
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ text: String, systemImage: String = "checkmark.circle.fill") {
        let toast = Toast(text: text, systemImage: systemImage)
        current = toast
        UIAccessibility.post(notification: .announcement, argument: text)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        if current?.id == id {
            current = nil
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(Palette.accent)
            Text(toast.text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background {
            if reduceTransparency {
                Capsule().fill(Palette.surface)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows the current toast from `center` at the top of this view.
    @MainActor
    func toastOverlay(_ center: ToastCenter) -> some View {
        overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast)
                    .padding(.top, Spacing.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss(toast.id) }
                    .id(toast.id)
            }
        }
        .animation(.snappy(duration: 0.3), value: center.current)
    }
}
