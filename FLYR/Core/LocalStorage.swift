import Foundation

final class LocalStorage {
    static let shared = LocalStorage()

    private let onboardingKey = "flyr_onboarding_data"
    private let hasCompletedOnboardingKey = "flyr_has_completed_onboarding"
    private let isInPreviewModeKey = "flyr_is_in_preview_mode"
    private let hasSeenMapInfoSheetKey = "flyr_has_seen_map_info_sheet"
    private let beaconTokensKey = "flyr_session_beacon_tokens"
    private let beaconRecipientsKey = "flyr_beacon_recipients"
    private let beaconMessageKey = "flyr_beacon_message"

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

    /// No longer used for routing; routing is backend-driven via access redirect. Kept for debug / legacy.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    var isInPreviewMode: Bool {
        get { UserDefaults.standard.bool(forKey: isInPreviewModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: isInPreviewModeKey) }
    }

    var hasSeenMapInfoSheet: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenMapInfoSheetKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenMapInfoSheetKey) }
    }

    // MARK: - Clean Slate

    func reset() {
        clearOnboardingData()
        hasCompletedOnboarding = false
        isInPreviewMode = false
        hasSeenMapInfoSheet = false
    }

    // MARK: - Beacon tokens

    func saveBeaconToken(_ token: String, for sessionId: UUID) {
        var tokens = beaconTokens
        tokens[sessionId.uuidString] = token
        UserDefaults.standard.set(tokens, forKey: beaconTokensKey)
    }

    func loadBeaconToken(for sessionId: UUID) -> String? {
        beaconTokens[sessionId.uuidString]
    }

    func clearBeaconToken(for sessionId: UUID) {
        var tokens = beaconTokens
        tokens.removeValue(forKey: sessionId.uuidString)
        UserDefaults.standard.set(tokens, forKey: beaconTokensKey)
    }

    private var beaconTokens: [String: String] {
        UserDefaults.standard.dictionary(forKey: beaconTokensKey) as? [String: String] ?? [:]
    }

    // MARK: - Beacon draft

    func saveBeaconRecipients(_ recipients: [BeaconContactRecipient]) {
        guard let encoded = try? JSONEncoder().encode(recipients) else { return }
        UserDefaults.standard.set(encoded, forKey: beaconRecipientsKey)
    }

    func loadBeaconRecipients() -> [BeaconContactRecipient] {
        guard let data = UserDefaults.standard.data(forKey: beaconRecipientsKey),
              let decoded = try? JSONDecoder().decode([BeaconContactRecipient].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveBeaconMessage(_ message: String) {
        UserDefaults.standard.set(message, forKey: beaconMessageKey)
    }

    func loadBeaconMessage() -> String? {
        UserDefaults.standard.string(forKey: beaconMessageKey)
    }
}
