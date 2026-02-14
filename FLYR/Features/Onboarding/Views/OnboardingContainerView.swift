import SwiftUI

struct OnboardingContainerView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Binding var appFlowState: AppFlowState
    var initialStep: Int = 0

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case 0:
                IndustryScreen(viewModel: viewModel)
            case 1:
                ActivityTypeScreen(viewModel: viewModel)
            case 2:
                ExperienceScreen(viewModel: viewModel)
            case 3:
                TerritoryScreen(viewModel: viewModel)
            case 4:
                GoalsScreen(viewModel: viewModel)
            case 5:
                ProfileSetupScreen(viewModel: viewModel)
            case 6:
                ContactPreferenceScreen(viewModel: viewModel)
            case 7:
                PricingFramingScreen(viewModel: viewModel)
            case 8:
                AuthScreen(viewModel: viewModel, embeddedInFlow: true)
            default:
                IndustryScreen(viewModel: viewModel)
            }
        }
        .onAppear {
            if initialStep > 0 {
                viewModel.currentStep = initialStep
                if let saved = LocalStorage.shared.loadOnboardingData() {
                    viewModel.response = saved
                }
            }
        }
        .onChange(of: AuthManager.shared.user?.id) { _, newId in
            if newId != nil {
                appFlowState = .authenticated
            }
        }
    }
}
