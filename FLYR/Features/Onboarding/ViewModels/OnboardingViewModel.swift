import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var response = OnboardingResponse()
    @Published var currentStep: Int = 0
    @Published var profileImage: UIImage?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    var canProceed: Bool {
        switch currentStep {
        case 0: return response.industry != nil
        case 1: return response.activityType != nil
        case 2: return response.experienceLevel != nil
        case 3: return response.territoryType != nil
        case 4: return !response.goals.isEmpty
        case 5: return !response.firstName.isEmpty && !response.lastName.isEmpty
        case 6: return response.contactPreference != nil
        case 7: return true // Pricing framing – optional
        case 8: return true // Auth
        default: return true
        }
    }

    func next() {
        guard currentStep < 9 else { return }
        currentStep += 1
        saveToLocalStorage()
    }

    func back() {
        guard currentStep > 0 else { return }
        currentStep -= 1
    }

    // MARK: - Local Storage

    /// Save draft for resume; do not set hasCompletedOnboarding or isInPreviewMode until after OAuth.
    func saveToLocalStorage() {
        LocalStorage.shared.saveOnboardingData(response)
    }

    // MARK: - Sync onboarding to profile (after OAuth sign-in)

    /// Call after user has signed in with Google or Apple to save onboarding data to their profile and clear draft.
    func syncOnboardingDataToProfile() async {
        guard let user = AuthManager.shared.user else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await upsertProfile(userId: user.id, email: user.email ?? "")
            LocalStorage.shared.clearOnboardingData()
            LocalStorage.shared.isInPreviewMode = false
            LocalStorage.shared.hasCompletedOnboarding = true
        } catch {
            errorMessage = "Failed to save your setup: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func upsertProfile(userId: UUID, email: String) async throws {
        let goalsArray = response.goals.map(\.rawValue)
        let proExpectationsArray = response.proExpectations.map(\.rawValue)

        var row: [String: AnyCodable] = [
            "id": AnyCodable(userId.uuidString),
            "email": AnyCodable(email),
            "first_name": AnyCodable(response.firstName),
            "last_name": AnyCodable(response.lastName),
            "contact_preference": AnyCodable(response.contactPreference?.rawValue ?? ""),
            "industry": AnyCodable(response.industry?.rawValue ?? ""),
            "activity_type": AnyCodable(response.activityType?.rawValue ?? ""),
            "territory_type": AnyCodable(response.territoryType?.rawValue ?? ""),
            "experience_level": AnyCodable(response.experienceLevel?.rawValue ?? ""),
            "goals": AnyCodable(goalsArray),
            "pro_expectations": AnyCodable(proExpectationsArray),
            "pro_expectations_other": AnyCodable(response.proExpectationsOther ?? ""),
            "profile_image_url": AnyCodable(response.profilePhotoURL ?? "")
        ]

        _ = try await client
            .from("profiles")
            .upsert(row, onConflict: "id")
            .execute()
    }
}
