import SwiftUI

// MARK: - Shared onboarding styling (adapts to light/dark mode)

private enum OnboardingStyle {
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let cardBorder = Color(.separator)
    static let primaryButton = Color(red: 0.7, green: 0.15, blue: 0.15)
    static let secondaryButtonBg = Color(.tertiarySystemFill)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let fieldBackground = Color(.tertiarySystemBackground)
    static let fieldBorder = Color(.separator)
    static let industries = [
        "Real Estate", "Logistics", "Sales", "Pest Control", "HVAC",
        "Insurance", "Solar", "Other"
    ]
}

// MARK: - Step container

struct WorkspaceOnboardingStepsView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onComplete: () -> Void

    @State private var step: Int = 0
    @State private var teamOnboardingURL: IdentifiableURL?

    private static let gradientStart = Color.black
    private static let gradientEnd = Color(red: 0.25, green: 0.02, blue: 0.02)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.gradientStart, Self.gradientEnd],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if step == 0 { NameStepView(viewModel: viewModel, onContinue: { step = 1 }) }
                else if step == 1 {
                    UseCaseStepView(
                        viewModel: viewModel,
                        onBack: { step = 0 },
                        onContinue: { step = 2 },
                        onContinueOnWeb: continueTeamOnWeb
                    )
                }
                else if step == 2 { WorkspaceStepView(viewModel: viewModel, onBack: { step = 1 }, onContinue: { step = 3 }) }
                else if step == 3 { ValuePropStepView(onBack: { step = 2 }, onContinue: { step = 4 }) }
                else { FeaturesStepView(viewModel: viewModel, onBack: { step = 3 }, onStartTrial: onComplete) }
            }
        }
        .sheet(item: $teamOnboardingURL) { item in
            TeamWebHandoffSafariView(url: item.url)
        }
    }

    private func continueTeamOnWeb() {
        Task {
            do {
                let url = try await TeamWebHandoff.shared.createTeamOnboardingURL()
                await MainActor.run {
                    teamOnboardingURL = IdentifiableURL(url: url)
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Page 1: What should we call you?

private struct NameStepView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(minHeight: 24)
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(spacing: 8) {
                                Text("What should we call you?")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("We use this to personalize your experience.")
                                    .font(.subheadline)
                                    .foregroundColor(OnboardingStyle.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("First name")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                TextField("First name", text: $viewModel.firstName)
                                    .textFieldStyle(OnboardingTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Last name")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                TextField("Last name", text: $viewModel.lastName)
                                    .textFieldStyle(OnboardingTextFieldStyle())
                            }

                            Button(action: onContinue) {
                                Text("Continue")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(canContinueName ? OnboardingStyle.primaryButton : OnboardingStyle.primaryButton.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!canContinueName)
                            .buttonStyle(.plain)
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 20)
                    Spacer().frame(minHeight: 24)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }

    private var canContinueName: Bool {
        !viewModel.firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Page 2: How will you use FLYR?

private struct UseCaseStepView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onBack: () -> Void
    var onContinue: () -> Void
    var onContinueOnWeb: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(minHeight: 24)
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(spacing: 8) {
                                Text("How will you use FLYR?")
                                    .font(.title.weight(.bold))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("Choose solo or invite your team.")
                                    .font(.subheadline)
                                    .foregroundColor(OnboardingStyle.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 16) {
                                UseCaseOption(
                                    title: "For myself",
                                    subtitle: "Solo use",
                                    icon: "person",
                                    isSelected: viewModel.useCase == .solo
                                ) {
                                    viewModel.useCase = .solo
                                }
                                UseCaseOption(
                                    title: "For my team",
                                    subtitle: "Invite others",
                                    icon: "person.3",
                                    isSelected: viewModel.useCase == .team
                                ) {
                                    viewModel.useCase = .team
                                }
                            }

                            if viewModel.useCase == .team {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Set up your team")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(OnboardingStyle.textPrimary)
                                    Text("Workspaces are created on the web. Team owners continue to set up desktop dashboard.")
                                        .font(.subheadline)
                                        .foregroundColor(OnboardingStyle.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(16)
                                .background(OnboardingStyle.fieldBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(OnboardingStyle.fieldBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            OnboardingBackButton(action: onBack)

                            if viewModel.useCase == .team {
                                Button(action: onContinueOnWeb) {
                                    Text("Continue on web")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OnboardingStyle.primaryButton)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            } else {
                                OnboardingPrimaryButton(title: "Continue", action: onContinue)
                            }
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 20)
                    Spacer().frame(minHeight: 24)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }
}

// MARK: - Page 3: Set up your workspace

private struct WorkspaceStepView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onBack: () -> Void
    var onContinue: () -> Void
    @FocusState private var isBrokerageFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(minHeight: 24)
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(spacing: 8) {
                                Text("Set up your workspace")
                                    .font(.title.weight(.bold))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("Name your business and tell us your industry.")
                                    .font(.subheadline)
                                    .foregroundColor(OnboardingStyle.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Business or team name")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                TextField("Business or team name", text: $viewModel.workspaceName)
                                    .textFieldStyle(OnboardingTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Industry")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                Menu {
                                    ForEach(OnboardingStyle.industries, id: \.self) { name in
                                        Button(name) {
                                            viewModel.onIndustryChanged(name)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(viewModel.industry ?? "Select industry")
                                            .foregroundColor(viewModel.industry == nil ? OnboardingStyle.textSecondary : OnboardingStyle.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(OnboardingStyle.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(OnboardingStyle.fieldBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(OnboardingStyle.fieldBorder, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }

                            if viewModel.showBrokerageField {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Brokerage (optional)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(OnboardingStyle.textPrimary)
                                    TextField(
                                        "Search or add brokerage",
                                        text: Binding(
                                            get: { viewModel.brokerage },
                                            set: { viewModel.onBrokerageTextChanged($0) }
                                        )
                                    )
                                    .textFieldStyle(OnboardingTextFieldStyle())
                                    .focused($isBrokerageFocused)
                                    .accessibilityLabel("Brokerage name")
                                    .accessibilityHint("Type to search existing brokerages or add a new brokerage name.")

                                    if viewModel.isBrokerageSearching {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .accessibilityLabel("Searching brokerages")
                                    }

                                    if viewModel.isBrokerageSuggestionsOpen && viewModel.hasTypedBrokerage {
                                        VStack(spacing: 0) {
                                            ForEach(viewModel.brokerageSuggestions) { item in
                                                Button {
                                                    viewModel.onSelectSuggestion(item)
                                                } label: {
                                                    HStack {
                                                        Text(item.name)
                                                            .foregroundColor(OnboardingStyle.textPrimary)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 10)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Brokerage suggestion: \(item.name)")
                                            }

                                            if shouldShowAddNewAction {
                                                Button {
                                                    viewModel.onSelectAddNewBrokerage()
                                                    isBrokerageFocused = true
                                                } label: {
                                                    HStack {
                                                        Text("Add \"\(trimmedBrokerageText)\" as new brokerage")
                                                            .foregroundColor(OnboardingStyle.textPrimary)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 10)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Add \(trimmedBrokerageText) as new brokerage")
                                            }
                                        }
                                        .background(OnboardingStyle.fieldBackground)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OnboardingStyle.fieldBorder, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }

                                    if let searchError = viewModel.brokerageSearchError {
                                        Text(searchError)
                                            .font(.caption)
                                            .foregroundColor(OnboardingStyle.textSecondary)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Referral code (optional)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(OnboardingStyle.textPrimary)
                                TextField("e.g. Launch2026", text: Binding(
                                    get: { viewModel.referralCode ?? "" },
                                    set: { viewModel.referralCode = $0.isEmpty ? nil : $0 }
                                ))
                                    .textFieldStyle(OnboardingTextFieldStyle())
                            }

                            OnboardingBackButton(action: onBack)
                            Button(action: onContinue) {
                                Text("Continue")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(canContinueWorkspace ? OnboardingStyle.primaryButton : OnboardingStyle.primaryButton.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!canContinueWorkspace)
                            .buttonStyle(.plain)
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 20)
                    Spacer().frame(minHeight: 24)
                }
                .frame(minHeight: geo.size.height)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    viewModel.dismissBrokerageSuggestions()
                }
            )
        }
        .onDisappear {
            viewModel.cancelBrokerageSearch()
        }
    }

    private var canContinueWorkspace: Bool {
        !viewModel.workspaceName.trimmingCharacters(in: .whitespaces).isEmpty
            && viewModel.industry != nil && !(viewModel.industry?.isEmpty ?? true)
    }

    private var trimmedBrokerageText: String {
        let trimmed = viewModel.brokerage.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    private var hasExactSuggestionMatch: Bool {
        let loweredInput = trimmedBrokerageText.lowercased()
        guard !loweredInput.isEmpty else { return false }
        return viewModel.brokerageSuggestions.contains { $0.name.lowercased() == loweredInput }
    }

    private var shouldShowAddNewAction: Bool {
        !trimmedBrokerageText.isEmpty && !hasExactSuggestionMatch
    }
}

// MARK: - Page 4: FLYR is revolutionizing...

private struct ValuePropStepView: View {
    var onBack: () -> Void
    var onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(minHeight: 24)
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 28) {
                            Text("FLYR is revolutionizing\nDoor 2 Door Marketing")
                                .font(.title2.weight(.bold))
                                .foregroundColor(OnboardingStyle.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            HStack(alignment: .top, spacing: 16) {
                                ValuePropItem(icon: "map", label: "Maps")
                                ValuePropItem(icon: "door.left.hand.open", label: "D2D")
                                ValuePropItem(icon: "chart.bar", label: "Tracking")
                            }

                            OnboardingBackButton(action: onBack)
                            OnboardingPrimaryButton(title: "Continue", action: onContinue)
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 20)
                    Spacer().frame(minHeight: 24)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }
}

// MARK: - Page 5: Features + Continue

private struct FeaturesStepView: View {
    @ObservedObject var viewModel: WorkspaceOnboardingViewModel
    var onBack: () -> Void
    var onStartTrial: () -> Void

    private let features: [(icon: String, label: String)] = [
        ("map", "Planning routes"),
        ("record.circle", "Recording activity"),
        ("megaphone", "Improving marketing"),
        ("list.bullet", "Staying organized"),
        ("trophy", "Competing against others")
    ]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(minHeight: 24)
                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 28) {
                            Text("You're one step away from")
                                .font(.title3.weight(.bold))
                                .foregroundColor(OnboardingStyle.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 20) {
                                ForEach(Array(features.enumerated()), id: \.offset) { _, f in
                                    HStack(spacing: 16) {
                                        Image(systemName: f.icon)
                                            .font(.title2)
                                            .foregroundColor(OnboardingStyle.textPrimary)
                                            .frame(width: 32, alignment: .center)
                                        Text(f.label)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(OnboardingStyle.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }

                            OnboardingBackButton(action: onBack)
                            Button(action: onStartTrial) {
                                Text("Continue")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(viewModel.canSubmit ? OnboardingStyle.primaryButton : OnboardingStyle.primaryButton.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!viewModel.canSubmit)
                            .buttonStyle(.plain)
                        }
                        .padding(24)
                    }
                    .padding(.horizontal, 20)
                    Spacer().frame(minHeight: 24)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }
}

// MARK: - Reusable components

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

private struct OnboardingTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(OnboardingStyle.fieldBackground)
            .foregroundColor(OnboardingStyle.textPrimary)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(OnboardingStyle.fieldBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(OnboardingStyle.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Back")
                .font(.headline)
                .foregroundColor(OnboardingStyle.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OnboardingStyle.secondaryButtonBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct UseCaseOption: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(OnboardingStyle.textPrimary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(OnboardingStyle.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(OnboardingStyle.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(OnboardingStyle.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OnboardingStyle.primaryButton : OnboardingStyle.fieldBorder, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct ValuePropItem: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(OnboardingStyle.textPrimary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(OnboardingStyle.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
