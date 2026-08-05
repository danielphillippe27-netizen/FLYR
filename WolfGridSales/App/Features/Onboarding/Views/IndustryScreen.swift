import SwiftUI

struct IndustryScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What's your industry?")
                    .font(.system(size: 28, weight: .bold))
                Text("We'll tailor the app for you.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(Industry.allCases, id: \.self) { industry in
                    Button {
                        viewModel.response.industry = industry
                        viewModel.next()
                    } label: {
                        HStack {
                            Text(industry.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if viewModel.response.industry == industry {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.flyrPrimary)
                            }
                        }
                        .padding()
                        .background(viewModel.response.industry == industry ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
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
