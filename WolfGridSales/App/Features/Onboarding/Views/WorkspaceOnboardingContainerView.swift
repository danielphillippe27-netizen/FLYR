import SwiftUI

/// Container for workspace onboarding steps. Presents 5-page flow and calls onComplete when user taps Continue.
struct WorkspaceOnboardingContainerView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onComplete: () -> Void

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("WolfGridAuth")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 96)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .accessibilityLabel("WolfGrid — Territory Domination")
            WorkspaceOnboardingStepsView(viewModel: viewModel, onComplete: onComplete)
        }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let msg = viewModel.errorMessage { Text(msg) }
            }
    }
}
