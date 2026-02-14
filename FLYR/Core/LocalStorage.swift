import Foundation

final class LocalStorage {
    static let shared = LocalStorage()

    private let onboardingKey = "flyr_onboarding_data"
    private let hasCompletedOnboardingKey = "flyr_has_completed_onboarding"
    private let isInPreviewModeKey = "flyr_is_in_preview_mode"

    private init() {}

    // MARK: - Onboarding Data

    func saveOnboardingData(_ response: OnboardingResponse) {
        guard let encoded = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(encoded, forKey: onboardingKey)
    }

    func loadOnboardingData() -> OnboardingResponse? {
        guard let data = UserDefaults.standard.data(forKey: onboardingKey),
              let decoded = try? JSONDecoder().decode(OnboardingResponse.self, from: data) else {
            return nil
        }
        return decoded
    }

    func clearOnboardingData() {
        UserDefaults.standard.removeObject(forKey: onboardingKey)
    }

    // MARK: - State Tracking

    var hasCompletedOnboarding: Bool {
        // Temporary override: bypass onboarding flow app-wide.
        get { true }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    var isInPreviewMode: Bool {
        get { UserDefaults.standard.bool(forKey: isInPreviewModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: isInPreviewModeKey) }
    }

    // MARK: - Clean Slate

    func reset() {
        clearOnboardingData()
        hasCompletedOnboarding = false
        isInPreviewMode = false
    }
}
