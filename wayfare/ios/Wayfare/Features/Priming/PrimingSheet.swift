import SwiftUI

/// Our own card shown before the system notification prompt (UX spec 2.4).
struct PrimingSheet: View {
    let request: PrimingRequest

    @Environment(NotificationPermission.self) private var permission
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false
    @State private var grantedCount = 0

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(request.title)
                .font(.wfSheetTitle)
                .multilineTextAlignment(.center)
            Text(request.body)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button {
                turnOn()
            } label: {
                if isRequesting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Turn On Notifications").frame(maxWidth: .infinity)
                }
            }
            .wfPrimaryButton()
            .disabled(isRequesting)
            Button("Not Now") {
                permission.markPrimed(request.moment)
                dismiss()
            }
            .foregroundStyle(Palette.accent)
        }
        .padding(Spacing.xxl)
        .presentationDetents([.medium])
        .background(Palette.background)
        .sensoryFeedback(.success, trigger: grantedCount)
        .onAppear {
            permission.markPrimed(request.moment)
        }
    }

    private func turnOn() {
        isRequesting = true
        Task {
            let granted = await permission.requestAuthorization()
            isRequesting = false
            if granted {
                grantedCount += 1
            }
            dismiss()
        }
    }
}

#Preview {
    Text("Trip")
        .sheet(isPresented: .constant(true)) {
            PrimingSheet(request: .firstTrip(tripTitle: "Lisbon & Porto"))
        }
        .previewServices()
}
