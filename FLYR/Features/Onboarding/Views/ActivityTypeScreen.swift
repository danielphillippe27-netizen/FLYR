import SwiftUI

struct ActivityTypeScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How do you plan on using FLYR?")
                    .font(.system(size: 28, weight: .bold))
                Text("We'll tailor the app for you.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(OnboardingActivityType.allCases, id: \.self) { type in
                    Button {
                        viewModel.response.activityType = type
                        viewModel.next()
                    } label: {
                        HStack {
                            Text(type.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if viewModel.response.activityType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.flyrPrimary)
                            }
                        }
                        .padding()
                        .background(viewModel.response.activityType == type ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
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
