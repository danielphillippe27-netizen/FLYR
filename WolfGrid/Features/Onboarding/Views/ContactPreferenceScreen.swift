import SwiftUI

struct ContactPreferenceScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("How can we reach you?")
                    .font(.system(size: 28, weight: .bold))
                Text("Session reminders and updates.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(ContactPreference.allCases, id: \.self) { pref in
                    Button {
                        viewModel.response.contactPreference = pref
                        viewModel.next()
                    } label: {
                        HStack {
                            Image(systemName: pref.icon)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pref.rawValue)
                                    .font(.system(size: 16, weight: .medium))
                                Text(pref.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if viewModel.response.contactPreference == pref {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.flyrPrimary)
                            }
                        }
                        .padding()
                        .background(viewModel.response.contactPreference == pref ? Color.flyrPrimary.opacity(0.1) : Color(.systemGray6))
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
