import SwiftUI

struct GoalsScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What matters most?")
                    .font(.system(size: 28, weight: .bold))
                Text("Select all that apply.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(Goal.allCases, id: \.self) { goal in
                    Button {
                        toggleGoal(goal)
                    } label: {
                        HStack {
                            Text(goal.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if viewModel.response.goals.contains(goal) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.flyrPrimary)
                            }
                        }
                        .padding()
                        .background(viewModel.response.goals.contains(goal) ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 16) {
                Button(action: { viewModel.next() }) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(viewModel.canProceed ? Color.flyrPrimary : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!viewModel.canProceed)
                Button(action: { viewModel.back() }) {
                    Text("Back")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func toggleGoal(_ goal: Goal) {
        if viewModel.response.goals.contains(goal) {
            viewModel.response.goals.removeAll { $0 == goal }
        } else {
            viewModel.response.goals.append(goal)
        }
    }
}
