import SwiftUI

struct PricingFramingScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var otherFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("FLYR is free to try but very limited.")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("To get the most out of FLYR, we recommend PRO.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)

                Text("What would you need from FLYR to make $30/month worth it?")
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    ForEach(ProExpectation.allCases, id: \.self) { option in
                        if option == .other {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    toggleProExpectation(option)
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                            .font(.system(size: 16, weight: .medium))
                                        Spacer()
                                        if viewModel.response.proExpectations.contains(option) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.flyrPrimary)
                                        }
                                    }
                                    .padding()
                                    .background(viewModel.response.proExpectations.contains(option) ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                if viewModel.response.proExpectations.contains(option) {
                                    TextField("Tell us more...", text: Binding(
                                        get: { viewModel.response.proExpectationsOther ?? "" },
                                        set: { viewModel.response.proExpectationsOther = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($otherFocused)
                                }
                            }
                        } else {
                            Button {
                                toggleProExpectation(option)
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    if viewModel.response.proExpectations.contains(option) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.flyrPrimary)
                                    }
                                }
                                .padding()
                                .background(viewModel.response.proExpectations.contains(option) ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    Button(action: { viewModel.next() }) {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.flyrPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
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
    }

    private func toggleProExpectation(_ option: ProExpectation) {
        if viewModel.response.proExpectations.contains(option) {
            viewModel.response.proExpectations.removeAll { $0 == option }
            if option == .other {
                viewModel.response.proExpectationsOther = nil
            }
        } else {
            viewModel.response.proExpectations.append(option)
        }
    }
}
