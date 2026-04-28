import Foundation
import CoreLocation

private struct StoredLiveSessionCode: Codable {
    let code: String
    let expiresAt: Date
}

struct StoredMapSelection: Codable {
    let campaignId: UUID
    let campaignName: String?
    let boundaryCoordinates: [StoredCoordinate]

    init(campaignId: UUID, campaignName: String?, boundaryCoordinates: [StoredCoordinate]) {
        self.campaignId = campaignId
        self.campaignName = campaignName
        self.boundaryCoordinates = boundaryCoordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaignId = try container.decode(UUID.self, forKey: .campaignId)
        campaignName = try container.decodeIfPresent(String.self, forKey: .campaignName)
        boundaryCoordinates = try container.decodeIfPresent([StoredCoordinate].self, forKey: .boundaryCoordinates) ?? []
    }
}

struct StoredCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class LocalStorage {
    static let shared = LocalStorage()

    private let onboardingKey = "flyr_onboarding_data"
    private let hasCompletedOnboardingKey = "flyr_has_completed_onboarding"
    private let isInPreviewModeKey = "flyr_is_in_preview_mode"
    private let hasSeenMapInfoSheetKey = "flyr_has_seen_map_info_sheet"
    private let beaconTokensKey = "flyr_session_beacon_tokens"
    private let beaconRecipientsKey = "flyr_beacon_recipients"
    private let beaconMessageKey = "flyr_beacon_message"
    private let liveSessionCodesKey = "flyr_live_session_codes"
    private let mapSelectionKey = "flyr_selected_map_campaign"

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
        UserDefaults.standard.removeObject(forKey: liveSessionCodesKey)
        clearMapSelection()
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

    // MARK: - Live session codes

    func saveLiveSessionCode(_ code: String, expiresAt: Date, for sessionId: UUID) {
        var storedCodes = liveSessionCodes
        storedCodes[sessionId.uuidString] = StoredLiveSessionCode(code: code, expiresAt: expiresAt)
        persistLiveSessionCodes(storedCodes)
    }

    func loadLiveSessionCode(for sessionId: UUID) -> (code: String, expiresAt: Date)? {
        var storedCodes = liveSessionCodes
        guard let stored = storedCodes[sessionId.uuidString] else {
            return nil
        }

        if stored.expiresAt <= Date() {
            storedCodes.removeValue(forKey: sessionId.uuidString)
            persistLiveSessionCodes(storedCodes)
            return nil
        }

        return (stored.code, stored.expiresAt)
    }

    func clearLiveSessionCode(for sessionId: UUID) {
        var storedCodes = liveSessionCodes
        storedCodes.removeValue(forKey: sessionId.uuidString)
        persistLiveSessionCodes(storedCodes)
    }

    private var liveSessionCodes: [String: StoredLiveSessionCode] {
        guard let data = UserDefaults.standard.data(forKey: liveSessionCodesKey),
              let decoded = try? JSONDecoder().decode([String: StoredLiveSessionCode].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistLiveSessionCodes(_ value: [String: StoredLiveSessionCode]) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: liveSessionCodesKey)
    }

    // MARK: - Map selection

    func saveMapSelection(
        campaignId: UUID,
        campaignName: String?,
        boundaryCoordinates: [CLLocationCoordinate2D] = []
    ) {
        let value = StoredMapSelection(
            campaignId: campaignId,
            campaignName: campaignName,
            boundaryCoordinates: boundaryCoordinates.map(StoredCoordinate.init)
        )
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: mapSelectionKey)
    }

    func loadMapSelection() -> StoredMapSelection? {
        guard let data = UserDefaults.standard.data(forKey: mapSelectionKey),
              let decoded = try? JSONDecoder().decode(StoredMapSelection.self, from: data) else {
            return nil
        }
        return decoded
    }

    func clearMapSelection() {
        UserDefaults.standard.removeObject(forKey: mapSelectionKey)
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
