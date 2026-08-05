import SwiftUI

/// Form fields for workspace onboarding. Industry options from guide.
struct WorkspaceOnboardingFormView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel

    private static let industries = [
        "Real Estate", "Logistics", "Sales", "Pest Control", "HVAC",
        "Insurance", "Solar", "Other"
    ]

    var body: some View {
        Form {
            Section("Name") {
                TextField("First name", text: $viewModel.firstName)
                TextField("Last name", text: $viewModel.lastName)
            }
            Section("Workspace") {
                TextField("Workspace name", text: $viewModel.workspaceName)
                Picker("Use case", selection: $viewModel.useCase) {
                    Text("Solo").tag(OnboardingUseCase.solo)
                    Text("Team").tag(OnboardingUseCase.team)
                }
            }
            Section("Industry") {
                Picker("Industry", selection: Binding(
                    get: { viewModel.industry ?? "" },
                    set: { viewModel.industry = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Select…").tag("")
                    ForEach(Self.industries, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            Section("Brokerage (optional)") {
                TextField("Brokerage name", text: $viewModel.brokerage)
            }
            if viewModel.useCase == .team {
                Section("Invite team members (optional)") {
                    TextField("Email addresses, comma-separated", text: Binding(
                        get: { viewModel.inviteEmails.joined(separator: ", ") },
                        set: { viewModel.inviteEmails = $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty } }
                    ))
                }
            }
        }
    }
}
