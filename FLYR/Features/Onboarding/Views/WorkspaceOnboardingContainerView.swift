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
        WorkspaceOnboardingStepsView(viewModel: viewModel, onComplete: onComplete)
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let msg = viewModel.errorMessage { Text(msg) }
            }
    }
}
