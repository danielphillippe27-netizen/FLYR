import SwiftUI

struct ExperienceScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Door-knocking experience?")
                    .font(.system(size: 28, weight: .bold))
                Text("We'll set realistic goals based on your experience.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(ExperienceLevel.allCases, id: \.self) { level in
                    Button {
                        viewModel.response.experienceLevel = level
                        viewModel.next()
                    } label: {
                        HStack {
                            Text(level.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if viewModel.response.experienceLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.flyrPrimary)
                            }
                        }
                        .padding()
                        .background(viewModel.response.experienceLevel == level ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: { viewModel.back() }) {
                Text("Back")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
    }
}
